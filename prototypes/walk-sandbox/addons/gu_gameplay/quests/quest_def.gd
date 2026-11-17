class_name QuestDef
extends Resource
## Declarative quest definition compatible with Inspector authoring and DataTableLoader JSON rows.

@export var id: StringName = &""
@export var title: String = ""
@export var description: String = ""
@export var objectives: Array[Dictionary] = []
@export var rewards: Array[Dictionary] = []
@export var auto_start: bool = false


static func from_dict(d: Dictionary) -> QuestDef:
	var q := QuestDef.new()
	q.id = StringName(str(d.get("id", "")))
	q.title = str(d.get("title", String(q.id)))
	q.description = str(d.get("description", ""))
	q.auto_start = bool(d.get("auto_start", false))

	var raw_objs: Variant = d.get("objectives", [])
	if raw_objs is Array:
		for obj in raw_objs as Array:
			if obj is Dictionary:
				q.objectives.append((obj as Dictionary).duplicate(true))

	var raw_rews: Variant = d.get("rewards", [])
	if raw_rews is Array:
		for rew in raw_rews as Array:
			if rew is Dictionary:
				q.rewards.append((rew as Dictionary).duplicate(true))

	return q


func is_valid() -> bool:
	return id != &"" and not objectives.is_empty()
