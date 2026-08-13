class_name MapGenerator
extends RefCounted

enum TileType {
	WATER,
	SAND,
	GRASS,
	FOREST,
	MOUNTAIN
}

enum ZoneType {
	HOUSING,
	COMMERCIAL,
	INDUSTRIAL
}

# Zone type fractions on a 1024 scale. Must match the shader's zone_split_a / zone_split_b defaults.
const ZONE_SPLIT_A := 512  # housing fraction
const ZONE_SPLIT_B := 819  # housing + commercial fraction
# District cell size (in tiles) scales between these limits with city population.
const CELL_SIZE_MIN := 3
const CELL_SIZE_MAX := 8
# Heart marker and zone influence radii, in shader "dist" units (0..1).
const MIN_HEART_RADIUS := 0.03
const MAX_HEART_RADIUS := 0.25
const MIN_INFLUENCE_RADIUS := 0.5
const MAX_INFLUENCE_RADIUS := 0.95
# Population at which a city's circles reach their maximum size. Tuned so the
# max influence cap lands around a fully built-out city, giving towns room to
# expand right up until that point, then stopping.
const POP_SCALE := 4000.0
# Marker rect size multipliers: the whole city circle physically grows from
# MARKER_SCALE_MIN to MARKER_SCALE_MAX as the population develops.
const MARKER_SCALE_MIN := 1.0
const MARKER_SCALE_MAX := 1.8
# Number of density tiers a city can level through (low -> medium -> high).
const DENSITY_LEVELS := 3

const TILE_ATLAS := {
	TileType.WATER: Vector2i(3, 0),
	TileType.SAND: Vector2i(0, 2),
	TileType.GRASS: Vector2i(1, 2),
	TileType.FOREST: Vector2i(1, 1),
	TileType.MOUNTAIN: Vector2i(2, 0)
}

class City:
	var position: Vector2i
	var population: int
	var base_population: int
	var cell_size: int
	var level: int = 0  # density tier: 0 = low, 1 = medium, 2 = high
	var level_up_cooldown: float = 0.0  # seconds left before it may level up again
	var pending_upgrades: Array[Vector2i] = []  # buildings still to densify

	func _init(pos: Vector2i, pop: int) -> void:
		position = pos
		population = pop
		base_population = pop
		cell_size = MapGenerator.get_cell_size(pop)

var chunk_size: Vector2i
var seed_value: int

var elevation_noise := FastNoiseLite.new()
var moisture_noise := FastNoiseLite.new()
var temperature_noise := FastNoiseLite.new()

# Typed array for safe tracking of active cities
var active_cities: Array[City] = []

func _init(size: Vector2i, map_seed: int) -> void:
	chunk_size = size
	seed_value = map_seed
	setup_noise()


func setup_noise() -> void:
	var noises: Array[FastNoiseLite] = [
		elevation_noise,
		moisture_noise,
		temperature_noise
	]
	for noise in noises:
		noise.seed = seed_value
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		
	elevation_noise.frequency = 0.008
	moisture_noise.frequency = 0.02
	temperature_noise.frequency = 0.015


func generate(player_position: Vector2i) -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(chunk_size.x * chunk_size.y)
	
	var start_x: int = player_position.x - int(chunk_size.x / 2.0)
	var start_y: int = player_position.y - int(chunk_size.y / 2.0)
	
	var index := 0
	for x in range(chunk_size.x):
		var world_x: int = start_x + x
		for y in range(chunk_size.y):
			var world_y: int = start_y + y
			map[index] = get_tile(world_x, world_y)
			index += 1
			
	return map


# Integrated temperature noise to determine deserts vs grass
func get_tile(world_x: int, world_y: int) -> TileType:
	var elevation := get_elevation(world_x, world_y)
	
	if elevation < -0.25:
		return TileType.WATER
	if elevation > 0.55:
		return TileType.MOUNTAIN
		
	var moisture := moisture_noise.get_noise_2d(world_x, world_y)
	var temperature := temperature_noise.get_noise_2d(world_x, world_y)
	
	# Sand now generates on coastlines OR in hot, dry areas
	if elevation < -0.05 or (temperature > 0.2 and moisture < 0.0):
		return TileType.SAND
	if moisture > 0.35 and temperature > -0.1:
		return TileType.FOREST
		
	return TileType.GRASS


# Clamped the ocean strength to prevent infinite negative scaling
func get_elevation(x: int, y: int) -> float:
	var value := elevation_noise.get_noise_2d(x, y)
	var coast_mask := float(x) / 1000.0
	
	if coast_mask < 0.2:
		var ocean_strength := clampf((0.2 - coast_mask) / 0.2, 0.0, 1.0)
		value -= ocean_strength * 0.35
		
	return value


func get_atlas_position(tile: TileType) -> Vector2i:
	return TILE_ATLAS[tile]


func get_cities(amount: int, bounds: Rect2i) -> Array[City]:
	active_cities.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var attempts := 0
	var max_attempts := amount * 500
	
	while active_cities.size() < amount and attempts < max_attempts:
		attempts += 1
		var x := rng.randi_range(bounds.position.x, bounds.end.x)
		var y := rng.randi_range(bounds.position.y, bounds.end.y)
		var position := Vector2i(x, y)
		
		if can_place_city(position, active_cities):
			var population := 0
			active_cities.append(City.new(position, population))
			
	print(active_cities)
	return active_cities


