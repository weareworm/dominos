extends Camera3D

@export var speed: float = 5.0
@export var mouse_sensitivity: float = 0.12

var yaw := 0.0
var pitch := 0.0
var mouse_locked := true

func _ready():
	current = false # Start inactive until F1 pressed
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _unhandled_input(event):
	# Mouse look
	if event is InputEventMouseMotion and mouse_locked and current:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, -89.0, 89.0)
		rotation_degrees.x = pitch
		rotation_degrees.y = yaw

	# Toggle mouse lock with Esc
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE and current:
			mouse_locked = not mouse_locked
			Input.set_mouse_mode(
				Input.MOUSE_MODE_CAPTURED if mouse_locked else Input.MOUSE_MODE_VISIBLE
			)

		# Toggle debug camera with F1
		if event.keycode == KEY_F1:
			current = not current
			mouse_locked = current
			Input.set_mouse_mode(
				Input.MOUSE_MODE_CAPTURED if current else Input.MOUSE_MODE_VISIBLE
			)

func _process(delta: float) -> void:
	if not current:
		return

	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir.z -= 1
	if Input.is_action_pressed("move_back"):
		dir.z += 1
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1
	if Input.is_action_pressed("move_up"):
		dir.y += 1
	if Input.is_action_pressed("move_down"):
		dir.y -= 1

	if dir != Vector3.ZERO:
		translate_object_local(dir.normalized() * speed * delta)
