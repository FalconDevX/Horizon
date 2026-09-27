extends Control

## The new-game tutorial: one HUD card on the right, one step at a time. It
## opens with a few info cards (the goal, how the game works), passed with
## their NEXT button; every step after that is only passed by doing it, and
## each one is checked against the game's own state (solar_system.gd, the
## ship, combat) every frame. The card hides while a full-screen window is open; checks keep
## running underneath, so "open J, then close it" steps work. SKIP SECTION
## jumps to the next section, SKIP ALL ends it (each clicked twice). solar_system.gd adds it on a new game when
## SettingsManager.show_tutorial is on.

signal finished

const WIDTH := 380.0
## Right edge of the screen, under the contacts panel (ends at 300) and above
## the ship schematic.
const TOP := 312.0
const RIGHT_MARGIN := 12.0
const PAD := 16.0
const TITLE_SIZE := 15
const BODY_SIZE := 11
const FADE_RATE := 6.0
## How long the green DONE state shows before the next step.
const DONE_HOLD := 0.9
## The closing card stays up this long (or until clicked).
const OUTRO_TIME := 12.0

var game: Node = null

var _steps: Array[Dictionary] = []
var _index := 0
## Per-step scratch values (timers, "seen" flags), cleared on every step.
var _state: Dictionary = {}
var _done_time := -1.0
var _outro_time := -1.0
## Which skip button was clicked once and waits for the confirming click:
## "", "section" or "all".
var _skip_armed := ""
var _skip_section_rect := Rect2()
var _skip_rect := Rect2()
var _next_rect := Rect2()
var _alpha := 0.0


func setup(game_node: Node) -> void:
	game = game_node
	_build_steps()


func _ready() -> void:
	name = "TutorialPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -WIDTH - RIGHT_MARGIN
	offset_right = -RIGHT_MARGIN
	offset_top = TOP
	modulate.a = 0.0
	_begin_step()


# ------------------------------------------------------------------------------
# Steps
# ------------------------------------------------------------------------------

func _step(section: String, title: String, text: String, keys: Array, check: Callable) -> void:
	_steps.append({"section": section, "title": title, "text": text, "keys": keys, "check": check})


## A card with nothing to do: its NEXT button passes it.
func _info(section: String, title: String, text: String) -> void:
	_steps.append({
		"section": section, "title": title, "text": text, "keys": [], "info": true,
		"check": func(_dt: float) -> bool: return false,
	})


