extends CanvasLayer

@export var winner_label: Label
@export var restart_button: Button

func _ready():
	# Wait until next frame to ensure nodes are ready
	await get_tree().process_frame
	if not winner_label:
		winner_label = $VBoxContainer/WinnerLabel
	if not restart_button:
		restart_button = $VBoxContainer/RestartButton
	
	restart_button.pressed.connect(_on_restart_button_pressed)

func set_winner(winner: String):
	if winner_label:
		winner_label.text = "Player Wins!" if winner == "player" else "AI Wins!"
	else:
		push_error("Winner label not found!")

func _on_restart_button_pressed():
	var board = get_parent() as DominoGameBoard
	if board:
		board.restart_game()
	queue_free()
