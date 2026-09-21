class_name HudPanelStyle
extends RefCounted

static var _font: Font

# ==============================================================================
# AVIONICS COLOR PALETTE TOKENS (HIGH-PRECISION TELEMETRY)
# ==============================================================================
# Canvas & Surfaces
const COLOR_BG_CANVAS := Color(0.045, 0.065, 0.095)          # Deep space obsidian (#0b1118)
const COLOR_BG_SURFACE := Color(0.075, 0.105, 0.155)         # Elevated instrument card plate (#131b27)
const COLOR_BORDER_DEFAULT := Color(0.18, 0.26, 0.38, 0.50)  # Structural hairline border (#2e4261)
const COLOR_BORDER_HOVER := Color(0.28, 0.40, 0.58, 0.65)    # Hover highlight border

# Calibrated Telemetry Accents
const COLOR_CYAN := Color(0.30, 0.78, 0.88)                  # Telemetry Teal / Ice Cyan (#4dc7e0)
const COLOR_CYAN_DIM := Color(0.30, 0.78, 0.88, 0.35)        # Subdued cyan tone
const COLOR_CYAN_GLOW := Color(0.30, 0.78, 0.88, 0.12)       # Ambient telemetry glow
const COLOR_AMBER := Color(0.96, 0.68, 0.24)                 # Telemetry Warning / Amber (#f5ae3d)
const COLOR_EMERALD := Color(0.28, 0.82, 0.56)               # Active System Emerald (#47d18f)

# Typography Scale
const COLOR_TEXT_PRIMARY := Color(0.92, 0.95, 0.98)          # High-contrast readable white
const COLOR_TEXT_SECONDARY := Color(0.72, 0.78, 0.86)        # Setting labels & body text
const COLOR_TEXT_MUTED := Color(0.44, 0.50, 0.60)            # Sublines, hints, shortcuts
const COLOR_TEXT_FAINT := Color(0.24, 0.30, 0.38)            # Calibration ticks & dividers


static func get_font() -> Font:
	if _font == null:
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Courier New"])
		system_font.subpixel_positioning = 0
		_font = system_font
	return _font


static func draw_chamfered(
	ci: CanvasItem, panel_size: Vector2, accent: Color, chamfer: float = 14.0, bg_alpha: float = 0.6, border_alpha: float = 0.5
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

	# Dark obsidian base polygon
	ci.draw_colored_polygon(points, Color(COLOR_BG_CANVAS, bg_alpha))

	# Subtle hairline border outline
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	ci.draw_polyline(outline, Color(accent, border_alpha), 1.0, true)

