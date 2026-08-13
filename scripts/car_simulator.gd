extends Node2D

## Commuter car traffic. Cars spawn on a road next to a housing building and
## drive to a commercial building, then back home, following the road network.
## Body colors come from a shader tint; the number of cars on the road scales
## with total city population and the time of day (rush hours + night lull).

const CARSHEET := "res://assets/art/carsheet.png"
const CAR_SHADER := "res://assets/shaders/car.gdshader"

const TILE_SIZE := 16.0

const MAX_CARS := 50
const SPAWN_TICK := 0.5
const MOVE_SPEED := 3.5
const MIN_LIFETIME := 15.0
const MAX_LIFETIME := 40.0
const CAR_FRAMES := 4

const ROAD_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT
]

# Everything on source 0 of the infrastructure layer that is a road.
const ROAD_ATLAS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
	Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1),
	Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3),
	Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3),
]

# Building sources on the housing layer: homes and workplaces for commutes.
const HOUSING_SOURCES: Array[int] = [0, 3, 6]
const COMMERCIAL_SOURCES: Array[int] = [1, 4, 7]

# Distinct, high-chroma body colors (the shader keeps them vivid).
const BODY_COLORS: Array[Color] = [
	Color(0.93, 0.10, 0.16),  # vivid red
	Color(0.10, 0.40, 0.95),  # vivid blue
	Color(0.08, 0.72, 0.22),  # vivid green
	Color(1.00, 0.78, 0.00),  # yellow
	Color(1.00, 0.40, 0.00),  # orange
	Color(0.62, 0.10, 0.90),  # purple
	Color(0.00, 0.80, 0.78),  # cyan
	Color(0.95, 0.20, 0.55),  # pink
	Color(0.95, 0.95, 0.90),  # white
	Color(0.20, 0.20, 0.22),  # black
	Color(0.60, 0.60, 0.64),  # silver
]

@export var building_layer: TileMapLayer
@export var housing_layer: TileMapLayer

var _carsheet: Texture2D
var _shader: Shader
var _spawn_timer := 0.0
var _cars: Array[Dictionary] = []
var _home_roads: Array[Vector2i] = []
var _work_roads: Array[Vector2i] = []
var _zone_refresh := 0


func _ready() -> void:
	_carsheet = load(CARSHEET) as Texture2D
	_shader = load(CAR_SHADER) as Shader
	if building_layer == null:
		building_layer = get_node_or_null("../Infastructure") as TileMapLayer
	if housing_layer == null:
		housing_layer = get_node_or_null("../Structures") as TileMapLayer


func _process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_TICK
		maybe_spawn()
	_update_cars(delta)


func _game_minutes() -> int:
	var parent := get_parent()
	if parent:
		return int(parent.call("get_game_minutes_of_day"))
	return 12 * 60


func _total_population() -> int:
	var parent := get_parent()
	if parent:
		return int(parent.call("get_total_population"))
	return 0


## How many cars should be cruising right now, from population + time of day.
func _target_cars() -> int:
	var f := traffic_factor()
	return clampi(int(round((3.0 + float(_total_population()) / 20.0) * f)), 0, MAX_CARS)


## Time-of-day traffic multiplier, 0.02..1.2. Roads empty out in the dead of night.
func traffic_factor() -> float:
	var hour := float(_game_minutes()) / 60.0
	var f := 0.34
	f += 0.50 * exp(-pow((hour - 8.0) / 2.2, 2.0))    # morning rush
	f += 0.55 * exp(-pow((hour - 17.0) / 2.2, 2.0))   # evening rush
	f += 0.15 * exp(-pow((hour - 12.5) / 2.5, 2.0))   # midday bump
	if hour >= 23.0 or hour < 4.0:
		f *= 0.03                                      # dead of night: almost none
	elif hour >= 21.0 or hour < 6.0:
		f *= 0.45                                      # edges of the night
	return clampf(f, 0.02, 1.2)


func maybe_spawn() -> void:
	if _cars.size() >= _target_cars() or _cars.size() >= MAX_CARS:
		return
	_refresh_zone_roads_if_needed()
	if _home_roads.is_empty() or _work_roads.is_empty():
		return
	for attempt in range(4):
		var home: Vector2i = _home_roads[randi() % _home_roads.size()]
		var work: Vector2i = _work_roads[randi() % _work_roads.size()]
		var path := _find_path(home, work)
		if path.size() >= 2:
			_spawn_car(path)
			return


func _refresh_zone_roads_if_needed() -> void:
	_zone_refresh -= 1
	if _zone_refresh > 0:
		return
	_zone_refresh = 20
	_home_roads = _collect_zone_roads(HOUSING_SOURCES)
	_work_roads = _collect_zone_roads(COMMERCIAL_SOURCES)


