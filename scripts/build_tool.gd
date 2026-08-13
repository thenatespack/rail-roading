class_name BuildTool
extends Node

signal building_placed(position: Vector2i, cost: float)
signal build_failed(reason: String)
signal structure_removed(position: Vector2i, structure: int)

@export var building_layer: TileMapLayer
@export var selection_layer: TileMapLayer

enum Structure {
	ROAD,
	RAIL,
	STATION,
	DEMOLISH,
	NONE
}

var active := true
var current_structure := Structure.ROAD
var map_reference: MapGenerator

# Tracks the last tile built during a drag so we don't spam it
var last_built_tile := Vector2i(-999999, -999999) 

# Tile placed instantly on mouse-down; excluded from the next line commit so
# click-and-drag doesn't place or charge the start tile twice
var press_placed_tile := Vector2i(-999999, -999999)

# All road tiles the player has placed, used for house placement near roads
var road_tiles: Array[Vector2i] = []

const BASE_COSTS := {
	Structure.ROAD: 10.0,
	Structure.RAIL: 25.0,
	Structure.STATION: 500.0
}

const REFUND_RATIO := 0.1

const ROAD_ATLAS_VERTICAL := Vector2i(0, 1)
const ROAD_ATLAS_CORNER := Vector2i(1, 1)
const ROAD_ATLAS_HORIZONTAL := Vector2i(2, 1)
const RAIL_ATLAS := Vector2i(0, 2)
const STATION_ATLAS := Vector2i(0, 0)

# Corner (1,1) base connects EAST and SOUTH. Alternative IDs are flip bitmasks:
# 0 = base {E,S}, 1 = flip_h {W,S}, 2 = flip_v {E,N}, 3 = flip_h+flip_v {W,N}
const CORNER_ALT_EAST_SOUTH := 0
const CORNER_ALT_WEST_SOUTH := 1
const CORNER_ALT_EAST_NORTH := 2
const CORNER_ALT_WEST_NORTH := 3

# Rail (0,2) base is vertical; alternative 4 is transpose (horizontal)
const RAIL_ALT_VERTICAL := 0
const RAIL_ALT_HORIZONTAL := 4


func setup(generator: MapGenerator, buildingLayer: TileMapLayer, selectionLayer: TileMapLayer = null) -> void:
	map_reference = generator
	building_layer = buildingLayer
	selection_layer = selectionLayer


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
	track_placed_tile(tile_position)


## Places a single structure instantly on mouse-down and returns its cost,
## or 0.0 if it can't be placed (invalid terrain, not enough money, demolish).
func try_place_single(tile_position: Vector2i, money: float) -> float:
	if not active or map_reference == null or current_structure == Structure.DEMOLISH:
		return 0.0
	var terrain_modifier := map_reference.cost_modifier(tile_position.x, tile_position.y)
	if terrain_modifier >= 2.0:
		return 0.0
	var cost: float = BASE_COSTS[current_structure] * terrain_modifier
	if money < cost:
		return 0.0
	place_structure(tile_position)
	press_placed_tile = tile_position
	return cost


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
	draw_preview_tiles(preview_tiles)


## Highlights the given tiles on the selection layer
func draw_preview_tiles(tiles: Array) -> void:
	if not selection_layer:
		return
	for tile_pos in tiles:
		selection_layer.set_cell(tile_pos, 0, Vector2i(0, 0), 0)


func commit_build(money: float) -> float:
	if not is_dragging or not active or map_reference == null:
		reset_drag()
		return 0.0
		
	if current_structure == Structure.DEMOLISH:
		var total_refund := 0.0
		for tile_pos in preview_tiles:
			total_refund += remove_structure(tile_pos)
		reset_drag()
		if total_refund > 0.0:
			print("Removed structures, refunded: ", total_refund)
		return -total_refund
		
	var total_cost := 0.0
	var valid_tiles := []
	
	for tile_pos in preview_tiles:
		# The start tile was already placed and charged on mouse-down
		if tile_pos == press_placed_tile:
			continue
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


func remove_structure(tile_position: Vector2i) -> float:
	var structure := get_structure_at(tile_position)
	if structure == Structure.NONE:
		return 0.0
	building_layer.erase_cell(tile_position)
	road_tiles.erase(tile_position)
	structure_removed.emit(tile_position, structure)
	var build_cost: float = BASE_COSTS[structure] * map_reference.cost_modifier(tile_position.x, tile_position.y)
	return build_cost * REFUND_RATIO


func get_structure_at(tile_position: Vector2i) -> int:
	if not building_layer or building_layer.get_cell_source_id(tile_position) == -1:
		return Structure.NONE
	match building_layer.get_cell_atlas_coords(tile_position):
		ROAD_ATLAS_VERTICAL, ROAD_ATLAS_CORNER, ROAD_ATLAS_HORIZONTAL:
			return Structure.ROAD
		RAIL_ATLAS:
			return Structure.RAIL
		STATION_ATLAS:
			return Structure.STATION
	return Structure.NONE


