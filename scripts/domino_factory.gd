extends Node
class_name DominoFactory

### CONSTANTS ###
const DOMINO_SCENE = preload("res://scenes/domino.tscn")

### PUBLIC METHODS ###

# Creates a domino with random values (0-6)
func create_random_domino() -> Node:
	if get_parent().domino_pool.size() == 0:
		push_error("FACTORY ERROR: Empty pool when creating random domino")
		return null
	
	var top_value = randi() % 7  # Values 0-6
	var bottom_value = randi() % 7
	return _create_domino_instance(top_value, bottom_value)

# Creates a domino with specific values
func create_specific_domino(top: int, bottom: int) -> Node:
	return _create_domino_instance(top, bottom)

### PRIVATE METHODS ###

# Internal domino creation logic
func _create_domino_instance(top: int, bottom: int) -> Node:
	var new_domino = DOMINO_SCENE.instantiate()
	
	_set_domino_values(new_domino, top, bottom)
	_initialize_domino_state(new_domino)
	_update_domino_visuals(new_domino)
	
	return new_domino

# Sets the numerical values of the domino
func _set_domino_values(domino: Node, top: int, bottom: int):
	domino.top_value = top
	domino.bottom_value = bottom

# Initializes the physical state of the domino
func _initialize_domino_state(domino: Node):
	domino.display_top = true
	domino.is_in_hand = true
	domino.freeze = true

# Updates the visual representation
func _update_domino_visuals(domino: Node):
	if domino.has_method("_update_all_dots"):
		domino._update_all_dots()
