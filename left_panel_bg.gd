extends PanelContainer


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, Color(0.45, 0.48, 0.55), 16.0, 0.55)
