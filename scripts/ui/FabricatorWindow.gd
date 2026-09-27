class_name FabricatorWindow
extends Control
## The fabricator's window (F): the hel in the hold, one card per recipe
## (what a batch takes and gives, how long, the tank it fills with what is
## already queued for it, and a REFINE button - or what stands in the way),
## and the queue, the batch being refined with its progress bar. Refining
## runs on in the background with the window shut (scripts/ship/Fabricator.gd).
## It does not hold the game. solar_system.gd routes F / Esc (close) and the
## keys 1 and 2 (queue a batch) while it is open.

const PANEL_SIZE := Vector2(600.0, 470.0)
const PAD := 20.0
const HEADER := 52.0
const CARD_HEIGHT := 178.0
const ROW_HEIGHT := 26.0
const COLOR_FUEL := Color(0.96, 0.68, 0.24)
const COLOR_WARP := Color(0.66, 0.46, 1.0)

var fabricator: Fabricator = null
## solar_system.gd: the ship, the hold and whether a fabricator is fitted.
var _system: Node = null
var _hover_close := false
var _hover_help := false
var _hover: String = ""
var _help: HelpPopup


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_help = HelpPopup.new(PackedStringArray([
		"Hel from gas giants is refined into fuel",
		"1: queue engine fuel, 2: queue warp fuel",
		"Click a queued batch to cancel it (hel comes back)",
		"Refining goes on with the window shut",
		"F or Esc: close",
	]))
	add_child(_help)


func setup(system: Node, p_fabricator: Fabricator) -> void:
	_system = system
	fabricator = p_fabricator


func toggle() -> void:
	if visible:
		hide_window()
	else:
		open()


func open() -> void:
	var view: Vector2 = get_viewport_rect().size
	size = PANEL_SIZE
	position = ((view - size) * 0.5).round()
	visible = true
	move_to_front()


func hide_window() -> void:
	visible = false
	_help.close()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## Queues a batch of `recipe` (keys 1 / 2 or the card's button).
func queue_batch(recipe: StringName) -> void:
	fabricator.add(recipe, _system.ship, _system.inventory, _system.has_fabricator())


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 36.0, 12.0), Vector2(24.0, 24.0))


func _card_rect(i: int) -> Rect2:
	var width: float = (size.x - PAD * 3.0) * 0.5
	return Rect2(Vector2(PAD + i * (width + PAD), HEADER + 34.0), Vector2(width, CARD_HEIGHT))


func _button_rect(i: int) -> Rect2:
	var card: Rect2 = _card_rect(i)
	return Rect2(card.position + Vector2(12.0, card.size.y - 40.0), Vector2(card.size.x - 24.0, 28.0))


func _queue_top() -> float:
	return _card_rect(0).end.y + 34.0


func _row_rect(i: int) -> Rect2:
	return Rect2(Vector2(PAD, _queue_top() + i * ROW_HEIGHT), Vector2(size.x - PAD * 2.0, ROW_HEIGHT - 3.0))


func _hit(point: Vector2) -> String:
	if _close_rect().has_point(point):
		return "close"
	if HelpPopup.button_rect(_close_rect()).has_point(point):
		return "help"
	for i in Fabricator.ORDER.size():
		if _button_rect(i).has_point(point):
			return "recipe:%d" % i
	for i in fabricator.queue.size():
		if _row_rect(i).has_point(point):
			return "row:%d" % i
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hit: String = _hit(event.position)
		_hover = hit
		_hover_close = hit == "close"
		_hover_help = hit == "help"
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit: String = _hit(event.position)
		if hit == "help":
			_help.toggle_at(Vector2(_close_rect().end.x, _close_rect().end.y + 10.0))
		else:
			_help.close()
			if hit == "close":
				hide_window()
			elif hit.begins_with("recipe:"):
				queue_batch(Fabricator.ORDER[int(hit.get_slice(":", 1))])
			elif hit.begins_with("row:"):
				fabricator.cancel(int(hit.get_slice(":", 1)), _system.inventory)
		accept_event()