func _build_steps() -> void:
	var ship: Node2D = game.ship

	# BASICS - read while the game waits paused.
	_info("BASICS", "Welcome to Horizon",
		"Your goal: explore the galaxy, chart its worlds and gather their resources, and turn them into a better ship - one strong enough to beat the guards and reach ever more distant, dangerous star systems."
	)
	_info("BASICS", "Real orbits",
		"Everything here moves under gravity: planets circle the star, moons circle planets, and your ship falls round whatever it is near. You do not steer like a car - you fire the engine to change your orbit. The line ahead of the ship shows where it will go."
	)
	_info("BASICS", "How you progress",
		"Land on planets and collect resources. Spend them in the tech tree to unlock modules, then fit those to your hull in the ship builder. Radar and guns deal with enemies. The warp drive hops between planets, hyper warp between star systems."
	)
	_step("BASICS", "Start time",
		"The game starts paused - nothing moves until you say so. Press P or Space to start time, and again whenever you need to stop and think.",
		["P", "SPACE"],
		func(_dt: float) -> bool:
			return not game._user_paused
	)

	# FLIGHT
	_step("FLIGHT", "Turn the ship",
		"Hold A or D (or the arrow keys) to rotate. Turn at least a quarter circle.",
		["A", "D"],
		func(dt: float) -> bool:
			var last: float = _state.get("rot", ship.rotation)
			_state["turned"] = float(_state.get("turned", 0.0)) + absf(angle_difference(last, ship.rotation))
			_state["rot"] = ship.rotation
			return game.landed_body == null and float(_state["turned"]) >= PI * 0.5
	)
	_step("FLIGHT", "Fire the main engine",
		"Hold W for 2 seconds. There is no RCS: all thrust goes out the back, so aim the nose first. Hold Shift for 20% power when you need precision.",
		["W", "SHIFT"],
		func(dt: float) -> bool:
			return _hold("burn", ship.throttle > 0.95 and game.landed_body == null, dt, 2.0)
	)
	_step("FLIGHT", "Cut the engine",
		"Press S. The engine stops at once; with flight assist on, holding S also brakes the ship.",
		["S"],
		func(dt: float) -> bool:
			return _hold("brake", Input.is_key_pressed(KEY_S), dt, 0.5)
	)
	_step("FLIGHT", "Flight assist",
		"Press V to turn flight assist OFF, then V again to turn it back ON. Assist removes sideways drift so the ship goes where the nose points. The ASSIST chip in the HUD shows its state.",
		["V"],
		func(_dt: float) -> bool:
			if not ship.flight_assist:
				_state["off"] = true
			return _state.has("off") and ship.flight_assist
	)
	_step("FLIGHT", "Hold a heading",
		"Press Z to hold prograde (nose along your motion), then C to hold retrograde (nose against it). A, D or pressing the same key again releases the hold.",
		["Z", "C"],
		func(_dt: float) -> bool:
			if ship.attitude_hold == 1:
				_state["pro"] = true
			return _state.has("pro") and ship.attitude_hold == 2
	)
	_step("FLIGHT", "Zoom out",
		"Scroll the mouse wheel down until the view is at least 4x wider than now. The coloured rings are planet orbits; the line from your ship is its predicted path.",
		["WHEEL"],
		func(_dt: float) -> bool:
			if not _state.has("zoom"):
				_state["zoom"] = game.camera_zoom
			return game.camera_zoom <= float(_state["zoom"]) * 0.25
	)
	_step("FLIGHT", "Pan and recentre",
		"Hold the middle mouse button and drag to move the camera. Then press . (period) to lock it back on the ship.",
		["MMB", "."],
		func(_dt: float) -> bool:
			if game.is_dragging:
				_state["dragged"] = true
			return _state.has("dragged") and not game.is_dragging and game.camera_follow_ship and game.camera_follow_body == null
	)

	# LANDING
	_step("LANDING", "Land on a planet",
		"Fly into the disc of any planet. When LAND appears at the top of the screen, press ENTER. Slow down on approach: follow the predicted path and burn against your motion (C, then W).",
		["ENTER"],
		func(_dt: float) -> bool:
			return game.landed_body != null
	)
	_step("LANDING", "Collect a resource",
		"Drive with WASD, or hold RMB to go to the cursor. Stop over a deposit until COLLECT appears, then press E. No deposits on this world? Take off with ENTER and land on another.",
		["WASD", "RMB", "E"],
		func(_dt: float) -> bool:
			if not _state.has("items"):
				_state["items"] = game.inventory.total()
			return game.inventory.total() > int(_state["items"])
	)
	_step("LANDING", "Check the cargo hold",
		"Press I to open the cargo hold and see what you carry. Close it with I or Esc.",
		["I"],
		func(_dt: float) -> bool:
			return _opened_then_closed(game.inventory_screen)
	)
	_step("LANDING", "Take off",
		"Press ENTER. The ship lifts into a circular orbit round the planet. Landing also refills warp fuel.",
		["ENTER"],
		func(_dt: float) -> bool:
			return game.landed_body == null
	)

	# NAVIGATION
	_step("NAVIGATION", "Open the planetary log",
		"Press J. Every planet you fly close to is charted here with its variant and resources. Close it with J or Esc.",
		["J"],
		func(_dt: float) -> bool:
			return _opened_then_closed(game.planet_info_panel)
	)
	_step("NAVIGATION", "Galaxy map",
		"Press M. Select a system and SET COURSE; HYPER WARP then jumps there once you are past the outer asteroid belt. Close the map with M or Esc.",
		["M"],
		func(_dt: float) -> bool:
			return _opened_then_closed(game.galaxy_map_window)
	)

	# COMBAT - before the warp: a planet reached by warp may be guarded.
	_step("COMBAT", "Radar scan",
		"Press R. A green beam sweeps round the ship and puts every enemy it finds in the contacts panel (top right). The radar then needs time to recharge.",
		["R"],
		func(_dt: float) -> bool:
			for radar: Dictionary in game.combat.radars.values():
				if float(radar.get("scan", 0.0)) > 0.0:
					return true
			return false
	)
	_step("COMBAT", "Manual fire",
		"Press 1 to pick your first gun. LMB fires at the cursor, RMB swings the turret. Press 1 again to put it away - while a gun is picked, LMB fires instead of selecting.",
		["1", "LMB", "RMB"],
		func(_dt: float) -> bool:
			if ship.selected_weapon >= 0:
				_state["picked"] = true
			return _state.has("picked") and ship.selected_weapon < 0
	)
	_step("COMBAT", "Automatic fire",
		"Click a gun in the module rack (bottom, right of the gauges) to switch it ON. Click an enemy in the contacts panel to target it, Ctrl+click to lock: active guns then fire by themselves when the lock is in their cone.",
		["LMB"],
		func(_dt: float) -> bool:
			return not game.combat.auto_fire.is_empty()
	)
	_step("SHIP", "Tech tree",
		"Press T. Collected resources pay for new modules here. Close it with T or Esc.",
		["T"],
		func(_dt: float) -> bool:
			return _opened_then_closed(game.tech_tree_window)
	)
	_step("SHIP", "Ship builder",
		"Press B. Fit unlocked modules to your hull: engines on the aft face, guns on the mount ring. Close it with B.",
		["B"],
		func(_dt: float) -> bool:
			return _opened_then_closed(game.ship_builder_panel)
	)

	# WARP - last, since the planet at the far end may be guarded.
	_step("WARP", "Lock a warp target",
		"Hold Ctrl and left-click another planet. A dashed line runs to it. Ctrl+click it again to drop the target.",
		["CTRL", "LMB"],
		func(_dt: float) -> bool:
			return game.warp_target != null
	)
	_step("WARP", "Warp",
		"Fly out of the ring round the planet you are orbiting (its sphere of influence), then press Q or the WARP button. If the jump is blocked, the HUD says why. W, A, S or D while the ship aligns cancels the jump.",
		["Q"],
		func(_dt: float) -> bool:
			return game.warp_active
	)


