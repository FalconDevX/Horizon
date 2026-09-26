extends Control
## The module rack, EVE-style: every gun a round slot in the top row (keys
## 1-9 pick them, in this order), the radars in the row below, offset half a
## slot. Each slot shows the module's art in a circle; its rim tells the state
## - green ready, amber reloading (an amber bar runs round the rim as the
## reload fills, a glint circling it), cyan switched on (click or 1-9) -
## blinking while there is no lock to fire at - grey without power -
## a red dot when the target is in its cone, amber when its own ship is in
## the line of fire. A radar's rim is green; scanning, a green beam turns in
## it. A Rocket Launcher shows its magazine as pips along the foot, in the
## loaded missile's colour. The hovered slot's name and state are written
## above the rack.
##
## Click a gun (or press its key 1-9) to switch it on or off, EVE-style: on,
## it fires by itself at the locked target, or waits for a lock; it is also
## picked for manual fire (LMB fires, RMB turns a turret). Right-click a
## Rocket Launcher to pick its missiles from a list over the slot. Click a
## radar (or press R) to scan. Drag a gun along the row to reorder. No panel
## is drawn behind the slots. Fed each frame by solar_system.gd with
## set_state().

signal weapon_picked(instance_id: int)
signal order_changed(instance_ids: Array)
signal radar_scan_requested(instance_id: int)
signal missile_type_picked(instance_id: int, type: StringName)

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
## The launcher whose missile list is open (slot index), or -1.
var _picker: int = -1
## The list row under the mouse, or -1.
var _picker_hover: int = -1

const PICKER_WIDTH := 200.0
const PICKER_ROW := 24.0
const PICKER_HEADER := 20.0
const PICKER_PAD := 6.0


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
	if _picker >= _weapons.size() or (_picker >= 0 and not _weapons[_picker].has("missile_options")):
		_close_picker()
	# One row of guns, a second only when radars are fitted; the rack keeps
	# its bottom edge and grows upward.
	var rows: int = 2 if _gun_count() < _weapons.size() else 1
	var height: float = HEADER + PAD * 2.0 + rows * SLOT + (rows - 1) * ROW_GAP + 8.0
	if not is_equal_approx(offset_bottom - offset_top, height):
		offset_top = offset_bottom - height
	queue_redraw()


## No panel behind the rack: only the slots (and an open missile list) take
## the mouse, the gaps between them let clicks through to the world.
func _has_point(point: Vector2) -> bool:
	return _dragging or _slot_at(point) >= 0 or _picker_rect().has_point(point)


## Whether the mouse is on the rack now - RMB there is not turret aiming.
func holds_mouse() -> bool:
	return is_visible_in_tree() and _has_point(get_local_mouse_position())


## The open missile list's options, or [] when none is open.
func _picker_options() -> Array:
	if _picker < 0 or _picker >= _weapons.size():
		return []
	return _weapons[_picker].get("missile_options", [])


## Where the missile list stands: over its slot, growing upward.
func _picker_rect() -> Rect2:
	if _picker < 0 or _picker >= _weapons.size():
		return Rect2()
	var rows: int = maxi(_picker_options().size(), 1)
	var height: float = PICKER_HEADER + rows * PICKER_ROW + PICKER_PAD * 2.0
	var c: Vector2 = _slot_center(_picker)
	return Rect2(Vector2(c.x - SLOT * 0.5, c.y - SLOT * 0.5 - 8.0 - height), Vector2(PICKER_WIDTH, height))


func _picker_row_at(point: Vector2) -> int:
	var rect: Rect2 = _picker_rect()
	if not rect.has_point(point):
		return -1
	var row: int = floori((point.y - rect.position.y - PICKER_PAD - PICKER_HEADER) / PICKER_ROW)
	return row if row >= 0 and row < _picker_options().size() else -1


func _close_picker() -> void:
	_picker = -1
	_picker_hover = -1
	queue_redraw()


