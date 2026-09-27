extends Control

## The planet-guard warning at the top of the screen: "HOSTILE PATROL - attack
## in 3.4 s" with a draining bar while the player sits in a patrol's alert
## range, then a short "UNDER ATTACK" flash when the guards break orbit.
## solar_system.gd feeds it every frame (set_countdown / flash_attack).

const WIDTH := 460.0
const HEIGHT := 58.0
## Under the two key prompts (landing_prompt.gd rows 0 and 1).
const TOP := 184.0
const FADE_RATE := 6.0
const ATTACK_FLASH_TIME := 2.5
const COLOR_RED := Color(1.0, 0.33, 0.28)

## Seconds left before the attack, -1 when nothing counts down.
var _countdown := -1.0
var _total := 5.0
var _attack_left := 0.0
var _alpha := 0.0
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = TOP
	offset_bottom = TOP + HEIGHT
	modulate.a = 0.0


## `seconds` left of `total` before the guards attack; -1 hides the countdown.
func set_countdown(seconds: float, total: float) -> void:
	_countdown = seconds
	_total = maxf(total, 0.01)


func flash_attack() -> void:
	_attack_left = ATTACK_FLASH_TIME


func _process(delta: float) -> void:
	_time += delta
	_attack_left = maxf(_attack_left - delta, 0.0)
	var wanted: bool = _countdown >= 0.0 or _attack_left > 0.0
	_alpha = move_toward(_alpha, 1.0 if wanted else 0.0, FADE_RATE * delta)
	modulate.a = _alpha
	visible = _alpha > 0.0
	if visible:
		queue_redraw()


func _draw() -> void:
	var font: Font = HudPanelStyle.get_font()
	var attacking: bool = _countdown < 0.0 and _attack_left > 0.0
	var accent: Color = COLOR_RED if attacking else HudPanelStyle.COLOR_AMBER
	# Pulses faster as the countdown runs out.
	var rate: float = 9.0 if attacking else lerpf(3.0, 9.0, 1.0 - clampf(_countdown / _total, 0.0, 1.0))
	var pulse: float = 0.5 + 0.5 * sin(_time * rate)
	HudPanelStyle.draw_chamfered(self, size, accent, 12.0, 0.9, 0.6 + 0.4 * pulse)

	# Warning triangle.
	var c := Vector2(38.0, 29.0)
	var tri := PackedVector2Array([c + Vector2(0.0, -15.0), c + Vector2(16.0, 13.0), c + Vector2(-16.0, 13.0)])
	draw_colored_polygon(tri, Color(accent, 0.18 + 0.2 * pulse))
	draw_polyline(tri + PackedVector2Array([tri[0]]), accent, 2.0, true)
	draw_string(font, c + Vector2(-8.0, 10.0), "!", HORIZONTAL_ALIGNMENT_CENTER, 16.0, 16, accent)

	var x := 70.0
	var text_w: float = size.x - x - 16.0
	if attacking:
		draw_string(font, Vector2(x, 27.0), "UNDER ATTACK", HORIZONTAL_ALIGNMENT_LEFT, text_w, 15, accent)
		draw_string(font, Vector2(x, 45.0), "The patrol broke orbit - fight or run out of range", HORIZONTAL_ALIGNMENT_LEFT, text_w, 10, HudPanelStyle.COLOR_TEXT_MUTED)
		return

	draw_string(font, Vector2(x, 25.0), "HOSTILE PATROL - ATTACK IN %.1f s" % maxf(_countdown, 0.0), HORIZONTAL_ALIGNMENT_LEFT, text_w, 15, accent)
	draw_string(font, Vector2(x, 40.0), "Leave the area - or open fire and they attack at once", HORIZONTAL_ALIGNMENT_LEFT, text_w, 10, HudPanelStyle.COLOR_TEXT_MUTED)
	var bar := Rect2(Vector2(x, 47.0), Vector2(text_w, 3.0))
	draw_rect(bar, HudPanelStyle.COLOR_TEXT_FAINT)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(_countdown / _total, 0.0, 1.0), bar.size.y)), accent)