func _draw() -> void:
	if fabricator == null or _system == null:
		return
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_CYAN, 18.0, 0.97, 0.8)
	var font: Font = HudPanelStyle.get_font()
	var fitted: bool = _system.has_fabricator()
	draw_string(font, Vector2(PAD, 34.0), "FABRICATOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, HudPanelStyle.COLOR_TEXT_PRIMARY)
	var state: String = "REFINING" if fitted and not fabricator.queue.is_empty() else ("IDLE" if fitted else "NOT FITTED")
	draw_string(
		font, Vector2(170.0, 32.0), state, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		HudPanelStyle.COLOR_EMERALD if state == "REFINING" else (HudPanelStyle.COLOR_TEXT_MUTED if fitted else HudPanelStyle.COLOR_AMBER)
	)
	HelpPopup.draw_button(self, HelpPopup.button_rect(_close_rect()), _hover_help, _help.visible)
	draw_string(
		font, _close_rect().position + Vector2(5.0, 18.0), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		HudPanelStyle.COLOR_TEXT_PRIMARY if _hover_close else HudPanelStyle.COLOR_TEXT_MUTED
	)
	draw_line(Vector2(18.0, 46.0), Vector2(size.x - 18.0, 46.0), Color(HudPanelStyle.COLOR_TEXT_FAINT, 0.8), 1.0)

	# The hel in the hold.
	var hel: int = (_system.inventory as Inventory).count(Fabricator.HEL)
	var icon: Texture2D = ResourceIcons.icon(Fabricator.HEL)
	if icon != null:
		draw_texture_rect(icon, Rect2(Vector2(PAD, HEADER + 2.0), Vector2(24.0, 24.0)), false)
	draw_string(
		font, Vector2(PAD + 30.0, HEADER + 19.0), "HEL IN HOLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		HudPanelStyle.COLOR_TEXT_SECONDARY
	)
	draw_string(
		font, Vector2(PAD + 120.0, HEADER + 20.0), "ENDLESS" if PlayerProgress.god_mode else str(hel),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ResourceIcons.color(Fabricator.HEL)
	)
	if hel == 0 and not PlayerProgress.god_mode:
		draw_string(
			font, Vector2(PAD + 170.0, HEADER + 19.0), "Collect hel on gas giants", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			HudPanelStyle.COLOR_TEXT_MUTED
		)

	for i in Fabricator.ORDER.size():
		_draw_card(font, i, fitted)
	_draw_queue(font, fitted)


func _draw_card(font: Font, i: int, fitted: bool) -> void:
	var recipe: StringName = Fabricator.ORDER[i]
	var info: Dictionary = Fabricator.RECIPES[recipe]
	var warp: bool = recipe == &"warp_fuel"
	var accent: Color = COLOR_WARP if warp else COLOR_FUEL
	var card: Rect2 = _card_rect(i)
	draw_rect(card, Color(HudPanelStyle.COLOR_BG_SURFACE, 0.7))
	draw_rect(card, Color(accent, 0.45), false, 1.0)
	draw_rect(Rect2(card.position, Vector2(3.0, card.size.y)), accent)
	var x: float = card.position.x + 14.0
	var width: float = card.size.x - 28.0
	var y: float = card.position.y
	draw_string(font, Vector2(x, y + 22.0), "%d  %s" % [i + 1, String(info["name"]).to_upper()], HORIZONTAL_ALIGNMENT_LEFT, width, 13, accent)
	var gives: String = "+%d%% warp tank" % roundi(float(info["yield"])) if warp else "+%d fuel" % roundi(float(info["yield"]))
	draw_string(
		font, Vector2(x, y + 42.0), "%d hel  >  %s" % [int(info["hel"]), gives], HORIZONTAL_ALIGNMENT_LEFT, width, 11,
		HudPanelStyle.COLOR_TEXT_PRIMARY
	)
	draw_string(
		font, Vector2(x, y + 58.0), "%ds a batch" % roundi(float(info["time"])), HORIZONTAL_ALIGNMENT_LEFT, width, 10,
		HudPanelStyle.COLOR_TEXT_MUTED
	)
	draw_string(font, Vector2(x, y + 74.0), String(info["note"]), HORIZONTAL_ALIGNMENT_LEFT, width, 10, HudPanelStyle.COLOR_TEXT_SECONDARY)

	# The tank: what is in it, and (dimmer) what the queue will add.
	var ship: Node = _system.ship
	var level: float = 0.0
	var capacity: float = 0.0
	if warp:
		level = float(ship.warp_fuel)
		capacity = float(ship.WARP_FUEL_CAPACITY)
	elif bool(ship.resources_enabled):
		level = float(ship.fuel)
		capacity = float(ship.fuel_capacity)
	var bar := Rect2(Vector2(x, y + 94.0), Vector2(width, 10.0))
	draw_rect(bar, Color(0.0, 0.0, 0.0, 0.5))
	if capacity > 0.0:
		var now: float = clampf(level / capacity, 0.0, 1.0)
		var coming: float = clampf((level + float(info["yield"]) * fabricator.queued(recipe)) / capacity, 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * coming, bar.size.y)), Color(accent, 0.3))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * now, bar.size.y)), accent)
		var tank_text: String = "%d%%" % roundi(now * 100.0) if warp else "%d / %d" % [roundi(level), roundi(capacity)]
		draw_string(font, Vector2(x, y + 122.0), ("WARP TANK " if warp else "FUEL TANK ") + tank_text, HORIZONTAL_ALIGNMENT_LEFT, width, 10, HudPanelStyle.COLOR_TEXT_SECONDARY)
		if fabricator.queued(recipe) > 0:
			draw_string(
				font, Vector2(x, y + 122.0), "%d queued" % fabricator.queued(recipe), HORIZONTAL_ALIGNMENT_RIGHT, width, 10,
				Color(accent, 0.85)
			)
	else:
		draw_string(font, Vector2(x, y + 122.0), "NO FUEL TANK", HORIZONTAL_ALIGNMENT_LEFT, width, 10, HudPanelStyle.COLOR_TEXT_MUTED)
	draw_rect(bar, Color(accent, 0.4), false, 1.0)

	# The button, or what stands in the way.
	var problem: String = fabricator.problem(recipe, ship, _system.inventory, fitted)
	var button: Rect2 = _button_rect(i)
	var hovered: bool = _hover == "recipe:%d" % i
	if problem == "":
		draw_rect(button, Color(accent, 0.3 if hovered else 0.16))
		draw_rect(button, accent, false, 1.0)
		draw_string(font, button.position + Vector2(0.0, 19.0), "REFINE", HORIZONTAL_ALIGNMENT_CENTER, button.size.x, 12, HudPanelStyle.COLOR_TEXT_PRIMARY)
	else:
		draw_rect(button, Color(HudPanelStyle.COLOR_BG_CANVAS, 0.6))
		draw_rect(button, HudPanelStyle.COLOR_BORDER_DEFAULT, false, 1.0)
		draw_string(font, button.position + Vector2(0.0, 19.0), problem.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, button.size.x, 11, HudPanelStyle.COLOR_TEXT_MUTED)