## True once `condition` has held for `seconds` in total during this step.
func _hold(key: String, condition: bool, dt: float, seconds: float) -> bool:
	if condition:
		_state[key] = float(_state.get(key, 0.0)) + dt
	return float(_state.get(key, 0.0)) >= seconds


func _opened_then_closed(panel: Control) -> bool:
	if panel == null:
		return false
	if panel.visible:
		_state["opened"] = true
	return _state.has("opened") and not panel.visible


# ------------------------------------------------------------------------------
# Running
# ------------------------------------------------------------------------------

func _begin_step() -> void:
	_state.clear()
	_done_time = -1.0
	_skip_armed = ""
	_layout()


func _process(delta: float) -> void:
	if game == null:
		return
	var busy: bool = game.loading_screen != null or game.hyperspace_jump != null
	if _outro_time >= 0.0:
		_outro_time -= delta
		if _outro_time <= 0.0:
			_close()
			return
	elif _done_time >= 0.0:
		_done_time -= delta
		if _done_time < 0.0:
			_go_to(_index + 1)
	elif not busy:
		var check: Callable = _steps[_index]["check"]
		if check.call(delta):
			_done_time = DONE_HOLD
			queue_redraw()

	# Out of the way while a full-screen window or a jump has the screen.
	var shown: bool = not busy and not game._is_menu_open()
	_alpha = move_toward(_alpha, 1.0 if shown else 0.0, FADE_RATE * delta)
	modulate.a = _alpha
	visible = _alpha > 0.0


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	if _outro_time >= 0.0:
		_close()
		return
	if _next_rect.has_point(event.position) and _done_time < 0.0:
		_go_to(_index + 1)
		return
	var clicked := ""
	if _skip_section_rect.has_point(event.position):
		clicked = "section"
	elif _skip_rect.has_point(event.position):
		clicked = "all"
	if clicked != "" and clicked == _skip_armed:
		if clicked == "all":
			_close()
		else:
			_skip_section()
		return
	_skip_armed = clicked
	queue_redraw()


## Moves to step `index`, or to the closing card past the last one.
func _go_to(index: int) -> void:
	_index = index
	if _index >= _steps.size():
		_index = _steps.size() - 1
		_outro_time = OUTRO_TIME
		_done_time = -1.0
		_skip_armed = ""
		_layout()
	else:
		_begin_step()


## Jumps to the first step of the next section (the closing card after the
## last section).
func _skip_section() -> void:
	var section: String = _steps[_index]["section"]
	var next: int = _index
	while next < _steps.size() and _steps[next]["section"] == section:
		next += 1
	_go_to(next)


func _close() -> void:
	finished.emit()
	queue_free()


# ------------------------------------------------------------------------------
# Drawing
# ------------------------------------------------------------------------------

func _title() -> String:
	return "TUTORIAL COMPLETE" if _outro_time >= 0.0 else String(_steps[_index]["title"]).to_upper()


func _text() -> String:
	if _outro_time >= 0.0:
		return "P or Space pauses. X locks the throttle. Esc opens the menu and saves. The tutorial runs on every new game; turn it off in Settings > Gameplay. Click to close."
	return _steps[_index]["text"]


func _text_width() -> float:
	return WIDTH - PAD * 2.0


func _text_height() -> float:
	return HudPanelStyle.get_font().get_multiline_string_size(
		_text(), HORIZONTAL_ALIGNMENT_LEFT, _text_width(), BODY_SIZE
	).y


func _layout() -> void:
	# Header 30, title 24, body, key row 34, progress + skip 34.
	var height: float = 30.0 + 24.0 + _text_height() + 8.0
	if _outro_time < 0.0:
		height += 34.0
	height += 34.0
	offset_bottom = offset_top + height
	queue_redraw()


