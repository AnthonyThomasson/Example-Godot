extends GameTest

## G17 (`docs/grenades.md`): the AI judges a lob from where the grenade really leaves the thrower's hand, the Character's `throw` stance,
## not from a copy of it. `grenade_throw_spot_round_jamb`'s scene: the Terrace house, bare; an invader with a stun outside the back door, off
## its axis to the north-east, sees a household puppet in the kitchen through it. With the stance as it is, the hand is to the thrower's right
## (north), the jamb is in the way and it walks to a throw spot. Here the `throw` stance is retuned to hold the hand to the thrower's left
## (south, toward the middle of the doorway), from where the lob clears the jamb: its first COMBAT decision, made where it stands, offers
## GRENADE from there, and it throws from where it stands.
##
## Scripted Von (COMBAT > GRENADE > stun when offered), as in `grenade_throw_spot_round_jamb`. Premises: the `throw` stance's `lateral` is
## negated (the hand on the left, the same distance out); the puppet cannot be killed and never shoots; the invader is armed at the start of
## `run`, the way Main arms a spawn.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Spot := preload("res://tests/_ai/throw_spot_probe.gd")
const I_AT := Vector2(960, 190)
const H_AT := Vector2(660, 120)


func describe() -> Dictionary:
	return {
		"name": "The AI's lob check follows the throw stance",
		"description": "With the throw stance retuned to the left hand, whose lob clears the back door's jamb, an invader offers and throws a stun from where it stands instead of walking to a throw spot.",
		"tags": ["ai", "grenade", "combat", "throw_spot", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	var stances: Dictionary = CharacterConfig.stances.duplicate(true)
	stances[&"throw"]["lateral"] = -float(stances[&"throw"]["lateral"])
	s.set_static(CharacterConfig, &"stances", stances)
	s.von_script([{ "pick": "combat" }, { "pick": "grenade" }, { "pick": "stun" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }])
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"i", &"invader", I_AT, { "facing": (H_AT - I_AT).normalized() })
	Probe.hostile(s, &"h", H_AT, Maps.DOOR_BACK)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 1, 0)
	if not t.require(Probe.count(inv, Probe.STUN) == 1, "the invader carries a stun (item_count(7) = %d)" % Probe.count(inv, Probe.STUN)):
		return
	var hand: Vector2 = inv.throw_release_offset(Probe.STUN)
	if not t.require(hand.y < 0.0, "set-up: the retuned stance holds the throwing hand to the thrower's left (offset %s)" % str(hand)):
		return
	if not t.require(Probe.line_clear(t, I_AT, H_AT) and Spot.hand_lob_clear(t, inv, I_AT, H_AT) and I_AT.distance_to(H_AT) <= Probe.MAX_RANGE,
			"set-up: in sight and in range, and the lob from the left hand clears the jamb"):
		return
	var brain := t.controller(&"i", &"debug_zones")
	var state := {}
	var walks: Array = []
	var first := {}
	var zones: Array = []
	var watch := func() -> bool:
		Spot.note(t, brain, inv, state, walks)
		if first.is_empty():
			for w in walks:
				if not w["combat"].is_empty():
					first.merge(w)
					zones.assign(Spot.throws(brain))
					break
		return not first.is_empty() and t.happened(&"throw", func(d): return d.get("attacker") == inv)
	await t.until(watch, 15.0)
	if not t.require(not first.is_empty() and (first["pos"] as Vector2).distance_to(I_AT) <= 12.0, "the invader made a COMBAT decision where it stands (walks %s)" % str(Spot.describe(walks))):
		return
	t.check(first["combat"].has("grenade"), "GRENADE was offered (offered %s)" % str(first["combat"]))
	var near := zones.filter(func(z): return (z["point"] as Vector2).distance_to(H_AT) < 60.0 and Spot.from_of(z) != Vector2.INF)
	if not t.check(not near.is_empty(), "the throw it weighed names where it throws from (zones %s)" % str(zones)):
		return
	var from := Spot.from_of(near[0])
	t.check(from.distance_to(I_AT) <= 12.0, "it throws from where it stands, not from a throw spot (%s)" % str(from.round()))
	var throws := Probe.raw(t, &"throw", func(d): return d.get("attacker") == inv)
	if t.check(not throws.is_empty(), "the invader threw (acts %s)" % Probe.acts(t, &"i")):
		var at: Vector2 = throws[0]["data"]["position"]
		t.check(at.distance_to(I_AT) <= 30.0, "from where it stands (thrown at %s)" % str(at.round()))
		if t.check(await Probe.wait_boom(t, &"stun", 4.0), "the stun went off"):
			var boom: Vector2 = Probe.booms(t, &"stun")[0]["data"]["position"]
			t.check(Maps.HOUSE_KITCHEN.has_point(boom) and boom.distance_to(H_AT) < 110.0, "in the kitchen on the householder's spot (%s)" % str(boom.round()))
