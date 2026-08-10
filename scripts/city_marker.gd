class_name CityMarker
extends Node2D

@onready var circle_visual: ColorRect = $CircleVisual
@onready var name_label: Label = $NameLabel

var city_name: String
var population: int

const MIN_HEART_RADIUS := 0.05
const MAX_HEART_RADIUS := 0.25
const INFLUENCE_MULTIPLIER := 3.5 # Area of influence is 3.5x the heart radius

func setup(name: String, pop: int) -> void:
	city_name = name
	population = pop
	name_label.text = "%s\nPop: %d" % [city_name, population]
	var pop_factor = inverse_lerp(0, 20000, population)
	
	var target_heart_radius = lerp(MIN_HEART_RADIUS, MAX_HEART_RADIUS, pop_factor)
	var target_influence_radius = target_heart_radius * INFLUENCE_MULTIPLIER
	
	target_influence_radius = minf(target_influence_radius, 0.9)
	
	var material := circle_visual.material as ShaderMaterial
	if material:
		material.set_shader_parameter("heart_radius", target_heart_radius)
		material.set_shader_parameter("influence_radius", target_influence_radius)
		
	var marker_size = Vector2(256, 256) 
	circle_visual.size = marker_size
	circle_visual.position = -marker_size / 2.0
