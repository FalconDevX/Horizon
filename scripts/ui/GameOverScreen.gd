class_name GameOverScreen
extends CanvasLayer
## Shown once when the ship's hull reaches 0. The game stops behind it (the
## tree is paused) and the only way on is back to the main menu: the run is
## over, its save is gone.

signal menu_requested

const HudPanelStyle = preload("res://hud_panel_style.gd")
const FADE_TIME := 1.2

var _root: Control
var _fade := 0.0


func _init() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallows every click: nothing behind can be used any more.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.modulate.a = 0.0
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.0, 0.0, 0.82)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	_root.add_child(column)

	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", HudPanelStyle.get_font())
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.95, 0.3, 0.25))
	column.add_child(title)

	var line := Label.new()
	line.text = "Your ship was destroyed"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_override("font", HudPanelStyle.get_font())
	line.add_theme_font_size_override("font_size", 16)
	line.add_theme_color_override("font_color", HudPanelStyle.COLOR_TEXT_SECONDARY)
	column.add_child(line)

	var button := Button.new()
	button.text = "MAIN MENU"
	button.custom_minimum_size = Vector2(220, 44)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_override("font", HudPanelStyle.get_font())
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(func() -> void: menu_requested.emit())
	column.add_child(button)


func _process(delta: float) -> void:
	if _fade < FADE_TIME:
		_fade += delta
		_root.modulate.a = clampf(_fade / FADE_TIME, 0.0, 1.0)
