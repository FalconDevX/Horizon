class_name HudPanelStyle
extends RefCounted

# Ta sama rodzina czcionek co lewy panel (Theme_hud/SystemFont_hud w
# solar_system.tscn) - tam to sub_resource w scenie (niedostępny z poziomu
# skryptu), więc tutaj budujemy identyczny SystemFont raz i cache'ujemy,
# żeby wszystkie własnoręcznie rysowane panele (draw_string) używały tej
# samej, pasującej monospace czcionki zamiast domyślnej ThemeDB.fallback_font.
static var _font: Font


static func get_font() -> Font:
	if _font == null:
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Courier New"])
		system_font.subpixel_positioning = 0
		_font = system_font
	return _font


static func draw_chamfered(
	ci: CanvasItem, panel_size: Vector2, accent: Color, chamfer: float = 16.0, bg_alpha: float = 0.6
) -> void:
	var w: float = panel_size.x
	var h: float = panel_size.y

	var points := PackedVector2Array([
		Vector2(chamfer, 0.0),
		Vector2(w, 0.0),
		Vector2(w, h - chamfer),
		Vector2(w - chamfer, h),
		Vector2(0.0, h),
		Vector2(0.0, chamfer),
	])

	ci.draw_colored_polygon(points, Color(0.05, 0.07, 0.12, bg_alpha))

	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	ci.draw_polyline(outline, Color(accent, 0.8), 1.5, true)
