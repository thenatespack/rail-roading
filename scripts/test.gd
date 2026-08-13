class_name MainGameScene
extends Node2D

@export var tile_map: TileMapLayer
@export var infrastructure_tilemap: TileMapLayer
@export var housing_tilemap: TileMapLayer
@export var selection_tilemap: TileMapLayer
@export var player: Camera2D
@export var city_marker_scene: PackedScene

@onready var build_tool: BuildTool
@onready var hud: CanvasLayer = get_node("HUD")

const TILE_SIZE := 16
const CHUNK_SIZE := Vector2i(32, 32)
const LOAD_DISTANCE := 2
const MAP_SEED := 12345

var generator: MapGenerator
var chunks := {}
var current_chunk := Vector2i.ZERO
var is_dragging := false
var housing_timer := 0.0
var growth_timer := 0.0
var city_markers := {}
const HOUSING_CHECK_INTERVAL := 10.0
const BUILDING_SPAWN_CHANCE := 0.3
const HOUSE_OFFSETS: Array[Vector2i] = [
	Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN
]
# Population contributed by each building type, per density level
# (zone index 0=housing, 1=commercial, 2=industrial, tier index = city level).
const POP_PER_HOUSING := [40, 80, 150]
const POP_PER_COMMERCIAL := [15, 30, 60]
const POP_PER_INDUSTRIAL := [10, 20, 40]
const GROWTH_INTERVAL := 2.0
const GROWTH_RATE := 0.08
# Tile source for each zone per density level (Structures tilemap sources)
const BUILDING_SOURCE := {
	MapGenerator.ZoneType.HOUSING: [0, 3, 6],
	MapGenerator.ZoneType.COMMERCIAL: [1, 4, 7],
	MapGenerator.ZoneType.INDUSTRIAL: [2, 5, 8],
}
# A city levels up when this fraction of its buildable zone tiles is filled.
const LEVEL_UP_RATIO := 0.6
# Minimum seconds between level ups, so a city can't densify in one burst.
const LEVEL_UP_COOLDOWN := 10.0
# How many buildings densify per growth tick while a level-up is in progress.
const UPGRADE_BATCH_SIZE := 12

func _ready() -> void:
	generator = MapGenerator.new(CHUNK_SIZE, MAP_SEED)
	build_tool = BuildTool.new()
	if build_tool:
		build_tool.setup(generator, infrastructure_tilemap, selection_tilemap)
		build_tool.structure_removed.connect(_on_structure_removed)

	var bounds = Rect2i(0, 0, 100, 100)
	var cities = generator.get_cities(2, bounds)
	
	for city in cities:
		print("City:", city.position, " Population:", city.population)
		spawn_city_marker(city)
		
	update_chunks()
	if player and "money" in player:
		hud.update_money(player.money)


func spawn_city_marker(city) -> void:
	if not city_marker_scene:
		return
	var marker = city_marker_scene.instantiate() as CityMarker
	add_city_to_scene(marker, city)


func add_city_to_scene(marker: Node2D, city) -> void:
	add_child(marker)
	# Convert city tile position to world coordinates (centered on tile)
	marker.position = Vector2(city.position * TILE_SIZE) + Vector2(TILE_SIZE / 2, TILE_SIZE / 2)
	var city_name = city.name if "name" in city else "City"
	marker.setup(
		city_name,
		city.population,
		generator.get_city_seed(city),
		city.cell_size
	)
	city_markers[city.position] = marker


func screen_to_tile(screen_position: Vector2) -> Vector2i:
	var world_pos = get_viewport().get_canvas_transform().affine_inverse() * screen_position
	return Vector2i(
		floor(world_pos.x / TILE_SIZE),
		floor(world_pos.y / TILE_SIZE)
	)


func _process(delta: float) -> void:
	housing_timer += delta
	if housing_timer >= HOUSING_CHECK_INTERVAL:
		housing_timer = 0.0
		try_build_buildings()
	growth_timer += delta
	if growth_timer >= GROWTH_INTERVAL:
		growth_timer = 0.0
		update_city_growth()


func try_build_buildings() -> void:
	if build_tool == null or build_tool.road_tiles.is_empty():
		return
	for road: Vector2i in build_tool.road_tiles:
		for offset: Vector2i in HOUSE_OFFSETS:
			var pos := road + offset
			if not can_build(pos):
				continue
			# Buildings only spawn inside a city's matching zone, using the
			# city's current density tier for the sprite and population yield.
			var city := generator.get_city_at(pos)
			if city == null:
				continue
			var zone := generator.get_zone(city, pos)
			if not BUILDING_SOURCE.has(zone):
				continue
			if randf() > BUILDING_SPAWN_CHANCE:
				continue
			housing_tilemap.set_cell(pos, BUILDING_SOURCE[zone][city.level], Vector2i(0, 0), 0)
			print("Built ", MapGenerator.ZoneType.keys()[zone], " building at ", pos)


