extends Node2D
@export var tile_map: TileMapLayer
@export var player: Node2D
const TILE_SIZE := 16
const CHUNK_SIZE := Vector2i(32,32)
const LOAD_DISTANCE := 2
const MAP_SEED := 12345
var generator: MapGenerator
var chunks := {}
var current_chunk := Vector2i.ZERO


func _ready():
	generator = MapGenerator.new(
		CHUNK_SIZE,
		MAP_SEED
	)
	var cities = generator.get_cities(10)
	
	for city in cities:
		print("City:", city.position, " Population:", city.population)
	update_chunks()

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			check_build_cost(event.position)

func check_build_cost(mouse_position:Vector2):
	var world_position = screen_to_world(mouse_position)
	var modifier = generator.costModifier(
		world_position.x,
		world_position.y
	)
	print("Clicked tile: ", world_position)
	print("Cost modifier: ", modifier)

func screen_to_world(screen_position:Vector2)->Vector2i:
	var world_pos = get_viewport().get_canvas_transform().affine_inverse() * screen_position

	return Vector2i(
		floor(world_pos.x / TILE_SIZE),
		floor(world_pos.y / TILE_SIZE)
	)

func _physics_process(delta):
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


func update_chunks():
	var needed := []
	for x in range(current_chunk.x - LOAD_DISTANCE, current_chunk.x + LOAD_DISTANCE + 1):
		for y in range(current_chunk.y - LOAD_DISTANCE, current_chunk.y + LOAD_DISTANCE + 1):
			var chunk_pos := Vector2i(x,y)
			needed.append(chunk_pos)
			if not chunks.has(chunk_pos):
				load_chunk(chunk_pos)
	for chunk_pos in chunks.keys():
		if chunk_pos not in needed:
			unload_chunk(chunk_pos)


func load_chunk(chunk_pos: Vector2i):
	var world_position := chunk_to_world(chunk_pos)
	var chunk := generator.generate(
		world_position + CHUNK_SIZE / 2
	)
	chunks[chunk_pos] = chunk
	draw_chunk(chunk, world_position)


func unload_chunk(chunk_pos: Vector2i):
	chunks.erase(chunk_pos)
	clear_chunk(chunk_pos)


func draw_chunk(chunk: Array, offset: Vector2i):
	for x in range(chunk.size()):
		for y in range(chunk[x].size()):
			var tile_type = chunk[x][y]
			tile_map.set_cell(
				offset + Vector2i(x,y),
				0,
				generator.get_atlas_position(tile_type)
			)


func clear_chunk(chunk_pos: Vector2i):
	var start := chunk_to_world(chunk_pos)
	for x in range(CHUNK_SIZE.x):
		for y in range(CHUNK_SIZE.y):
			tile_map.erase_cell(
				start + Vector2i(x,y)
			)
