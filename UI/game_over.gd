# game_over.gd
extends CanvasLayer

func _on_play_again_pressed():
	get_tree().reload_current_scene()
