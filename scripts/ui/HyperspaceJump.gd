class_name HyperspaceJump
extends CanvasLayer
## One hyperspace jump, full screen over the game and its HUD
## (hyperspace.gdshader). Three stages:
##   SPOOL  - stars stretch into streaks and the view blacks out; at its end
##            `midpoint` fires, and the game swaps in the new system.
##   TUNNEL - the blue tunnel, held at least TUNNEL_MIN seconds and until
##            `ready_check` says the new system has finished loading (or
##            TUNNEL_MAX runs out).
##   EXIT   - a white flash, the tunnel falls away and the streaks shrink back
##            to stars over the new system; then `finished`, and it frees itself.

signal midpoint
signal finished

enum Stage { SPOOL, TUNNEL, EXIT }

const SHADER := preload("res://hyperspace.gdshader")
const SPOOL_TIME := 1.8
const TUNNEL_MIN := 2.6
const TUNNEL_MAX := 25.0
const EXIT_TIME := 1.3

## Returns true once the new system is ready to be shown.
var ready_check: Callable = func() -> bool: return true
## Shown under the tunnel: where the jump goes.
var destination_name: String = ""

var _stage: Stage = Stage.SPOOL
var _time: float = 0.0
var _travel: float = 0.0
var _rect: ColorRect
var _material: ShaderMaterial
var _caption: Control


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect.material = _material
	add_child(_rect)
	_caption = Control.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.draw.connect(_draw_caption)
	add_child(_caption)
	_apply(0.0, 0.0, 0.0, 0.0, 0.0)


## 0..1 through the spool, for the ship's run-up; 1 after it.
func spool_progress() -> float:
	return clampf(_time / SPOOL_TIME, 0.0, 1.0) if _stage == Stage.SPOOL else 1.0


func _process(delta: float) -> void:
	_time += delta
	var speed: float
	match _stage:
		Stage.SPOOL:
			var s: float = clampf(_time / SPOOL_TIME, 0.0, 1.0)
			speed = 0.3 + 7.0 * s * s * s
			_apply(
				s * s, smoothstep(0.85, 1.0, s), smoothstep(0.9, 1.0, s) * 0.6,
				smoothstep(0.55, 1.0, s), smoothstep(0.0, 0.25, s)
			)
			if _time >= SPOOL_TIME:
				_stage = Stage.TUNNEL
				_time = 0.0
				midpoint.emit()
		Stage.TUNNEL:
			speed = 3.5
			_apply(1.0, 1.0, 0.6 * exp(-_time * 5.0), 1.0, 1.0)
			if (_time >= TUNNEL_MIN and ready_check.call()) or _time >= TUNNEL_MAX:
				_stage = Stage.EXIT
				_time = 0.0
		Stage.EXIT:
			var e: float = clampf(_time / EXIT_TIME, 0.0, 1.0)
			speed = 0.3 + 5.0 * pow(1.0 - e, 3.0)
			_apply(
				(1.0 - e) * (1.0 - e), 1.0 - smoothstep(0.05, 0.25, e),
				sin(clampf(e / 0.35, 0.0, 1.0) * PI) * 0.9,
				1.0 - smoothstep(0.15, 0.6, e), 1.0 - smoothstep(0.4, 1.0, e)
			)
			if _time >= EXIT_TIME:
				finished.emit()
				queue_free()
				return
	_travel += speed * delta
	_material.set_shader_parameter("travel", _travel)
	_material.set_shader_parameter("rect_size", _rect.size)
	_caption.queue_redraw()


func _apply(stretch: float, tunnel: float, flash: float, darken: float, stars: float) -> void:
	_material.set_shader_parameter("stretch", stretch)
	_material.set_shader_parameter("tunnel", tunnel)
	_material.set_shader_parameter("flash", flash)
	_material.set_shader_parameter("darken", darken)
	_material.set_shader_parameter("star_alpha", stars)


func _draw_caption() -> void:
	if _stage != Stage.TUNNEL or destination_name.is_empty():
		return
	var alpha: float = clampf(_time / 0.6, 0.0, 1.0) * 0.85
	var font: Font = HudPanelStyle.get_font()
	var area: Vector2 = _caption.size
	_caption.draw_string(
		font, Vector2(0.0, area.y - 64.0), "HYPERSPACE", HORIZONTAL_ALIGNMENT_CENTER, area.x, 11,
		Color(HudPanelStyle.COLOR_TEXT_SECONDARY, alpha)
	)
	_caption.draw_string(
		font, Vector2(0.0, area.y - 42.0), destination_name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, area.x, 18,
		Color(HudPanelStyle.COLOR_TEXT_PRIMARY, alpha)
	)