## A click anywhere off the open list (or Esc) closes it.
func _input(event: InputEvent) -> void:
	if _picker < 0:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_picker()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if not _picker_rect().has_point(local) and _slot_at(local) != _picker:
			_close_picker()


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
		_picker_hover = _picker_row_at(event.position)
		if _press >= 0 and not _dragging and _mouse.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragging = not _weapons[_press].get("radar", false)
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			# RMB on a launcher opens (or closes) its missile list.
			var slot: int = _slot_at(event.position)
			if slot >= 0 and _weapons[slot].has("missile_options"):
				if _picker == slot:
					_close_picker()
				else:
					_picker = slot
					_picker_hover = -1
					queue_redraw()
			elif _picker >= 0:
				_close_picker()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _picker >= 0 \
			and _picker_rect().has_point(event.position):
		if not event.pressed:
			var row: int = _picker_row_at(event.position)
			if row >= 0:
				var option: Dictionary = _picker_options()[row]
				missile_type_picked.emit(int(_weapons[_picker]["id"]), option["type"])
				_close_picker()
		accept_event()
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
	if _picker >= 0:
		_draw_picker(font)


## The hovered slot, for the caption: name and state.
func _describe(w: Dictionary) -> String:
	var title: String = String(w["title"]).to_upper()
	if w.get("radar", false):
		if float(w.get("scan", 0.0)) > 0.0:
			return title + "  SCANNING"
		return title + ("  RECHARGING" if float(w.get("reload", 0.0)) > 0.0 else "  READY")
	if w.has("missile"):
		var m: Dictionary = w["missile"]
		var load_text: String = "%s %d/%d" % [String(m["name"]).to_upper(), int(m["loaded"]), int(m["capacity"])]
		if m["reloading"]:
			load_text += "  RELOADING"
		elif int(m["loaded"]) == 0 and int(m["stock"]) == 0:
			load_text += "  NO MISSILES"
		return title + "  " + load_text + ("  ON" if w.get("auto", false) else "")
	if w.get("auto", false):
		return title + ("  ACTIVE" if _locked else "  ON, NO LOCK")
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
	elif w.get("auto", false) and not _locked:
		# On with nothing locked: blinks, waiting for a lock to fire at.
		rim = Color(COLOR_PICKED, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008))
	elif picked or w.get("auto", false):
		rim = COLOR_PICKED
	elif reload > 0.0:
		rim = COLOR_RELOAD
	_draw_slot_base(c, r, w, index)
	if reload > 0.0:
		# Dimmed while it reloads; the bar round the rim fills as it goes.
		draw_circle(c, r - 2.0, Color(0.0, 0.0, 0.0, 0.35))
		draw_arc(c, r - 1.0, 0.0, TAU, 40, Color(rim, 0.35), 1.6, true)
		_draw_progress_ring(c, r - 1.0, 1.0 - reload, COLOR_RELOAD)
	else:
		draw_arc(c, r - 1.0, 0.0, TAU, 40, rim, 2.5 if picked or w.get("auto", false) else 1.6, true)
	if w.has("missile"):
		_draw_magazine(c, r, w["missile"])
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
	var rim: Color = COLOR_OFF if not _powered else (COLOR_RELOAD if reload > 0.0 and scan <= 0.0 else COLOR_RADAR)
	if reload > 0.0 and scan <= 0.0:
		draw_circle(c, r - 2.0, Color(0.0, 0.0, 0.0, 0.35))
		draw_arc(c, r - 1.0, 0.0, TAU, 40, Color(rim, 0.35), 1.6, true)
		_draw_progress_ring(c, r - 1.0, 1.0 - reload, COLOR_RELOAD)
	else:
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