## Road tiles adjacent to any building using one of the given sources.
func _collect_zone_roads(sources: Array[int]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if housing_layer == null:
		return result
	for cell in housing_layer.get_used_cells():
		if not (housing_layer.get_cell_source_id(cell) in sources):
			continue
		for direction in ROAD_DIRECTIONS:
			var neighbor := cell + direction
			if _is_road(neighbor) and not result.has(neighbor):
				result.append(neighbor)
	return result


func _is_road(tile: Vector2i) -> bool:
	if building_layer == null or building_layer.get_cell_source_id(tile) != 0:
		return false
	return building_layer.get_cell_atlas_coords(tile) in ROAD_ATLAS


## BFS over the road grid. Returns the shortest road path start..goal, or [].
func _find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if start == goal:
		return [start]
	var prev := {start: start}
	var visited := {start: true}
	var queue: Array[Vector2i] = [start]
	var explored := 0
	while not queue.is_empty() and explored < 4000:
		explored += 1
		var current: Vector2i = queue.pop_front()
		if current == goal:
			break
		for direction in ROAD_DIRECTIONS:
			var neighbor := current + direction
			if visited.has(neighbor) or not _is_road(neighbor):
				continue
			visited[neighbor] = true
			prev[neighbor] = current
			queue.append(neighbor)
	if not visited.has(goal):
		return []
	var path: Array[Vector2i] = [goal]
	var node: Vector2i = goal
	while node != start:
		node = prev[node]
		path.push_front(node)
	return path


func _spawn_car(path: Array[Vector2i]) -> void:
	var car := {
		"sprite": _make_sprite(),
		"path": path,
		"path_index": 0,
		"progress": 0.0,
		"speed": MOVE_SPEED * randf_range(0.85, 1.15),
		"lifetime": randf_range(MIN_LIFETIME, MAX_LIFETIME),
		"legs": 0,
	}
	_cars.append(car)
	_update_sprite_transform(car)


func _make_sprite() -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _carsheet
	sprite.hframes = CAR_FRAMES
	sprite.frame = randi() % CAR_FRAMES
	sprite.z_index = 5

	var material := ShaderMaterial.new()
	material.shader = _shader
	var color: Color = BODY_COLORS[randi() % BODY_COLORS.size()]
	color = color * randf_range(0.95, 1.05)
	material.set_shader_parameter("tint", color)
	sprite.material = material

	add_child(sprite)
	return sprite


func _update_sprite_transform(car: Dictionary) -> void:
	var path: Array = car["path"]
	if path.is_empty():
		return
	var idx: int = clampi(car["path_index"], 0, path.size() - 1)
	var from: Vector2i = path[idx]
	var to: Vector2i = path[min(idx + 1, path.size() - 1)]
	var t: float = car["progress"]
	var pos := (Vector2(from) + (Vector2(to) - Vector2(from)) * t) * TILE_SIZE \
		+ Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)

	var rotation := 0.0
	var direction := to - from
	if direction == Vector2i.DOWN:
		rotation = PI
	elif direction == Vector2i.LEFT:
		rotation = -PI / 2.0
	elif direction == Vector2i.RIGHT:
		rotation = PI / 2.0

	var sprite: Sprite2D = car["sprite"]
	sprite.position = pos
	sprite.rotation = rotation


func _update_cars(delta: float) -> void:
	if _cars.is_empty():
		return
	var target := _target_cars()
	var remove := []
	for car in _cars:
		car["lifetime"] -= delta
		car["progress"] += car["speed"] * delta

		var path: Array = car["path"]
		var idx: int = car["path_index"]
		var done := false
		while car["progress"] >= 1.0:
			car["progress"] -= 1.0
			if idx >= path.size() - 1:
				car["legs"] += 1
				if int(car["legs"]) >= 2:
					done = true
					break
				path.reverse()
				idx = 0
			else:
				idx += 1
		if done:
			remove.append(car)
			continue
		car["path_index"] = idx

		var tile_for_check: Vector2i = path[idx]
		var dead: bool = car["lifetime"] <= 0.0
		if not dead:
			# Retire mature cars early when traffic has died down.
			if _cars.size() > target and car["lifetime"] < 5.0:
				dead = true
			if building_layer != null and not _is_road(tile_for_check):
				dead = true
		if dead:
			remove.append(car)
			continue

		_update_sprite_transform(car)

	for car in remove:
		_cars.erase(car)
		var sprite: Node = car.get("sprite")
		if sprite and is_instance_valid(sprite):
			sprite.queue_free()