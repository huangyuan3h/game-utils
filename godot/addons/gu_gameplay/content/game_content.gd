class_name GameContent
extends RefCounted
## Typed definitions built from the JSON tables under `res://data/content/`.
## Tables are authored as `{"rows": [...]}` so `gu data validate` and `gu data build` can check them.

const CONTENT_DIR := "res://data/content"

static var _db: ContentDatabase = null


static func database() -> ContentDatabase:
	if _db == null:
		_db = ContentDatabase.new()
		_db.load_dir(CONTENT_DIR)
	return _db


static func reload() -> void:
	_db = null


static func quests() -> Array[QuestDef]:
	var out: Array[QuestDef] = []
	for row in database().rows("quests"):
		var def := QuestDef.from_dict(row)
		if def != null and def.is_valid():
			out.append(def)
	return out


static func quest(id: StringName) -> QuestDef:
	var row := database().find("quests", String(id))
	if row.is_empty():
		GuLog.warn("Content", "Missing quest '%s'" % String(id))
		return null
	return QuestDef.from_dict(row)


static func dialogue(id: StringName) -> DialogueDef:
	var row := database().find("dialogue", String(id))
	if row.is_empty():
		GuLog.warn("Content", "Missing dialogue '%s'" % String(id))
		return null
	var def := DialogueDef.from_dict(row)
	return def if def.is_valid() else null


static func items() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for row in database().rows("items"):
		var def := ItemDef.new()
		def.id = StringName(str(row.get("id", "")))
		def.display_name = str(row.get("display_name", String(def.id)))
		def.max_stack = int(row.get("max_stack", 99))
		for raw_tag in row.get("tags", []) as Array:
			def.tags.append(StringName(str(raw_tag)))
		out.append(def)
	return out


static func resource_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in database().rows("resources"):
		var spec := row.duplicate(true)
		spec["kind"] = StringName(str(row.get("kind", "")))
		spec["action"] = StringName(str(row.get("action", "")))
		spec["offset"] = _to_vector2(row.get("offset", [0.0, 0.0]))
		spec["color"] = _to_color(row.get("color", [1.0, 1.0, 1.0]))
		if not (spec.get("yields") is Array):
			spec["yields"] = []
		out.append(spec)
	return out


static func _to_vector2(raw: Variant) -> Vector2:
	if raw is Array:
		var arr := raw as Array
		if arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO


static func _to_color(raw: Variant) -> Color:
	if raw is Array:
		var arr := raw as Array
		if arr.size() >= 4:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
		if arr.size() >= 3:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return Color.WHITE
