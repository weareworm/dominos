extends RigidBody3D
class_name Domino

# ======================
# SIGNALS
# ======================
signal domino_selected(domino)
signal domino_deselected

# ======================
# CONSTANTS
# ======================
const DOMINO_WIDTH = 0.16
const DOMINO_HEIGHT = 0.32
const DOMINO_THICKNESS = 0.055
const HAND_MASS = 0.5
const BOARD_MASS = 1.0
const BOUNCE = 0.1
const FRICTION = 0.8
const HIGHLIGHT_EXTRA_WIDTH = 0.04
const HIGHLIGHT_WIDTH = DOMINO_WIDTH + HIGHLIGHT_EXTRA_WIDTH
const HIGHLIGHT_HEIGHT = DOMINO_HEIGHT + 0.04
const HIGHLIGHT_THICKNESS = 0.001
const HIGHLIGHT_Z_OFFSET = DOMINO_THICKNESS/2 + 0.002
const DOT_RADIUS = 0.022
const DOT_HEIGHT = 0.035
const DOT_Z_OFFSET = DOMINO_THICKNESS/2 - 0.003
const DOT_POSITIONS = {
	1: Vector2(0, 0),
	2: Vector2(-0.03, 0.04),
	3: Vector2(0.03, 0.04),
	4: Vector2(-0.03, 0),
	5: Vector2(0.03, 0),
	6: Vector2(-0.03, -0.04),
	7: Vector2(0.03, -0.04)
}

# ======================
# EXPORTED VARIABLES
# ======================
@export_range(0, 6) var top_value := 1:
	set(value):
		top_value = clamp(value, 0, 6)
		if is_inside_tree():
			call_deferred("_update_top_dots")

@export_range(0, 6) var bottom_value := 1:
	set(value):
		bottom_value = clamp(value, 0, 6)
		if is_inside_tree():
			call_deferred("_update_bottom_dots")

@export var debug_visible := false

# ======================
# STATE VARIABLES
# ======================
var is_selected := false
var highlight_mesh: MeshInstance3D
var is_in_hand := true
var initial_position := Vector3.ZERO
var is_selecting := false
var top_label: Label3D
var bottom_label: Label3D
# Add this new variable to track visual flip state
var is_flipped := false:
	set(value):
		is_flipped = value
		_update_all_dots()  # Refresh dot display when flipped
var display_top := true  # True = showing top_value, False = showing bottom_value
# ======================
# CORE FUNCTIONS
# ======================
func _ready():
	initial_position = global_position
	contact_monitor = true
	max_contacts_reported = 5
	_setup_physics()
	_setup_highlight()
	_setup_domino_visuals()
	_update_all_dots()
	
	if debug_visible:
		_setup_debug_labels()
	
	print("Domino created with values: %d (top), %d (bottom)" % [top_value, bottom_value])
	input_ray_pickable = true
	_setup_input()

func _physics_process(_delta: float):
	if is_selected:
		global_position.y = initial_position.y + 0.3

func _setup_debug_labels():
	top_label = Label3D.new()
	top_label.text = str(top_value)
	top_label.font_size = 16
	top_label.pixel_size = 0.01
	top_label.position = Vector3(0, DOMINO_HEIGHT/2 + 0.02, DOMINO_THICKNESS/2 + 0.001)
	add_child(top_label)
	
	bottom_label = Label3D.new()
	bottom_label.text = str(bottom_value)
	bottom_label.font_size = 16
	bottom_label.pixel_size = 0.01
	bottom_label.position = Vector3(0, -DOMINO_HEIGHT/2 - 0.02, DOMINO_THICKNESS/2 + 0.001)
	add_child(bottom_label)

# ======================
# SETUP FUNCTIONS
# ======================
func _setup_physics():
	var material = PhysicsMaterial.new()
	material.bounce = BOUNCE
	material.friction = FRICTION
	physics_material_override = material
	
	mass = HAND_MASS if is_in_hand else BOARD_MASS
	freeze = is_in_hand
	continuous_cd = true
	collision_layer = 0b10 if is_in_hand else 0b01
	collision_mask = collision_layer

func _setup_highlight():
	if has_node("HighlightMesh"):
		$HighlightMesh.queue_free()
	
	highlight_mesh = MeshInstance3D.new()
	highlight_mesh.name = "HighlightMesh"
	
	var box = BoxMesh.new()
	# Make highlight flat (Y is up in Godot, so we want Z to be thickness)
	box.size = Vector3(HIGHLIGHT_WIDTH, HIGHLIGHT_HEIGHT, 0.001)  # Thin in Z-axis
	
	highlight_mesh.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.8, 0.2, 0.6)
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	highlight_mesh.set_surface_override_material(0, mat)
	
	# Position and rotate to lie flat on domino
	highlight_mesh.position = Vector3(0, 0, DOMINO_THICKNESS/2 + 0.001)
	highlight_mesh.rotation_degrees = Vector3(90, 0, 0)  # Rotate to lie flat
	
	add_child(highlight_mesh)
	highlight_mesh.owner = get_tree().edited_scene_root
	highlight_mesh.visible = false

