extends Control

## The cargo hold, full screen: a dimmed backdrop and a HUD plate framing an
## InventoryView. Only the frame lives here - the view is the component, and
## moves on its own if the hold becomes part of a bigger interface. Toggled
## with I; solar_system.gd routes the keys while it is open (arrows move the
## selection, I or Esc close it). The (i) button next to the X lists the keys.

const PANEL_SIZE := Vector2(980.0, 600.0)
const MARGIN := 36.0
const HEADER := 64.0
const PADDING := 22.0

var view: InventoryView
var _system: Node = null
var _inventory: Inventory = null
var _hover_close := false
var _hover_help := false
var _help: HelpPopup


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	view = InventoryView.new()
	add_child(view)
	_help = HelpPopup.new(PackedStringArray([
		"Arrows: select an item",
		"J: switch to the planetary log",
		"I or Esc: close the cargo hold",
	]))
	# Last child, so it draws over the view.
	add_child(_help)
	resized.connect(_layout)
	move_to_front.call_deferred()


## `system` is solar_system.gd.
func setup(system: Node, inventory: Inventory) -> void:
	_system = system
	_inventory = inventory
	view.bind(inventory)
	inventory.changed.connect(queue_redraw)


func toggle() -> void:
	if visible:
		hide_panel()
	else:
		open()


func open() -> void:
	visible = true
	_layout()


func hide_panel() -> void:
	visible = false
	_help.close()


func _panel_rect() -> Rect2:
	var panel_size: Vector2 = PANEL_SIZE.min(size - Vector2.ONE * MARGIN * 2.0)
	return Rect2((size - panel_size) * 0.5, panel_size)


func _close_rect() -> Rect2:
	var panel: Rect2 = _panel_rect()
	return Rect2(Vector2(panel.end.x - 36.0, panel.position.y + 12.0), Vector2(24.0, 24.0))


func _layout() -> void:
	var panel: Rect2 = _panel_rect()
	view.position = panel.position + Vector2(PADDING, HEADER + 14.0)
	view.size = panel.size - Vector2(PADDING * 2.0, HEADER + 14.0 + PADDING)
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
		else:
			_help.close()
			if close.has_point(event.position) or not _panel_rect().has_point(event.position):
				hide_panel()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.7))
	var panel: Rect2 = _panel_rect()
	draw_set_transform(panel.position)
	HudPanelStyle.draw_chamfered(self, panel.size, HudPanelStyle.COLOR_CYAN, 18.0, 0.98)
	draw_set_transform(Vector2.ZERO)

	var font: Font = HudPanelStyle.get_font()
	draw_string(
		font, panel.position + Vector2(22.0, 36.0), "CARGO HOLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		HudPanelStyle.COLOR_TEXT_PRIMARY
	)
	var total: int = _inventory.total() if _inventory != null else 0
	draw_string(
		font, panel.position + Vector2(200.0, 34.0),
		"%d %s" % [total, "ITEM" if total == 1 else "ITEMS"],
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
