extends CanvasLayer

@onready var winner_label: Label = get_node("CenterContainer/VBoxContainer/WinnerLabel")
@onready var restart_button: Button = get_node("CenterContainer/VBoxContainer/RestartButton")

func _ready():
	# Safety check - print node tree if there's issues
	if not winner_label or not restart_button:
		print_tree_pretty()
		push_error("Game Over Screen: Missing required nodes!")
		return
	
	restart_button.pressed.connect(_on_restart_pressed)

func set_winner(winner: String):
	if winner_label:
		winner_label.text = "Player Wins!" if winner == "player" else "AI Wins!"
	else:
		push_error("WinnerLabel reference is missing!")

func _on_restart_pressed():
	get_tree().reload_current_scene()
