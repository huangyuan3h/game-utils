class_name ItemDef
extends Resource
## Reusable item metadata resource for stack limits, display names, tags, and icons.

@export var id: StringName = &""
@export var display_name: String = ""
@export var max_stack: int = 99
@export var tags: Array[StringName] = []
@export var icon: Texture2D = null
