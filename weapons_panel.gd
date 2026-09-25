extends Control
## Every weapon mounted on the ship, one row each: its name, a reload bar,
## and whether the current target (or, with none, the nearest contact) sits
## in its cone. Between the resource bars and the centre gauges; fed each
## frame by solar_system.gd with set_state().

const PAD := 12.0
const ROW_HEIGHT := 28.0
const HEADER := 38.0
const COLOR_READY := HudPanelStyle.COLOR_EMERALD
const COLOR_RELOAD := HudPanelStyle.COLOR_AMBER
const COLOR_ON_TARGET := Color(1.0, 0.35, 0.3)

## [{title, reload (0 loaded .. 1 just fired), on_target}]
var _weapons: Array = []
var _powered := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(weapons: Array, powered: bool) -> void:
	_weapons = weapons
	_powered = powered
	queue_redraw()


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_BORDER_DEFAULT, 14.0, 0.85, 0.55)
	var font: Font = HudPanelStyle.get_font()
	var width: float = size.x - PAD * 2.0
	draw_string(font, Vector2(PAD, 22.0), "WEAPONS", HORIZONTAL_ALIGNMENT_LEFT, width, 13, HudPanelStyle.COLOR_CYAN)
	draw_string(font, Vector2(PAD, 22.0), "G fire", HORIZONTAL_ALIGNMENT_RIGHT, width, 10, HudPanelStyle.COLOR_TEXT_MUTED)
	if _weapons.is_empty():
		draw_string(font, Vector2(PAD, HEADER + 14.0), "No weapons mounted", HORIZONTAL_ALIGNMENT_LEFT, width, 11, Color(0.55, 0.6, 0.68, 0.8))
		return
	if not _powered:
		draw_string(font, Vector2(PAD, size.y - 10.0), "NO POWER", HORIZONTAL_ALIGNMENT_LEFT, width, 10, HudPanelStyle.COLOR_AMBER)
	var rows: int = mini(_weapons.size(), maxi(int((size.y - HEADER - 22.0) / ROW_HEIGHT), 1))
	for i in rows:
		var weapon: Dictionary = _weapons[i]
		var y: float = HEADER + i * ROW_HEIGHT
		var reload: float = float(weapon["reload"])
		var loaded: bool = reload <= 0.0 and _powered
		var on_target: bool = weapon["on_target"]
		draw_string(
			font, Vector2(PAD, y + 11.0), String(weapon["title"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			width - 48.0, 10, HudPanelStyle.COLOR_TEXT_PRIMARY if loaded else HudPanelStyle.COLOR_TEXT_SECONDARY
		)
		if on_target:
			draw_string(font, Vector2(PAD, y + 11.0), "LOCK", HORIZONTAL_ALIGNMENT_RIGHT, width, 9, COLOR_ON_TARGET)
		# Reload bar: fills back up as the weapon reloads.
		var bar := Rect2(Vector2(PAD, y + 16.0), Vector2(width, 4.0))
		draw_rect(bar, Color(HudPanelStyle.COLOR_BORDER_DEFAULT, 0.5))
		var fill: float = 1.0 - clampf(reload, 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), COLOR_READY if loaded else COLOR_RELOAD)
	if _weapons.size() > rows:
		draw_string(
			font, Vector2(PAD, size.y - 10.0), "+%d more" % (_weapons.size() - rows), HORIZONTAL_ALIGNMENT_RIGHT,
			width, 10, HudPanelStyle.COLOR_TEXT_MUTED
		)
