class_name LoadingScreen
extends CanvasLayer
## Full-screen loading overlay: the title art with a progress bar underneath.
##
## Two stages share one bar. The main menu puts it up on the scene tree's root
## before loading solar_system.tscn (the first SCENE_SHARE of the bar); being
## on the root it survives the scene change, and the solar system takes the same
## screen over (`current`) and fills the rest as the planets' terrain bakes
## land. Started straight from the editor, the solar system makes its own.
## Once everything is in, it holds a moment - the first frames behind it
## compile the planet shaders - then fades out.

signal finished

const IMAGE := preload("res://textures/loading_background.png")
const HudPanelStyle = preload("res://hud_panel_style.gd")

## Share of the bar taken by loading the scene itself.
const SCENE_SHARE := 0.3
## How fast the shown bar may catch up, in bar-widths per second.
const FILL_SPEED := 1.2
## Held full for this long before fading - the shader warm-up.
const HOLD_TIME := 0.35
const FADE_TIME := 0.45
## Never shown for less than this, so it cannot flash past.
const MIN_TIME := 0.8

const BAR_WIDTH := 560.0
const BAR_HEIGHT := 4.0
const BAR_BOTTOM_MARGIN := 42.0

## The screen currently up, if any.
static var current: LoadingScreen = null

var status_text := "Loading"
## 0..1, where the bar is heading. Set it, or hand planets to track_bodies().
var target_progress := 0.0

var _shown := 0.0
var _elapsed := 0.0
var _hold := 0.0
var _fade := 0.0
var _done := false
var _bodies: Array = []

var _root: Control
var _bar: Control
var _label: Label


func _init() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallows every click, so nothing behind can be pressed mid-load.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	var art := TextureRect.new()
	art.texture = IMAGE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(art)

	_bar = Control.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	_root.add_child(_bar)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", HudPanelStyle.get_font())
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", HudPanelStyle.COLOR_TEXT_SECONDARY)
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_left = -BAR_WIDTH * 0.5
	_label.offset_right = BAR_WIDTH * 0.5
	_label.offset_top = -BAR_BOTTOM_MARGIN - 34.0
	_label.offset_bottom = -BAR_BOTTOM_MARGIN - 12.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_label)
	_update_label()


## Fill the rest of the bar (after the scene share) as these bodies finish
## building their surfaces (CelestialBody.is_surface_ready()).
func track_bodies(bodies: Array) -> void:
	_bodies = bodies


func is_done() -> bool:
	return _done


func _process(delta: float) -> void:
	_elapsed += delta

	var bodies_ready: bool = true
	if not _bodies.is_empty():
		var ready_count: int = 0
		for body in _bodies:
			if body.call("is_surface_ready"):
				ready_count += 1
		bodies_ready = ready_count == _bodies.size()
		target_progress = lerpf(SCENE_SHARE, 1.0, float(ready_count) / _bodies.size())
		status_text = "Generating planets  %d / %d" % [ready_count, _bodies.size()]

	_shown = move_toward(_shown, target_progress, FILL_SPEED * delta)
	_update_label()
	_bar.queue_redraw()

	if _bodies.is_empty() or not bodies_ready or _shown < 1.0 or _elapsed < MIN_TIME:
		return

	if _hold < HOLD_TIME:
		_hold += delta
		status_text = "Ready"
		return

	_fade += delta
	_root.modulate.a = 1.0 - clampf(_fade / FADE_TIME, 0.0, 1.0)
	# Let clicks through as soon as it starts to go.
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _fade >= FADE_TIME and not _done:
		_done = true
		finished.emit()
		queue_free()


func _update_label() -> void:
	if _label != null:
		_label.text = "%s   %d%%" % [status_text.to_upper(), roundi(_shown * 100.0)]


func _draw_bar() -> void:
	var view: Vector2 = _bar.size
	var origin := Vector2((view.x - BAR_WIDTH) * 0.5, view.y - BAR_BOTTOM_MARGIN)
	var track := Rect2(origin, Vector2(BAR_WIDTH, BAR_HEIGHT))
	var fill := Rect2(origin, Vector2(BAR_WIDTH * clampf(_shown, 0.0, 1.0), BAR_HEIGHT))

	_bar.draw_rect(track.grow(1.0), Color(0.0, 0.0, 0.0, 0.6))
	_bar.draw_rect(track, HudPanelStyle.COLOR_CYAN_GLOW)
	# Soft glow under the fill, then the fill itself with a bright leading edge.
	_bar.draw_rect(fill.grow(3.0), Color(HudPanelStyle.COLOR_CYAN, 0.12))
	_bar.draw_rect(fill, HudPanelStyle.COLOR_CYAN)
	if fill.size.x > 2.0:
		_bar.draw_rect(Rect2(fill.end.x - 2.0, fill.position.y - 2.0, 2.0, BAR_HEIGHT + 4.0), Color(1, 1, 1, 0.9))
