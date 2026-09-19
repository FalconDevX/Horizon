extends PanelContainer


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, Color(0.35, 0.85, 1.0), 18.0, 0.6)
