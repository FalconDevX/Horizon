extends Control
## The ship's resources as segmented bars: fuel, energy, shield, hull and -
## in violet - warp fuel. With a warp target locked, the warp bar previews the
## jump: the share it would burn blinks, with the cost and what is left after.
## solar_system.gd feeds it every frame from ship.gd (set_values), or shows the
## stock ship - nothing built in the yard yet, so no limits - as full
## (set_unlimited). Energy turns amber while the ship has no power.

## Monochromatic blue - the bars share one accent, distinguished only by label.
const BAR_COLOR := Color(0.72, 0.88, 1.0)
## Hull running low, and no power.
const LOW_COLOR := Color(0.95, 0.45, 0.3)
const NO_POWER_COLOR := HudPanelStyle.COLOR_AMBER
const LOW_HULL := 0.3

const FUEL_UNIT := "L"
const ENERGY_UNIT := "MJ"
const SHIELD_UNIT := "SP"
const HULL_UNIT := "HP"

const BAR_SEGMENTS := 16
const BAR_SEGMENT_GAP := 2.0
const BAR_WIDTH := 28.0
const COLUMN_GAP := 16.0
const WARP_COLOR := Color(0.62, 0.55, 1.0)
const PAD_TOP := 48.0
const PAD_BOTTOM := 46.0

## {pct, amount, max} per bar; `unlimited` shows full with no numbers.
var _values: Array = [[1.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 0.0, 0.0]]
var _unlimited := true
var _powered := true
## Warp fuel share (every ship has it, the stock one too) and the share the
## locked jump would burn (0 = no target).
var _warp_share := 1.0
var _warp_cost := 0.0


func set_warp(share: float, cost_share: float) -> void:
	_warp_share = clampf(share, 0.0, 1.0)
	_warp_cost = clampf(cost_share, 0.0, 1.0)
	queue_redraw()


func set_values(
	fuel: float, fuel_max: float,
	energy: float, energy_max: float,
	shield: float, shield_max: float,
	hull: float, hull_max: float,
	powered: bool
) -> void:
	var values: Array = [
		_entry(fuel, fuel_max), _entry(energy, energy_max),
		_entry(shield, shield_max), _entry(hull, hull_max),
	]
	if not _unlimited and powered == _powered and _same(values):
		return
	_values = values
	_unlimited = false
	_powered = powered
	queue_redraw()


func set_unlimited() -> void:
	if _unlimited:
		return
	_unlimited = true
	_powered = true
	queue_redraw()


static func _entry(amount: float, maximum: float) -> Array:
	return [clampf(amount / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0, amount, maximum]


## Redraw only when a bar would show something different.
func _same(values: Array) -> bool:
	for i in values.size():
		if roundi(float(values[i][1])) != roundi(float(_values[i][1])):
			return false
		if roundi(float(values[i][2])) != roundi(float(_values[i][2])):
			return false
	return true


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_BORDER_DEFAULT, 14.0, 0.85, 0.55)

	var font: Font = HudPanelStyle.get_font()
	var hull_pct: float = float(_values[3][0])
	var columns := [
		{"label": "FUEL", "unit": FUEL_UNIT, "value": _values[0], "color": BAR_COLOR},
		{"label": "ENERGY", "unit": ENERGY_UNIT, "value": _values[1], "color": BAR_COLOR if _powered else NO_POWER_COLOR},
		{"label": "SHIELD", "unit": SHIELD_UNIT, "value": _values[2], "color": BAR_COLOR},
		{"label": "HULL", "unit": HULL_UNIT, "value": _values[3], "color": LOW_COLOR if hull_pct < LOW_HULL and not _unlimited else BAR_COLOR},
		{"label": "WARP", "warp": true, "color": WARP_COLOR},
	]

	var total_width: float = BAR_WIDTH * columns.size() + COLUMN_GAP * (columns.size() - 1)
	var start_x: float = (size.x - total_width) * 0.5
	var bar_top: float = PAD_TOP
	var bar_height: float = size.y - PAD_TOP - PAD_BOTTOM

	for i in range(columns.size()):
		var col: Dictionary = columns[i]
		var x: float = start_x + float(i) * (BAR_WIDTH + COLUMN_GAP)
		_draw_column(Vector2(x, bar_top), bar_height, col, font)


