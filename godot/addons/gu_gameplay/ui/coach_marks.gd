class_name CoachMarks
extends RefCounted
## One-shot guidance flags. The second call for the same flag does nothing.

static func try_show(flags, flag_id: StringName) -> bool:
	if flags == null or flag_id == &"" or flags.get_bool(flag_id, false):
		return false
	flags.set_flag(flag_id, true)
	return true
