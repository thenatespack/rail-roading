extends CanvasLayer

enum PlayerType { TA, DOT, BOTH }

enum BuildingType {ROAD, RAIL, STATION}

@export var player_type: PlayerType = PlayerType.BOTH

signal build_time

func _ready() -> void:
	filter_player_ui()


func filter_player_ui() -> void:
	var show_ta := player_type == PlayerType.TA or player_type == PlayerType.BOTH
	var show_dot := player_type == PlayerType.DOT or player_type == PlayerType.BOTH

	for node in get_tree().get_nodes_in_group("TA"):
		if node is CanvasItem:
			node.visible = show_ta

	for node in get_tree().get_nodes_in_group("DOT"):
		if node is CanvasItem:
			node.visible = show_dot

func _process(_delta: float) -> void:
	var fps = Engine.get_frames_per_second();
	$Debug/VBoxContainer/FPS.text ="FPS: "+ str(fps)
	var max_memory = Performance.get_monitor(Performance.MEMORY_STATIC)
	$Debug/VBoxContainer/Ram_Usage.text = "RAM: %.2f MB" % (max_memory / 1024.0 / 1024.0)

func update_money(money: float):
	$Debug/VBoxContainer/Money.text ="Money: $"+ str(money)


func _on_roads_button_pressed() -> void:
	emit_signal("build_time",BuildingType.ROAD)


func _on_tracks_button_pressed() -> void:
	emit_signal("build_time",BuildingType.RAIL)


func _on_stations_button_pressed() -> void:
	emit_signal("build_time",BuildingType.STATION)
