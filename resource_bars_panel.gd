extends Control
## Placeholder ship-resource readout (fuel/energy/shield). No gameplay system
## feeds these yet - solar_system.gd currently passes fixed demo values.

## Monochromatic blue - all three bars share one accent, distinguished only by label.
const BAR_COLOR := Color(0.72, 0.88, 1.0)

const FUEL_UNIT := "L"
const ENERGY_UNIT := "MJ"
const SHIELD_UNIT := "SP"

const FUEL_MAX := 420.0
const ENERGY_MAX := 180.0
const SHIELD_MAX := 250.0

const BAR_SEGMENTS := 16
const BAR_SEGMENT_GAP := 2.0
const BAR_WIDTH := 34.0
const COLUMN_GAP := 22.0
const PAD_TOP := 48.0
const PAD_BOTTOM := 46.0

var fuel_pct := 1.0
var energy_pct := 1.0
var shield_pct := 1.0


func set_state(p_fuel_pct: float, p_energy_pct: float, p_shield_pct: float) -> void:
	var f: float = clampf(p_fuel_pct, 0.0, 1.0)
	var e: float = clampf(p_energy_pct, 0.0, 1.0)
	var s: float = clampf(p_shield_pct, 0.0, 1.0)
	if is_equal_approx(fuel_pct, f) and is_equal_approx(energy_pct, e) and is_equal_approx(shield_pct, s):
		return
	fuel_pct = f
	energy_pct = e
	shield_pct = s
	queue_redraw()


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_BORDER_DEFAULT, 14.0, 0.85, 0.55)

	var font: Font = HudPanelStyle.get_font()

	var columns := [
		{"label": "FUEL", "pct": fuel_pct, "color": BAR_COLOR, "max": FUEL_MAX, "unit": FUEL_UNIT},
		{"label": "ENERGY", "pct": energy_pct, "color": BAR_COLOR, "max": ENERGY_MAX, "unit": ENERGY_UNIT},
		{"label": "SHIELD", "pct": shield_pct, "color": BAR_COLOR, "max": SHIELD_MAX, "unit": SHIELD_UNIT},
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
	var color: Color = col.color
	var pct: float = col.pct
	var label_width: float = BAR_WIDTH + 20.0
	var label_x: float = pos.x - 10.0

	var pct_text: String = "%d%%" % roundi(pct * 100.0)
	draw_string(
		font, Vector2(label_x, pos.y - 10.0), pct_text,
		HORIZONTAL_ALIGNMENT_CENTER, label_width, 13, color
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
		HORIZONTAL_ALIGNMENT_CENTER, label_width, 11, HudPanelStyle.COLOR_TEXT_SECONDARY
	)

	var value_text: String = "%d %s" % [roundi(pct * float(col.max)), String(col.unit)]
	draw_string(
		font, Vector2(label_x, pos.y + height + 30.0), value_text,
		HORIZONTAL_ALIGNMENT_CENTER, label_width, 9, HudPanelStyle.COLOR_TEXT_MUTED
	)
