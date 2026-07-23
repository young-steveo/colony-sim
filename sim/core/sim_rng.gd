class_name SimRng
extends RefCounted
## Context-keyed deterministic randomness ("Don't Generate, Hash!").
##
## Every random decision in the sim is a pure function of the world seed plus
## the context that identifies the decision: hash the context into a key, then
## either mix the key directly (one value) or open a Stream on it (many
## values). Identical context always yields identical results, so worlds
## reproduce exactly from a seed and systems never entangle through shared
## RNG state.

# 64-bit constants composed from 32-bit halves because GDScript int literals
# above INT64_MAX don't parse; the shift wraps into the intended bit pattern.
const _GOLDEN := (0x9E3779B9 << 32) | 0x7F4A7C15
const _MIX1 := (0xBF58476D << 32) | 0x1CE4E5B9
const _MIX2 := (0x94D049BB << 32) | 0x133111EB
const _FNV_OFFSET := (0xCBF29CE4 << 32) | 0x84222325
const _FNV_PRIME := 1099511628211

const _INV_2_53 := 1.0 / 9007199254740992.0


static func _ushr(x: int, n: int) -> int:
	# Logical (unsigned) right shift; GDScript's >> is arithmetic.
	return (x >> n) & ((1 << (64 - n)) - 1)


static func _finalize(z: int) -> int:
	z = (z ^ _ushr(z, 30)) * _MIX1
	z = (z ^ _ushr(z, 27)) * _MIX2
	return z ^ _ushr(z, 31)


static func mix(x: int) -> int:
	# SplitMix64 step: mix(0) == 0xE220A8397B1DCDAF (verified in tests).
	return _finalize(x + _GOLDEN)


static func combine(a: int, b: int) -> int:
	return mix(a ^ mix(b))


static func _fnv1a(s: String) -> int:
	var h := _FNV_OFFSET
	for b: int in s.to_utf8_buffer():
		h = (h ^ b) * _FNV_PRIME
	return h


static func _hash_part(p: Variant) -> int:
	match typeof(p):
		TYPE_INT:
			return int(p)
		TYPE_STRING:
			return _fnv1a(str(p))
		_:
			# Floats are banned as context keys (precision drift breaks
			# determinism); anything else is almost certainly a mistake.
			push_error("SimRng: unsupported context part type %s" % type_string(typeof(p)))
			return _fnv1a(str(p))


## Hash heterogeneous context parts (ints and strings) into a 64-bit key.
static func key(parts: Array) -> int:
	return derive(0, parts)


## Extend an existing key with more context (cheaper than rebuilding).
static func derive(base: int, parts: Array) -> int:
	var h := base
	for p: Variant in parts:
		h = combine(h, _hash_part(p))
	return h


## One uniform float in [0, 1) from a key.
static func randf(k: int) -> float:
	return float(_ushr(mix(k), 11)) * _INV_2_53


## One uniform int in [lo, hi] (inclusive) from a key.
static func randi_range(k: int, lo: int, hi: int) -> int:
	return lo + posmod(mix(k), hi - lo + 1)


## Open a sequential stream on a key, for contexts that need many values.
## Different stream_ids on the same key are statistically independent.
static func stream(k: int, stream_id: int = 0) -> Stream:
	return Stream.new(k, stream_id)


class Stream:
	extends RefCounted

	var _state: int
	var _gamma: int

	func _init(k: int, stream_id: int = 0) -> void:
		_state = k
		_gamma = SimRng.mix(stream_id) | 1

	func next() -> int:
		_state += _gamma
		return SimRng._finalize(_state)

	func nextf() -> float:
		return float(SimRng._ushr(next(), 11)) * SimRng._INV_2_53

	func next_range(lo: int, hi: int) -> int:
		return lo + posmod(next(), hi - lo + 1)
