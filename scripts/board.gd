extends Node3D
class_name DominoGameBoard

### CONSTANTS
const FACTORY_SCRIPT := preload("res://scripts/domino_factory.gd")
const TRACK_COUNT := 3
const TRACK_LENGTH := 9
const HAND_SPACING := 0.5
const MAX_HAND_SIZE := 5
const GAME_OVER_SCREEN := preload("res://ui/game_over_screen.tscn")

### NODE REFERENCES
@onready var domino_factory: DominoFactory = FACTORY_SCRIPT.new()
@onready var score_ui: CanvasLayer = preload("res://ui/score_display.tscn").instantiate()

### GAME STATE
var tracks := []
var player_hand := []
var ai_hand := []
var domino_pool := []
var selected_domino: Domino = null
var discard_candidate: Domino = null

var player_score := 0
var ai_score := 0
var current_turn: String = "player"
var game_winner: String = ""

var is_processing_selection := false
var is_discard_mode := false
var is_game_over := false
var has_extra_turn := false

# New variables for power dominos
var power_hand := []  # Array to hold power dominos
var regular_dominos_played := 0  # Counter for how many regular dominos have been played
const MAX_POWER_DOMINOS := 3  # Max power dominos player can hold


func _ready():
	initialize_game()
	setup_viewport()
	connect_signals()

### INITIALIZATION ============================================================
func initialize_game():
	add_child(domino_factory)
	add_child(score_ui)
	
	setup_camera()
	initialize_tracks()
	initialize_domino_pool()
	
	spawn_starting_dominos()
	draw_initial_hands()
	
	update_scores(0, 0)
	current_turn = "player"
	update_turn_indicator()

func setup_viewport():
	get_viewport().size = Vector2i(720, 1208)
	get_viewport().scaling_3d_scale = 1.0
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST

func connect_signals():
	if score_ui:
		score_ui.pass_turn_requested.connect(_on_pass_turn_requested)
		if score_ui.has_signal("discard_confirmed"):
			score_ui.discard_confirmed.connect(_on_discard_confirmed)

