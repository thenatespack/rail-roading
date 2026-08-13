extends CanvasLayer

enum PlayerType { TA, DOT, BOTH }

enum BuildingType {ROAD, RAIL, STATION, TOLL, DEMOLISH, UPGRADE}

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
	if has_node("Control/VBoxContainer/HBoxContainer2/BalanceLabel"):
		$Control/VBoxContainer/HBoxContainer2/BalanceLabel.text = "Balance: $%.2f" % money


func update_time(text: String) -> void:
	if has_node("Control/VBoxContainer/HBoxContainer2/TimeLabel"):
		$Control/VBoxContainer/HBoxContainer2/TimeLabel.text = text


func update_population(population: int, pct_change: float = 0.0) -> void:
	var text := "Population: %d (%.1f%%)" % [population, pct_change]
	$Debug/VBoxContainer/PopulationLabel.text = text
	if has_node("Control/VBoxContainer/HBoxContainer2/PopulationLabel"):
		$Control/VBoxContainer/HBoxContainer2/PopulationLabel.text = "Population: %d (%.1f%%)" % [population, pct_change]


func _on_roads_button_pressed() -> void:
	emit_signal("build_time",BuildingType.ROAD)


func _on_tracks_button_pressed() -> void:
	emit_signal("build_time",BuildingType.RAIL)


func _on_stations_button_pressed() -> void:
	emit_signal("build_time",BuildingType.STATION)


func _on_toll_button_pressed() -> void:
	emit_signal("build_time",BuildingType.TOLL)


func update_toll_income(income: float, traffic: int) -> void:
	if has_node("Control/VBoxContainer/HBoxContainer2/IncomeLabel"):
		$Control/VBoxContainer/HBoxContainer2/IncomeLabel.text = "Income: +$%.2f" % income
	if has_node("Debug/VBoxContainer/TollLabel"):
		$Debug/VBoxContainer/TollLabel.text = "Tolls: %d trips, +$%.2f" % [traffic, income]


func update_expenses(expense: float) -> void:
	if has_node("Control/VBoxContainer/HBoxContainer2/ExpensesLabel"):
		$Control/VBoxContainer/HBoxContainer2/ExpensesLabel.text = "Expenses: -$%.2f" % expense


func _on_remove_button_pressed() -> void:
	emit_signal("build_time", BuildingType.DEMOLISH)


func _on_upgrade_button_pressed() -> void:
	emit_signal("build_time", BuildingType.UPGRADE)
