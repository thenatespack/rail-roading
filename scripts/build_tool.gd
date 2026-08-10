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
		
	if world_tile_position == last_built_tile:
		return false
		
	var terrain_modifier := map_reference.cost_modifier(
		world_tile_position.x, 
		world_tile_position.y
	)
	
	if terrain_modifier > 2000000.0:
		build_failed.emit("Terrain unsuitable for building.")
		return false
		
	var base_cost: float = BASE_COSTS[current_structure]
	var final_cost: float = base_cost * terrain_modifier
	
	place_structure(world_tile_position)
	last_built_tile = world_tile_position
	
	print("Built ", Structure.keys()[current_structure], " at ", world_tile_position, " for ", final_cost)
	building_placed.emit(world_tile_position, final_cost)
	
	return true


func place_structure(tile_position: Vector2i) -> void:
	if not building_layer:
		return
		
	var data := get_texture_and_alternative(tile_position)
	building_layer.set_cell(tile_position, 0, data.atlas, data.alternative)


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


func commit_build(money: float) -> float:
	if not is_dragging or not active or map_reference == null:
		reset_drag()
		return 0.0
		
	var total_cost := 0.0
	var valid_tiles := []
	
	for tile_pos in preview_tiles:
		var terrain_modifier := map_reference.cost_modifier(tile_pos.x, tile_pos.y)
		
		if terrain_modifier < 2.0:
			valid_tiles.append(tile_pos)
			total_cost += BASE_COSTS[current_structure] * terrain_modifier
	
	if money < total_cost:
		print("Not enough money. Required: ", total_cost, ", Available: ", money)
		reset_drag()
		return total_cost
	
	if not valid_tiles.is_empty():
		place_structure_line(valid_tiles)
		print("Built line of ", valid_tiles.size(), " structures for total cost: ", total_cost)
		building_placed.emit(valid_tiles[0], total_cost)
		
	reset_drag()
	return total_cost


func place_structure_line(tiles: Array) -> void:
	if not building_layer:
		return
		
	for i in range(tiles.size()):
		var tile_pos = tiles[i]
		
		# Determine orientation context from neighbors within the line or existing map
		var data := get_texture_and_alternative_for_line(tiles, i)
		building_layer.set_cell(tile_pos, 0, data.atlas, data.alternative)


## Determines atlas coordinates and alternative tile flags (rotation/flip)
func get_texture_and_alternative(tile_position: Vector2) -> Dictionary:
	var atlas_coords := Vector2i.ZERO
	var alternative_tile := 0 # Default (e.g., Horizontal)
	
	match current_structure:
		Structure.ROAD:
			atlas_coords = Vector2i(0, 1)
		Structure.RAIL:
			atlas_coords = Vector2i(0, 0)
			# Check neighbors to decide if it should be vertical (Alt ID 1 or transpose flags)
			# Assuming alternative tile 1 is rotated 90 degrees or vertical variant:
			if is_vertical_neighbor(tile_position):
				alternative_tile = 1 
		Structure.STATION:
			atlas_coords = Vector2i(2, 0)
			
	return {"atlas": atlas_coords, "alternative": alternative_tile}


## Specialized check for batch/line placements to look at adjacent items in the drag array
func get_texture_and_alternative_for_line(tiles: Array, index: int) -> Dictionary:
	var tile_pos = tiles[index]
	var atlas_coords := Vector2i.ZERO
	var alternative_tile := 0
	
	match current_structure:
		Structure.ROAD:
			atlas_coords = Vector2i(0, 1)
		Structure.RAIL:
			atlas_coords = Vector2i(0, 0)
			
			# Look at adjacent tiles in the dragged line to determine orientation
			var direction = Vector2i.ZERO
			if index > 0:
				direction = tile_pos - tiles[index - 1]
			elif tiles.size() > 1:
				direction = tiles[1] - tile_pos
				
			if direction.y != 0 and direction.x == 0:
				alternative_tile = 1 # Vertical alignment alternative ID
		Structure.STATION:
			atlas_coords = Vector2i(2, 0)
			
	return {"atlas": atlas_coords, "alternative": alternative_tile}


func is_vertical_neighbor(tile_pos: Vector2i) -> bool:
	if not building_layer:
		return false
	var top_neighbor = tile_pos + Vector2i.UP
	var bottom_neighbor = tile_pos + Vector2i.DOWN
	
	# If already connected vertically via existing tiles on the layer
	var has_top = building_layer.get_cell_source_id(top_neighbor) != -1
	var has_bottom = building_layer.get_cell_source_id(bottom_neighbor) != -1
	
	return has_top or has_bottom


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
