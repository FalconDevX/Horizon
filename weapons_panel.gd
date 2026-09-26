extends Control
## The module rack, EVE-style: every gun a round slot in the top row (keys
## 1-9 pick them, in this order), the radars in the row below, offset half a
## slot. Each slot shows the module's art in a circle; its rim tells the state
## - green ready, amber reloading (a dark clock-hand sweep covers what is
## left of the reload), cyan picked, pulsing red AUTO, grey without power -
## a red dot when the target is in its cone, amber when its own ship is in
## the line of fire. A radar's rim is green; scanning, a green beam turns in
## it. The hovered slot's name and state are written above the rack.
##
## Click a gun to pick it (LMB then fires it, RMB turns a turret) - or, with a
## target locked in the contacts panel, to set it firing on its own (AUTO)
## until clicked again. Click a radar (or press R) to scan. Drag a gun along
## the row to reorder. No panel is drawn behind the slots. Fed each frame
## by solar_system.gd with set_state().

signal weapon_picked(instance_id: int)
signal order_changed(instance_ids: Array)
signal radar_scan_requested(instance_id: int)

const PAD := 10.0
const HEADER := 22.0
const SLOT := 40.0
const GAP := 6.0
const ROW_GAP := 4.0
const DRAG_THRESHOLD := 6.0
const COLOR_READY := HudPanelStyle.COLOR_EMERALD
const COLOR_RELOAD := HudPanelStyle.COLOR_AMBER
const COLOR_ON_TARGET := Color(1.0, 0.35, 0.3)
const COLOR_PICKED := HudPanelStyle.COLOR_CYAN
const COLOR_AUTO := Color(1.0, 0.2, 0.15)
const COLOR_RADAR := Color(0.3, 1.0, 0.45)
const COLOR_OFF := Color(0.45, 0.5, 0.58)
const SLOT_BG := Color(0.03, 0.05, 0.08, 0.92)

## Guns: [{id, module_id, title, reload (0 loaded .. 1 just fired),
## on_target, blocked, auto}] in rack order, then the radars:
## [{id, module_id, title, radar, scan, reload}].
var _weapons: Array = []
var _powered := true
var _selected: int = -1
var _locked := false
var _hover: int = -1
## Slot pressed and where; becomes a drag once the mouse moves far enough.
var _press: int = -1
var _press_pos := Vector2.ZERO
var _dragging := false
var _mouse := Vector2.ZERO
## Module id -> its art (or null when there is none).
var _icons: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func() -> void:
		_hover = -1
		queue_redraw()
	)


func set_state(weapons: Array, powered: bool, selected: int, locked: bool = false) -> void:
	_weapons = weapons
	_powered = powered
	_selected = selected
	_locked = locked
	# One row of guns, a second only when radars are fitted; the rack keeps
	# its bottom edge and grows upward.
	var rows: int = 2 if _gun_count() < _weapons.size() else 1
	var height: float = HEADER + PAD * 2.0 + rows * SLOT + (rows - 1) * ROW_GAP + 8.0
	if not is_equal_approx(offset_bottom - offset_top, height):
		offset_top = offset_bottom - height
	queue_redraw()


## No panel behind the rack: only the slots take the mouse, the gaps
## between them let clicks through to the world.
func _has_point(point: Vector2) -> bool:
	return _dragging or _slot_at(point) >= 0


func _gun_count() -> int:
	var n := 0
	for w: Dictionary in _weapons:
		if not w.get("radar", false):
			n += 1
	return n


## Centre of slot `i` (guns first, then radars on the second row).
func _slot_center(i: int) -> Vector2:
	var guns: int = _gun_count()
	var row: int = 0 if i < guns else 1
	var col: int = i if row == 0 else i - guns
	var x: float = PAD + SLOT * 0.5 + col * (SLOT + GAP) + (SLOT + GAP) * 0.5 * row
	var y: float = HEADER + PAD + SLOT * 0.5 + row * (SLOT + ROW_GAP)
	return Vector2(x, y)


func _slot_at(point: Vector2) -> int:
	for i in _weapons.size():
		if point.distance_to(_slot_center(i)) <= SLOT * 0.5:
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		_hover = _slot_at(event.position)
		if _press >= 0 and not _dragging and _mouse.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragging = not _weapons[_press].get("radar", false)
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press = _slot_at(event.position)
			_press_pos = event.position
			_dragging = false
		else:
			if _press >= 0 and _press < _weapons.size():
				var slot: Dictionary = _weapons[_press]
				if slot.get("radar", false):
					radar_scan_requested.emit(int(slot["id"]))
				elif _dragging:
					_drop(event.position)
				else:
					weapon_picked.emit(int(slot["id"]))
			_press = -1
			_dragging = false
			queue_redraw()
		accept_event()


## Moves the dragged gun to the gun slot nearest `point` along the row.
func _drop(point: Vector2) -> void:
	var guns: int = _gun_count()
	var to: int = clampi(roundi((point.x - PAD - SLOT * 0.5) / (SLOT + GAP)), 0, guns - 1)
	if to == _press:
		return
	var ids: Array = []
	for i in guns:
		ids.append(int(_weapons[i]["id"]))
	var moved: int = ids[_press]
	ids.remove_at(_press)
	ids.insert(to, moved)
	order_changed.emit(ids)