func can_build(pos: Vector2i) -> bool:
	if housing_tilemap and housing_tilemap.get_cell_source_id(pos) != -1:
		return false
	if infrastructure_tilemap and infrastructure_tilemap.get_cell_source_id(pos) != -1:
		return false
	return generator.cost_modifier(pos.x, pos.y) < 2.0


## Counts buildings per city and eases each city's population toward the total
## its buildings support. Growing population expands the influence circle, and
## cities level up (denser buildings) when they run out of buildable room.
func update_city_growth() -> void:
	var counts := {}
	if housing_tilemap:
		for cell in housing_tilemap.get_used_cells():
			var city = generator.get_city_at(cell)
			if city == null:
				continue
			var zone := source_to_zone(housing_tilemap.get_cell_source_id(cell))
			if zone < 0:
				continue
			if not counts.has(city.position):
				counts[city.position] = [0, 0, 0]
			counts[city.position][zone] += 1

	var total_population := 0
	for city in generator.active_cities:
		city.level_up_cooldown = maxf(city.level_up_cooldown - GROWTH_INTERVAL, 0.0)
		process_pending_upgrades(city)

		var building_counts: Array = counts.get(city.position, [0, 0, 0])
		var level := clampi(city.level, 0, MapGenerator.DENSITY_LEVELS - 1)
		var target_population : int = city.base_population \
			+ building_counts[0] * POP_PER_HOUSING[level] \
			+ building_counts[1] * POP_PER_COMMERCIAL[level] \
			+ building_counts[2] * POP_PER_INDUSTRIAL[level]
		city.population = int(round(lerpf(float(city.population), float(target_population), GROWTH_RATE)))
		total_population += city.population

		check_city_level_up(city)

		var marker: CityMarker = city_markers.get(city.position)
		if marker:
			marker.update_population(city.population, city.level)

	if hud:
		hud.update_population(total_population)


## Zone (0/1/2) for a building tile source, or -1 if it isn't a building.
func source_to_zone(source: int) -> int:
	for zone in BUILDING_SOURCE:
		if BUILDING_SOURCE[zone].has(source):
			return zone
	return -1


## Levels a city up when nearly all of its buildable zone tiles are filled.
## On level up the tier applies immediately (for new buildings and pop yield),
## but existing buildings only densify in small batches over time, and the city
## is put on a cooldown before it can level up again.
func check_city_level_up(city: MapGenerator.City) -> void:
	if city.level >= MapGenerator.DENSITY_LEVELS - 1:
		return
	if city.level_up_cooldown > 0.0:
		return
	var radius := generator.get_influence_radius_tiles(city.population)
	var radius_i := int(ceil(radius))
	var total := 0
	var developed := 0
	for dx in range(-radius_i, radius_i + 1):
		for dy in range(-radius_i, radius_i + 1):
			var pos := city.position + Vector2i(dx, dy)
			if float(pos.distance_to(city.position)) > radius:
				continue
			if generator.cost_modifier(pos.x, pos.y) >= 2.0:
				continue  # heart / water / mountains aren't buildable
			total += 1
			if housing_tilemap and housing_tilemap.get_cell_source_id(pos) != -1:
				developed += 1
	if total == 0 or developed == 0:
		return
	if float(developed) / float(total) >= LEVEL_UP_RATIO:
		city.level += 1
		city.level_up_cooldown = LEVEL_UP_COOLDOWN
		collect_pending_upgrades(city)
		print("City at ", city.position, " leveled up to density level ", city.level + 1)


## Queues every building in the city that still uses an older-tier sprite so it
## can be upgraded in batches rather than all at once.
func collect_pending_upgrades(city: MapGenerator.City) -> void:
	city.pending_upgrades.clear()
	if not housing_tilemap:
		return
	var radius := generator.get_influence_radius_tiles(city.population)
	for cell in housing_tilemap.get_used_cells():
		if float(cell.distance_to(city.position)) > radius:
			continue
		var zone := source_to_zone(housing_tilemap.get_cell_source_id(cell))
		if zone < 0:
			continue
		if housing_tilemap.get_cell_source_id(cell) != BUILDING_SOURCE[zone][city.level]:
			city.pending_upgrades.append(cell)


## Densifies up to UPGRADE_BATCH_SIZE queued buildings each growth tick.
func process_pending_upgrades(city: MapGenerator.City) -> void:
	if not housing_tilemap or city.pending_upgrades.is_empty():
		return
	var upgraded := 0
	while not city.pending_upgrades.is_empty() and upgraded < UPGRADE_BATCH_SIZE:
		var cell: Vector2i = city.pending_upgrades.pop_front()
		var zone := source_to_zone(housing_tilemap.get_cell_source_id(cell))
		if zone < 0:
			continue  # building was removed while queued
		var source: int = BUILDING_SOURCE[zone][city.level]
		if housing_tilemap.get_cell_source_id(cell) != source:
			housing_tilemap.set_cell(cell, source, Vector2i(0, 0), 0)
		upgraded += 1


