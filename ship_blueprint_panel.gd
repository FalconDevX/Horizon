extends Control
## Bottom-right: the ship's status - view only. Every module built in the
## yard is drawn with its own art, nose up, turrets turned as they aim; a
## damaged one is tinted by what is left of it (yellow, orange, dark red when
## wrecked). Modules light up: blue a gun picked (1-9) or switched on in the
## rack, orange a gun that just fired, red a module just hit. The stock ship
## (nothing built) shows its outline. Reads ship.gd `built_visual.modules`,
## `module_hp` / `module_hit_msec`, `weapon_fire_msec`, `selected_weapon`,
## `active_weapons` and `turret_aim`.
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
const COLOR_HIT := Color(1.0, 0.2, 0.15)
const COLOR_FIRE := Color(1.0, 0.6, 0.15)
const COLOR_ON := Color(0.3, 0.7, 1.0)
## How long a gun glows orange after a shot, msec.
const FIRE_MSEC := 300.0

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
	var shots: Dictionary = ship.get("weapon_fire_msec")
	var active: Dictionary = ship.get("active_weapons")
	var aims: Dictionary = ship.get("turret_aim")
	var picked: int = int(ship.get("selected_weapon"))
	var combat: Node = _game.get("combat")
	var locked: bool = combat != null and combat.call("is_locked")
	var now: int = Time.get_ticks_msec()
	var worst := 1.0
	for module: Dictionary in modules:
		var id: int = int(module["id"])
		var rect: Rect2 = module["rect"]
		var a: Vector2 = to_screen.call(rect.position)
		var b: Vector2 = to_screen.call(rect.end)
		var box := Rect2(a, Vector2.ZERO).expand(b)
		var share: float = float(hp.get(id, module["max_hp"])) / float(module["max_hp"])
		if not module["structure"]:
			worst = minf(worst, share)
		# The art, turned nose up (a turret also by its aim), darkened and
		# tinted as it wears down.
		var art: Texture2D = module.get("texture")
		if art != null:
			var tint: Color = Color.WHITE.lerp(health_color(share), 0.0 if share >= 1.0 else 0.35 + 0.4 * (1.0 - share))
			if share <= 0.0:
				tint = tint.darkened(0.5)
			var turn: float = -PI * 0.5 + float(aims.get(id, 0.0))
			draw_set_transform(box.get_center(), turn, Vector2.ONE)
			var drawn: Vector2 = rect.size * k
			draw_texture_rect(art, Rect2(-drawn * 0.5, drawn), false, tint)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_rect(box.grow(-0.6), Color(health_color(share), 0.35 if module["structure"] else 0.75))
		if share < 1.0 and not module["structure"]:
			draw_rect(box.grow(-0.6), Color(health_color(share), 0.8), false, 1.0)
		# The glow: red just hit, orange just fired, blue picked or switched on.
		var hit: float = 1.0 - clampf(float(now - int(hits.get(id, -100000))) / FLASH_MSEC, 0.0, 1.0)
		var fire: float = 1.0 - clampf(float(now - int(shots.get(id, -100000))) / FIRE_MSEC, 0.0, 1.0)
		if hit > 0.0:
			_draw_glow(box, COLOR_HIT, hit)
		elif fire > 0.0:
			_draw_glow(box, COLOR_FIRE, fire)
		elif id == picked or active.has(id):
			# Blinks while it waits for a lock, steady once it has one.
			_draw_glow(box, COLOR_ON, 0.7 if locked else 0.35 + 0.35 * sin(now * 0.008))
	var hull_share: float = 1.0
	if bool(ship.get("resources_enabled")) and float(ship.get("max_hull_hp")) > 0.0:
		hull_share = float(ship.get("hull_hp")) / float(ship.get("max_hull_hp"))
	_draw_footer(font, "Hull %d%%" % roundi(hull_share * 100.0), "Worst module %d%%" % roundi(worst * 100.0))


func _draw_glow(box: Rect2, colour: Color, strength: float) -> void:
	draw_rect(box.grow(1.5), Color(colour, 0.25 * strength))
	draw_rect(box, Color(colour, 0.35 * strength))
	draw_rect(box.grow(0.5), Color(colour, 0.95 * strength), false, 1.5)


func _draw_stock_ship(area: Rect2) -> void:
	var tex_size: Vector2 = SHIP_TEXTURE.get_size()
	var fit: float = minf(area.size.x / tex_size.x, area.size.y / tex_size.y) * 0.8
	var drawn: Vector2 = tex_size * fit
	draw_texture_rect(SHIP_TEXTURE, Rect2(area.get_center() - drawn * 0.5, drawn), false, Color(COLOR_WHOLE, 0.8))


func _draw_footer(font: Font, left: String, right: String) -> void:
	var y: float = size.y - PAD - 2.0
	draw_string(font, Vector2(PAD + 2.0, y), left, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, HudPanelStyle.COLOR_TEXT_MUTED)
	draw_string(font, Vector2(PAD, y), right, HORIZONTAL_ALIGNMENT_RIGHT, size.x - PAD * 2.0 - 2.0, 9, HudPanelStyle.COLOR_TEXT_MUTED)
