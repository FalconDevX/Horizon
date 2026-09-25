extends Control

## A key prompt at the top of the screen - "ENTER - land" / "ENTER - take off",
## "E - collect": a chamfered HUD plate with a key cap, the action and a hint
## line. Fades in and out on its own; solar_system.gd only says what it should
## read. Further prompts stack under the first by `row`.

const WIDTH := 460.0
const HEIGHT := 58.0
## From the top of the screen - under the notice toast (HUD/MusicToast, which
## ends at 44), clear of the speed gauge and the side panels.
const TOP_MARGIN := 52.0
const FADE_RATE := 6.0
const ROW_GAP := 8.0

var _action := ""
var _hint := ""
var _key := "ENTER"
var _row := 0
var _wanted := false
var _alpha := 0.0


func _init(key: String = "ENTER", row: int = 0) -> void:
	_key = key
	_row = row


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Pinned to the top middle of the screen, whatever its size.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = TOP_MARGIN + _row * (HEIGHT + ROW_GAP)
	offset_bottom = offset_top + HEIGHT
	modulate.a = 0.0


## Shows the prompt: `action` in capitals beside the key cap, `hint` under it.
func show_prompt(action: String, hint: String) -> void:
	if action != _action or hint != _hint:
		_action = action
		_hint = hint
		queue_redraw()
	_wanted = true


func hide_prompt() -> void:
	_wanted = false


func _process(delta: float) -> void:
	_alpha = move_toward(_alpha, 1.0 if _wanted else 0.0, FADE_RATE * delta)
	modulate.a = _alpha
	visible = _alpha > 0.0


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_CYAN, 12.0, 0.9, 0.7)
	var font: Font = HudPanelStyle.get_font()

	# The key cap.
	var cap := Rect2(Vector2(16.0, 14.0), Vector2(74.0, 30.0))
	draw_rect(cap, HudPanelStyle.COLOR_CYAN_GLOW)
	draw_rect(cap, HudPanelStyle.COLOR_CYAN, false, 1.0)
	draw_string(
		font, cap.position + Vector2(0.0, 20.0), _key, HORIZONTAL_ALIGNMENT_CENTER, cap.size.x, 13,
		HudPanelStyle.COLOR_TEXT_PRIMARY
	)

	var x: float = cap.end.x + 16.0
	draw_string(font, Vector2(x, 27.0), _action, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 12.0, 15, HudPanelStyle.COLOR_CYAN)
	draw_string(font, Vector2(x, 45.0), _hint, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 12.0, 10, HudPanelStyle.COLOR_TEXT_MUTED)
