extends Node3D
class_name DominoGameBoard

### CONSTANTS
const FACTORY_SCRIPT = preload("res://scripts/domino_factory.gd")
const TRACK_COUNT := 3
const TRACK_LENGTH := 9
const HAND_SPACING := 0.5
const MAX_HAND_SIZE := 5
const GAME_OVER_SCREEN = preload("res://ui/game_over_screen.tscn")

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
var game_winner: String = ""
var is_game_over := false
var has_extra_turn := false  # Add with other game state variables

func _ready():
	print("Initializing game...")
	_initialize_game()
	_initialize_score_ui()
	update_scores(0, 0)
	current_turn = "player"
	
	# Safe signal connection
	if score_ui:
		# Clean up existing connections
		if score_ui.pass_turn_requested.is_connected(_on_pass_turn_requested):
			score_ui.pass_turn_requested.disconnect(_on_pass_turn_requested)
		score_ui.pass_turn_requested.connect(_on_pass_turn_requested)
		
		# Connect discard signal to handler (not directly to confirm_discard)
		if score_ui.has_signal("discard_confirmed"):
			if score_ui.discard_confirmed.is_connected(_on_discard_confirmed):
				score_ui.discard_confirmed.disconnect(_on_discard_confirmed)
			score_ui.discard_confirmed.connect(_on_discard_confirmed)
	
	update_turn_indicator()

# Add this handler if not already present
func _on_discard_confirmed():
	if discard_candidate and confirm_discard():
		end_player_turn()

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
	# Create standard double-six set (28 unique dominos)
	for i in range(7):  # 0-6
		for j in range(i, 7):  # This creates all unique combinations
			domino_pool.append([i, j])
	
	# For a double set (56 total), duplicate and shuffle
	domino_pool += domino_pool.duplicate()
	domino_pool.shuffle()
	print("Initialized domino pool with %d pieces (double set)" % domino_pool.size())

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

func _on_pass_turn_requested():
	if current_turn != "player" or player_has_valid_moves():
		return
	
	if is_discard_mode:
		if discard_candidate:
			if confirm_discard():
				disable_discard_mode()
				end_player_turn()  # Only end turn AFTER successful discard
		else:
			print("No domino selected for discard!")
	else:
		enable_discard_mode()

func enable_discard_mode():
	print("Entered discard mode")
	if player_hand.is_empty():
		return
	
	is_discard_mode = true
	discard_candidate = null
	
	# Highlight all dominos
	for domino in player_hand:
		if is_instance_valid(domino) and domino.has_method("set_highlight"):
			domino.set_highlight(true, Color.YELLOW)
	
	# Update button state
	if score_ui and score_ui.has_node("PassButton"):
		var button = score_ui.get_node("PassButton")
		button.text = "CONFIRM DISCARD"
		button.disabled = true  # Starts disabled until selection
		button.visible = true

func confirm_discard() -> bool:
	if not discard_candidate or not is_instance_valid(discard_candidate):
		return false
	
	print("Discarding ", discard_candidate.top_value, "-", discard_candidate.bottom_value)
	
	# 1. Store values before removal
	var values = [discard_candidate.top_value, discard_candidate.bottom_value]
	
	# 2. Remove from hand and scene
	player_hand.erase(discard_candidate)
	remove_child(discard_candidate)
	discard_candidate.queue_free()
	
	# 3. Return to pool and shuffle
	domino_pool.append(values)
	domino_pool.shuffle()
	print("Returned to pool. Pool size: ", domino_pool.size())
	
	# 4. Draw replacement if pool isn't empty
	if domino_pool.size() > 0 and player_hand.size() < MAX_HAND_SIZE:
		var new_values = domino_pool.pop_back()
		var new_domino = domino_factory.create_specific_domino(new_values[0], new_values[1])
		_setup_hand_domino(new_domino, Vector3.ZERO, player_hand.size())
		add_child(new_domino)
		player_hand.append(new_domino)
		_safe_connect_domino_signals(new_domino)
		print("Drew new domino: ", new_values)
	else:
		print("Warning: Couldn't draw replacement")
	
	reposition_hand()
	return true

