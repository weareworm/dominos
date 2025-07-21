# pass_button.gd
extends Button

@export var disabled_tooltip := "You have valid moves available"
@export var enabled_tooltip := "No valid moves - pass your turn"

func _ready():
	mouse_entered.connect(_on_hover)

func _on_hover():
	if disabled:
		tooltip_text = disabled_tooltip
	else:
		tooltip_text = enabled_tooltip
