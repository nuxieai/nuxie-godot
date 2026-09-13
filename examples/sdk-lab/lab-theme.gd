extends RefCounted
## Native equivalents of Nuxie's dark canvas, neutral capsules and violet primary.
const BACKGROUND := Color("111116")
const FOREGROUND := Color("eeeeee")
const MUTED_FOREGROUND := Color("a5a5ae")
const SURFACE := Color("25252a")
const HOVER := Color("303037")
const PRIMARY := Color("7c3aed")

static func capsule(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(24)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

static func create() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.set_color("font_color", "Label", FOREGROUND)
	result.set_color("default_color", "RichTextLabel", MUTED_FOREGROUND)
	for control: String in ["Button", "LineEdit"]:
		result.set_color("font_color", control, FOREGROUND)
		result.set_stylebox("normal", control, capsule(SURFACE))
		result.set_stylebox("focus", control, capsule(HOVER))
	result.set_stylebox("hover", "Button", capsule(HOVER))
	result.set_stylebox("pressed", "Button", capsule(HOVER))
	result.set_stylebox("disabled", "Button", capsule(SURFACE))
	result.set_type_variation("PrimaryButton", "Button")
	result.set_stylebox("normal", "PrimaryButton", capsule(PRIMARY))
	result.set_stylebox("hover", "PrimaryButton", capsule(PRIMARY.lightened(0.12)))
	return result