func _draw() -> void:
	if _steps.is_empty():
		return
	var font: Font = HudPanelStyle.get_font()
	var done: bool = _done_time >= 0.0 or _outro_time >= 0.0
	var accent: Color = HudPanelStyle.COLOR_EMERALD if done else HudPanelStyle.COLOR_CYAN
	HudPanelStyle.draw_chamfered(self, size, accent, 14.0, 0.92, 0.8)
	draw_rect(Rect2(Vector2(0.0, 14.0), Vector2(3.0, size.y - 28.0)), accent)

	# Header: section and step count.
	var header: String = "TUTORIAL"
	if _outro_time < 0.0:
		header = "TUTORIAL  /  %s" % _steps[_index]["section"]
		draw_string(
			font, Vector2(PAD, 22.0), "%d / %d" % [_index + 1, _steps.size()],
			HORIZONTAL_ALIGNMENT_RIGHT, _text_width(), 10, HudPanelStyle.COLOR_TEXT_MUTED
		)
	draw_string(font, Vector2(PAD, 22.0), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HudPanelStyle.COLOR_TEXT_MUTED)

	var y: float = 48.0
	var title: String = _title()
	if _done_time >= 0.0:
		title = "DONE  -  " + title
	draw_string(font, Vector2(PAD, y), title, HORIZONTAL_ALIGNMENT_LEFT, _text_width(), TITLE_SIZE, accent)
	y += 12.0

	draw_multiline_string(
		font, Vector2(PAD, y + font.get_ascent(BODY_SIZE)), _text(), HORIZONTAL_ALIGNMENT_LEFT,
		_text_width(), BODY_SIZE, -1, HudPanelStyle.COLOR_TEXT_SECONDARY,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	)
	y += _text_height() + 8.0

	# Key caps for the step, or NEXT on an info card.
	_next_rect = Rect2()
	if _outro_time < 0.0 and _steps[_index].get("info", false):
		_next_rect = Rect2(Vector2(PAD, y + 4.0), Vector2(96.0, 22.0))
		draw_rect(_next_rect, HudPanelStyle.COLOR_CYAN_GLOW)
		draw_rect(_next_rect, HudPanelStyle.COLOR_CYAN, false, 1.0)
		draw_string(
			font, _next_rect.position + Vector2(0.0, 15.0), "NEXT  >", HORIZONTAL_ALIGNMENT_CENTER,
			_next_rect.size.x, 11, HudPanelStyle.COLOR_TEXT_PRIMARY
		)
		y += 34.0
	elif _outro_time < 0.0:
		var x: float = PAD
		for key: String in _steps[_index]["keys"]:
			var w: float = font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 16.0
			var cap := Rect2(Vector2(x, y + 4.0), Vector2(maxf(w, 28.0), 22.0))
			draw_rect(cap, HudPanelStyle.COLOR_CYAN_GLOW)
			draw_rect(cap, HudPanelStyle.COLOR_CYAN, false, 1.0)
			draw_string(
				font, cap.position + Vector2(0.0, 15.0), key, HORIZONTAL_ALIGNMENT_CENTER, cap.size.x, 11,
				HudPanelStyle.COLOR_TEXT_PRIMARY
			)
			x = cap.end.x + 6.0
		y += 34.0

	# Progress bar and SKIP.
	var bar_width: float = _text_width() if _outro_time >= 0.0 else _text_width() - 216.0
	var bar := Rect2(Vector2(PAD, y + 12.0), Vector2(bar_width, 4.0))
	draw_rect(bar, HudPanelStyle.COLOR_TEXT_FAINT)
	var passed: float = float(_index + (1 if done else 0)) / float(_steps.size())
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * minf(passed, 1.0), bar.size.y)), accent)

	_skip_rect = Rect2()
	_skip_section_rect = Rect2()
	if _outro_time < 0.0:
		_skip_rect = Rect2(Vector2(size.x - PAD - 96.0, y + 2.0), Vector2(96.0, 22.0))
		_skip_section_rect = Rect2(_skip_rect.position - Vector2(102.0, 0.0), _skip_rect.size)
		_draw_skip_button(_skip_section_rect, "SKIP SECTION", _skip_armed == "section")
		_draw_skip_button(_skip_rect, "SKIP ALL", _skip_armed == "all")


func _draw_skip_button(rect: Rect2, label: String, armed: bool) -> void:
	var color: Color = HudPanelStyle.COLOR_AMBER if armed else HudPanelStyle.COLOR_TEXT_MUTED
	draw_rect(rect, color, false, 1.0)
	draw_string(
		HudPanelStyle.get_font(), rect.position + Vector2(0.0, 15.0), "CONFIRM?" if armed else label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 10, color
	)