func disable_discard_mode():
	is_discard_mode = false
	for domino in player_hand:
		if is_instance_valid(domino):
			domino.call("set_highlight", false)
	
	if score_ui.has_node("PassButton"):
		var button = score_ui.get_node("PassButton")
		button.text = "DISCARD DOMINO"
		button.disabled = false
		button.visible = not player_has_valid_moves()

func update_scores(player_points: int, ai_points: int):
	if is_game_over:
		return
	
	player_score += player_points
	ai_score += ai_points
	
	if is_instance_valid(score_ui):
		if score_ui.has_node("PlayerScoreLabel"):
			score_ui.get_node("PlayerScoreLabel").text = "Player: %d" % player_score
		if score_ui.has_node("AIScoreLabel"):
			score_ui.get_node("AIScoreLabel").text = "AI: %d" % ai_score
	
	# Check for winner after every score change
	check_for_winner()

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
		await try_place_domino(domino, i, true)  # Note the added true parameter

func _on_pass_button_pressed():
	if current_turn != "player" or player_has_valid_moves():
		return
	
	if is_discard_mode:
		if discard_candidate:
			if confirm_discard():
				end_player_turn()
	else:
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
			turn_label.text = "SELECT DOMINO TO DISCARD"
			turn_label.modulate = Color.GOLD
		else:
			turn_label.text = "YOUR TURN" if current_turn == "player" else "AI THINKING..."
			turn_label.modulate = Color.LIME_GREEN if current_turn == "player" else Color.RED
	
	# Update pass/discard button
	if score_ui.has_node("PassButton"):
		var pass_button = score_ui.get_node("PassButton") as Button
		var has_valid_moves = player_has_valid_moves()
		
		pass_button.visible = (current_turn == "player" and not has_valid_moves)
		
		if is_discard_mode:
			pass_button.text = "CONFIRM DISCARD"
			pass_button.disabled = (discard_candidate == null)
			pass_button.modulate = Color.WHITE if discard_candidate else Color.GRAY
		else:
			pass_button.text = "DISCARD DOMINO"
			pass_button.disabled = false
			pass_button.modulate = Color.WHITE
	
	# Visual feedback for AI turn
	if current_turn == "ai":
		if score_ui.has_node("AITurnIndicator"):
			var ai_indicator = score_ui.get_node("AITurnIndicator")
			ai_indicator.visible = true
	if score_ui.has_node("TurnLabel"):
		var turn_label = score_ui.get_node("TurnLabel")
		if has_extra_turn and current_turn == "player":
			turn_label.text = "EXTRA TURN!"
			turn_label.modulate = Color.GOLD


func check_for_winner():
	if player_score >= 3:
		game_winner = "player"
		is_game_over = true
	elif ai_score >= 3:
		game_winner = "ai"
		is_game_over = true
	
	if is_game_over:
		_handle_game_over()
		return true
	return false

func _handle_game_over():
	set_process_input(false)
	
	# Add slight delay to ensure safe instantiation
	await get_tree().create_timer(0.1).timeout
	
	var game_over = GAME_OVER_SCREEN.instantiate()
	add_child(game_over)
	
	# Wait until screen is fully ready
	await game_over.ready
	game_over.set_winner(game_winner)

func restart_game():
	# Clear all dominos
	for track in tracks:
		for domino in track.pieces:
			if is_instance_valid(domino):
				domino.queue_free()
		track.pieces.clear()
	
	# Reset game state
	player_hand.clear()
	ai_hand.clear()
	domino_pool.clear()
	game_winner = ""
	is_game_over = false
	player_score = 0
	ai_score = 0
	
	# Reinitialize
	_initialize_game()
	set_process_input(true)
	
	# Hide winner message
	if score_ui.has_node("WinnerLabel"):
		score_ui.get_node("WinnerLabel").visible = false

func check_pass_button_state():
	if score_ui and score_ui.has_node("PassButton"):
		var can_pass = (current_turn == "player") and not player_has_valid_moves()
		score_ui.get_node("PassButton").visible = can_pass
		score_ui.get_node("PassButton").disabled = not can_pass


