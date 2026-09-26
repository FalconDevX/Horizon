class_name WarpFX
extends CanvasLayer
## The warp jump's look (warp_lens.gdshader), between the world and the HUD
## (the HUD sits on layer 2). solar_system.gd drives it:
##   play()         - a jump starts; set_spool(0..1) each frame, space bends
##                    round the ship harder and harder
##   set_jump(0..1) - the crossing: full lensing, everything streaks past
##   arrive()       - a flash and a shockwave ripple, then it all settles
##                    over EXIT_TIME and the layer hides itself
## Hidden (and costing nothing) whenever no jump is under way.

const SHADER := preload("res://warp_lens.gdshader")
const COLOR := Color(0.62, 0.55, 1.0)
const EXIT_TIME := 0.9

var _rect: ColorRect
var _material: ShaderMaterial
## Seconds since arrive(), or -1 while not settling.
var _exit_age: float = -1.0


func _init() -> void:
	layer = 1


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("tint", COLOR)
	_rect.material = _material
	add_child(_rect)
	visible = false


func play() -> void:
	_exit_age = -1.0
	_apply(0.0, 0.0, -1.0, 0.0)
	visible = true


func stop() -> void:
	_exit_age = -1.0
	visible = false


func arrive() -> void:
	_exit_age = 0.0
	visible = true


func is_idle() -> bool:
	return not visible


## Where the ship is on screen (0..1) and the screen's size, for the aspect.
func set_center(uv: Vector2, screen_size: Vector2) -> void:
	_material.set_shader_parameter("center", uv)
	_material.set_shader_parameter("aspect", screen_size.x / maxf(screen_size.y, 1.0))


func set_spool(s: float) -> void:
	_apply(0.8 * s * s, 0.5 * s * s * s, -1.0, 0.0)


func set_jump(u: float) -> void:
	# Hardest in the middle of the crossing, a white-out as it lands.
	var peak: float = sin(u * PI)
	_apply(0.8 + 0.4 * peak, 0.5 + 0.5 * peak, -1.0, smoothstep(0.85, 1.0, u) * 0.8)


func _process(delta: float) -> void:
	if _exit_age < 0.0:
		return
	_exit_age += delta
	var e: float = clampf(_exit_age / EXIT_TIME, 0.0, 1.0)
	var settle: float = 1.0 - e
	_apply(1.0 * settle * settle, 0.6 * settle * settle * settle, e * 1.3, 0.8 * (1.0 - smoothstep(0.0, 0.35, e)))
	if e >= 1.0:
		stop()


func _apply(lens: float, streak: float, ring: float, flash: float) -> void:
	_material.set_shader_parameter("lens", lens)
	_material.set_shader_parameter("streak", streak)
	_material.set_shader_parameter("ring", ring)
	_material.set_shader_parameter("flash", flash)