func can_place_city(pos: Vector2i, cities: Array[City]) -> bool:
	var tile := get_tile(pos.x, pos.y)
	if tile != TileType.GRASS and tile != TileType.FOREST:
		return false
		
	for city in cities:
		if city.position.distance_squared_to(pos) < 5625:
			return false
			
	return true


func cost_modifier(x: int, y: int) -> float:
	var pos := Vector2i(x, y)
	
	# Prevent building inside the city's heart zone (matches shader radius logic)
	for city in active_cities:
		var factor := pop_factor(city.population)
		var heart_radius_in_tiles = lerpf(0.8, 4.0, factor)
		
		if pos.distance_to(city.position) <= heart_radius_in_tiles:
			return 999.0 # Blocks building in the heart via BuildTool check
			
	var tile := get_tile(x, y)
	
	match tile:
		TileType.GRASS:
			return 0.5
		TileType.FOREST:
			return 1.0
		TileType.SAND:
			return 1.25
		TileType.MOUNTAIN, TileType.WATER:
			return 2.0
			
	return 1.0


# --- City zoning ---
# The zone query below is intentionally integer-exact and mirrors the Voronoi
# district lookup in city_circle.gdshader (get_zone), so buildings placed by the
# game logic always land in the exact same zone the shader draws.

## Stable 32-bit wrap hash shared with the shader.
func hash3i(ix: int, iy: int, iz: int) -> int:
	var h := (ix * 374761393 + iy * 668265263 + iz * 180461551) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return h


## Unique seed per city so each one gets a different zone pattern.
func get_city_seed(city: City) -> int:
	return absi((city.position.x * 73856093) ^ (city.position.y * 19349663)) % 2000000000


## District cell size in tiles; bigger cities get bigger districts.
static func get_cell_size(population: int) -> int:
	return int(round(lerpf(CELL_SIZE_MIN, CELL_SIZE_MAX, pop_factor(population))))


## Normalized growth factor (0..1) used for cell size and circle radii.
## Smoothed with an S-curve (smoothstep) so growth is gentle at the start and
## end of a city's development, and fastest in the middle.
static func pop_factor(population: int) -> float:
	var x := clampf(float(population) / POP_SCALE, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Heart radius (shader dist units) for a population.
static func get_heart_radius(population: int) -> float:
	return lerpf(MIN_HEART_RADIUS, MAX_HEART_RADIUS, pop_factor(population))


## Zone influence radius (shader dist units) for a population.
static func get_influence_radius(population: int) -> float:
	return lerpf(MIN_INFLUENCE_RADIUS, MAX_INFLUENCE_RADIUS, pop_factor(population))


## Influence radius in tiles, matching the shader's influence_radius math.
## Scaled up by the marker growth so the physical circle keeps pace with the
## drawn marker as the city develops.
func get_influence_radius_tiles(population: int) -> float:
	return get_influence_radius(population) * 8.0 * get_marker_scale(population)


## How much the whole city marker grows as the city develops, so a mature city
## physically covers a much larger area. Also applied to the gameplay radius so
## the zoned/expandable land always matches the drawn circle.
static func get_marker_scale(population: int) -> float:
	return lerpf(MARKER_SCALE_MIN, MARKER_SCALE_MAX, pop_factor(population))


## Zone for a tile offset from a city. Mirrors city_circle.gdshader get_zone().
func get_zone(city: City, tile_pos: Vector2i) -> int:
	var dx := tile_pos.x - city.position.x
	var dy := tile_pos.y - city.position.y
	var cs := city.cell_size
	var seed := get_city_seed(city)
	var cx := int(floor(float(dx) / float(cs)))
	var cy := int(floor(float(dy) / float(cs)))
	var best_cx := cx
	var best_cy := cy
	var best_d2 := 1 << 62
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			var cxx := cx + ox
			var cyy := cy + oy
			var h := hash3i(cxx, cyy, seed)
			var jx := h % cs
			var jy := (h >> 16) % cs
			var center_x := cxx * cs + jx
			var center_y := cyy * cs + jy
			var dxx := center_x - dx
			var dyy := center_y - dy
			var d2 := dxx * dxx + dyy * dyy
			if d2 < best_d2:
				best_d2 = d2
				best_cx = cxx
				best_cy = cyy
	var bh := hash3i(best_cx, best_cy, seed + 1000003)
	var bucket := bh >> 22
	if bucket < ZONE_SPLIT_A:
		return ZoneType.HOUSING
	if bucket < ZONE_SPLIT_B:
		return ZoneType.COMMERCIAL
	return ZoneType.INDUSTRIAL


## Zone at a world tile, or -1 when the tile isn't inside any city's influence.
func get_zone_at(tile_pos: Vector2i) -> int:
	var city := get_city_at(tile_pos)
	if city == null:
		return -1
	return get_zone(city, tile_pos)


## The city whose influence circle contains the tile, or null.
func get_city_at(tile_pos: Vector2i) -> City:
	for city in active_cities:
		if tile_pos.distance_to(city.position) <= get_influence_radius_tiles(city.population):
			return city
	return null
