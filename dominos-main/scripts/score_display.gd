extends CanvasLayer
signal pass_turn_requested

func _ready():
	var button = $PassButton
	if button:
		button.pressed.connect(_on_button_pressed)

func _on_button_pressed():
	emit_signal("pass_turn_requested")
