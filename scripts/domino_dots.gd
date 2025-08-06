extends Node3D

### DOTS MANAGEMENT ###

# Updates the visible dots based on the domino value
func update_dots(value: int):
	print("\n--- UPDATING DOTS TO VALUE ", value, " ---")
	
	# Get all dot nodes in order
	var dots = _get_ordered_dots()
	if dots.size() != 6:
		push_error("Incorrect number of dots! Found: ", dots.size())
		return
	
	_debug_print_dots(dots)
	_hide_all_dots(dots)
	_show_correct_pattern(value, dots)

# Returns an ordered array of all dot nodes
func _get_ordered_dots() -> Array:
	var dots = []
	for i in range(1, 7):
		var dot = get_node_or_null("Dot"+str(i))
		if dot:
			dots.append(dot)
		else:
			push_error("Missing Dot", i)
	return dots

### VISIBILITY CONTROL ###

# Hides all dots
func _hide_all_dots(dots: Array):
	for dot in dots:
		dot.visible = false

# Shows dots based on the value pattern
func _show_correct_pattern(value: int, dots: Array):
	match value:
		1: _set_visible(dots, [4])       # Center (Dot5)
		2: _set_visible(dots, [0, 5])    # Diagonal (Dot1 & Dot6)
		3: _set_visible(dots, [0, 4, 5]) # Diagonal + center
		4: _set_visible(dots, [0, 2, 3, 5]) # Corners
		5: _set_visible(dots, [0, 2, 3, 4, 5]) # Corners + center
		6: _set_visible(dots, range(6))   # All dots
		_: push_error("Invalid value: ", value)

# Sets visibility for specific dot indices
func _set_visible(dots: Array, indices: Array):
	for idx in indices:
		if idx < dots.size():
			dots[idx].visible = true
			print("Showing ", dots[idx].name)
		else:
			push_error("Invalid index: ", idx)

### DEBUG UTILITIES ###

# Prints debug information about dots
func _debug_print_dots(dots: Array):
	for i in dots.size():
		print("Dot", i+1, ": ", dots[i].name, " at ", dots[i].global_transform.origin)
