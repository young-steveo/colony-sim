class_name AiDefs
extends RefCounted
## Data-driven AI definitions: needs, considerations, actions — parsed from
## plain JSON (content/actors/ai.json) so modders author on the same rails we do
## (Built to Be Modded). Validation is loud and happens at load, never
## mid-decision.
##
## Scoring model (adopted from The Final Archive's proven core): each action
## multiplies its considerations' curve outputs, applies Dave Mark's
## compensation factor so many-consideration actions aren't starved, then
## multiplies by the action's weight. Weights are priority tiers, not tuning
## knobs. An action with zero considerations scores exactly its weight — the
## mandatory constant-utility idle floor.

## Inputs that aren't need levels; the matching read lives in ActorPool.
const MISC_INPUTS: Array[StringName] = [
	&"food_distance", &"bed_distance", &"blueprint_distance", &"build_crowding",
	&"chop_distance", &"wood_distance", &"haul_target_distance", &"has_order",
]
const EXECUTIONS: Array[StringName] = [
	&"eat", &"sleep", &"sleep_bed", &"build", &"wander", &"chop", &"haul", &"goto",
]


class NeedDef:
	extends RefCounted
	var id := &""
	var start := 1.0
	var drain_per_second := 0.0


class ConsiderationDef:
	extends RefCounted
	var input := &""
	var need_idx := -1  # resolved index into needs, or -1 for misc inputs
	var curve: ResponseCurve
	var input_min := 0.0
	var input_max := 1.0

	## Normalize a raw input through the [input_min, input_max] window,
	## clamped at the edges, then through the response curve.
	func score(raw: float) -> float:
		var t := clampf((raw - input_min) / (input_max - input_min), 0.0, 1.0)
		return curve.evaluate(t)


class ActionDef:
	extends RefCounted
	var id := &""
	var bucket := 0
	var weight := 1.0
	var execution := &""
	var considerations: Array[ConsiderationDef] = []
	# The need this action's execution restores (explicit "restores" key
	# in the JSON — never inferred from consideration order, which is a
	# hidden contract a modder reordering a list would silently break).
	var restores_need_idx := -1
	# Typed execution params (parsed from the "params" object with defaults).
	var restore_per_bite := 0.35
	var ticks_per_bite := 45
	var restore_per_second := 0.12
	var wake_threshold := 0.95


var needs: Array[NeedDef] = []
var actions: Array[ActionDef] = []
var bucket_order: Array[int] = []  # distinct buckets, highest first


## Executions whose activity restores a need — their actions must name
## it with an explicit "restores" key.
const _RESTORING_EXECUTIONS: Array[StringName] = [&"eat", &"sleep", &"sleep_bed"]


## Strict load: dev crashes on any problem, release logs every problem
## and refuses the file (returns null). See ContentJson.
static func load_file(path: String) -> AiDefs:
	var errors: Array[String] = []
	var defs := parse(path, errors)
	return defs if ContentJson.ok(errors) else null


