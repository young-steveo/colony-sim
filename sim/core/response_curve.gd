class_name ResponseCurve
extends RefCounted
## Parametric IAUS response curve: maps a normalized input in [0,1] to a
## score in [0,1]. Authored as plain data (see data/ai.json) so mods ride
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


static func from_dict(d: Dictionary) -> ResponseCurve:
	var curve := ResponseCurve.new()
	var type_name: String = d.get("type", "poly")
	match type_name:
		"poly":
			curve.type = Type.POLY
		"logistic":
			curve.type = Type.LOGISTIC
		_:
			assert(false, "ResponseCurve: unknown type '%s'" % type_name)
	curve.m = d.get("m", 1.0)
	curve.k = d.get("k", 1.0)
	curve.b = d.get("b", 0.0)
	curve.c = d.get("c", 0.0)
	return curve


func evaluate(x: float) -> float:
	match type:
		Type.LOGISTIC:
			return clampf(b + m / (1.0 + exp(-k * (x - c))), 0.0, 1.0)
		_:
			return clampf(m * pow(x - c, k) + b, 0.0, 1.0)
