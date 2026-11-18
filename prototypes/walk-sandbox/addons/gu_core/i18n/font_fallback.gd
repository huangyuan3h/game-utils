class_name FontFallback
extends RefCounted
## Uses a CJK system font as the UI font so Chinese menu text draws instead of boxes.

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
	var cjk := _cjk_font()
	var base := ThemeDB.fallback_font
	if base == cjk:
		return cjk
	if base != null and not _contains(cjk, base):
		var chain: Array[Font] = [base]
		for item in cjk.fallbacks:
			var existing := item as Font
			if existing != null and existing != base:
				chain.append(existing)
		cjk.fallbacks = chain
	# Primary font, not a hidden fallback. Menus and popups then draw CJK glyphs.
	ThemeDB.fallback_font = cjk
	return cjk


static func apply_theme(theme: Theme) -> void:
	if theme == null:
		return
	theme.default_font = apply()


static func is_applied() -> bool:
	var base := ThemeDB.fallback_font
	return base != null and _has_cjk(base)


static var _cached: SystemFont


static func _cjk_font() -> SystemFont:
	if _cached == null:
		_cached = SystemFont.new()
		_cached.font_names = _names()
	return _cached


static func _contains(font: Font, needle: Font) -> bool:
	if font == needle:
		return true
	for item in font.fallbacks:
		var nested := item as Font
		if nested != null and _contains(nested, needle):
			return true
	return false


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