## Validating core: collects problems instead of crashing. Side-effect
## free, so tests can feed it garbage and inspect the error list.
static func parse(path: String, errors: Array[String]) -> AiDefs:
	var data: Variant = ContentJson.parse_file(path, errors)
	if data == null:
		return null
	var root: Dictionary = data
	var defs := AiDefs.new()

	var needs_raw: Array = root.get("needs", [])
	for n: int in needs_raw.size():
		if not needs_raw[n] is Dictionary:
			errors.push_back("%s: needs[%d] is not an object" % [path, n])
			continue
		var nd: Dictionary = needs_raw[n]
		var ctx := "%s: need '%s'" % [path, nd.get("id", "#%d" % n)]
		var need := NeedDef.new()
		need.id = StringName(ContentJson.text(nd, "id", "", errors, ctx))
		need.start = ContentJson.num(nd, "start", 1.0, errors, ctx)
		need.drain_per_second = ContentJson.num(nd, "drain_per_second", 0.0, errors, ctx)
		if need.id == &"":
			errors.push_back("%s: missing id" % ctx)
		defs.needs.append(need)

	var actions_raw: Array = root.get("actions", [])
	for n: int in actions_raw.size():
		if not actions_raw[n] is Dictionary:
			errors.push_back("%s: actions[%d] is not an object" % [path, n])
			continue
		var ad: Dictionary = actions_raw[n]
		var ctx := "%s: action '%s'" % [path, ad.get("id", "#%d" % n)]
		var action := ActionDef.new()
		action.id = StringName(ContentJson.text(ad, "id", "", errors, ctx))
		action.bucket = int(ContentJson.num(ad, "bucket", 0.0, errors, ctx))
		action.weight = ContentJson.num(ad, "weight", 1.0, errors, ctx)
		action.execution = StringName(ContentJson.text(ad, "execution", "", errors, ctx))
		if action.id == &"":
			errors.push_back("%s: missing id" % ctx)
		if not action.execution in EXECUTIONS:
			errors.push_back("%s: unknown execution '%s'" % [ctx, action.execution])
		var restores := StringName(ContentJson.text(ad, "restores", "", errors, ctx))
		if restores != &"":
			action.restores_need_idx = defs.need_index(restores)
			if action.restores_need_idx < 0:
				errors.push_back("%s: restores unknown need '%s'" % [ctx, restores])
		elif action.execution in _RESTORING_EXECUTIONS:
			errors.push_back(
				"%s: execution '%s' restores a need — add a \"restores\" key naming it" % [
					ctx, action.execution,
				]
			)
		var params: Dictionary = ad.get("params", {})
		action.restore_per_bite = ContentJson.num(params, "restore_per_bite", 0.35, errors, ctx)
		action.ticks_per_bite = int(ContentJson.num(params, "ticks_per_bite", 45.0, errors, ctx))
		action.restore_per_second = ContentJson.num(params, "restore_per_second", 0.12, errors, ctx)
		action.wake_threshold = ContentJson.num(params, "wake_threshold", 0.95, errors, ctx)
		var cons_raw: Array = ad.get("considerations", [])
		for cn: int in cons_raw.size():
			if not cons_raw[cn] is Dictionary:
				errors.push_back("%s: considerations[%d] is not an object" % [ctx, cn])
				continue
			var cd: Dictionary = cons_raw[cn]
			var con := ConsiderationDef.new()
			con.input = StringName(ContentJson.text(cd, "input", "", errors, ctx))
			con.need_idx = defs.need_index(con.input)
			if con.need_idx < 0 and not con.input in MISC_INPUTS:
				errors.push_back("%s: unknown consideration input '%s'" % [ctx, con.input])
			con.input_min = ContentJson.num(cd, "input_min", 0.0, errors, ctx)
			con.input_max = ContentJson.num(cd, "input_max", 1.0, errors, ctx)
			if con.input_max <= con.input_min:
				errors.push_back("%s: input window must satisfy max > min" % ctx)
			var curve_raw: Dictionary = cd.get("curve", {})
			con.curve = ResponseCurve.from_dict(curve_raw, errors, ctx)
			action.considerations.append(con)
		defs.actions.append(action)

	if defs.actions.is_empty():
		errors.push_back("%s: defines no actions" % path)
		return defs
	for action: ActionDef in defs.actions:
		if not defs.bucket_order.has(action.bucket):
			defs.bucket_order.append(action.bucket)
	defs.bucket_order.sort()
	defs.bucket_order.reverse()

	# The lowest bucket must contain a constant-utility idle: without one an
	# all-zero pass would "win" with an arbitrary authored-order action.
	var lowest: int = defs.bucket_order[defs.bucket_order.size() - 1]
	var has_idle := false
	for action: ActionDef in defs.actions:
		if action.bucket == lowest and action.considerations.is_empty():
			has_idle = true
	if not has_idle:
		errors.push_back("%s: lowest bucket needs a zero-consideration idle action" % path)
	return defs


func need_index(id: StringName) -> int:
	for n: int in needs.size():
		if needs[n].id == id:
			return n
	return -1


func action_index(id: StringName) -> int:
	for a: int in actions.size():
		if actions[a].id == id:
			return a
	return -1


## Dave Mark's compensation factor: rescues many-consideration actions from
## the shrinking-product problem. compensate(1.0, 0) == 1.0, so a
## zero-consideration action's score is exactly its weight.
static func compensate(product: float, consideration_count: int) -> float:
	if consideration_count == 0:
		return product
	var mod := 1.0 - 1.0 / consideration_count
	return product + product * (1.0 - product) * mod
