class_name MainGameScene
extends Node2D

@export var tile_map: TileMapLayer
@export var infrastructure_tilemap: TileMapLayer
@export var housing_tilemap: TileMapLayer
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
var influence_roads: Array[Vector2i] = []
var housing_timer := 0.0
@export var housing_spawn_chance_per_second := 5.0

func _ready() -> void:
	generator = MapGenerator.new(CHUNK_SIZE, MAP_SEED)
	build_tool = BuildTool.new()
	if build_tool:
		build_tool.setup(generator, infrastructure_tilemap)

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
	marker.setup(city_name, city.population)


func screen_to_tile(screen_position: Vector2) -> Vector2i:
	var world_pos = get_viewport().get_canvas_transform().affine_inverse() * screen_position
	return Vector2i(
		floor(world_pos.x / TILE_SIZE),
		floor(world_pos.y / TILE_SIZE)
	)


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
				if build_tool:
					build_tool.start_drag(tile_pos)
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
