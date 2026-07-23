class_name BuildTool
extends Node

signal building_placed(position: Vector2i, cost: float)
signal build_failed(reason: String)

@export var building_layer: TileMapLayer

enum Structure {
	ROAD,
	RAIL,
	STATION
}

var active := true
var current_structure := Structure.ROAD
var map_reference: MapGenerator

# Tracks the last tile built during a drag so we don't spam it
var last_built_tile := Vector2i(-999999, -999999) 

const BASE_COSTS := {
	Structure.ROAD: 10.0,
	Structure.RAIL: 25.0,
	Structure.STATION: 500.0
}


func setup(generator: MapGenerator, buildingLayer: TileMapLayer) -> void:
	map_reference = generator
	building_layer = buildingLayer


func attempt_build(world_tile_position: Vector2i) -> bool:
	if not active or map_reference == null:
		return false
		
	# Prevent building on the exact same tile we just built on during this drag
	if world_tile_position == last_built_tile:
		return false
		
	var terrain_modifier := map_reference.cost_modifier(
		world_tile_position.x, 
		world_tile_position.y
	)
	
	if terrain_modifier >= 2.0:
		build_failed.emit("Terrain unsuitable for building.")
		return false
		
	var base_cost: float = BASE_COSTS[current_structure]
	var final_cost: float = base_cost * terrain_modifier
	
	# TODO: Deduct resources/money here
	
	place_structure(world_tile_position)
	last_built_tile = world_tile_position # Remember this tile for the drag
	
	print("Built ", Structure.keys()[current_structure], " at ", world_tile_position, " for ", final_cost)
	building_placed.emit(world_tile_position, final_cost)
	
	return true


func place_structure(tile_position: Vector2i) -> void:
	var atlas_coords := Vector2i.ZERO
	
	match current_structure:
		Structure.ROAD:
			atlas_coords = Vector2i(0, 1)
		Structure.RAIL:
			atlas_coords = Vector2i(0, 0) 
		Structure.STATION:
			atlas_coords = Vector2i(2, 0)
			
	if building_layer:
		building_layer.set_cell(tile_position, 0, atlas_coords)


var is_dragging := false
var drag_start_position := Vector2i.ZERO
var preview_tiles := []

func start_drag(tile_position: Vector2i) -> void:
	is_dragging = true
	drag_start_position = tile_position
	preview_tiles = [tile_position]


func update_drag_preview(current_tile_position: Vector2i) -> void:
	if not is_dragging:
		return
		
	clear_preview()
	preview_tiles = get_line_tiles(drag_start_position, current_tile_position)
	# draw_preview_feedback(preview_tiles)


func commit_build() -> void:
	if not is_dragging or not active or map_reference == null:
		reset_drag()
		return
		
	var total_cost := 0.0
	var valid_tiles := []
	
	for tile_pos in preview_tiles:
		var terrain_modifier := map_reference.cost_modifier(tile_pos.x, tile_pos.y)
		
		if terrain_modifier < 2.0: # Skip unbuildable terrain
			valid_tiles.append(tile_pos)
			total_cost += BASE_COSTS[current_structure] * terrain_modifier
			
	if not valid_tiles.is_empty():
		print(valid_tiles)
		place_structure_line(valid_tiles)
		print("Built line of ", valid_tiles.size(), " structures for total cost: ", total_cost)
		building_placed.emit(valid_tiles[0], total_cost)
		
	reset_drag()

func place_structure_line(tiles: Array) -> void:
	if not building_layer:
		return
		
	var atlas_coords := Vector2i.ZERO
	
	match current_structure:
		Structure.ROAD:
			atlas_coords = Vector2i(0, 1)
		Structure.RAIL:
			atlas_coords = Vector2i(0, 0)
		Structure.STATION:
			atlas_coords = Vector2i(2, 0)
			
	for tile_pos in tiles:
		building_layer.set_cell(tile_pos, 0, atlas_coords)

# Helper function to generate a straight line of tiles between two points (Bresenham's Algorithm)
func get_line_tiles(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var line: Array[Vector2i] = []
	var dx = abs(to.x - from.x)
	var dy = abs(to.y - from.y)
	var x = from.x
	var y = from.y
	var sx = 1 if from.x < to.x else -1
	var sy = 1 if from.y < to.y else -1
	var err = dx - dy
	
	while true:
		line.append(Vector2i(x, y))
		if x == to.x and y == to.y:
			break
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
			
	return line


func clear_preview() -> void:
	pass


func reset_drag() -> void:
	is_dragging = false
	drag_start_position = Vector2i.ZERO
	preview_tiles.clear()
	clear_preview()
