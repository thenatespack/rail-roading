extends Camera2D

@export var move_speed: float = 500.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 1.0
@export var max_zoom: float = 10.0
@export var zoom_smoothness: float = 8.0
var money: float = 100.0

signal display_settings

var target_zoom: Vector2

func _ready():
	target_zoom = zoom


func _process(delta):
	# Camera movement
	var direction = Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)

	if Input.is_key_pressed(KEY_A):
		direction.x -= 1
	if Input.is_key_pressed(KEY_D):
		direction.x += 1
	if Input.is_key_pressed(KEY_W):
		direction.y -= 1
	if Input.is_key_pressed(KEY_S):
		direction.y += 1

	if direction.length() > 0:
		position += direction.normalized() * move_speed * delta

	zoom = zoom.lerp(target_zoom, zoom_smoothness * delta)


func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change_zoom(zoom_speed)

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change_zoom(-zoom_speed)

	# Trackpad pinch gesture
	if event is InputEventMagnifyGesture:
		change_zoom(event.factor - 1.0)

	# Reset zoom
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_SPACE:
			target_zoom = Vector2.ONE + Vector2.ONE
		elif event.pressed and event.keycode == KEY_ESCAPE:
			emit_signal("display_settings")


func change_zoom(amount: float):
	var new_zoom = target_zoom + Vector2(amount, amount)
	new_zoom.x = clamp(new_zoom.x, min_zoom, max_zoom)
	new_zoom.y = clamp(new_zoom.y, min_zoom, max_zoom)
	target_zoom = new_zoom
