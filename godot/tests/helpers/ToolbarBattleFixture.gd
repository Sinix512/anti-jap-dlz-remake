extends "res://scripts/Battle.gd"
# Isolated policy dispatch observer; never a campaign-play certificate.
var requested_end_turn:Array=[]
func _on_end_turn(remaining_ai:=false) -> void:
	requested_end_turn.append(remaining_ai)
