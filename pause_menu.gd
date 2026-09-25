extends Control

signal settings_requested
signal save_requested
signal exit_requested

@onready var _settings_btn: Button = %SettingsButton
@onready var _exit_btn: Button = %ExitButton


func _ready() -> void:
	# Save Game goes above Settings; built here so the scene stays as it was.
	var save_btn := Button.new()
	save_btn.name = "SaveButton"
	save_btn.text = "Save Game"
	_settings_btn.add_sibling(save_btn)
	_settings_btn.get_parent().move_child(save_btn, _settings_btn.get_index())
	_style_button(save_btn)
	save_btn.pressed.connect(func() -> void: save_requested.emit())
	# Room for the extra row, grown evenly about the centre.
	offset_top -= 30.0
	offset_bottom += 30.0
	_style_button(_settings_btn)
	_style_button(_exit_btn)
	_settings_btn.pressed.connect(func() -> void: settings_requested.emit())
	_exit_btn.pressed.connect(func() -> void: exit_requested.emit())


func open() -> void:
	visible = true


func close() -> void:
	visible = false


func _style_button(btn: Button) -> void:
	if btn == null:
		return
	var flat := StyleBoxFlat.new()
	flat.bg_color = HudPanelStyle.COLOR_BG_SURFACE
	flat.border_color = HudPanelStyle.COLOR_BORDER_DEFAULT
	flat.set_border_width_all(1)
	flat.set_corner_radius_all(4)
	flat.content_margin_left = 14.0
	flat.content_margin_right = 14.0
	flat.content_margin_top = 10.0
	flat.content_margin_bottom = 10.0
	var flat_hover := flat.duplicate() as StyleBoxFlat
	flat_hover.border_color = HudPanelStyle.COLOR_CYAN
	btn.add_theme_stylebox_override("normal", flat)
	btn.add_theme_stylebox_override("hover", flat_hover)
	btn.add_theme_stylebox_override("pressed", flat_hover)
	btn.add_theme_stylebox_override("focus", flat)
	btn.add_theme_font_override("font", HudPanelStyle.get_font())
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", HudPanelStyle.COLOR_TEXT_SECONDARY)
	btn.add_theme_color_override("font_hover_color", HudPanelStyle.COLOR_CYAN)


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_CYAN, 14.0, 0.94, 0.6)
