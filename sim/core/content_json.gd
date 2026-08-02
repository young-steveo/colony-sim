class_name ContentJson
extends RefCounted
## Shared plumbing for content-def loaders (Built to Be Modded): one
## always-on validation pass per loader, collecting problems with real
## diagnostics — file, entry, field, what was wrong. Dev builds crash
## hard on any problem (the assert in ok()); release builds push every
## error to the log and the loader refuses the file. Bad data is loud in
## both, silent in neither — asserts alone strip out of export builds,
## which is exactly where mods load.


## Parse a JSON file to its root Dictionary, or null with the error
## (including line number — JSON.parse_string discards it) collected.
static func parse_file(path: String, errors: Array[String]) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.push_back("%s: missing or empty" % path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.push_back("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		errors.push_back("%s: root is not a JSON object" % path)
		return null
	return json.data


## True when the load was clean. Otherwise every error hits the log, dev
## builds stop on the full list, and the caller refuses the file.
static func ok(errors: Array[String]) -> bool:
	if errors.is_empty():
		return true
	for e: String in errors:
		push_error(e)
	assert(false, "\n".join(errors))
	return false


## Typed field reads: wrong-typed mod data becomes a collected error and
## a safe default, never a runtime cast blowup mid-load.
static func num(d: Dictionary, key: String, def: float, errors: Array[String], ctx: String) -> float:
	var v: Variant = d.get(key, def)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return v
	errors.push_back("%s: '%s' must be a number, got %s" % [ctx, key, type_string(typeof(v))])
	return def


static func text(d: Dictionary, key: String, def: String, errors: Array[String], ctx: String) -> String:
	var v: Variant = d.get(key, def)
	if typeof(v) == TYPE_STRING:
		return v
	errors.push_back("%s: '%s' must be a string, got %s" % [ctx, key, type_string(typeof(v))])
	return def


static func color(d: Dictionary, key: String, def: String, errors: Array[String], ctx: String) -> Color:
	var v := text(d, key, def, errors, ctx)
	if Color.html_is_valid(v):
		return Color(v)
	errors.push_back("%s: '%s' is not a valid color: '%s'" % [ctx, key, v])
	return Color(def)