func setup_camera():
	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.position = Vector3(0, 10, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	add_child(camera)
	camera.make_current()

func initialize_tracks():
	for i in TRACK_COUNT:
		var track_node = get_node("Track%d" % (i+1))
		track_node.position.z = -2.0
		var static_body = create_track_collision(track_node)
		
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

func create_track_collision(track: Node3D) -> StaticBody3D:
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

func initialize_domino_pool():
	domino_pool.clear()
	# Create standard double-six set (28 unique dominos)
	for i in range(7):  # 0-6
		for j in range(i, 7):  # Creates all unique combinations
			domino_pool.append([i, j])
	
	# For a double set (56 total), duplicate and shuffle
	domino_pool += domino_pool.duplicate()
	domino_pool.shuffle()

### GAME SETUP ================================================================
func spawn_starting_dominos():
	for i in TRACK_COUNT:
		var domino = domino_factory.create_random_domino()
		if domino:
			domino.is_in_hand = false
			domino.place_on_board()
			add_child(domino)
			try_place_domino(domino, i, true)

func draw_initial_hands():
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
			setup_hand_domino(domino, i)
			add_child(domino)
			player_hand.append(domino)
			safe_connect_domino_signals(domino)
		else:
			# AI's dominos
			ai_hand.append(values)
	
	refill_hand()
	refill_ai_hand()
	reposition_hand()

func setup_hand_domino(domino: Domino, index: int):
	domino.is_in_hand = true
	domino.position = Vector3((index - 2) * HAND_SPACING, 0.2, 3.0)
	domino.rotation_degrees = Vector3.ZERO
	domino.scale = Vector3(1.2, 1.2, 1.2)
	domino.freeze = true
	domino.collision_layer = 0b10

func safe_connect_domino_signals(domino: Domino):
	if domino.domino_selected.is_connected(_on_domino_selected):
		domino.domino_selected.disconnect(_on_domino_selected)
	if domino.domino_deselected.is_connected(_on_domino_deselected):
		domino.domino_deselected.disconnect(_on_domino_deselected)
	
	domino.domino_selected.connect(_on_domino_selected)
	domino.domino_deselected.connect(_on_domino_deselected)

### HAND MANAGEMENT ===========================================================
func refill_hand():
	while player_hand.size() < MAX_HAND_SIZE and domino_pool.size() > 0:
		var values = domino_pool.pop_back()
		var new_domino = domino_factory.create_specific_domino(values[0], values[1])
		setup_hand_domino(new_domino, player_hand.size())
		add_child(new_domino)
		player_hand.append(new_domino)
		safe_connect_domino_signals(new_domino)
	reposition_hand()

func refill_ai_hand():
	while ai_hand.size() < MAX_HAND_SIZE and domino_pool.size() > 0:
		ai_hand.append(domino_pool.pop_back())

func reposition_hand():
	var hand_center = Vector3(0, 0.2, 3.0)
	for i in player_hand.size():
		player_hand[i].position = hand_center + Vector3((i - player_hand.size() * 0.5) * HAND_SPACING, 0, 0)

func player_has_valid_moves() -> bool:
	for domino in player_hand + power_hand:
		for track_idx in tracks.size():
			if can_place_on_track(domino, track_idx):
				return true
	return false


### TURN MANAGEMENT ===========================================================
func update_turn_indicator():
	if not score_ui:
		return
	
	# Update turn label
	if score_ui.has_node("TurnLabel"):
		var turn_label = score_ui.get_node("TurnLabel")
		if is_discard_mode:
			turn_label.text = "SELECT DOMINO TO DISCARD"
			turn_label.modulate = Color.GOLD
		elif has_extra_turn and current_turn == "player":
			turn_label.text = "EXTRA TURN!"
			turn_label.modulate = Color.GOLD
		else:
			turn_label.text = "YOUR TURN" if current_turn == "player" else "AI THINKING..."
			turn_label.modulate = Color.LIME_GREEN if current_turn == "player" else Color.RED
	
	# Update pass/discard button
	if score_ui.has_node("PassButton"):
		var pass_button = score_ui.get_node("PassButton")
		pass_button.visible = (current_turn == "player" and not player_has_valid_moves())
		
		if is_discard_mode:
			pass_button.text = "CONFIRM DISCARD"
			pass_button.disabled = (discard_candidate == null)
			pass_button.modulate = Color.WHITE if discard_candidate else Color.GRAY
		else:
			pass_button.text = "DISCARD DOMINO"
			pass_button.disabled = false
			pass_button.modulate = Color.WHITE


func end_player_turn() -> void:
	if is_discard_mode:
		return

	if has_extra_turn:
		has_extra_turn = false
		return

	current_turn = "ai"
	update_turn_indicator()
	await get_tree().create_timer(0.5).timeout
	await start_ai_turn()  # <-- IMPORTANT: await this to run AI turn





func start_ai_turn() -> void:
	print("AI's turn starting - Current hand size: ", ai_hand.size())
	has_extra_turn = false

	var double_move = find_ai_double_move()
	if double_move:
		await ai_play_domino(double_move.values, double_move.track)
		if has_extra_turn:
			has_extra_turn = false
			await get_tree().create_timer(0.5).timeout
			await start_ai_turn()  # await recursive call
			return

	var valid_moves = find_ai_valid_moves()
	if valid_moves.size() > 0:
		await ai_play_domino(valid_moves[0].values, valid_moves[0].track)
	else:
		await ai_discard_domino()

	end_ai_turn()



func end_ai_turn() -> void:
	current_turn = "player"
	update_turn_indicator()



func find_ai_double_move() -> Dictionary:
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

func find_ai_valid_moves() -> Array:
	var valid_moves = []
	print("Finding AI valid moves. AI hand size: ", ai_hand.size())
	
	for domino_values in ai_hand:
		var top_val = domino_values[0]
		var bottom_val = domino_values[1]
		print("Checking domino: ", top_val, "-", bottom_val)
		
		# Create a temporary Domino-like dict to check power status and values
		var temp_domino = {
			"is_power_domino": false,  # AI power dominos may require special handling if you have them
			"top_value": top_val,
			"bottom_value": bottom_val
		}
		
		for track_idx in range(tracks.size()):
			if can_place_on_track_ai(temp_domino, track_idx):
				print("Valid move on track ", track_idx)
				valid_moves.append({
					"values": [top_val, bottom_val],
					"track": track_idx,
					"domino_values": domino_values
				})
	
	print("AI valid moves found: ", valid_moves.size())
	return valid_moves

func can_place_on_track_ai(domino_data, track_idx: int) -> bool:
	var track = tracks[track_idx]

	if track.pieces.size() >= TRACK_LENGTH:
		return false

	if domino_data.has("is_power_domino") and domino_data.is_power_domino:
		return true  # Power dominos can go anywhere

	if track.pieces.is_empty():
		return true

	var last = track.pieces.back()
	var visible_end = last.bottom_value if last.display_top else last.top_value

	if domino_data.top_value == visible_end or domino_data.bottom_value == visible_end:
		if track.pieces.size() == TRACK_LENGTH - 1:
			var first = track.pieces.front()
			var first_value = first.top_value if first.display_top else first.bottom_value
			var domino_other_value = domino_data.bottom_value if domino_data.top_value == visible_end else domino_data.top_value
			return domino_other_value == first_value
		return true

	return false



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
		permanent_domino.update_dots()
		visual_domino.update_dots()
	
	# Animate falling
	var tween = create_tween()
	tween.tween_property(visual_domino, "global_position", target_position, 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	await tween.finished
	
	# Finalize placement
	permanent_domino.visible = true
	visual_domino.queue_free()
	tracks[track_idx].pieces.append(permanent_domino)
	ai_hand.erase(domino_values)
	
	# Handle double domino
	if is_double:
		has_extra_turn = true
	
	# Refill hand if needed
	if ai_hand.size() < MAX_HAND_SIZE and domino_pool.size() > 0:
		refill_ai_hand()
	
	# Check for track completion
	if tracks[track_idx].pieces.size() == TRACK_LENGTH:
		var first = tracks[track_idx].pieces.front()
		var last = tracks[track_idx].pieces.back()
		var first_value = first.top_value if first.display_top else first.bottom_value
		var last_value = last.bottom_value if last.display_top else last.top_value
		
		if first_value == last_value:
			clear_and_restart_track(track_idx)

func ai_discard_domino():
	if ai_hand.is_empty() or domino_pool.is_empty():
		end_ai_turn()
		return
	
	print("AI is discarding a domino")
	
	# 1. Select domino to discard (prefer non-doubles)
	var discard_index = 0
	for i in range(ai_hand.size()):
		if ai_hand[i][0] != ai_hand[i][1]:
			discard_index = i
			break
	
	var discarded_values = ai_hand[discard_index]
	
	# 2. Visual feedback
	var visual_domino = domino_factory.create_specific_domino(discarded_values[0], discarded_values[1])
	add_child(visual_domino)
	visual_domino.global_position = Vector3(0, 2, 0)
	visual_domino.set_highlight(true, Color.PURPLE)
	
	# 3. Animate the discard
	var tween = create_tween()
	tween.tween_property(visual_domino, "position:y", 0, 0.3)
	await tween.finished
	
	# 4. Return to pool and shuffle
	domino_pool.append(discarded_values)
	ai_hand.remove_at(discard_index)
	domino_pool.shuffle()
	
	# 5. Draw new random domino
	if domino_pool.size() > 0:
		var new_values = domino_pool.pop_back()
		while new_values == discarded_values and domino_pool.size() > 1:
			domino_pool.append(new_values)
			domino_pool.shuffle()
			new_values = domino_pool.pop_back()
		
		ai_hand.append(new_values)
	
	visual_domino.queue_free()
	end_ai_turn()

### GAMEPLAY LOGIC ============================================================
func can_place_on_track(domino: Domino, track_idx: int) -> bool:
	var track = tracks[track_idx]

	if track.pieces.size() >= TRACK_LENGTH:
		return false

	if domino.is_power_domino:
		return true  # Power dominos can be placed anywhere

	if track.pieces.is_empty():
		return true

	var last = track.pieces.back()
	var visible_end = last.bottom_value if last.display_top else last.top_value

	if domino.top_value == visible_end or domino.bottom_value == visible_end:
		if track.pieces.size() == TRACK_LENGTH - 1:
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
	if pos_idx > 0 and not domino.is_power_domino:
		var last = track.pieces.back()
		var must_match = last.bottom_value if last.display_top else last.top_value

		if domino.top_value == must_match:
			domino.display_top = true
		elif domino.bottom_value == must_match:
			domino.display_top = false
		else:
			return false

		domino.update_dots()

	# Place the domino physically
	domino.freeze = false
	if domino.get_parent() != self:
		add_child(domino)

	domino.global_transform = track.positions[pos_idx].global_transform
	domino.global_position.y += 0.2

	# Removed await here — just proceed immediately

	domino.freeze = true

	# Add to track
	track.pieces.append(domino)
	if not is_starting_domino:
		player_hand.erase(domino)

	# Check for double domino
	if not is_starting_domino and domino.top_value == domino.bottom_value:
		has_extra_turn = true
		var tween = create_tween()
		tween.tween_property(domino, "scale", Vector3(1.3, 1.3, 1.3), 0.2)
		tween.tween_property(domino, "scale", Vector3(1, 1, 1), 0.2)
		if has_node("DoubleSound"):
			$DoubleSound.play()

	# Handle selection cleanup
	if domino == selected_domino:
		domino.deselect()
		selected_domino = null
		hide_valid_moves()

	# Refill hand if needed
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
			clear_and_restart_track(track_idx)

	# Only count regular dominos placed by player (not starting dominos or AI)
	if not is_starting_domino and current_turn == "player" and not is_discard_mode:
		regular_dominos_played += 1

	# Check if 3 regular dominos played, then add a power domino if possible
	if regular_dominos_played >= 3 and power_hand.size() < MAX_POWER_DOMINOS:
		regular_dominos_played = 0  # Reset counter
		add_power_domino()

	return true






func add_power_domino():
	print("Adding a power domino now!")
	if power_hand.size() >= MAX_POWER_DOMINOS:
		print("Power hand full, not adding.")
		return

	print("Power domino awarded!")
	var power_domino = domino_factory.create_random_domino()
	power_domino.is_power_domino = true
	power_domino.set_highlight(true, Color(1, 0, 0))  # Red highlight
	power_hand.append(power_domino)
	add_child(power_domino)
	safe_connect_domino_signals(power_domino)  # Connect signals here!
	reposition_power_hand()





func reposition_power_hand():
	var power_hand_center = Vector3(0, 0.2, 2.0)  # In front of regular hand along Z-axis
	for i in power_hand.size():
		power_hand[i].position = power_hand_center + Vector3((i - power_hand.size() * 0.5) * HAND_SPACING, 0, 0)


func clear_and_restart_track(track_idx: int):
	var track = tracks[track_idx]
	
	# Check if this is a valid completion
	var first = track.pieces.front()
	var last = track.pieces.back()
	var first_value = first.top_value if first.display_top else first.bottom_value
	var last_value = last.bottom_value if last.display_top else last.top_value
	
	if first_value != last_value:
		return
	
	# Score points
	if current_turn == "player":
		update_scores(1, 0)
	else:
		update_scores(0, 1)
	
	# Return dominos to pool
	for domino in track.pieces:
		if is_instance_valid(domino):
			domino_pool.append([domino.top_value, domino.bottom_value])
			domino.queue_free()
	
	track.pieces.clear()
	domino_pool.shuffle()
	
	# Restart track
	if domino_pool.size() > 0:
		var new_domino = domino_factory.create_random_domino()
		if new_domino:
			new_domino.is_in_hand = false
			new_domino.place_on_board()
			add_child(new_domino)
			try_place_domino(new_domino, track_idx, true)

### DISCARD SYSTEM ============================================================
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
		button.disabled = true
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
	
	# 4. Draw replacement if pool isn't empty
	if domino_pool.size() > 0 and player_hand.size() < MAX_HAND_SIZE:
		var new_values = domino_pool.pop_back()
		var new_domino = domino_factory.create_specific_domino(new_values[0], new_values[1])
		setup_hand_domino(new_domino, player_hand.size())
		add_child(new_domino)
		player_hand.append(new_domino)
		safe_connect_domino_signals(new_domino)
	
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

### SCORE SYSTEM ==============================================================
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
	
	check_for_winner()

func check_for_winner():
	if player_score >= 3:
		game_winner = "player"
		is_game_over = true
	elif ai_score >= 3:
		game_winner = "ai"
		is_game_over = true
	
	if is_game_over:
		handle_game_over()
		return true
	return false

func handle_game_over():
	set_process_input(false)
	
	await get_tree().create_timer(0.1).timeout
	
	var game_over = GAME_OVER_SCREEN.instantiate()
	add_child(game_over)
	
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
	initialize_game()
	set_process_input(true)
	
	if score_ui.has_node("WinnerLabel"):
		score_ui.get_node("WinnerLabel").visible = false

### VISUAL FEEDBACK ===========================================================
func show_valid_moves(domino: Domino):
	hide_valid_moves()
	
	if not domino or not is_instance_valid(domino):
		return
	
	for track_idx in tracks.size():
		if can_place_on_track(domino, track_idx):
			var track = tracks[track_idx]
			var pos_idx = track.pieces.size()
			
			var indicator = get_or_create_indicator(track)
			indicator.visible = true
			indicator.global_position = track.positions[pos_idx].global_position + Vector3(0, 0.02, 0)
			
			var mat = indicator.get_surface_override_material(0)
			if track.pieces.size() == TRACK_LENGTH - 1:
				mat.albedo_color = Color(1, 0, 0, 0.7)
			else:
				mat.albedo_color = Color(0, 1, 0, 0.5)
			indicator.set_surface_override_material(0, mat)

func hide_valid_moves():
	for track in tracks:
		if track.node.has_node("Indicator"):
			track.node.get_node("Indicator").visible = false

func get_or_create_indicator(track: Dictionary) -> MeshInstance3D:
	if not track.node.has_node("Indicator"):
		var indicator = MeshInstance3D.new()
		indicator.name = "Indicator"
		indicator.mesh = BoxMesh.new()
		indicator.mesh.size = Vector3(0.8, 0.01, 0.8)
		
		var mat = StandardMaterial3D.new()
		mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		indicator.set_surface_override_material(0, mat)
		
		track.node.add_child(indicator)
	
	return track.node.get_node("Indicator")

### INPUT HANDLING ============================================================


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
			var from = camera.project_ray_origin(event.position)
			var to = from + camera.project_ray_normal(event.position) * 100
			
			var query = PhysicsRayQueryParameters3D.create(from, to)
			var result = get_world_3d().direct_space_state.intersect_ray(query)
			
			if result and result.collider is StaticBody3D:
				for i in tracks.size():
					if tracks[i]["static_body"] == result.collider and can_place_on_track(selected_domino, i):
						var success = try_place_domino(selected_domino, i)  # sync call
						if success:
							selected_domino = null
							hide_valid_moves()
							end_player_turn()



func _on_domino_selected(domino: Domino):
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
		
		# Update button state
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

func _on_pass_turn_requested():
	if current_turn != "player" or player_has_valid_moves():
		return
	
	if is_discard_mode:
		if discard_candidate:
			if confirm_discard():
				disable_discard_mode()
				end_player_turn()
		else:
			print("No domino selected for discard!")
	else:
		enable_discard_mode()

func _on_discard_confirmed():
	if discard_candidate and confirm_discard():
		end_player_turn()

### PHYSICS ===================================================================
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

func check_pass_button_state():
	if score_ui and score_ui.has_node("PassButton"):
		var can_pass = (current_turn == "player") and not player_has_valid_moves()
		score_ui.get_node("PassButton").visible = can_pass
		score_ui.get_node("PassButton").disabled = not can_pass
