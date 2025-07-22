extends CanvasLayer

signal pass_turn_requested

func _ready():
	var button = $PassButton
	if button:
		# Disconnect first to prevent duplicates
		if button.pressed.is_connected(_on_pass_button_pressed):
			button.pressed.disconnect(_on_pass_button_pressed)
		button.pressed.connect(_on_pass_button_pressed)

func _on_pass_button_pressed():
	emit_signal("pass_turn_requested")

func update_button_state():
	var button = $PassButton
	if button:
		# Only enable if in discard mode AND has selection
		var should_enable = get_parent().is_discard_mode and get_parent().discard_candidate != null
		button.disabled = !should_enable
		button.text = "CONFIRM DISCARD" if get_parent().is_discard_mode else "DISCARD DOMINO"
