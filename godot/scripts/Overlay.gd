extends Node2D

## 移动/攻击/地雷范围的透明叠加层。绘制逻辑在 Battle.draw_overlay()。

var battle: Node


func _draw() -> void:
	if battle != null and battle.has_method("draw_overlay"):
		battle.draw_overlay(self)
