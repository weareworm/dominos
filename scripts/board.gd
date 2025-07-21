extends Node3D
class_name DominoGameBoard

### CONSTANTS
const FACTORY_SCRIPT = preload("res://scripts/domino_factory.gd")
const TRACK_COUNT := 3
const TRACK_LENGTH := 9
const HAND_SPACING := 0.5
const MAX_HAND_SIZE := 5

### NODE REFERENCES
var domino_factory: DominoFactory
var selected_domino: Domino = null

### GAME STATE
var tracks := []
var player_hand := []
var is_processing_selection := false
var domino_pool: Array = []
var player_score := 0  # Add this
var ai_score := 0      # Add this
@onready var score_ui: CanvasLayer = null
var ai_hand := []
var current_turn: String = "player"

var is_discard_mode := false
var discard_candidate: Domino = null

func _ready():
	_initialize_game()
	_initialize_score_ui()
	update_scores(0,0)
	current_turn = "player"  # Ensure player starts first
	update_turn_indicator()  # Add this function (shown below)

### INITIALIZATION
func _initialize_game():
	_initialize_factory()
	_setup_camera()
	_initialize_tracks()
	initialize_domino_pool()
	spawn_starting_dominos()
	draw_initial_hand()
	player_score = 0  # Reset scores
	ai_score = 0
	update_scores(0, 0)  # Initialize display

func _initialize_factory():
	domino_factory = FACTORY_SCRIPT.new()
	add_child(domino_factory)