func _on_structure_removed(position: Vector2i, structure: int) -> void:
	if structure != BuildTool.Structure.ROAD:
		return
	for offset in HOUSE_OFFSETS:
		var house_pos := position + offset
		if housing_tilemap and housing_tilemap.get_cell_source_id(house_pos) == -1:
			continue
		if has_road_neighbor(house_pos):
			continue
		housing_tilemap.erase_cell(house_pos)
		print("Removed house at ", house_pos)


func has_road_neighbor(pos: Vector2i) -> bool:
	if infrastructure_tilemap == null:
		return false
	for offset in HOUSE_OFFSETS:
		var neighbor := pos + offset
		if build_tool.get_structure_at(neighbor) == BuildTool.Structure.ROAD:
			return true
	return false


func _physics_process(_delta: float) -> void:
	if not player:
		return
	var player_tile := Vector2i(
		floor(player.position.x / TILE_SIZE),
		floor(player.position.y / TILE_SIZE)
	)
	var player_chunk := world_to_chunk(player_tile)
	
	if player_chunk != current_chunk:
		current_chunk = player_chunk
		update_chunks()


func world_to_chunk(tile_position: Vector2i) -> Vector2i:
	return Vector2i(
		floor(float(tile_position.x) / CHUNK_SIZE.x),
		floor(float(tile_position.y) / CHUNK_SIZE.y)
	)


func chunk_to_world(chunk: Vector2i) -> Vector2i:
	return Vector2i(
		chunk.x * CHUNK_SIZE.x,
		chunk.y * CHUNK_SIZE.y
	)


func update_chunks() -> void:
	var needed := []
	for x in range(current_chunk.x - LOAD_DISTANCE, current_chunk.x + LOAD_DISTANCE + 1):
		for y in range(current_chunk.y - LOAD_DISTANCE, current_chunk.y + LOAD_DISTANCE + 1):
			var chunk_pos := Vector2i(x, y)
			needed.append(chunk_pos)
			if not chunks.has(chunk_pos):
				load_chunk(chunk_pos)
				
	for chunk_pos in chunks.keys():
		if chunk_pos not in needed:
			unload_chunk(chunk_pos)


func load_chunk(chunk_pos: Vector2i) -> void:
	var world_position := chunk_to_world(chunk_pos)
	var chunk = generator.generate(world_position + Vector2i(int(CHUNK_SIZE.x / 2.0), int(CHUNK_SIZE.y / 2.0)))
	chunks[chunk_pos] = chunk
	draw_chunk(chunk, world_position)


func unload_chunk(chunk_pos: Vector2i) -> void:
	chunks.erase(chunk_pos)
	clear_chunk(chunk_pos)


func draw_chunk(chunk: PackedInt32Array, offset: Vector2i) -> void:
	for x in CHUNK_SIZE.x:
		for y in CHUNK_SIZE.y:
			var tile_type: int = chunk[x * CHUNK_SIZE.y + y]
			tile_map.set_cell(
				offset + Vector2i(x, y),
				0,
				generator.get_atlas_position(tile_type as MapGenerator.TileType)
			)


func clear_chunk(chunk_pos: Vector2i) -> void:
	var start := chunk_to_world(chunk_pos)
	for x in range(CHUNK_SIZE.x):
		for y in range(CHUNK_SIZE.y):
			tile_map.erase_cell(start + Vector2i(x, y))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var tile_pos = screen_to_tile(event.position)
			
			if event.pressed:
				is_dragging = true
				if build_tool and player:
					build_tool.start_drag(tile_pos)
					var placed_cost = build_tool.try_place_single(tile_pos, player.money)
					if placed_cost > 0.0:
						player.money -= placed_cost
						hud.update_money(player.money)
			else:
				if is_dragging:
					is_dragging = false
					if build_tool and player:
						var build_cost = build_tool.commit_build(player.money)
						if build_cost <= player.money:
							player.money -= build_cost
							hud.update_money(player.money)
						
	elif event is InputEventMouseMotion and is_dragging:
		if build_tool:
			var tile_pos = screen_to_tile(event.position)
			build_tool.update_drag_preview(tile_pos)


func _on_hud_build_time(building_type: int) -> void:
	if build_tool:
		build_tool.current_structure = building_type as BuildTool.Structure
		print("Switched building mode to: ", BuildTool.Structure.keys()[building_type])


func _on_player_cam_display_settings() -> void:
	$HUD/SettingsPopup.visible = not $HUD/SettingsPopup.visible
	get_tree().paused = not get_tree().paused