func _draw_queue(font: Font, fitted: bool) -> void:
	var top: float = _queue_top()
	draw_string(
		font, Vector2(PAD, top - 10.0), "QUEUE  %d / %d" % [fabricator.queue.size(), Fabricator.MAX_QUEUE],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudPanelStyle.COLOR_CYAN
	)
	if fabricator.queue.is_empty():
		draw_string(
			font, Vector2(PAD, top + 18.0), "Nothing queued", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HudPanelStyle.COLOR_TEXT_MUTED
		)
		return
	var fits: int = int((size.y - top - 14.0) / ROW_HEIGHT)
	var left: float = 0.0
	for i in fabricator.queue.size():
		var recipe: StringName = fabricator.queue[i]
		var info: Dictionary = Fabricator.RECIPES[recipe]
		var time: float = float(info["time"])
		left += time - (fabricator.progress if i == 0 else 0.0)
		if i >= fits:
			continue
		var accent: Color = COLOR_WARP if recipe == &"warp_fuel" else COLOR_FUEL
		var row: Rect2 = _row_rect(i)
		var hovered: bool = _hover == "row:%d" % i
		draw_rect(row, Color(1.0, 1.0, 1.0, 0.06) if hovered else Color(HudPanelStyle.COLOR_BG_SURFACE, 0.5))
		if i == 0:
			draw_rect(Rect2(row.position, Vector2(row.size.x * fabricator.share_done(), row.size.y)), Color(accent, 0.25 if fitted else 0.1))
		draw_rect(Rect2(row.position, Vector2(3.0, row.size.y)), accent)
		draw_string(font, row.position + Vector2(12.0, 16.0), String(info["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 200.0, 11, accent)
		var what: String = "CANCEL" if hovered else (("PAUSED" if not fitted else "REFINING") if i == 0 else "WAITING")
		draw_string(font, row.position + Vector2(210.0, 16.0), what, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 10, HudPanelStyle.COLOR_TEXT_SECONDARY if not hovered else HudPanelStyle.COLOR_AMBER)
		draw_string(
			font, row.position + Vector2(0.0, 16.0), "done in %ds" % ceili(left), HORIZONTAL_ALIGNMENT_RIGHT, row.size.x - 12.0, 10,
			HudPanelStyle.COLOR_TEXT_MUTED
		)
