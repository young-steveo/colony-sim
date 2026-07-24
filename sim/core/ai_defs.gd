class_name AiDefs
extends RefCounted
## Data-driven AI definitions: needs, considerations, actions — parsed from
## plain JSON (data/ai.json) so modders author on the same rails we do
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
const MISC_INPUTS: Array[StringName] = [&"food_distance"]
const EXECUTIONS: Array[StringName] = [&"eat", &"sleep", &"wander"]


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
	# Typed execution params (parsed from the "params" object with defaults).
	var restore_per_bite := 0.35
	var ticks_per_bite := 45
	var restore_per_second := 0.12
	var wake_threshold := 0.95


var needs: Array[NeedDef] = []
var actions: Array[ActionDef] = []
var bucket_order: Array[int] = []  # distinct buckets, highest first


static func load_file(path: String) -> AiDefs:
	var text := FileAccess.get_file_as_string(path)
	assert(not text.is_empty(), "AiDefs: cannot read %s" % path)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "AiDefs: %s is not a JSON object" % path)
	var root: Dictionary = parsed
	var defs := AiDefs.new()

	var needs_raw: Array = root.get("needs", [])
	for entry: Variant in needs_raw:
		var nd: Dictionary = entry
		var need := NeedDef.new()
		need.id = StringName(str(nd.get("id", "")))
		need.start = nd.get("start", 1.0)
		need.drain_per_second = nd.get("drain_per_second", 0.0)
		assert(need.id != &"", "AiDefs: need without id")
		defs.needs.append(need)

	var actions_raw: Array = root.get("actions", [])
	for entry: Variant in actions_raw:
		var ad: Dictionary = entry
		var action := ActionDef.new()
		action.id = StringName(str(ad.get("id", "")))
		var bucket_f: float = ad.get("bucket", 0.0)
		action.bucket = int(bucket_f)
		action.weight = ad.get("weight", 1.0)
		action.execution = StringName(str(ad.get("execution", "")))
		assert(action.id != &"", "AiDefs: action without id")
		assert(
			action.execution in EXECUTIONS,
			"AiDefs: action '%s' has unknown execution '%s'" % [action.id, action.execution]
		)
		var params: Dictionary = ad.get("params", {})
		action.restore_per_bite = params.get("restore_per_bite", 0.35)
		var tpb: float = params.get("ticks_per_bite", 45.0)
		action.ticks_per_bite = int(tpb)
		action.restore_per_second = params.get("restore_per_second", 0.12)
		action.wake_threshold = params.get("wake_threshold", 0.95)
		var cons_raw: Array = ad.get("considerations", [])
		for centry: Variant in cons_raw:
			var cd: Dictionary = centry
			var con := ConsiderationDef.new()
			con.input = StringName(str(cd.get("input", "")))
			con.need_idx = defs.need_index(con.input)
			assert(
				con.need_idx >= 0 or con.input in MISC_INPUTS,
				"AiDefs: consideration on '%s' has unknown input '%s'" % [action.id, con.input]
			)
			con.input_min = cd.get("input_min", 0.0)
			con.input_max = cd.get("input_max", 1.0)
			assert(con.input_max > con.input_min, "AiDefs: bad window on '%s'" % action.id)
			var curve_raw: Dictionary = cd.get("curve", {})
			con.curve = ResponseCurve.from_dict(curve_raw)
			action.considerations.append(con)
		defs.actions.append(action)

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
	assert(has_idle, "AiDefs: lowest bucket needs a zero-consideration idle action")
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
