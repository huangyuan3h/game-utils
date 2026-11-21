class_name ContentDatabase
extends RefCounted
## Loads every JSON table in a directory and indexes rows by `table/id`.
## Tables use the `{"rows": [...]}` shape that `gu data build` writes, and may
## contain nested objects/arrays for definitions such as quests or dialogue.

var _tables: Dictionary = {} ## String table name -> Array[Dictionary]
var _index: Dictionary = {} ## "table/id" -> Dictionary


func load_dir(dir_path: String) -> int:
	_tables.clear()
	_index.clear()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	var total := 0
	for file_name in dir.get_files():
		if not file_name.ends_with(".json") or file_name.ends_with(".schema.json"):
			continue
		var table_name := file_name.get_basename()
		var rows := DataTableLoader.load_table(dir_path.path_join(file_name))
		_tables[table_name] = rows
		total += rows.size()
		for row in rows:
			if row.has("id"):
				_index["%s/%s" % [table_name, str(row["id"])]] = row
	return total


func table_names() -> Array[String]:
	var names: Array[String] = []
	for key in _tables:
		names.append(str(key))
	names.sort()
	return names


func rows(table_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var found: Variant = _tables.get(table_name, [])
	if found is Array:
		for row in found as Array:
			if row is Dictionary:
				out.append((row as Dictionary).duplicate(true))
	return out


func find(table_name: String, id: String) -> Dictionary:
	var found: Variant = _index.get("%s/%s" % [table_name, id], {})
	if found is Dictionary:
		return (found as Dictionary).duplicate(true)
	return {}


func has(table_name: String, id: String) -> bool:
	return _index.has("%s/%s" % [table_name, id])


func count(table_name: String) -> int:
	var found: Variant = _tables.get(table_name, [])
	return (found as Array).size() if found is Array else 0


func total_rows() -> int:
	var total := 0
	for key in _tables:
		total += (_tables[key] as Array).size()
	return total
