extends Node
class_name DominoFactory

# Load the domino scene
const DOMINO_SCENE = preload("res://scenes/domino.tscn")

func create_random_domino() -> Node:
	var top_value = randi() % 6  # Values 0-6
	var bottom_value = randi() % 6
	return create_specific_domino(top_value, bottom_value)

func create_specific_domino(top: int, bottom: int) -> Node:
	var new_domino = DOMINO_SCENE.instantiate()
	
	# Set domino values
	new_domino.top_value = top
	new_domino.bottom_value = bottom
	
	# Initialize domino state
	new_domino.display_top = true
	new_domino.is_in_hand = true
	new_domino.freeze = true
	
	# Call this if you have a visual update function
	if new_domino.has_method("_update_all_dots"):
		new_domino._update_all_dots()
	
	return new_domino