# ======================
# VISUAL FUNCTIONS
# ======================
func _setup_domino_visuals():
	var mesh = $MeshInstance3D
	mesh.mesh.size = Vector3(DOMINO_WIDTH, DOMINO_HEIGHT, DOMINO_THICKNESS)
	
	for side in ["TopDots", "BottomDots"]:
		if not has_node(side):
			continue
			
		var dots_node = get_node(side)
		for i in range(1, 8):
			var dot_name = "Dot%d" % i
			var dot = _get_or_create_dot(dots_node, dot_name)
			var pos = DOT_POSITIONS[i]
			dot.position = Vector3(pos.x, pos.y, DOT_Z_OFFSET)
			_setup_dot_appearance(dot)

func _process(_delta):
	if Input.is_key_pressed(KEY_V):
		print("Current Visual: %d-%d | Rotation: %s" % [
			top_value if display_top else bottom_value,
			bottom_value if display_top else top_value,
			str(rotation_degrees)
		])

		
func get_visual_values() -> String:
	return "Visual: %d-%d | Logical: %d-%d" % [
		bottom_value, top_value,  # Inverted!
		top_value, bottom_value
	]

func get_visual_representation() -> String:
	return "%d-%d (Rotation: %s)" % [
		top_value if display_top else bottom_value,
		bottom_value if display_top else top_value,
		str(rotation_degrees)
	]

# Modified dot update functions
func _update_top_dots():
	if has_node("TopDots"):
		_update_dots_for_value($TopDots, bottom_value if display_top else top_value)

func _update_bottom_dots():
	if has_node("BottomDots"):
		_update_dots_for_value($BottomDots, top_value if display_top else bottom_value)

func _update_all_dots():
	_update_top_dots()
	_update_bottom_dots()

func _update_dots_for_value(dots_node: Node3D, value: int):
	for i in range(1, 8):
		var dot = dots_node.get_node("Dot%d" % i) as MeshInstance3D
		if is_instance_valid(dot):
			dot.visible = false

	match value:
		1: _show_dot(dots_node, 1)
		2: _show_dots(dots_node, [2, 7])
		3: _show_dots(dots_node, [2, 1, 7])
		4: _show_dots(dots_node, [2, 3, 6, 7])
		5: _show_dots(dots_node, [2, 3, 1, 6, 7])
		6: _show_dots(dots_node, range(2, 8))

func flip():
	"""Flip the domino visually without changing values"""
	is_flipped = !is_flipped
	var tween = create_tween()
	tween.tween_property(self, "rotation_degrees:x", 270, 0.1)
	tween.tween_property(self, "rotation_degrees:x", 90, 0.1)

func flip_display():
	"""Flip which side is visually showing without changing values"""
	display_top = !display_top
	rotation_degrees.y = 180 if !display_top else 0
	_update_all_dots()

# ======================
# INPUT HANDLING
# ======================
func _setup_input():
	if input_event.is_connected(_on_input_event):
		input_event.disconnect(_on_input_event)
	
	var err = input_event.connect(_on_input_event)
	if err != OK:
		push_error("Failed to connect input_event signal: ", err)

func _on_input_event(_camera: Node, event: InputEvent, click_position: Vector3, _normal: Vector3, _shape_idx: int):
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or \
		(event is InputEventScreenTouch and event.pressed):
			print("Domino clicked: ", top_value, "-", bottom_value)
			if is_selected:
				deselect()
				emit_signal("domino_deselected")
			else:
				select()
				emit_signal("domino_selected", self)
				if is_in_hand:
					global_position = click_position + Vector3(0, 0.2, 0)

# ======================
# SELECTION LOGIC
# ======================
func select():
	if is_selecting:
		return
	is_selecting = true
	is_selected = true
	freeze = false
	global_position.y += 0
	if highlight_mesh:
		highlight_mesh.visible = true
	is_selecting = false

func deselect():
	is_selected = false
	freeze = true
	if highlight_mesh:
		highlight_mesh.visible = false

# ======================
# GAMEPLAY FUNCTIONS
# ======================
func place_on_board():
	is_in_hand = false
	freeze = false
	collision_layer = 0b01
	collision_mask = 0b01
	mass = BOARD_MASS

# ======================
# HELPER FUNCTIONS
# ======================
func _get_or_create_dot(parent: Node3D, dot_name: String) -> MeshInstance3D:
	if parent.has_node(dot_name):
		return parent.get_node(dot_name)
	
	var dot = MeshInstance3D.new()
	dot.name = dot_name
	parent.add_child(dot)
	dot.owner = get_tree().edited_scene_root
	return dot

func get_connecting_value() -> int:
	"""Returns the value that should connect to other dominos"""
	return top_value if display_top else bottom_value

func _setup_dot_appearance(dot: MeshInstance3D):
	if dot.mesh == null:
		var sphere = SphereMesh.new()
		sphere.radius = DOT_RADIUS
		sphere.height = DOT_HEIGHT
		dot.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0, 0, 0)
	dot.set_surface_override_material(0, mat)
	dot.visible = false

func _show_dots(dots_node: Node3D, dot_indices: Array):
	for i in dot_indices:
		_show_dot(dots_node, i)

func _show_dot(dots_node: Node3D, dot_num: int):
	var dot = dots_node.get_node("Dot%d" % dot_num) as MeshInstance3D
	if is_instance_valid(dot):
		dot.visible = true
		
func get_visible_side() -> int:
	"""Returns the value currently facing up"""
	return bottom_value if is_flipped else top_value
