class_name ResponseCurve
extends RefCounted
## Parametric IAUS response curve: maps a normalized input in [0,1] to a
## score in [0,1]. Authored as plain data (see content/actors/ai.json) so mods ride
## the same rails — no editor-drawn Curve resources in the sim.
##
##   poly:     y = m * (x - c)^k + b
##   logistic: y = b + m / (1 + e^(-k * (x - c)))

enum Type { POLY, LOGISTIC }

var type := Type.POLY
var m := 1.0
var k := 1.0
var b := 0.0
var c := 0.0


## Validating parse: problems are collected (with ctx naming the owning
## action) rather than crashing — see ContentJson for the loud/strict
## split between dev and release builds.
static func from_dict(d: Dictionary, errors: Array[String], ctx: String) -> ResponseCurve:
	var curve := ResponseCurve.new()
	var type_name := ContentJson.text(d, "type", "poly", errors, ctx)
	match type_name:
		"poly":
			curve.type = Type.POLY
		"logistic":
			curve.type = Type.LOGISTIC
		_:
			errors.push_back("%s: unknown curve type '%s'" % [ctx, type_name])
	curve.m = ContentJson.num(d, "m", 1.0, errors, ctx)
	curve.k = ContentJson.num(d, "k", 1.0, errors, ctx)
	curve.b = ContentJson.num(d, "b", 0.0, errors, ctx)
	curve.c = ContentJson.num(d, "c", 0.0, errors, ctx)
	# poly evaluates m * (x - c)^k: with fractional k, any x < c raises a
	# negative base to a fractional power — NaN, which clampf keeps as
	# NaN and the scoring pass silently propagates. Reject at load.
	if curve.type == Type.POLY and curve.k != roundf(curve.k) and curve.c > 0.0:
		errors.push_back(
			"%s: poly curve with fractional k (%.2f) and c > 0 (%.2f) is NaN for x < c" % [
				ctx, curve.k, curve.c,
			]
		)
	return curve


func evaluate(x: float) -> float:
	match type:
		Type.LOGISTIC:
			return clampf(b + m / (1.0 + exp(-k * (x - c))), 0.0, 1.0)
		_:
			return clampf(m * pow(x - c, k) + b, 0.0, 1.0)
