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
	TileType.WATER: Vector2i(3,0),
	TileType.SAND: Vector2i(0,2),
	TileType.GRASS: Vector2i(1,2),
	TileType.FOREST: Vector2i(1,1),
	TileType.MOUNTAIN: Vector2i(2,0)
}

class City:
	var position: Vector2i
	var population: int

	func _init(pos:Vector2i, pop:int):
		position = pos
		population = pop

var chunk_size: Vector2i
var seed_value: int

var elevation_noise := FastNoiseLite.new()
var moisture_noise := FastNoiseLite.new()
var temperature_noise := FastNoiseLite.new()


func _init(size:Vector2i, map_seed:int):
	chunk_size = size
	seed_value = map_seed
	setup_noise()


func setup_noise():
	var noises = [
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


func generate(player_position:Vector2i) -> Array:
	var map := []
	var start_x = player_position.x - chunk_size.x / 2.0
	var start_y = player_position.y - chunk_size.y / 2.0
	for x in range(chunk_size.x):
		var column := []
		for y in range(chunk_size.y):
			var world_x = start_x + x
			var world_y = start_y + y
			column.append(get_tile(world_x, world_y))
		map.append(column)
	return map


func get_tile(world_x:int, world_y:int)->TileType:
	var elevation = get_elevation(world_x, world_y)
	var moisture = moisture_noise.get_noise_2d(world_x, world_y)
	if elevation < -0.25:
		return TileType.WATER
	if elevation < -0.05:
		return TileType.SAND
	if elevation > 0.55:
		return TileType.MOUNTAIN
	if moisture > 0.35:
		return TileType.FOREST
	return TileType.GRASS


func get_elevation(x:int,y:int)->float:
	var value = elevation_noise.get_noise_2d(x,y)
	var coast_mask = float(x) / 1000.0
	if coast_mask < 0.2:
		var ocean_strength = (0.2 - coast_mask) / 0.2
		value -= ocean_strength * 0.35
	return value


func get_atlas_position(tile:TileType)->Vector2i:
	return TILE_ATLAS[tile]


func get_cities(amount:int) -> Array[City]:
	var cities:Array[City] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var attempts = 0
	var max_attempts = amount * 500
	while cities.size() < amount and attempts < max_attempts:
		attempts += 1
		var x = rng.randi_range(-500,500)
		var y = rng.randi_range(-500,500)
		var position = Vector2i(x,y)
		if can_place_city(position,cities):
			var population = rng.randi_range(1000,20000)
			cities.append(City.new(position,population))
	return cities


func can_place_city(position:Vector2i, cities:Array)->bool:
	var tile = get_tile(position.x,position.y)
	if tile != TileType.GRASS and tile != TileType.FOREST:
		return false
	for city in cities:
		if city.position.distance_to(position) < 75:
			return false
	return true

func costModifier(x:int,y:int)->float:
	var tile = get_tile(x,y)
	
	match tile:
		TileType.GRASS:
			return 0.5
		TileType.FOREST:
			return 1.0
		TileType.SAND:
			return 1.25
		TileType.MOUNTAIN:
			return 2.0
		TileType.WATER:
			return 2.0
	
	return 1.0