func start_ai_turn():
	print("AI's turn starting - Current hand size: ", ai_hand.size())
	
	# Clear any leftover extra turn flag
	has_extra_turn = false
	
	# Check for double piece first
	var double_move = _find_ai_double_move()
	if double_move:
		await ai_play_domino(double_move.values, double_move.track)
		if has_extra_turn:
			print("AI gets ONE extra turn from double")
			has_extra_turn = false  # Clear immediately after detecting
			await get_tree().create_timer(0.5).timeout
			start_ai_turn()  # Take exactly one extra turn
			return
	
	# Normal move if no double available
	var valid_moves = _find_ai_valid_moves()
	if valid_moves.size() > 0:
		await ai_play_domino(valid_moves[0].values, valid_moves[0].track)
	else:
		await ai_discard_domino()
	
	end_ai_turn()

func _find_ai_double_move() -> Dictionary:
	for domino_values in ai_hand:
		if domino_values[0] == domino_values[1]:  # Check if double
			var domino = domino_factory.create_specific_domino(domino_values[0], domino_values[1])
			for track_idx in tracks.size():
				if can_place_on_track(domino, track_idx):
					domino.queue_free()
					return {
						"values": domino_values,
						"track": track_idx,
						"is_double": true
					}
			domino.queue_free()
	return {}

func _find_ai_valid_moves() -> Array:
	var valid_moves = []
	for domino_values in ai_hand:
		var domino = domino_factory.create_specific_domino(domino_values[0], domino_values[1])
		for track_idx in tracks.size():
			if can_place_on_track(domino, track_idx):
				valid_moves.append({
					"values": domino_values,
					"track": track_idx
				})
		domino.queue_free()
	return valid_moves

func ai_discard_domino():
	if ai_hand.is_empty() or domino_pool.is_empty():
		end_ai_turn()
		return
	
	print("AI is discarding a domino")
	
	# 1. Select domino to discard (prefer non-doubles)
	var discard_index = 0
	for i in range(ai_hand.size()):
		if ai_hand[i][0] != ai_hand[i][1]:  # Find first non-double
			discard_index = i
			break
	
	var discarded_values = ai_hand[discard_index]
	print("AI discarding: ", discarded_values)
	
	# 2. Visual feedback
	var visual_domino = domino_factory.create_specific_domino(discarded_values[0], discarded_values[1])
	add_child(visual_domino)
	visual_domino.global_position = Vector3(0, 2, 0)
	visual_domino.set_highlight(true, Color.PURPLE)
	
	# 3. Animate the discard
	var tween = create_tween()
	tween.tween_property(visual_domino, "position:y", 0, 0.3)
	await tween.finished
	
	# 4. Return to pool and SHUFFLE
	domino_pool.append(discarded_values)
	ai_hand.remove_at(discard_index)
	domino_pool.shuffle()  # CRITICAL: Shuffle before drawing
	
	# 5. Draw new random domino
	if domino_pool.size() > 0:
		var new_values = domino_pool.pop_back()
		# Verify we're not drawing the same domino
		while new_values == discarded_values and domino_pool.size() > 1:
			domino_pool.append(new_values)  # Put it back
			domino_pool.shuffle()
			new_values = domino_pool.pop_back()
		
		ai_hand.append(new_values)
		print("AI drew new domino: ", new_values)
	
	visual_domino.queue_free()
	end_ai_turn()

