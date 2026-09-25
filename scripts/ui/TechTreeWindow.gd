class_name TechTreeWindow
extends Control
## Full-screen window for the module tech tree (TechTreePanel), framed like
## the planet catalog. Toggled with T (solar_system.gd routes the keys while
## it is open); Esc, the X or a click outside closes it.

const MARGIN := 36.0

var _panel: TechTreePanel
var _hover_close: bool = false
var _hover_help: bool = false
var _help: HelpPopup


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_panel = TechTreePanel.new()
	add_child(_panel)
	_help = HelpPopup.new(PackedStringArray([
		"T or Esc: close the tech tree",
	]))
	add_child(_help)
	resized.connect(_layout)
	_layout()


func toggle() -> void:
	if visible:
		hide_window()
	else:
		open()


func open() -> void:
	visible = true
	move_to_front()
	_panel.refresh()
	_layout()


func hide_window() -> void:
	visible = false
	_help.close()


func _panel_rect() -> Rect2:
	return Rect2(Vector2.ONE * MARGIN, size - Vector2.ONE * MARGIN * 2.0)


func _close_rect() -> Rect2:
	var panel: Rect2 = _panel_rect()
	return Rect2(Vector2(panel.end.x - 36.0, panel.position.y + 12.0), Vector2(24.0, 24.0))


func _layout() -> void:
	var panel: Rect2 = _panel_rect()
	_panel.position = panel.position + Vector2(18.0, 64.0)
	_panel.size = panel.size - Vector2(36.0, 82.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hover: bool = _close_rect().has_point(event.position)
		var hover_help: bool = HelpPopup.button_rect(_close_rect()).has_point(event.position)
		if hover != _hover_close or hover_help != _hover_help:
			_hover_close = hover
			_hover_help = hover_help
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var close: Rect2 = _close_rect()
		if HelpPopup.button_rect(close).has_point(event.position):
			_help.toggle_at(Vector2(close.end.x, close.end.y + 10.0))
			queue_redraw()
			accept_event()
			return
		_help.close()
		queue_redraw()
		if _close_rect().has_point(event.position) or not _panel_rect().has_point(event.position):
			hide_window()
	accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.8))
	var panel: Rect2 = _panel_rect()
	draw_set_transform(panel.position)
	HudPanelStyle.draw_chamfered(self, panel.size, HudPanelStyle.COLOR_CYAN, 18.0, 0.98)
	draw_set_transform(Vector2.ZERO)

	var font: Font = HudPanelStyle.get_font()
	draw_string(
		font, panel.position + Vector2(22.0, 36.0), "TECH TREE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, HudPanelStyle.COLOR_TEXT_PRIMARY
	)
	draw_string(
		font, panel.position + Vector2(170.0, 36.0), "SHIP MODULES",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudPanelStyle.COLOR_TEXT_MUTED
	)
	var close: Rect2 = _close_rect()
	HelpPopup.draw_button(self, HelpPopup.button_rect(close), _hover_help, _help.visible)
	draw_string(
		font, close.position + Vector2(5.0, 18.0), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		HudPanelStyle.COLOR_TEXT_PRIMARY if _hover_close else HudPanelStyle.COLOR_TEXT_MUTED
	)
	draw_line(
		panel.position + Vector2(18.0, 50.0), Vector2(panel.end.x - 18.0, panel.position.y + 50.0),
		Color(HudPanelStyle.COLOR_TEXT_FAINT, 0.8), 1.0
	)
