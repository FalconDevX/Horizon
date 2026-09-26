extends Control
## Every weapon mounted on the ship, one numbered row each (keys 1-9 pick by
## this order): name, a reload bar, and IN CONE while the target - or, with
## none, the nearest contact - sits in its cone (BLOCKED instead while the
## ship itself is in its line of fire). Click a row to pick that weapon (LMB
## then fires it, RMB turns it if it is a turret) - or, with a target locked
## in the contacts panel, to set it firing on its own (AUTO) until clicked
## again. Drag a row up or down to reorder. Radars follow the guns: click one
## (or press R) to scan; its bar shows the scan, then the recharge.
## Fed each frame by solar_system.gd with set_state().

signal weapon_picked(instance_id: int)
signal order_changed(instance_ids: Array)
signal radar_scan_requested(instance_id: int)

const PAD := 12.0
const ROW_HEIGHT := 28.0
const HEADER := 38.0
const DRAG_THRESHOLD := 6.0
const COLOR_READY := HudPanelStyle.COLOR_EMERALD
const COLOR_RELOAD := HudPanelStyle.COLOR_AMBER
const COLOR_ON_TARGET := Color(1.0, 0.35, 0.3)
const COLOR_PICKED := HudPanelStyle.COLOR_CYAN
const COLOR_AUTO := Color(1.0, 0.2, 0.15)
const COLOR_RADAR := Color(0.3, 1.0, 0.45)

## [{id, title, reload (0 loaded .. 1 just fired), on_target, auto}], in
## panel order, then the radars: [{id, title, radar, scan, reload}].
var _weapons: Array = []
var _powered := true
var _selected: int = -1
## A target is locked: clicking a gun sets it on auto-fire.
var _locked := false
var _hover_help := false
var _help: HelpPopup
var _hover_row: int = -1
## Row pressed and where; becomes a drag once the mouse moves far enough.
var _press_row: int = -1
var _press_pos := Vector2.ZERO
var _dragging := false
var _mouse := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_help = HelpPopup.new(PackedStringArray([
		"1-9 or click: pick a gun (again: put it away)",
		"LMB (hold): fire the picked gun",
		"RMB (hold): turn the picked turret to the cursor",
		"With a target locked: click a gun to fire on its own",
		"Click a radar or press R: scan",
		"Drag a row: reorder",
	]))
	add_child(_help)


func set_state(weapons: Array, powered: bool, selected: int, locked: bool = false) -> void:
	_weapons = weapons
	_powered = powered
	_selected = selected
	_locked = locked
	queue_redraw()


func _help_rect() -> Rect2:
	return Rect2(size.x - PAD - 18.0, 8.0, 18.0, 18.0)


func _row_rect(i: int) -> Rect2:
	return Rect2(Vector2(PAD * 0.5, HEADER + i * ROW_HEIGHT), Vector2(size.x - PAD, ROW_HEIGHT - 2.0))


func _max_rows() -> int:
	return maxi(int((size.y - HEADER - 22.0) / ROW_HEIGHT), 1)


func _row_at(point: Vector2, clamp_to_rows: bool = false) -> int:
	var rows: int = mini(_weapons.size(), _max_rows())
	if rows == 0:
		return -1
	var index: int = int(floor((point.y - HEADER) / ROW_HEIGHT))
	if clamp_to_rows:
		return clampi(index, 0, rows - 1)
	return index if index >= 0 and index < rows and point.x >= 0.0 and point.x <= size.x else -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_help = _help_rect().has_point(event.position)
		_mouse = event.position
		if _press_row >= 0 and not _dragging and _mouse.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragging = true
		_hover_row = _row_at(_mouse)
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _help_rect().has_point(event.position):
			_help.toggle_at(Vector2(size.x - PAD, _help_rect().end.y + 4.0))
			accept_event()
			return
		if event.pressed:
			_help.close()
			_press_row = _row_at(event.position)
			_press_pos = event.position
			_dragging = false
		else:
			if _press_row >= 0:
				var row: Dictionary = _weapons[_press_row]
				if row.get("radar", false):
					radar_scan_requested.emit(int(row["id"]))
				elif _dragging:
					_drop(_row_at(event.position, true))
				else:
					weapon_picked.emit(int(row["id"]))
			_press_row = -1
			_dragging = false
			queue_redraw()
		accept_event()


