extends Control

const HudPanelStyle = preload("res://hud_panel_style.gd")
const TITLE_FONT: Font = preload("res://fonts/nasalization.otf")

const COLOR_CYAN := HudPanelStyle.COLOR_CYAN
const COLOR_TEXT_PRIMARY := HudPanelStyle.COLOR_TEXT_PRIMARY
const COLOR_TEXT_SECONDARY := HudPanelStyle.COLOR_TEXT_SECONDARY
const COLOR_TEXT_MUTED := HudPanelStyle.COLOR_TEXT_MUTED
const COLOR_TEXT_FAINT := HudPanelStyle.COLOR_TEXT_FAINT

const SUBTITLE := "EXPLORE   ORBIT   ENGINEER"
const VERSION_TAG := "HORIZON   v0.1.0"

const CONTRIBUTORS := [
	{"rank": "#1", "name": "FalconDevX", "commits": "4 commits"},
	{"rank": "#2", "name": "Gawronek-8", "commits": "2 commits"},
	{"rank": "#3", "name": "claude", "commits": "2 commits"},
	{"rank": "#4", "name": "DawidWy", "commits": "1 commit"},
]

const MENU_MARGIN := 110.0
const MENU_COLUMN_WIDTH := 300.0
const MENU_ROW_HEIGHT := 52.0


class MenuItem:
	var label: String
	var enabled: bool
	var action: Callable

	func _init(p_label: String, p_enabled: bool, p_action: Callable) -> void:
		label = p_label
		enabled = p_enabled
		action = p_action


@onready var gradient_overlay: TextureRect = $Background/GradientOverlay
@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var settings_menu: Control = $SettingsMenu

var settings_mgr: SettingsManager
var music_mgr: MusicManager

var menu_items: Array[MenuItem] = []
var _item_rects: Array[Rect2] = []
var hovered_index: int = -1
var selected_index: int = 0

var _credits_open: bool = false
var _credits_panel_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	grab_focus()

	settings_mgr = SettingsManager.new()
	music_mgr = MusicManager.new()
	music_mgr.intro_track_title = "End of Line"
	add_child(music_mgr)
	music_mgr.setup(music_player, settings_mgr.autoplay_music, "res://music/End_Of_Line.wav")

	settings_menu.setup(settings_mgr, music_mgr)
	settings_menu.closed.connect(queue_redraw)

	_setup_gradient()

	menu_items = [
		MenuItem.new("NEW GAME", true, _on_new_game),
		MenuItem.new("LOAD GAME", false, Callable()),
		MenuItem.new("SETTINGS", true, _on_settings),
		MenuItem.new("CREDITS", true, _on_credits),
		MenuItem.new("EXIT", true, _on_exit),
	]

	queue_redraw()


