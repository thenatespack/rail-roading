class_name MapGenerator
extends RefCounted

enum TileType {
	WATER,
	SAND,
	GRASS,
	FOREST,
	MOUNTAIN
}

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

	func _init(pos: Vector2i, pop: int) -> void:
		position = pos
		population = pop

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
			var population := rng.randi_range(1000, 20000)
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
		var pop_factor = clampf(float(city.population) / 20000.0, 0.0, 1.0)
		var heart_radius_in_tiles = lerpf(0.8, 4.0, pop_factor)
		
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
