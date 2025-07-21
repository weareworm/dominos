extends Camera3D

func _ready():
	# Position camera for debug view
	self.position = Vector3(0, 2, 3)
	self.look_at(Vector3.ZERO)
	self.make_current()
	
	# Debug view settings
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_OVERDRAW