## A reload bar round the rim: `done` (0..1) of it filled from the top,
## clockwise, a bright head at its tip and a glint circling the whole ring
## so a slow reload still shows it is working.
func _draw_progress_ring(c: Vector2, r: float, done: float, colour: Color) -> void:
	done = clampf(done, 0.0, 1.0)
	var start: float = -PI * 0.5
	if done > 0.0:
		draw_arc(c, r, start, start + TAU * done, maxi(int(48 * done), 2), colour, 3.0, true)
		draw_circle(c + Vector2.from_angle(start + TAU * done) * r, 2.2, Color(1.0, 0.95, 0.8))
	var spin: float = start + fposmod(Time.get_ticks_msec() / 1000.0 * TAU / 1.4, TAU)
	draw_arc(c, r, spin, spin + 0.55, 8, Color(colour, 0.55), 2.0, true)


## A launcher's magazine: a pip per missile it holds along the slot's foot,
## lit in the loaded type's colour, hollow when spent.
func _draw_magazine(c: Vector2, r: float, m: Dictionary) -> void:
	var capacity: int = int(m["capacity"])
	var colour: Color = m["color"]
	for k in capacity:
		var at := c + Vector2((float(k) - (capacity - 1) * 0.5) * 8.0, r - 6.0)
		draw_circle(at, 3.2, Color(0.02, 0.03, 0.05, 0.9))
		if k < int(m["loaded"]):
			draw_circle(at, 2.4, colour)
		else:
			draw_arc(at, 2.4, 0.0, TAU, 10, Color(colour, 0.5), 1.0, true)


## The open missile list over a launcher: every type it can load, with how
## many the hold has (∞ in god mode); the loaded type is marked.
func _draw_picker(font: Font) -> void:
	var rect: Rect2 = _picker_rect()
	var options: Array = _picker_options()
	var current: StringName = (_weapons[_picker].get("missile", {}) as Dictionary).get("type", &"")
	draw_rect(rect, Color(0.03, 0.05, 0.08, 0.96))
	draw_rect(rect, Color(HudPanelStyle.COLOR_CYAN, 0.6), false, 1.0)
	draw_string(font, rect.position + Vector2(PICKER_PAD + 2.0, PICKER_PAD + 12.0), "MISSILES", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HudPanelStyle.COLOR_TEXT_MUTED)
	if options.is_empty():
		draw_string(font, rect.position + Vector2(PICKER_PAD + 2.0, PICKER_PAD + PICKER_HEADER + 15.0), "None in the hold", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - PICKER_PAD * 2.0, 11, HudPanelStyle.COLOR_AMBER)
		return
	for i in options.size():
		var option: Dictionary = options[i]
		var row := Rect2(
			rect.position + Vector2(PICKER_PAD, PICKER_PAD + PICKER_HEADER + i * PICKER_ROW),
			Vector2(rect.size.x - PICKER_PAD * 2.0, PICKER_ROW - 2.0)
		)
		var is_current: bool = option["type"] == current
		if i == _picker_hover:
			draw_rect(row, Color(1.0, 1.0, 1.0, 0.08))
		if is_current:
			draw_rect(row, Color(HudPanelStyle.COLOR_CYAN, 0.12))
			draw_rect(Rect2(row.position, Vector2(2.0, row.size.y)), HudPanelStyle.COLOR_CYAN)
		MissileCatalog.draw_icon(self, row.position + Vector2(18.0, row.size.y * 0.5), 24.0, option["type"])
		draw_string(font, row.position + Vector2(36.0, row.size.y * 0.5 + 4.0), String(option["name"]), HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 80.0, 11,
			HudPanelStyle.COLOR_CYAN if is_current else HudPanelStyle.COLOR_TEXT_PRIMARY)
		var count: int = int(option["count"])
		var count_text: String = "∞" if count < 0 else "×%d" % count
		draw_string(font, row.position + Vector2(0.0, row.size.y * 0.5 + 4.0), count_text, HORIZONTAL_ALIGNMENT_RIGHT, row.size.x - 4.0, 11,
			HudPanelStyle.COLOR_TEXT_SECONDARY if count != 0 else HudPanelStyle.COLOR_AMBER)