func _icon(module_id: StringName) -> Texture2D:
	if not _icons.has(module_id):
		var path := "res://textures/modules/%s.png" % String(module_id)
		_icons[module_id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[module_id]


func _draw() -> void:
	var font: Font = HudPanelStyle.get_font()
	# Only a name over the hovered slot (or a power warning): no title.
	var caption: String = ""
	var caption_colour: Color = HudPanelStyle.COLOR_CYAN
	if _hover >= 0 and _hover < _weapons.size():
		caption = _describe(_weapons[_hover])
		caption_colour = HudPanelStyle.COLOR_TEXT_PRIMARY
	elif not _powered:
		caption = "NO POWER"
		caption_colour = HudPanelStyle.COLOR_AMBER
	draw_string(font, Vector2(PAD, 16.0), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2.0, 10, caption_colour)
	if _weapons.is_empty():
		draw_string(font, Vector2(PAD, HEADER + PAD + 14.0), "No weapons mounted", HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2.0, 10, HudPanelStyle.COLOR_TEXT_MUTED)
		return
	var guns: int = _gun_count()
	for i in _weapons.size():
		if _dragging and i == _press:
			continue
		var w: Dictionary = _weapons[i]
		if w.get("radar", false):
			_draw_radar_slot(font, _slot_center(i), w, i)
		else:
			_draw_gun_slot(font, _slot_center(i), w, i, i < 9 and i < guns)
	if _dragging and _press >= 0:
		_draw_gun_slot(font, _mouse, _weapons[_press], _press, false)


## The hovered slot, for the caption: name and state.
func _describe(w: Dictionary) -> String:
	var title: String = String(w["title"]).to_upper()
	if w.get("radar", false):
		if float(w.get("scan", 0.0)) > 0.0:
			return title + "  SCANNING"
		return title + ("  RECHARGING" if float(w.get("reload", 0.0)) > 0.0 else "  READY")
	if w.get("auto", false):
		return title + "  AUTO"
	if w.get("blocked", false):
		return title + "  BLOCKED"
	if float(w.get("reload", 0.0)) > 0.0:
		return title + "  RELOADING"
	return title + ("  IN CONE" if w.get("on_target", false) else "  READY")


func _draw_gun_slot(font: Font, c: Vector2, w: Dictionary, index: int, show_key: bool) -> void:
	var r: float = SLOT * 0.5
	var reload: float = clampf(float(w.get("reload", 0.0)), 0.0, 1.0)
	var picked: bool = int(w["id"]) == _selected
	var rim: Color = COLOR_READY
	if not _powered:
		rim = COLOR_OFF
	elif w.get("auto", false):
		rim = Color(COLOR_AUTO, 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012))
	elif picked:
		rim = COLOR_PICKED
	elif reload > 0.0:
		rim = COLOR_RELOAD
	_draw_slot_base(c, r, w, index)
	if reload > 0.0:
		_draw_sweep(c, r - 2.0, reload, Color(0.0, 0.0, 0.0, 0.62))
	draw_arc(c, r - 1.0, 0.0, TAU, 40, rim, 2.5 if picked or w.get("auto", false) else 1.6, true)
	# Target in the cone / own ship in the line of fire.
	if w.get("blocked", false):
		draw_circle(c + Vector2(r * 0.72, -r * 0.72), 3.5, COLOR_RELOAD)
	elif w.get("on_target", false):
		draw_circle(c + Vector2(r * 0.72, -r * 0.72), 3.5, COLOR_ON_TARGET)
	if show_key:
		draw_string(font, c + Vector2(-r, r + 1.0), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, HudPanelStyle.COLOR_TEXT_MUTED)


func _draw_radar_slot(_font: Font, c: Vector2, w: Dictionary, index: int) -> void:
	var r: float = SLOT * 0.5
	var scan: float = float(w.get("scan", 0.0))
	var reload: float = clampf(float(w.get("reload", 0.0)), 0.0, 1.0)
	_draw_slot_base(c, r, w, index)
	if scan > 0.0:
		# The beam turning, as in space.
		var a: float = Time.get_ticks_msec() / 1000.0 * TAU / 1.2
		for k in 6:
			var a0: float = a - 0.18 * (k + 1)
			var a1: float = a - 0.18 * k
			draw_colored_polygon(PackedVector2Array([
				c, c + Vector2.from_angle(a0) * (r - 2.0), c + Vector2.from_angle(a1) * (r - 2.0),
			]), Color(COLOR_RADAR, 0.35 * (1.0 - k / 6.0)))
	elif reload > 0.0:
		_draw_sweep(c, r - 2.0, reload, Color(0.0, 0.0, 0.0, 0.62))
	var rim: Color = COLOR_OFF if not _powered else (COLOR_RELOAD if reload > 0.0 and scan <= 0.0 else COLOR_RADAR)
	draw_arc(c, r - 1.0, 0.0, TAU, 40, rim, 2.4 if scan > 0.0 else 1.6, true)


func _draw_slot_base(c: Vector2, r: float, w: Dictionary, index: int) -> void:
	draw_circle(c, r, SLOT_BG)
	if index == _hover:
		draw_circle(c, r, Color(1.0, 1.0, 1.0, 0.06))
	var icon: Texture2D = _icon(StringName(w.get("module_id", "")))
	if icon != null:
		var box: float = r * 1.35
		var tex: Vector2 = icon.get_size()
		var fit: float = box / maxf(tex.x, tex.y)
		var drawn: Vector2 = tex * fit
		draw_texture_rect(icon, Rect2(c - drawn * 0.5, drawn), false, Color(1, 1, 1, 1.0 if _powered else 0.45))


## A clock-hand sweep over `share` of the circle, from the top clockwise.
func _draw_sweep(c: Vector2, r: float, share: float, colour: Color) -> void:
	var steps: int = maxi(int(40 * share), 2)
	var points := PackedVector2Array([c])
	for k in steps + 1:
		var a: float = -PI * 0.5 + TAU * share * float(k) / steps
		points.append(c + Vector2.from_angle(a) * r)
	draw_colored_polygon(points, colour)