func _setup_camera():
	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.position = Vector3(0, 10, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	add_child(camera)
	camera.make_current()

func initialize_domino_pool():
	domino_pool.clear()
	for i in range(7):
		for j in range(i, 7):
			domino_pool.append([i, j])
	domino_pool.shuffle()

func _initialize_tracks():
	for i in TRACK_COUNT:
		var track_node = get_node("Track%d" % (i+1))
		track_node.position.z = -2.0
		var static_body = _create_track_collision(track_node)
		
		var positions = []
		for child in track_node.get_children():
			if child is Marker3D:
				positions.append(child)
		
		tracks.append({
			"node": track_node,
			"pieces": [],
			"positions": positions,
			"static_body": static_body
		})

### SCORE SYSTEM
func _initialize_score_ui():
	var score_scene = preload("res://ui/score_display.tscn")
	score_ui = score_scene.instantiate()
	add_child(score_ui)
	await get_tree().process_frame  # Ensure nodes are ready
	update_scores(0, 0)  # Initialize both scores to 0

	score_ui.pass_turn_requested.connect(_on_pass_turn_requested)

func _on_pass_turn_requested():
	if current_turn == "player":
		print("Turn passed via UI")
		end_player_turn()

func enable_discard_mode():
	if player_hand.is_empty():
		return
	
	is_discard_mode = true
	discard_candidate = null
	
	# Highlight all dominos in hand
	for domino in player_hand:
		domino.set_highlight(true, Color.YELLOW)
	
	# Update UI
	update_turn_indicator()
	
	# Show visual feedback
	if score_ui.has_node("PassButton"):
		var pass_button = score_ui.get_node("PassButton") as Button
		pass_button.text = "Confirm Discard"
		pass_button.disabled = true  # Disabled until domino selected

func disable_discard_mode():
	is_discard_mode = false
	
	# Remove highlights from all dominos
	for domino in player_hand:
		if is_instance_valid(domino):
			domino.set_highlight(false)
	
	discard_candidate = null
	update_turn_indicator()

func confirm_discard() -> bool:
	if not discard_candidate or not is_instance_valid(discard_candidate):
		return false
	
	# Remove highlight before discarding
	discard_candidate.set_highlight(false)
	
	# Return to pool (unless it's a double)
	if discard_candidate.top_value != discard_candidate.bottom_value:
		domino_pool.append([discard_candidate.top_value, discard_candidate.bottom_value])
		domino_pool.shuffle()  # Important to shuffle when returning
	
	# Remove from hand
	player_hand.erase(discard_candidate)
	discard_candidate.queue_free()
	
	# Draw new domino if pool isn't empty
	if not domino_pool.is_empty():
		var values = domino_pool.pop_back()
		var new_domino = domino_factory.create_specific_domino(values[0], values[1])
		_setup_hand_domino(new_domino, Vector3.ZERO, player_hand.size())
		add_child(new_domino)
		player_hand.append(new_domino)
		_safe_connect_domino_signals(new_domino)
	
	reposition_hand()
	disable_discard_mode()
	return true

# Replace update_score() with this:
func update_scores(player_points: int, ai_points: int):
	player_score += player_points
	ai_score += ai_points
	
	if is_instance_valid(score_ui):
		# Update player score
		if score_ui.has_node("PlayerScoreLabel"):
			var player_label = score_ui.get_node("PlayerScoreLabel") as Label
			player_label.text = "Player: %d" % player_score
		
		# Update AI score
		if score_ui.has_node("AIScoreLabel"):
			var ai_label = score_ui.get_node("AIScoreLabel") as Label
			ai_label.text = "AI: %d" % ai_score

### TRACK MANAGEMENT
func _create_track_collision(track: Node3D) -> StaticBody3D:
	var static_body = StaticBody3D.new()
	static_body.name = "StaticBody3D"
	static_body.collision_layer = 0b01
	
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = BoxShape3D.new()
	collision_shape.shape.size = Vector3(1.5, 0.2, 9.0)
	static_body.add_child(collision_shape)
	static_body.position.y = -0.1
	track.add_child(static_body)
	return static_body

### GAME SETUP
func spawn_starting_dominos():
	for i in TRACK_COUNT:
		var domino = domino_factory.create_random_domino()
		if not domino:
			continue
			
		domino.is_in_hand = false
		domino.place_on_board()
		add_child(domino)
		await try_place_domino(domino, i)

func _on_pass_button_pressed():
	if current_turn != "player":
		return
	
	if player_has_valid_moves():
		return  # Shouldn't be possible since button should be hidden
	
	if is_discard_mode and discard_candidate:
		# Confirm discard and draw new domino
		if confirm_discard():
			end_player_turn()
	else:
		# Enter discard selection mode
		enable_discard_mode()

func draw_initial_hand():
	player_hand.clear()
	ai_hand.clear()
	
	# Draw for both players
	for i in range(MAX_HAND_SIZE * 2):
		if domino_pool.is_empty():
			break
			
		var values = domino_pool.pop_back()
		if i < MAX_HAND_SIZE:
			# Player's dominos
			var domino = domino_factory.create_specific_domino(values[0], values[1])
			_setup_hand_domino(domino, Vector3.ZERO, i)
			add_child(domino)
			player_hand.append(domino)
			_safe_connect_domino_signals(domino)
		else:
			# AI's dominos
			ai_hand.append(values)
	
	# Ensure both hands are filled as much as possible
	if player_hand.size() < MAX_HAND_SIZE:
		refill_hand()
	if ai_hand.size() < MAX_HAND_SIZE:
		refill_ai_hand()
	
	reposition_hand()

func draw_new_domino(center: Vector3, index: int):
	if domino_pool.is_empty():
		return
	
	var values = domino_pool.pop_back()
	var domino = domino_factory.create_specific_domino(values[0], values[1])
	_setup_hand_domino(domino, center, index)
	add_child(domino)
	player_hand.append(domino)
	_safe_connect_domino_signals(domino)

func _setup_hand_domino(domino: Domino, center: Vector3, index: int):
	domino.is_in_hand = true
	domino.position = center + Vector3((index - 2) * HAND_SPACING, 0, 0)
	domino.rotation_degrees = Vector3(0, 0, 0)
	domino.scale = Vector3(1.2, 1.2, 1.2)
	domino.freeze = true
	domino.collision_layer = 0b10

func player_has_valid_moves() -> bool:
	for domino in player_hand:
		for track_idx in tracks.size():
			if can_place_on_track(domino, track_idx):
				return true
	return false

### HAND MANAGEMENT
func refill_hand():
	while player_hand.size() < MAX_HAND_SIZE and domino_pool.size() > 0:
		var values = domino_pool.pop_back()
		var new_domino = domino_factory.create_specific_domino(values[0], values[1])
		_setup_hand_domino(new_domino, Vector3.ZERO, player_hand.size())
		add_child(new_domino)
		player_hand.append(new_domino)
		_safe_connect_domino_signals(new_domino)
	reposition_hand()

func refill_ai_hand():
	while ai_hand.size() < MAX_HAND_SIZE and domino_pool.size() > 0:
		var values = domino_pool.pop_back()
		ai_hand.append(values)
	print("AI hand refilled: ", ai_hand)

func reposition_hand():
	var hand_center = Vector3(0, 0.2, 3.0)
	for i in player_hand.size():
		player_hand[i].position = hand_center + Vector3((i - player_hand.size() * 0.5) * HAND_SPACING, 0, 0)

func update_turn_indicator():
	# Update turn label
	if score_ui.has_node("TurnLabel"):
		var turn_label = score_ui.get_node("TurnLabel") as Label
		if is_discard_mode:
			turn_label.text = "Select Domino to Discard"
			turn_label.modulate = Color.GOLD
		else:
			turn_label.text = "Your Turn" if current_turn == "player" else "AI Thinking..."
			turn_label.modulate = Color.GREEN if current_turn == "player" else Color.RED
	
	# Update pass button - only show when no valid moves exist
	if score_ui.has_node("PassButton"):
		var pass_button = score_ui.get_node("PassButton") as Button
		var has_valid_moves = player_has_valid_moves()
		
		pass_button.visible = (current_turn == "player" and not has_valid_moves and not is_discard_mode)
		pass_button.disabled = (current_turn != "player" or has_valid_moves)
		
		if is_discard_mode:
			pass_button.text = "Confirm Discard"
			pass_button.visible = true
			pass_button.disabled = (discard_candidate == null)
		else:
			pass_button.text = "Pass Turn"

func check_pass_button_state():
	if score_ui and score_ui.has_node("PassButton"):
		var can_pass = (current_turn == "player") and not player_has_valid_moves()
		score_ui.get_node("PassButton").visible = can_pass
		score_ui.get_node("PassButton").disabled = not can_pass


func start_ai_turn():
	print("AI's turn starting - Current hand size: ", ai_hand.size())
	
	# Refill AI hand if empty
	if ai_hand.is_empty() and domino_pool.size() > 0:
		refill_ai_hand()
	
	# If still no dominos, end turn
	if ai_hand.is_empty():
		print("AI has no dominos left")
		end_ai_turn()
		return
	
	var valid_moves = []
	for domino_values in ai_hand:
		var domino = domino_factory.create_specific_domino(domino_values[0], domino_values[1])
		for track_idx in tracks.size():
			if can_place_on_track(domino, track_idx):
				valid_moves.append({
					"values": domino_values,
					"track": track_idx
				})
	
	if valid_moves.size() == 0:
		print("AI has no valid moves")
		end_ai_turn()
		return
	
	var move = valid_moves[randi() % valid_moves.size()]
	await ai_play_domino(move.values, move.track)

func ai_play_domino(domino_values: Array, track_idx: int):
	print("AI playing ", domino_values[0], "-", domino_values[1], " on track ", track_idx+1)
	
	# Create the temporary visual domino for animation
	var visual_domino = domino_factory.create_specific_domino(domino_values[0], domino_values[1])
	add_child(visual_domino)
	
	# Position it above the board for the animation
	var target_position = tracks[track_idx].positions[tracks[track_idx].pieces.size()].global_transform.origin + Vector3(0, 0.2, 0)
	visual_domino.global_position = target_position + Vector3(0, 2, 0)  # Start above
	
	# Create the permanent domino but keep it hidden initially
	var permanent_domino = domino_factory.create_specific_domino(domino_values[0], domino_values[1])
	permanent_domino.visible = false  # Start hidden
	add_child(permanent_domino)
	permanent_domino.global_position = target_position
	permanent_domino.freeze = true
	permanent_domino.is_in_hand = false
	permanent_domino.place_on_board()
	
	# Set correct orientation
	var pos_idx = tracks[track_idx].pieces.size()
	if pos_idx > 0:
		var last = tracks[track_idx].pieces.back()
		var must_match = last.bottom_value if last.display_top else last.top_value
		if domino_values[0] == must_match:
			permanent_domino.display_top = true
			visual_domino.display_top = true
		elif domino_values[1] == must_match:
			permanent_domino.display_top = false
			visual_domino.display_top = false
		permanent_domino._update_all_dots()
		visual_domino._update_all_dots()
	
	# Animate the visual domino falling
	var tween = create_tween()
	tween.tween_property(visual_domino, "global_position", target_position, 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	# When animation completes:
	tween.tween_callback(func():
		# Show the permanent domino
		permanent_domino.visible = true
		# Remove the visual domino
		visual_domino.queue_free()
		
		# Add to track pieces
		tracks[track_idx].pieces.append(permanent_domino)
		ai_hand.erase(domino_values)
		
		ai_hand.erase(domino_values)
		if ai_hand.size() < MAX_HAND_SIZE and domino_pool.size() > 0:
			refill_ai_hand()
		
		# Check for track completion
		if tracks[track_idx].pieces.size() == TRACK_LENGTH:
			var first = tracks[track_idx].pieces.front()
			var last = tracks[track_idx].pieces.back()
			if (first.top_value if first.display_top else first.bottom_value) == (last.bottom_value if last.display_top else last.top_value):
				_clear_and_restart_track(track_idx)
		
		end_ai_turn()
	)



func end_player_turn():
	check_pass_button_state()
	current_turn = "ai"
	update_turn_indicator()
	await get_tree().create_timer(0.5).timeout  # Small delay before AI moves
	start_ai_turn()

func end_ai_turn():
	check_pass_button_state()
	current_turn = "player"
	update_turn_indicator()


### GAMEPLAY LOGIC
func can_place_on_track(domino: Domino, track_idx: int) -> bool:
	var track = tracks[track_idx]
	
	if track.pieces.size() >= TRACK_LENGTH:
		return false
		
	if track.pieces.is_empty():
		return true
		
	var last = track.pieces.back()
	var visible_end = last.bottom_value if last.display_top else last.top_value
	
	if domino.top_value == visible_end || domino.bottom_value == visible_end:
		if track.pieces.size() == TRACK_LENGTH - 1:
			var first = track.pieces.front()
			var first_value = first.top_value if first.display_top else first.bottom_value
			var domino_other_value = domino.bottom_value if domino.top_value == visible_end else domino.top_value
			return domino_other_value == first_value
		return true
		
	return false

func try_place_domino(domino: Domino, track_idx: int) -> bool:
	if not is_instance_valid(domino):
		return false
		
	var track = tracks[track_idx]
	var pos_idx = track.pieces.size()
	
	if pos_idx >= track.positions.size():
		return false
	
	if pos_idx > 0:
		var last = track.pieces.back()
		var must_match = last.bottom_value if last.display_top else last.top_value
		
		if domino.top_value == must_match:
			domino.display_top = true
		elif domino.bottom_value == must_match:
			domino.display_top = false
		else:
			return false
			
		domino._update_all_dots()
	
	domino.freeze = false
	if domino.get_parent() != self:
		add_child(domino)
	
	domino.global_transform = track.positions[pos_idx].global_transform
	domino.global_position.y += 0.2
	
	await get_tree().physics_frame
	domino.freeze = true
	
	track.pieces.append(domino)
	player_hand.erase(domino)
	
	if domino == selected_domino:
		domino.deselect()
		selected_domino = null
		hide_valid_moves()
	
	refill_hand()
	reposition_hand()
	
	if track.pieces.size() == TRACK_LENGTH:
		var first = track.pieces.front()
		var last = track.pieces.back()
		if (first.top_value if first.display_top else first.bottom_value) == (last.bottom_value if last.display_top else last.top_value):
			_clear_and_restart_track(track_idx)
	
	return true

func _clear_and_restart_track(track_idx: int):
	var track = tracks[track_idx]
	
	# Return dominos to pool before clearing
	for domino in track.pieces:
		if domino.top_value != domino.bottom_value:  # Don't return doubles
			domino_pool.append([domino.top_value, domino.bottom_value])
		domino.queue_free()
	
	track.pieces.clear()
	
	# Award points
	if current_turn == "player":
		update_scores(1, 0)
	else:
		update_scores(0, 1)
	
	await get_tree().create_timer(0.5).timeout
	
	# Shuffle the pool to randomize returned dominos
	domino_pool.shuffle()
	
	# Create new starting domino
	var new_domino = domino_factory.create_random_domino()
	if new_domino:
		new_domino.is_in_hand = false
		new_domino.place_on_board()
		add_child(new_domino)
		new_domino.global_transform = track.positions[0].global_transform
		new_domino.global_position.y += 0.2
		new_domino.freeze = true
		new_domino.display_top = true
		track.pieces.append(new_domino)

### SIGNAL HANDLING
func _safe_connect_domino_signals(domino: Domino):
	if domino.is_connected("domino_selected", _on_domino_selected):
		domino.disconnect("domino_selected", _on_domino_selected)
	domino.connect("domino_selected", _on_domino_selected)
	domino.connect("domino_deselected", _on_domino_deselected)

func _on_domino_selected(domino: Domino):
	if is_processing_selection:
		return
		
	is_processing_selection = true
	
	if is_discard_mode:
		# Handle discard selection
		if discard_candidate:
			discard_candidate.set_highlight(true, Color.YELLOW)  # Reset previous selection
		
		discard_candidate = domino
		domino.set_highlight(true, Color.ORANGE_RED)  # Highlight as selected
		
		# Enable confirm button now that we have a selection
		if score_ui.has_node("PassButton"):
			var pass_button = score_ui.get_node("PassButton") as Button
			pass_button.disabled = false
	else:
		# Original game selection logic
		if selected_domino and selected_domino != domino:
			selected_domino.deselect()
		
		selected_domino = domino
		domino.select()
		show_valid_moves(domino)
	
	is_processing_selection = false

func _on_domino_deselected():
	if selected_domino:
		selected_domino = null
	hide_valid_moves()

### VISUAL FEEDBACK
func show_valid_moves(domino: Domino):
	hide_valid_moves()
	
	if not domino or not is_instance_valid(domino):
		return
		
	for i in tracks.size():
		if can_place_on_track(domino, i):
			var indicator = _get_or_create_indicator(tracks[i])
			if indicator:
				_position_indicator(tracks[i], domino)
				var material = indicator.get_surface_override_material(0)
				if tracks[i].pieces.size() == TRACK_LENGTH - 1:
					material.albedo_color = Color(1, 0, 0, 0.7)
				else:
					material.albedo_color = Color(0, 1, 0, 0.5)
				indicator.set_surface_override_material(0, material)
				tracks[i]["static_body"].input_ray_pickable = true

func hide_valid_moves():
	for track in tracks:
		if track.has("static_body"):
			track["static_body"].input_ray_pickable = false

func _get_or_create_indicator(track: Dictionary) -> MeshInstance3D:
	if not track.node.has_node("Indicator"):
		var indicator = MeshInstance3D.new()
		indicator.name = "Indicator"
		indicator.mesh = BoxMesh.new()
		indicator.mesh.size = Vector3(0.8, 0.01, 0.8)
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0, 1, 0, 0.5)
		mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		indicator.set_surface_override_material(0, mat)
		
		track.node.add_child(indicator)
		indicator.owner = get_tree().edited_scene_root
	
	return track.node.get_node("Indicator")

func _position_indicator(track: Dictionary, _domino: Domino):
	var indicator = track.node.get_node("Indicator")
	if indicator:
		indicator.global_position = track.positions[track.pieces.size()].global_position + Vector3(0, 0.02, 0)
		indicator.visible = true

### INPUT HANDLING
func _input(event):
	if current_turn != "player":  # Block input during AI's turn
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if is_discard_mode:
			disable_discard_mode()
			return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if selected_domino:
			var camera = get_viewport().get_camera_3d()
			var result = get_world_3d().direct_space_state.intersect_ray(
				PhysicsRayQueryParameters3D.create(
					camera.project_ray_origin(event.position),
					camera.project_ray_normal(event.position) * 100
				)
			)
			
			if result and result.collider is StaticBody3D:
				for i in tracks.size():
					if tracks[i]["static_body"] == result.collider and can_place_on_track(selected_domino, i):
						if await try_place_domino(selected_domino, i):
							selected_domino = null
							hide_valid_moves()
							end_player_turn()  # Add this function

### PHYSICS
func _physics_process(_delta):
	# Handle domino physics and positioning
	for track in tracks:
		for i in track.pieces.size():
			var domino = track.pieces[i]
			if domino.freeze and i < track.positions.size():
				domino.global_position = domino.global_position.lerp(
					track.positions[i].global_transform.origin + Vector3(0, 0.2, 0),
					0.2
				)
	
	# Only check pass button state during player's turn when not in discard mode
	if current_turn == "player" and not is_discard_mode:
		check_pass_button_state()
