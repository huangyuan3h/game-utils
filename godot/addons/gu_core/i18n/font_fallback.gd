class_name FontFallback
extends RefCounted
## Attaches a CJK SystemFont behind ThemeDB.fallback_font so mixed Latin and CJK text does not draw boxes.

static func _names() -> PackedStringArray:
	return PackedStringArray([
		"PingFang SC",
		"Hiragino Sans",
		"Noto Sans CJK SC",
		"Noto Sans SC",
		"Microsoft YaHei",
		"sans-serif",
	])


static func apply() -> Font:
	var extra := _cjk_font()
	var base := ThemeDB.fallback_font
	if base == null:
		ThemeDB.fallback_font = extra
		return extra
	if _has_cjk(base):
		return base
	var chain: Array[Font] = []
	for item in base.fallbacks:
		var existing := item as Font
		if existing != null:
			chain.append(existing)
	chain.append(extra)
	base.fallbacks = chain
	return base


static func is_applied() -> bool:
	var base := ThemeDB.fallback_font
	return base != null and _has_cjk(base)


static func _cjk_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = _names()
	return font


static func _has_cjk(font: Font) -> bool:
	if font is SystemFont and _names_match(font as SystemFont):
		return true
	for item in font.fallbacks:
		var nested := item as Font
		if nested is SystemFont and _names_match(nested as SystemFont):
			return true
	return false


static func _names_match(font: SystemFont) -> bool:
	return font.font_names.has("PingFang SC") and font.font_names.has("Noto Sans CJK SC")
