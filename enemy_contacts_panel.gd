extends Control
## Enemy contacts: every enemy the ship's radars see, nearest first, under
## the autopilot panel. Clicking a row targets that enemy (clicking it again
## lets go): G then fires at it first (solar_system.gd _try_fire_fov_weapon).
## solar_system.gd feeds it each frame with set_state().

signal target_picked(enemy: Node2D)

const PAD := 12.0
const ROW_HEIGHT := 30.0
const HEADER := 38.0
const ICON_SIZE := 22.0
const COLOR_TARGET := Color(1.0, 0.35, 0.3)

## [{enemy, title, distance, kind_id}], nearest first.
var _contacts: Array = []
## "" when the radars work, else why the list is empty ("No radar fitted"...).
var _status: String = ""
var _target: Node2D = null
var _hover_row: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_state(contacts: Array, status: String, target: Node2D) -> void:
	_contacts = contacts
	_status = status
	_target = target
	queue_redraw()


func _row_rect(i: int) -> Rect2:
	return Rect2(Vector2(PAD * 0.5, HEADER + i * ROW_HEIGHT), Vector2(size.x - PAD, ROW_HEIGHT - 2.0))


func _max_rows() -> int:
	return maxi(int((size.y - HEADER - PAD) / ROW_HEIGHT), 1)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var row: int = _row_at(event.position)
		if row != _hover_row:
			_hover_row = row
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var row: int = _row_at(event.position)
		if row >= 0:
			var enemy: Node2D = _contacts[row]["enemy"]
			target_picked.emit(null if enemy == _target else enemy)
		accept_event()


func _row_at(point: Vector2) -> int:
	for i in mini(_contacts.size(), _max_rows()):
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
		font, Vector2(PAD, 22.0), "%d" % _contacts.size(), HORIZONTAL_ALIGNMENT_RIGHT, width, 12,
		HudPanelStyle.COLOR_TEXT_MUTED
	)
	if _contacts.is_empty():
		draw_string(
			font, Vector2(PAD, HEADER + 14.0), _status if _status != "" else "No enemies on radar",
			HORIZONTAL_ALIGNMENT_LEFT, width, 11, Color(0.55, 0.6, 0.68, 0.8)
		)
		return
	var rows: int = mini(_contacts.size(), _max_rows())
	for i in rows:
		var contact: Dictionary = _contacts[i]
		var rect: Rect2 = _row_rect(i)
		var picked: bool = contact["enemy"] == _target
		if picked:
			draw_rect(rect, Color(COLOR_TARGET, 0.16))
			draw_rect(Rect2(rect.position, Vector2(3.0, rect.size.y)), COLOR_TARGET)
		elif i == _hover_row:
			draw_rect(rect, Color(1.0, 1.0, 1.0, 0.05))
		var kind_id: String = str(contact.get("kind_id", "basic"))
		var icon_center: Vector2 = rect.position + Vector2(PAD + ICON_SIZE * 0.5, rect.size.y * 0.5)
		EnemyCatalog.draw_glyph(self, icon_center, ICON_SIZE * 0.42, kind_id, false)
		var name_color: Color = EnemyCatalog.marker_color(kind_id) if picked else HudPanelStyle.COLOR_TEXT_PRIMARY
		draw_string(
			font, rect.position + Vector2(PAD + ICON_SIZE + 6.0, 19.0), String(contact["title"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 110.0 - ICON_SIZE, 11, name_color
		)
		var tag: String = "TARGET" if picked else _distance(float(contact["distance"]))
		draw_string(
			font, rect.position + Vector2(0.0, 19.0), tag, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 10.0, 10,
			COLOR_TARGET if picked else HudPanelStyle.COLOR_TEXT_MUTED
		)
	if _contacts.size() > rows:
		draw_string(
			font, Vector2(PAD, size.y - 10.0), "+%d more" % (_contacts.size() - rows), HORIZONTAL_ALIGNMENT_LEFT,
			width, 10, HudPanelStyle.COLOR_TEXT_MUTED
		)


static func _distance(value: float) -> String:
	if value >= 1000.0:
		return "%.1fk SU" % (value / 1000.0)
	return "%d SU" % int(value)