func ai_play_domino(domino_values: Array, track_idx: int):
	print("AI playing ", domino_values[0], "-", domino_values[1], " on track ", track_idx+1)
	
	var is_double = domino_values[0] == domino_values[1]
	var visual_domino = domino_factory.create_specific_domino(domino_values[0], domino_values[1])
	add_child(visual_domino)
	
	# Get target position safely
	var target_position = tracks[track_idx].positions[tracks[track_idx].pieces.size()].global_transform.origin + Vector3(0, 0.2, 0)
	visual_domino.global_position = target_position + Vector3(0, 2, 0)
	
	# Special effects for doubles
	if is_double:
		visual_domino.scale = Vector3(1.3, 1.3, 1.3)
		if has_node("DoubleSound"):
			$DoubleSound.play()
	
	# Create permanent domino
	var permanent_domino = domino_factory.create_specific_domino(domino_values[0], domino_values[1])
	permanent_domino.visible = false
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
	
	# Animate falling
	var tween = create_tween()
	tween.tween_property(visual_domino, "global_position", target_position, 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	await tween.finished
	
	# Finalize placement
	permanent_domino.visible = true
	visual_domino.queue_free()
	
	# Add to track
	tracks[track_idx].pieces.append(permanent_domino)
	ai_hand.erase(domino_values)
	
	# Handle double domino
	if is_double:
		has_extra_turn = true
		print("AI played double domino - extra turn queued")
	
	# Refill hand if needed
	if ai_hand.size() < MAX_HAND_SIZE and domino_pool.size() > 0:
		refill_ai_hand()
	
	# Check for track completion (MOVED SCORING TO _clear_and_restart_track)
	if tracks[track_idx].pieces.size() == TRACK_LENGTH:
		var first = tracks[track_idx].pieces.front()
		var last = tracks[track_idx].pieces.back()
		if (first.top_value if first.display_top else first.bottom_value) == (last.bottom_value if last.display_top else last.top_value):
			_clear_and_restart_track(track_idx)
			# REMOVED THE update_scores CALL FROM HERE
	
	return true

func end_player_turn():
	if is_discard_mode:
		return
		
	if has_extra_turn:
		has_extra_turn = false
		print("Player takes extra turn")
		return  # Don't change turns
		
	current_turn = "ai"
	update_turn_indicator()
	await get_tree().create_timer(0.5).timeout
	start_ai_turn()

func end_ai_turn():
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
	
	# Check if domino matches the end
	if domino.top_value == visible_end or domino.bottom_value == visible_end:
		if track.pieces.size() == TRACK_LENGTH - 1:
			# For last position, check if it completes the loop
			var first = track.pieces.front()
			var first_value = first.top_value if first.display_top else first.bottom_value
			var domino_other_value = domino.bottom_value if domino.top_value == visible_end else domino.top_value
			return domino_other_value == first_value
		return true
		
	return false

func try_place_domino(domino: Domino, track_idx: int, is_starting_domino: bool = false) -> bool:
	if not is_instance_valid(domino):
		return false
		
	var track = tracks[track_idx]
	var pos_idx = track.pieces.size()
	
	if pos_idx >= track.positions.size():
		return false
	
	# Check if domino matches the track rules
	if pos_idx > 0:  # Only check matching for non-starting dominos
		var last = track.pieces.back()
		var must_match = last.bottom_value if last.display_top else last.top_value
		
		if domino.top_value == must_match:
			domino.display_top = true
		elif domino.bottom_value == must_match:
			domino.display_top = false
		else:
			return false
			
		domino._update_all_dots()
	
	# Place the domino physically
	domino.freeze = false
	if domino.get_parent() != self:
		add_child(domino)
	
	domino.global_transform = track.positions[pos_idx].global_transform
	domino.global_position.y += 0.2
	
	await get_tree().physics_frame
	domino.freeze = true
	
	# Add to track
	track.pieces.append(domino)
	if not is_starting_domino:  # Only remove from hand if not starting domino
		player_hand.erase(domino)
	
	# Check for double domino (only for non-starting dominos)
	if not is_starting_domino and domino.top_value == domino.bottom_value:
		has_extra_turn = true
		# Visual feedback
		var tween = create_tween()
		tween.tween_property(domino, "scale", Vector3(1.3, 1.3, 1.3), 0.2)
		tween.tween_property(domino, "scale", Vector3(1, 1, 1), 0.2)
		if has_node("DoubleSound"):
			$DoubleSound.play()
		print("Double domino played - extra turn granted!")
	
	# Handle selection cleanup
	if domino == selected_domino:
		domino.deselect()
		selected_domino = null
		hide_valid_moves()
	
	# Refill hand if needed (only for player turns)
	if not is_starting_domino and current_turn == "player":
		refill_hand()
		reposition_hand()
	
	# Check for track completion
	if track.pieces.size() == TRACK_LENGTH:
		var first = track.pieces.front()
		var last = track.pieces.back()
		var first_value = first.top_value if first.display_top else first.bottom_value
		var last_value = last.bottom_value if last.display_top else last.top_value
		
		if first_value == last_value:
			_clear_and_restart_track(track_idx)
	return true

func _clear_and_restart_track(track_idx: int):
	var track = tracks[track_idx]
	
	# Check if this is a valid completion (first and last match)
	var first = track.pieces.front()
	var last = track.pieces.back()
	var first_value = first.top_value if first.display_top else first.bottom_value
	var last_value = last.bottom_value if last.display_top else last.top_value
	
	if first_value != last_value:
		return  # Not a valid completion
	
	# Score points (only once)
	if current_turn == "player":
		update_scores(1, 0)
	else:
		update_scores(0, 1)
	
	# [Rest of your existing track clearing code]
	for domino in track.pieces:
		if is_instance_valid(domino):
			domino_pool.append([domino.top_value, domino.bottom_value])
			domino.queue_free()
	
	track.pieces.clear()
	domino_pool.shuffle()
	print("Returned track dominos to pool. New pool size: ", domino_pool.size())
	
	# Restart track
	if domino_pool.size() > 0:
		var new_domino = domino_factory.create_random_domino()
		if new_domino:
			new_domino.is_in_hand = false
			new_domino.place_on_board()
			add_child(new_domino)
			await try_place_domino(new_domino, track_idx, true)

### SIGNAL HANDLING
func _safe_connect_domino_signals(domino: Domino):
	if domino.is_connected("domino_selected", _on_domino_selected):
		domino.disconnect("domino_selected", _on_domino_selected)
	domino.connect("domino_selected", _on_domino_selected)
	domino.connect("domino_deselected", _on_domino_deselected)

func _on_domino_selected(domino: Domino):
	print("Selected domino - Discard mode:", is_discard_mode, " Has candidate:", discard_candidate != null)
	if current_turn != "player" or is_processing_selection:
		return
	
	is_processing_selection = true
	
	if is_discard_mode:
		# Reset previous selection highlight
		if discard_candidate and is_instance_valid(discard_candidate):
			discard_candidate.set_highlight(true, Color.YELLOW)
		
		# Set new selection
		discard_candidate = domino
		domino.set_highlight(true, Color.ORANGE_RED)
		
		# Update button state - THIS IS THE CRITICAL FIX
		if score_ui and score_ui.has_node("PassButton"):
			var button = score_ui.get_node("PassButton")
			button.disabled = false
			button.text = "CONFIRM DISCARD"
	else:
		# Normal selection logic
		if selected_domino and selected_domino != domino:
			selected_domino.deselect()
			hide_valid_moves()
		
		if domino == selected_domino:
			domino.deselect()
			selected_domino = null
			hide_valid_moves()
		else:
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
	hide_valid_moves()  # Clear any existing indicators
	
	if not domino or not is_instance_valid(domino):
		return
	
	for track_idx in tracks.size():
		if can_place_on_track(domino, track_idx):
			var track = tracks[track_idx]
			var pos_idx = track.pieces.size()
			
			# Create or get indicator
			var indicator = _get_or_create_indicator(track)
			indicator.visible = true
			indicator.global_position = track.positions[pos_idx].global_position + Vector3(0, 0.02, 0)
			
			# Set color based on placement type
			var mat = indicator.get_surface_override_material(0)
			if track.pieces.size() == TRACK_LENGTH - 1:
				mat.albedo_color = Color(1, 0, 0, 0.7)  # Red for completing track
			else:
				mat.albedo_color = Color(0, 1, 0, 0.5)  # Green for normal placement
			indicator.set_surface_override_material(0, mat)

func hide_valid_moves():
	for track in tracks:
		if track.node.has_node("Indicator"):
			track.node.get_node("Indicator").visible = false

func _get_or_create_indicator(track: Dictionary) -> MeshInstance3D:
	if not track.node.has_node("Indicator"):
		# Create new indicator
		var indicator = MeshInstance3D.new()
		indicator.name = "Indicator"
		indicator.mesh = BoxMesh.new()
		indicator.mesh.size = Vector3(0.8, 0.01, 0.8)
		
		var mat = StandardMaterial3D.new()
		mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		indicator.set_surface_override_material(0, mat)
		
		track.node.add_child(indicator)
	
	return track.node.get_node("Indicator")

func _position_indicator(track: Dictionary, _domino: Domino):
	var indicator = track.node.get_node("Indicator")
	if indicator:
		indicator.global_position = track.positions[track.pieces.size()].global_position + Vector3(0, 0.02, 0)
		indicator.visible = true

### INPUT HANDLING
func _input(event):
	if current_turn != "player" or is_discard_mode:
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
