class_name CityMarker
extends Node2D

@onready var circle_visual: ColorRect = $CircleVisual
@onready var name_label: Label = $NameLabel

const BASE_MARKER_SIZE := 256.0

var city_name: String
var population: int
var zone_seed: int
var cell_size: int
var level: int = 0
var _material: ShaderMaterial

func setup(name: String, pop: int, zone_seed: int = 2, cell_size: int = 4) -> void:
	city_name = name
	population = pop
	self.zone_seed = zone_seed
	self.cell_size = cell_size
	
	# Duplicate the material so each city gets its own shader parameters
	circle_visual.material = circle_visual.material.duplicate()
	_material = circle_visual.material as ShaderMaterial
	
	apply_marker_size()
	refresh()


## Updates the city's live population and density level, then redraws.
func update_population(pop: int, level: int = 0) -> void:
	population = pop
	self.level = level
	refresh()


## Sizes the marker rect from the population so the physical circle grows (or
## shrinks) with the city's development.
func apply_marker_size() -> void:
	var marker_size := Vector2(BASE_MARKER_SIZE, BASE_MARKER_SIZE) * MapGenerator.get_marker_scale(population)
	circle_visual.size = marker_size
	circle_visual.position = -marker_size / 2.0


## Recomputes the label and shader radii from the current population, so the
## circles grow (or shrink) live as the city develops.
func refresh() -> void:
	name_label.text = "%s\nPop: %d\nLv %d" % [city_name, population, level + 1]
	apply_marker_size()
	if _material:
		_material.set_shader_parameter("heart_radius", MapGenerator.get_heart_radius(population))
		_material.set_shader_parameter("influence_radius", MapGenerator.get_influence_radius(population))
		# Per-city seed + fixed district size keep the zone pattern stable
		_material.set_shader_parameter("zone_seed_i", zone_seed)
		_material.set_shader_parameter("cell_size", cell_size)