func _setup_gradient() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.03, 0.05, 0.88))
	gradient.set_color(1, Color(0.02, 0.03, 0.05, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.02, 0.55)
	tex.fill_to = Vector2(0.6, 0.05)
	gradient_overlay.texture = tex


func _draw_tracked_text(pos: Vector2, text: String, font_size: int, color: Color, tracking: float = 0.0, custom_font: Font = null) -> float:
	var font: Font = custom_font if custom_font != null else HudPanelStyle.get_font()
	var cursor_x: float = pos.x
	for i in text.length():
		var ch: String = text.substr(i, 1)
		draw_string(font, Vector2(cursor_x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		cursor_x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + tracking
	return cursor_x


func _draw_title(pos: Vector2) -> void:
	_draw_tracked_text(pos, "HORIZON", 78, COLOR_TEXT_PRIMARY, 4.0, TITLE_FONT)


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y

	var title_baseline: float = h * 0.34
	_draw_title(Vector2(MENU_MARGIN, title_baseline))

	var subtitle_y: float = title_baseline + 36.0
	_draw_tracked_text(Vector2(MENU_MARGIN + 4.0, subtitle_y), SUBTITLE, 14, COLOR_TEXT_MUTED, 4.0)

	_item_rects.clear()
	var menu_y: float = subtitle_y + 76.0
	for i in menu_items.size():
		var item: MenuItem = menu_items[i]
		var row_y: float = menu_y + i * MENU_ROW_HEIGHT
		var is_hot: bool = item.enabled and (i == hovered_index or i == selected_index)
		var color: Color = COLOR_TEXT_FAINT
		if item.enabled:
			color = COLOR_TEXT_PRIMARY if is_hot else COLOR_TEXT_SECONDARY
		_draw_tracked_text(Vector2(MENU_MARGIN, row_y), item.label, 20, color, 3.0)

		var rect := Rect2(MENU_MARGIN - 12.0, row_y - 26.0, MENU_COLUMN_WIDTH, 40.0)
		_item_rects.append(rect)

		if is_hot:
			draw_line(Vector2(MENU_MARGIN - 20.0, row_y - 12.0), Vector2(MENU_MARGIN - 20.0, row_y + 12.0), COLOR_CYAN, 2.0)
			draw_line(Vector2(MENU_MARGIN, row_y + 14.0), Vector2(MENU_MARGIN + MENU_COLUMN_WIDTH - 24.0, row_y + 14.0), Color(COLOR_CYAN, 0.7), 1.0)

	_draw_tracked_text(Vector2(MENU_MARGIN, h - 40.0), VERSION_TAG, 12, COLOR_TEXT_FAINT, 2.0)

	if _credits_open:
		_draw_credits_panel()


func _draw_credits_panel() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.03, 0.6))

	var panel_size := Vector2(520.0, 420.0)
	var panel_pos: Vector2 = (size - panel_size) * 0.5
	_credits_panel_rect = Rect2(panel_pos, panel_size)

	draw_set_transform(panel_pos)
	HudPanelStyle.draw_chamfered(self, panel_size, COLOR_CYAN, 14.0, 0.92, 0.55)

	var font := HudPanelStyle.get_font()
	draw_string(font, Vector2(30.0, 46.0), "CREDITS", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, COLOR_TEXT_PRIMARY)
	draw_line(Vector2(30.0, 60.0), Vector2(panel_size.x - 30.0, 60.0), Color(COLOR_TEXT_FAINT, 0.7), 1.0)

	draw_string(font, Vector2(30.0, 102.0), "HORIZON", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_CYAN)
	draw_string(font, Vector2(30.0, 126.0), "An orbital mechanics sandbox", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_TEXT_SECONDARY)

	draw_string(font, Vector2(30.0, 168.0), "CONTRIBUTORS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_TEXT_MUTED)

	var row_h := 34.0
	var list_top := 196.0
	for i in CONTRIBUTORS.size():
		var entry: Dictionary = CONTRIBUTORS[i]
		var row_y: float = list_top + i * row_h
		draw_string(font, Vector2(30.0, row_y), entry.rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_TEXT_FAINT)
		draw_string(font, Vector2(66.0, row_y), entry.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COLOR_TEXT_PRIMARY)
		draw_string(font, Vector2(260.0, row_y - 3.0), entry.commits, HORIZONTAL_ALIGNMENT_RIGHT, panel_size.x - 30.0 - 260.0, 11, COLOR_TEXT_SECONDARY)

	var footer_y: float = list_top + CONTRIBUTORS.size() * row_h + 18.0
	draw_line(Vector2(30.0, footer_y), Vector2(panel_size.x - 30.0, footer_y), Color(COLOR_TEXT_FAINT, 0.5), 1.0)
	draw_string(font, Vector2(30.0, footer_y + 26.0), "Built with Godot Engine", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT_MUTED)
	draw_string(font, Vector2(30.0, panel_size.y - 22.0), "ESC or click outside to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_TEXT_FAINT)

	draw_set_transform(Vector2.ZERO)


func _gui_input(event: InputEvent) -> void:
	if settings_menu.visible:
		return

	if _credits_open:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if not _credits_panel_rect.has_point(event.position):
				_credits_open = false
				queue_redraw()
		return

	if event is InputEventMouseMotion:
		var new_hover: int = _index_at(event.position)
		if new_hover != hovered_index:
			hovered_index = new_hover
			if new_hover != -1:
				selected_index = new_hover
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx: int = _index_at(event.position)
		if idx != -1:
			_activate(idx)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if settings_menu.visible:
				settings_menu.close_menu()
				get_viewport().set_input_as_handled()
			elif _credits_open:
				_credits_open = false
				queue_redraw()
				get_viewport().set_input_as_handled()
			return

		if settings_menu.visible or _credits_open:
			return

		if event.keycode == KEY_DOWN or event.keycode == KEY_S:
			_move_selection(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_UP or event.keycode == KEY_W:
			_move_selection(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
			_activate(selected_index)
			get_viewport().set_input_as_handled()


func _index_at(pos: Vector2) -> int:
	for i in _item_rects.size():
		if menu_items[i].enabled and _item_rects[i].has_point(pos):
			return i
	return -1


func _move_selection(dir: int) -> void:
	var n: int = menu_items.size()
	if n == 0:
		return
	var idx: int = selected_index
	for _i in n:
		idx = posmod(idx + dir, n)
		if menu_items[idx].enabled:
			selected_index = idx
			break
	hovered_index = -1
	queue_redraw()


func _activate(idx: int) -> void:
	selected_index = idx
	queue_redraw()
	var item: MenuItem = menu_items[idx]
	if item.action.is_valid():
		item.action.call()


func _on_new_game() -> void:
	get_tree().change_scene_to_file("res://solar_system.tscn")


func _on_settings() -> void:
	settings_menu.open_menu()


func _on_credits() -> void:
	_credits_open = true
	queue_redraw()


func _on_exit() -> void:
	get_tree().quit()