## Moves the dragged row to `to` and reports the new order.
func _drop(to: int) -> void:
	if to < 0 or to == _press_row:
		return
	# Only the guns reorder; radars stay below them.
	var guns: Array = _weapons.filter(func(w: Dictionary) -> bool: return not w.get("radar", false))
	if _press_row >= guns.size() or to >= guns.size():
		return
	var ids: Array = guns.map(func(w: Dictionary) -> int: return int(w["id"]))
	var moved: int = ids[_press_row]
	ids.remove_at(_press_row)
	ids.insert(to, moved)
	order_changed.emit(ids)


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_BORDER_DEFAULT, 14.0, 0.85, 0.55)
	var font: Font = HudPanelStyle.get_font()
	var width: float = size.x - PAD * 2.0
	draw_string(font, Vector2(PAD, 22.0), "WEAPONS", HORIZONTAL_ALIGNMENT_LEFT, width, 13, HudPanelStyle.COLOR_CYAN)
	HelpPopup.draw_button(self, _help_rect(), _hover_help, _help.visible)
	if _weapons.is_empty():
		draw_string(font, Vector2(PAD, HEADER + 14.0), "No weapons mounted", HORIZONTAL_ALIGNMENT_LEFT, width, 11, Color(0.55, 0.6, 0.68, 0.8))
		return
	var rows: int = mini(_weapons.size(), _max_rows())
	for i in rows:
		var weapon: Dictionary = _weapons[i]
		var rect: Rect2 = _row_rect(i)
		if _dragging and i == _press_row:
			draw_rect(rect, Color(1.0, 1.0, 1.0, 0.03))
			continue
		_draw_row(font, rect, weapon, i)
	if _dragging and _press_row >= 0 and _press_row < _weapons.size():
		# The dragged row follows the mouse, with a line where it would land.
		var landing: int = _row_at(_mouse, true)
		var line_y: float = HEADER + (landing + (1 if landing > _press_row else 0)) * ROW_HEIGHT - 1.0
		draw_line(Vector2(PAD, line_y), Vector2(size.x - PAD, line_y), COLOR_PICKED, 2.0)
		var ghost := Rect2(Vector2(PAD * 0.5, _mouse.y - ROW_HEIGHT * 0.5), Vector2(size.x - PAD, ROW_HEIGHT - 2.0))
		draw_rect(ghost, Color(HudPanelStyle.COLOR_BG_SURFACE, 0.95))
		draw_rect(ghost, COLOR_PICKED, false, 1.0)
		_draw_row(font, ghost, _weapons[_press_row], _press_row)
	if not _powered:
		draw_string(font, Vector2(PAD, size.y - 10.0), "NO POWER", HORIZONTAL_ALIGNMENT_LEFT, width, 10, HudPanelStyle.COLOR_AMBER)
	if _weapons.size() > rows:
		draw_string(
			font, Vector2(PAD, size.y - 10.0), "+%d more" % (_weapons.size() - rows), HORIZONTAL_ALIGNMENT_RIGHT,
			width, 10, HudPanelStyle.COLOR_TEXT_MUTED
		)


func _draw_row(font: Font, rect: Rect2, weapon: Dictionary, index: int) -> void:
	if weapon.get("radar", false):
		_draw_radar_row(font, rect, weapon, index)
		return
	var picked: bool = int(weapon["id"]) == _selected
	if picked:
		draw_rect(rect, Color(COLOR_PICKED, 0.14))
		draw_rect(Rect2(rect.position, Vector2(3.0, rect.size.y)), COLOR_PICKED)
	elif index == _hover_row and not _dragging:
		draw_rect(rect, Color(1.0, 1.0, 1.0, 0.05))
	var reload: float = float(weapon["reload"])
	var loaded: bool = reload <= 0.0 and _powered
	var x: float = rect.position.x + 8.0
	var key: String = str(index + 1) if index < 9 else ""
	draw_string(font, Vector2(x, rect.position.y + 13.0), key, HORIZONTAL_ALIGNMENT_LEFT, 14.0, 10, COLOR_PICKED if picked else HudPanelStyle.COLOR_TEXT_MUTED)
	draw_string(
		font, Vector2(x + 16.0, rect.position.y + 13.0), String(weapon["title"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 70.0, 10, HudPanelStyle.COLOR_TEXT_PRIMARY if loaded or picked else HudPanelStyle.COLOR_TEXT_SECONDARY
	)
	if weapon.get("auto", false):
		draw_string(font, Vector2(rect.position.x, rect.position.y + 13.0), "AUTO", HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8.0, 9, COLOR_AUTO)
	elif weapon.get("blocked", false):
		# Its own ship is in the line of fire: it holds.
		draw_string(font, Vector2(rect.position.x, rect.position.y + 13.0), "BLOCKED", HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8.0, 9, HudPanelStyle.COLOR_AMBER)
	elif weapon["on_target"]:
		draw_string(font, Vector2(rect.position.x, rect.position.y + 13.0), "IN CONE", HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8.0, 9, COLOR_ON_TARGET)
	# Reload bar: fills back up as the weapon reloads.
	var bar := Rect2(Vector2(x + 16.0, rect.position.y + 18.0), Vector2(rect.size.x - 32.0, 4.0))
	draw_rect(bar, Color(HudPanelStyle.COLOR_BORDER_DEFAULT, 0.5))
	var fill: float = 1.0 - clampf(reload, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), COLOR_READY if loaded else COLOR_RELOAD)


## A radar: green while scanning (the bar runs down), amber while it
## recharges (the bar fills back up), READY when it can scan again.
func _draw_radar_row(font: Font, rect: Rect2, radar: Dictionary, index: int) -> void:
	if index == _hover_row and not _dragging:
		draw_rect(rect, Color(1.0, 1.0, 1.0, 0.05))
	var scan: float = float(radar.get("scan", 0.0))
	var reload: float = float(radar.get("reload", 0.0))
	var x: float = rect.position.x + 8.0
	draw_arc(Vector2(x + 5.0, rect.position.y + 9.0), 4.0, 0.0, TAU, 16, COLOR_RADAR, 1.2, true)
	draw_string(
		font, Vector2(x + 16.0, rect.position.y + 13.0), String(radar["title"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 80.0, 10, HudPanelStyle.COLOR_TEXT_PRIMARY
	)
	var state: String = "SCAN" if scan > 0.0 else ("RECHARGE" if reload > 0.0 else "READY")
	var state_colour: Color = COLOR_RADAR if scan > 0.0 or reload <= 0.0 else COLOR_RELOAD
	draw_string(font, Vector2(rect.position.x, rect.position.y + 13.0), state, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8.0, 9, state_colour)
	var bar := Rect2(Vector2(x + 16.0, rect.position.y + 18.0), Vector2(rect.size.x - 32.0, 4.0))
	draw_rect(bar, Color(HudPanelStyle.COLOR_BORDER_DEFAULT, 0.5))
	var fill: float = scan if scan > 0.0 else 1.0 - clampf(reload, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), state_colour)

