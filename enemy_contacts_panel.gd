extends Control
## Enemy contacts, top right: every enemy the combat control holds
## (scripts/ship/CombatControl.gd - passive sensors and radar scans), nearest
## first. Each row: the type's glyph and code, its name, distance and status
## (LOCK 40% / LOCKED / TARGET, or seconds since a radar sweep last saw it).
## Click a row to target it (again to let go); Ctrl+click to lock on - with a
## lock, guns clicked in the weapons panel fire at it on their own. The panel
## grows with the list. solar_system.gd feeds it each frame with set_state().

signal target_picked(enemy: Node2D)
signal lock_requested(enemy: Node2D)

const PAD := 12.0
const ROW_HEIGHT := 30.0
const HEADER := 38.0
const ICON_SIZE := 22.0
const MAX_ROWS := 8
const COLOR_TARGET := Color(1.0, 0.35, 0.3)
const COLOR_LOCKED := Color(1.0, 0.2, 0.15)

## [{enemy, title, kind_id, distance, status}], nearest first.
var _contacts: Array = []
## Shown when the list is empty.
var _status: String = ""
var _target: Node2D = null
var _locked := false
var _hover_row: int = -1
var _hover_help := false
var _help: HelpPopup


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_help = HelpPopup.new(PackedStringArray([
		"Click a contact: target it (again: let go)",
		"Ctrl+click a contact: lock on",
		"With a lock, click a gun in WEAPONS: it fires on its own",
		"R: radar scan (radars reach far, planets hide enemies)",
		"G: fire every gun at the target",
	]))
	add_child(_help)


func set_state(contacts: Array, status: String, target: Node2D, locked: bool) -> void:
	_contacts = contacts
	_status = status
	_target = target
	_locked = locked
	# Grow and shrink with the list.
	var rows: int = clampi(_contacts.size(), 1, MAX_ROWS)
	var height: float = HEADER + rows * ROW_HEIGHT + PAD
	if not is_equal_approx(offset_bottom - offset_top, height):
		offset_bottom = offset_top + height
	queue_redraw()


func _row_rect(i: int) -> Rect2:
	return Rect2(Vector2(PAD * 0.5, HEADER + i * ROW_HEIGHT), Vector2(size.x - PAD, ROW_HEIGHT - 2.0))


func _help_rect() -> Rect2:
	return Rect2(size.x - PAD - 18.0, 8.0, 18.0, 18.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var row: int = _row_at(event.position)
		var over_help: bool = _help_rect().has_point(event.position)
		if row != _hover_row or over_help != _hover_help:
			_hover_row = row
			_hover_help = over_help
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _help_rect().has_point(event.position):
			_help.toggle_at(Vector2(size.x - PAD, _help_rect().end.y + 4.0))
			accept_event()
			return
		_help.close()
		var row: int = _row_at(event.position)
		if row >= 0:
			var enemy: Node2D = _contacts[row]["enemy"]
			if event.ctrl_pressed:
				lock_requested.emit(enemy)
			else:
				target_picked.emit(null if enemy == _target else enemy)
		accept_event()


func _row_at(point: Vector2) -> int:
	for i in mini(_contacts.size(), MAX_ROWS):
		if _row_rect(i).has_point(point):
			return i
	return -1


func _draw() -> void:
	var accent: Color = COLOR_TARGET if _target != null else HudPanelStyle.COLOR_BORDER_DEFAULT
	HudPanelStyle.draw_chamfered(self, size, accent, 14.0, 0.85, 0.65)
	var font: Font = HudPanelStyle.get_font()
	var width: float = size.x - PAD * 2.0
	draw_string(font, Vector2(PAD, 22.0), "CONTACTS", HORIZONTAL_ALIGNMENT_LEFT, width, 13, accent if _target != null else HudPanelStyle.COLOR_CYAN)
	draw_string(
		font, Vector2(PAD, 22.0), "%d" % _contacts.size(), HORIZONTAL_ALIGNMENT_RIGHT, width - 26.0, 12,
		HudPanelStyle.COLOR_TEXT_MUTED
	)
	HelpPopup.draw_button(self, _help_rect(), _hover_help, _help.visible)
	if _contacts.is_empty():
		draw_string(
			font, Vector2(PAD, HEADER + 18.0), _status, HORIZONTAL_ALIGNMENT_LEFT, width, 10, Color(0.55, 0.6, 0.68, 0.8)
		)
		return
	var rows: int = mini(_contacts.size(), MAX_ROWS)
	for i in rows:
		_draw_row(font, _row_rect(i), _contacts[i], i)
	if _contacts.size() > rows:
		draw_string(
			font, Vector2(PAD, size.y - 4.0), "+%d more" % (_contacts.size() - rows), HORIZONTAL_ALIGNMENT_RIGHT,
			width, 9, HudPanelStyle.COLOR_TEXT_MUTED
		)


func _draw_row(font: Font, rect: Rect2, contact: Dictionary, index: int) -> void:
	var picked: bool = contact["enemy"] == _target
	if picked:
		var mark: Color = COLOR_LOCKED if _locked else COLOR_TARGET
		draw_rect(rect, Color(mark, 0.16))
		draw_rect(Rect2(rect.position, Vector2(3.0, rect.size.y)), mark)
	elif index == _hover_row:
		draw_rect(rect, Color(1.0, 1.0, 1.0, 0.05))
	var kind_id: String = str(contact.get("kind_id", "basic"))
	var colour: Color = EnemyCatalog.marker_color(kind_id)
	var icon_center: Vector2 = rect.position + Vector2(PAD + ICON_SIZE * 0.5, rect.size.y * 0.5)
	EnemyCatalog.draw_glyph(self, icon_center, ICON_SIZE * 0.42, kind_id, false)
	var x: float = rect.position.x + PAD + ICON_SIZE + 6.0
	draw_string(font, Vector2(x, rect.position.y + 19.0), EnemyCatalog.abbreviation(kind_id), HORIZONTAL_ALIGNMENT_LEFT, 24.0, 10, colour)
	x += 26.0
	draw_string(
		font, Vector2(x, rect.position.y + 19.0), String(contact["title"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - (x - rect.position.x) - 118.0, 11, colour if picked else HudPanelStyle.COLOR_TEXT_PRIMARY
	)
	draw_string(
		font, Vector2(rect.end.x - 118.0, rect.position.y + 19.0), _distance(float(contact["distance"])),
		HORIZONTAL_ALIGNMENT_RIGHT, 56.0, 10, HudPanelStyle.COLOR_TEXT_SECONDARY
	)
	var status: String = str(contact.get("status", ""))
	var status_colour: Color = HudPanelStyle.COLOR_TEXT_MUTED
	if status == "LOCKED":
		status_colour = COLOR_LOCKED
	elif status.begins_with("LOCK") or status == "TARGET":
		status_colour = COLOR_TARGET
	draw_string(
		font, Vector2(rect.end.x - 58.0, rect.position.y + 19.0), status, HORIZONTAL_ALIGNMENT_RIGHT, 50.0, 9,
		status_colour
	)


static func _distance(value: float) -> String:
	if value >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	return "%d" % int(value)