func _draw_column(pos: Vector2, height: float, col: Dictionary, font: Font) -> void:
	if col.get("warp", false):
		_draw_warp_column(pos, height, col, font)
		return
	var color: Color = col.color
	var value: Array = col.value
	var pct: float = 1.0 if _unlimited else float(value[0])
	var label_width: float = BAR_WIDTH + 14.0
	var label_x: float = pos.x - 7.0

	var pct_text: String = "%d%%" % roundi(pct * 100.0)
	draw_string(
		font, Vector2(label_x, pos.y - 10.0), pct_text,
		HORIZONTAL_ALIGNMENT_CENTER, label_width, 12, color
	)

	var seg_height: float = (height - BAR_SEGMENT_GAP * float(BAR_SEGMENTS - 1)) / float(BAR_SEGMENTS)
	var filled_segments: int = roundi(pct * BAR_SEGMENTS)

	for i in range(BAR_SEGMENTS):
		var seg_y: float = pos.y + height - float(i + 1) * seg_height - float(i) * BAR_SEGMENT_GAP
		var seg_rect := Rect2(pos.x, seg_y, BAR_WIDTH, seg_height)
		var active: bool = i < filled_segments
		var seg_color: Color = Color(color, 0.9) if active else Color(HudPanelStyle.COLOR_BORDER_DEFAULT, 0.35)
		draw_rect(seg_rect, seg_color, true)

	draw_string(
		font, Vector2(label_x, pos.y + height + 16.0), String(col.label),
		HORIZONTAL_ALIGNMENT_CENTER, label_width, 10, HudPanelStyle.COLOR_TEXT_SECONDARY
	)

	var value_text: String = "-" if _unlimited else "%d %s" % [roundi(float(value[1])), String(col.unit)]
	draw_string(
		font, Vector2(label_x, pos.y + height + 30.0), value_text,
		HORIZONTAL_ALIGNMENT_CENTER, label_width, 9, HudPanelStyle.COLOR_TEXT_MUTED
	)


## Warp fuel: the jump's cost blinks on top of what stays, with "-12%" over
## the bar and the share left after it under the label.
func _draw_warp_column(pos: Vector2, height: float, col: Dictionary, font: Font) -> void:
	var color: Color = col.color
	var label_width: float = BAR_WIDTH + 14.0
	var label_x: float = pos.x - 7.0
	var cost: float = minf(_warp_cost, _warp_share)
	var after: float = _warp_share - cost
	draw_string(
		font, Vector2(label_x, pos.y - 10.0), "%d%%" % roundi(_warp_share * 100.0),
		HORIZONTAL_ALIGNMENT_CENTER, label_width, 12, color
	)
	if cost > 0.0:
		draw_string(
			font, Vector2(label_x, pos.y - 26.0), "-%d%%" % maxi(roundi(cost * 100.0), 1),
			HORIZONTAL_ALIGNMENT_CENTER, label_width, 10, HudPanelStyle.COLOR_AMBER
		)

	var seg_height: float = (height - BAR_SEGMENT_GAP * float(BAR_SEGMENTS - 1)) / float(BAR_SEGMENTS)
	var filled: int = roundi(_warp_share * BAR_SEGMENTS)
	var kept: int = roundi(after * BAR_SEGMENTS)
	var blink: float = 0.35 + 0.35 * sin(Time.get_ticks_msec() * 0.008)
	for i in range(BAR_SEGMENTS):
		var seg_y: float = pos.y + height - float(i + 1) * seg_height - float(i) * BAR_SEGMENT_GAP
		var seg_color: Color = Color(HudPanelStyle.COLOR_BORDER_DEFAULT, 0.35)
		if i < kept:
			seg_color = Color(color, 0.9)
		elif i < filled:
			# Would burn on the jump.
			seg_color = Color(color, 0.9) if cost <= 0.0 else Color(HudPanelStyle.COLOR_AMBER, blink)
		draw_rect(Rect2(pos.x, seg_y, BAR_WIDTH, seg_height), seg_color, true)

	draw_string(
		font, Vector2(label_x, pos.y + height + 16.0), String(col.label),
		HORIZONTAL_ALIGNMENT_CENTER, label_width, 10, HudPanelStyle.COLOR_TEXT_SECONDARY
	)
	var value_text: String = "-> %d%%" % roundi(after * 100.0) if cost > 0.0 else "READY" if _warp_share > 0.0 else "EMPTY"
	draw_string(
		font, Vector2(label_x - 6.0, pos.y + height + 30.0), value_text,
		HORIZONTAL_ALIGNMENT_CENTER, label_width + 12.0, 9, color if cost > 0.0 else HudPanelStyle.COLOR_TEXT_MUTED
	)
