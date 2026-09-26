extends Control
## Bottom-right: the ship's damage schematic - view only. Every module built
## in the yard is a block, nose up, coloured by what is left of it (green
## whole, through yellow and orange, to dark red when wrecked); the one just
## hit flashes. The stock ship (nothing built) shows its outline. Reads
## ship.gd `built_visual.modules` and `module_hp` / `module_hit_msec`.
## Clicking it points the main camera back at the ship. solar_system.gd calls
## setup() once and set_state() every frame.

signal clicked

const PAD := 10.0
const HEADER := 22.0
const LABEL_HEIGHT := 16.0
const SHIP_TEXTURE := preload("res://textures/ship_blueprint.png")
## How long a hit module flashes, msec.
const FLASH_MSEC := 450.0
const COLOR_WHOLE := Color(0.3, 0.85, 0.45)
const COLOR_WORN := Color(0.95, 0.85, 0.3)
const COLOR_BAD := Color(1.0, 0.5, 0.15)
const COLOR_WRECKED := Color(0.45, 0.08, 0.06)
const COLOR_FLASH := Color(1.0, 0.95, 0.9)

var throttle := 0.0
var _game: Node = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(game: Node) -> void:
	_game = game


func set_state(p_throttle: float) -> void:
	throttle = p_throttle


## Kept for solar_system.gd: the schematic is drawn from the modules.
func set_built_texture(_texture: Texture2D) -> void:
	pass


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		accept_event()


## Green -> yellow -> orange -> dark red as `share` of a module's hit points
## goes from 1 to 0.
static func health_color(share: float) -> Color:
	if share >= 0.75:
		return COLOR_WORN.lerp(COLOR_WHOLE, (share - 0.75) / 0.25)
	if share >= 0.4:
		return COLOR_BAD.lerp(COLOR_WORN, (share - 0.4) / 0.35)
	if share > 0.0:
		return COLOR_WRECKED.lerp(COLOR_BAD, share / 0.4)
	return COLOR_WRECKED


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_BORDER_DEFAULT, 16.0, 0.85, 0.55)
	var font: Font = HudPanelStyle.get_font()
	draw_string(font, Vector2(PAD + 2.0, PAD + 10.0), "SHIP STATUS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudPanelStyle.COLOR_CYAN)
	var ship: Node2D = _game.get("ship") if _game != null else null
	if ship == null:
		return
	var area := Rect2(Vector2(PAD, PAD + HEADER), size - Vector2(PAD * 2.0, PAD * 2.0 + HEADER + LABEL_HEIGHT))
	var modules: Array = (ship.get("built_visual") as Dictionary).get("modules", [])
	if modules.is_empty():
		_draw_stock_ship(area)
		_draw_footer(font, "Stock ship", "")
		return

	# Fit the ship's footprint, turned nose up, into the area.
	var bounds := Rect2(modules[0]["rect"])
	for module: Dictionary in modules:
		bounds = bounds.merge(module["rect"])
	# Turning a quarter left swaps the axes: ship x (nose) becomes screen -y.
	var turned := Vector2(bounds.size.y, bounds.size.x)
	var k: float = minf(area.size.x / turned.x, area.size.y / turned.y) * 0.92
	var centre: Vector2 = area.get_center()
	var mid: Vector2 = bounds.get_center()
	var to_screen := func(p: Vector2) -> Vector2:
		var d: Vector2 = p - mid
		return centre + Vector2(d.y, -d.x) * k

	var hp: Dictionary = ship.get("module_hp")
	var hits: Dictionary = ship.get("module_hit_msec")
	var now: int = Time.get_ticks_msec()
	var worst := 1.0
	for module: Dictionary in modules:
		var rect: Rect2 = module["rect"]
		var a: Vector2 = to_screen.call(rect.position)
		var b: Vector2 = to_screen.call(rect.end)
		var box := Rect2(a, Vector2.ZERO).expand(b).grow(-0.6)
		var share: float = float(hp.get(int(module["id"]), module["max_hp"])) / float(module["max_hp"])
		if not module["structure"]:
			worst = minf(worst, share)
		var colour: Color = health_color(share)
		var fill_alpha: float = 0.35 if module["structure"] else 0.75
		var since: float = float(now - int(hits.get(int(module["id"]), -100000)))
		var flash: float = 1.0 - clampf(since / FLASH_MSEC, 0.0, 1.0)
		draw_rect(box, Color(colour.lerp(COLOR_FLASH, flash * 0.8), fill_alpha + 0.25 * flash))
		draw_rect(box, Color(colour, 0.9), false, 1.0 + 2.0 * flash)
	var hull_share: float = 1.0
	if bool(ship.get("resources_enabled")) and float(ship.get("max_hull_hp")) > 0.0:
		hull_share = float(ship.get("hull_hp")) / float(ship.get("max_hull_hp"))
	_draw_footer(font, "Hull %d%%" % roundi(hull_share * 100.0), "Worst module %d%%" % roundi(worst * 100.0))


func _draw_stock_ship(area: Rect2) -> void:
	var tex_size: Vector2 = SHIP_TEXTURE.get_size()
	var fit: float = minf(area.size.x / tex_size.x, area.size.y / tex_size.y) * 0.8
	var drawn: Vector2 = tex_size * fit
	draw_texture_rect(SHIP_TEXTURE, Rect2(area.get_center() - drawn * 0.5, drawn), false, Color(COLOR_WHOLE, 0.8))


func _draw_footer(font: Font, left: String, right: String) -> void:
	var y: float = size.y - PAD - 2.0
	draw_string(font, Vector2(PAD + 2.0, y), left, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, HudPanelStyle.COLOR_TEXT_MUTED)
	draw_string(font, Vector2(PAD, y), right, HORIZONTAL_ALIGNMENT_RIGHT, size.x - PAD * 2.0 - 2.0, 9, HudPanelStyle.COLOR_TEXT_MUTED)