func is_road(tile_position: Vector2i) -> bool:
	return get_structure_at(tile_position) == Structure.ROAD


# Returns the directions (UP/DOWN/LEFT/RIGHT) a road tile connects to,
# from existing map roads plus the planned drag line.
func get_road_connections(tile_position: Vector2i, planned_tiles: Array) -> Array[Vector2i]:
	var connections: Array[Vector2i] = []
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbor := tile_position + direction
		if planned_tiles.has(neighbor) or is_road(neighbor):
			connections.append(direction)
	return connections


# Picks atlas coords + alternative for a road tile based on its connections.
func get_road_data(tile_position: Vector2i, planned_tiles: Array) -> Dictionary:
	var conns := get_road_connections(tile_position, planned_tiles)
	var up := conns.has(Vector2i.UP)
	var down := conns.has(Vector2i.DOWN)
	var left := conns.has(Vector2i.LEFT)
	var right := conns.has(Vector2i.RIGHT)

	if up and down:
		return {"atlas": ROAD_ATLAS_VERTICAL, "alternative": 0}
	if left and right:
		return {"atlas": ROAD_ATLAS_HORIZONTAL, "alternative": 0}

	# Corner base tile connects EAST and SOUTH; alternatives cover the rest
	if right and down:
		return {"atlas": ROAD_ATLAS_CORNER, "alternative": CORNER_ALT_EAST_SOUTH}
	if left and down:
		return {"atlas": ROAD_ATLAS_CORNER, "alternative": CORNER_ALT_WEST_SOUTH}
	if right and up:
		return {"atlas": ROAD_ATLAS_CORNER, "alternative": CORNER_ALT_EAST_NORTH}
	if left and up:
		return {"atlas": ROAD_ATLAS_CORNER, "alternative": CORNER_ALT_WEST_NORTH}

	# Dead end: point the straight toward the single connection
	if up or down:
		return {"atlas": ROAD_ATLAS_VERTICAL, "alternative": 0}
	return {"atlas": ROAD_ATLAS_HORIZONTAL, "alternative": 0}


func place_structure_line(tiles: Array) -> void:
	if not building_layer:
		return
		
	for i in range(tiles.size()):
		var tile_pos = tiles[i]
		
		# Determine orientation context from neighbors within the line or existing map
		var data := get_texture_and_alternative_for_line(tiles, i)
		building_layer.set_cell(tile_pos, 0, data.atlas, data.alternative)
		track_placed_tile(tile_pos)


# Records road tiles so houses can be built along them later
func track_placed_tile(tile_position: Vector2i) -> void:
	if current_structure != Structure.ROAD:
		return
	if not road_tiles.has(tile_position):
		road_tiles.append(tile_position)


# Determines atlas coordinates and alternative tile flags (rotation/flip)
func get_texture_and_alternative(tile_position: Vector2) -> Dictionary:
	var atlas_coords := Vector2i.ZERO
	var alternative_tile := 0

	match current_structure:
		Structure.ROAD:
			return get_road_data(Vector2i(tile_position), [])
		Structure.RAIL:
			atlas_coords = RAIL_ATLAS
			if is_vertical_neighbor(Vector2i(tile_position)):
				alternative_tile = RAIL_ALT_VERTICAL
			else:
				alternative_tile = RAIL_ALT_HORIZONTAL
		Structure.STATION:
			atlas_coords = STATION_ATLAS

	return {"atlas": atlas_coords, "alternative": alternative_tile}


# Specialized check for batch/line placements to look at adjacent items in the drag array
func get_texture_and_alternative_for_line(tiles: Array, index: int) -> Dictionary:
	var tile_pos: Vector2i = tiles[index]
	var atlas_coords := Vector2i.ZERO
	var alternative_tile := 0

	match current_structure:
		Structure.ROAD:
			return get_road_data(tile_pos, tiles)
		Structure.RAIL:
			atlas_coords = RAIL_ATLAS

			# Determine direction from adjacent tiles in the dragged line
			var direction := Vector2i.ZERO
			if index > 0:
				direction = tile_pos - tiles[index - 1]
			elif tiles.size() > 1:
				direction = tiles[1] - tile_pos

			if direction.y != 0 and direction.x == 0:
				alternative_tile = RAIL_ALT_VERTICAL
			else:
				alternative_tile = RAIL_ALT_HORIZONTAL
		Structure.STATION:
			atlas_coords = STATION_ATLAS

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
	if selection_layer:
		selection_layer.clear()


func reset_drag() -> void:
	is_dragging = false
	drag_start_position = Vector2i.ZERO
	preview_tiles.clear()
	press_placed_tile = Vector2i(-999999, -999999)
	clear_preview()
