extends RefCounted

## Shared helpers for the outfit tests (not a test itself): `const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")` (not `Outfit`: that is the Items class).
## The behaviour they assert is `docs/outfits.md` (O1 to O14 = the rules of the plan on issue #38).
##
## The outfit API is called directly: `Character.set_outfit(ids)` / `outfit_view()` (behind `has_api`, so a body without them
## fails a named check rather than an engine error) and `LoadoutConfig.outfit_options()`. `Visuals.drawn_art()` (the textures
## the last draw of the body painted, in order) is reached by `has_method` / `call`: the Visuals script has no class_name.
##
## Rounds are fired straight down a lane with `ProjectileSpawner.spawn` and the gun's own `GunConfig` numbers (or the frag's
## fragment numbers from `GrenadeConfig`), at a pinned `BallisticsConfig.bullet_height`, so a round meets a body square on
## at a known zone. A test that fires calls `pin_height(s)` in `configure`, so the height it sets in `run` is restored.

## The outfit slots, in the order the setup window lists them: the String keys of `set_outfit`'s ids, of `outfit_view()` and of a
## loadout's `outfit` (like a loadout's own keys); the garment ids are StringNames.
const SLOTS: Array[String] = ["head", "body", "vest", "pants", "feet", "front_plate", "back_plate"]
## The garments of each slot (O1) and the plates (O8). `&""` = nothing worn there.
const GARMENTS := {
	"head": [&"hat", &"helmet"],
	"body": [&"tshirt", &"shirt"],
	"vest": [&"tactical_vest", &"plate_carrier"],
	"pants": [&"jeans", &"tactical_pants"],
	"feet": [&"shoes", &"boots"],
	"front_plate": [&"soft_iiia", &"steel_iii", &"ceramic_iv"],
	"back_plate": [&"soft_iiia", &"steel_iii", &"ceramic_iv"],
}
## The slots that may be left empty (O1: head and vest; O8: each plate).
const MAY_BE_EMPTY: Array[String] = ["head", "vest", "front_plate", "back_plate"]

## Bullet heights (0..100) inside each zone (O2: height / coverage -> feet <= 0.08, legs <= 0.45, torso <= 0.85, head above)
## of a standing body (coverage 60) and a crouched one (coverage 35). 25 is the legs standing and the torso crouched.
const STAND := { &"feet": 3.0, &"legs": 25.0, &"torso": 40.0, &"head": 55.0 }
const CROUCH := { &"feet": 2.0, &"legs": 12.0, &"torso": 25.0, &"head": 32.0 }
## O3: the damage each zone takes, against the torso's.
const ZONE_DAMAGE := { &"feet": 0.6, &"legs": 0.6, &"torso": 1.0, &"head": 2.0 }

## A full plated kit (O10, O11: the invaders' default) and the defenders' default.
const PLATED_KIT := {
	"head": &"helmet", "body": &"shirt", "vest": &"plate_carrier", "pants": &"tactical_pants", "feet": &"boots",
	"front_plate": &"steel_iii", "back_plate": &"steel_iii",
}
const PLAIN_CLOTHES := {
	"head": &"", "body": &"tshirt", "vest": &"", "pants": &"jeans", "feet": &"shoes",
	"front_plate": &"", "back_plate": &"",
}


# --- Wearing and reading an outfit ------------------------------------------------------------------

## Pin the bullet height through `set_static` so the heights `fire` sets in `run` are restored after the test.
static func pin_height(s: TestSetup, height := 40.0) -> void:
	s.set_static(BallisticsConfig, &"bullet_height", height)


## Whether `c` has the outfit API (`set_outfit` and `outfit_view`).
static func has_api(c: Node) -> bool:
	return c.has_method("set_outfit") and c.has_method("outfit_view")


## `require` that the outfit API exists on `c`, naming what is missing. Use as `if not OutfitProbe.require_api(t, c): return`.
static func require_api(t: TestContext, c: Node) -> bool:
	return t.require(has_api(c), "Character.set_outfit(ids) and Character.outfit_view() exist (docs/outfits.md O1)")


## Dress `c` in `ids` (`{ head, body, vest, pants, feet, front_plate, back_plate }`, missing = none). False when the API is missing.
static func wear(c: Node, ids: Dictionary) -> bool:
	if not has_api(c):
		return false
	c.set_outfit(ids)
	return true


## `c.outfit_view()`: `{ head, body, vest, pants, feet }` garment names and `front_plate` / `back_plate` as `{ type, condition }`.
static func view(c: Node) -> Dictionary:
	return c.outfit_view() if has_api(c) else {}


## The condition (1 new .. 0 spent) of the plate on `side` (`"front_plate"` / `"back_plate"`); -1 when there is none to read.
static func condition(c: Node, side: String) -> float:
	var plate: Variant = view(c).get(side, {})
	return float((plate as Dictionary).get("condition", -1.0)) if plate is Dictionary else -1.0


# --- LoadoutConfig ----------------------------------------------------------------------------------

## Whether `LoadoutConfig` has the static function `name` (read off the script's method list).
static func loadout_has(name: StringName) -> bool:
	for m: Dictionary in (LoadoutConfig as Script).get_script_method_list():
		if StringName(m["name"]) == name:
			return true
	return false


## `LoadoutConfig.outfit_options()`: `[{ slot, label, choices: [{ id, label }] }]`, one row per slot in `SLOTS` order.
static func options() -> Array:
	return LoadoutConfig.outfit_options()


## The row of `options()` for `slot`, {} when there is none.
static func option_row(slot: String) -> Dictionary:
	for row: Dictionary in options():
		if str(row.get("slot", "")) == slot:
			return row
	return {}


## The label `outfit_options()` gives garment `id` in `slot` ("" when it is not offered).
static func label_of(slot: String, id: StringName) -> String:
	for choice: Dictionary in option_row(slot).get("choices", []):
		if StringName(choice.get("id", &"")) == id:
			return str(choice.get("label", ""))
	return ""


# --- Firing -------------------------------------------------------------------------------------------

## Fire one `gun` round (`&"pistol"`, `&"smg"`, `&"rifle"`, or `&"fragment"` for a frag's fragment) from `from` along `dir` at
## bullet height `height`, with that round's real numbers, dead straight. Returns the projectile.
static func fire(t: TestContext, from: Vector2, dir: Vector2, gun: StringName, height: float) -> Node:
	BallisticsConfig.bullet_height = height
	if gun == &"fragment":
		var frag := GrenadeConfig.row(&"frag")
		var fragment := ProjectileSpawner.spawn(from, dir, t.world, null, 0.0, float(frag["fragment_speed"]),
			float(frag["fragment_penetration"]), float(frag["fragment_range"]))
		fragment.set("damage", float(frag["fragment_damage"]))
		return fragment
	var row := GunConfig.row(gun)
	return ProjectileSpawner.spawn(from, dir, t.world, null, float(row["damage"]), float(row["muzzle_speed"]),
		float(row["penetration"]))


# --- Shooting lanes: a target, a witness behind it, one round each ---------------------------------------

## Where a lane's round starts, its target stands and the witness behind the target stands (x). The witness is struck only by a
## round that got through the target (O6: a stopped round has no exit). Within a fragment's 500 px reach.
const FROM_X := 250.0
const TARGET_X := 560.0
const WITNESS_X := 660.0
const LANE_TOP := 60.0
const LANE_GAP := 55.0


## Declare the actors of `lanes` (each `{ id, outfit, gun, height, facing }`; `facing` is the target's, default toward the
## shooter, `Vector2.LEFT`): a target `<id>` and a witness `<id>_witness` per lane, both with plenty of health.
static func lay_lanes(s: TestSetup, lanes: Array) -> void:
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var y := lane_y(i)
		var facing: Vector2 = lane.get("facing", Vector2.LEFT)
		s.actor(lane["id"], &"puppet", Vector2(TARGET_X, y),
			{ "max_health": 10000.0, "facing": facing, "aim_point": Vector2(TARGET_X, y) + facing * 300.0 })
		s.actor(witness_id(lane), &"puppet", Vector2(WITNESS_X, y),
			{ "max_health": 10000.0, "facing": Vector2.LEFT, "aim_point": Vector2(0, y) })


## The y of shooting lane `i`, top down.
static func lane_y(i: int) -> float:
	return LANE_TOP + LANE_GAP * i


## The id of the witness standing behind `lane`'s target.
static func witness_id(lane: Dictionary) -> StringName:
	return StringName("%s_witness" % lane["id"])


## Dress every lane's target in its `outfit` and hold its facing; then let the shoulders settle. False (after a failed
## `require`) when the outfit API is missing.
static func dress(t: TestContext, lanes: Array) -> bool:
	for lane: Dictionary in lanes:
		var target := t.actor(lane["id"])
		var facing: Vector2 = lane.get("facing", Vector2.LEFT)
		t.puppet(lane["id"]).aim_at(target.global_position + facing * 300.0)
		t.puppet(witness_id(lane)).aim_at(Vector2(0, target.global_position.y))
		if not (lane.get("outfit", {}) as Dictionary).is_empty():
			if not require_api(t, target):
				return false
			wear(target, lane["outfit"])
	await t.seconds(0.6)
	return true


## Fire every lane's round at once (`lanes` may be a part of the lanes laid: each round flies down its target's row) and wait for
## them to land. Returns, by lane id, what each did: `lost` (the target's health
## lost), `through` (the witness behind was struck), `wounded` (the target's `damage_taken()` rose: a dent, a wound), and the
## target's first `hit` event (`hit`, {} if none).
static func volley(t: TestContext, lanes: Array) -> Dictionary:
	var before := {}
	for lane: Dictionary in lanes:
		var target := t.actor(lane["id"])
		before[lane["id"]] = [target.health, target.damage_taken(), hits_on(t, target).size(), hits_on(t, t.actor(witness_id(lane))).size()]
	for lane: Dictionary in lanes:
		fire(t, Vector2(FROM_X, t.actor(lane["id"]).global_position.y), Vector2.RIGHT, lane["gun"], float(lane["height"]))
	var landed := func() -> bool:
		for lane: Dictionary in lanes:
			if hits_on(t, t.actor(lane["id"])).size() <= before[lane["id"]][2]:
				return false
		return true
	t.check(await t.until(landed, 2.0), "every lane's round strikes its target")
	await t.seconds(0.3)
	var out := {}
	for lane: Dictionary in lanes:
		var target := t.actor(lane["id"])
		var was: Array = before[lane["id"]]
		var hits := hits_on(t, target)
		out[lane["id"]] = {
			"lost": float(was[0]) - target.health,
			"wounded": target.damage_taken() > float(was[1]) + 0.001,
			"through": hits_on(t, t.actor(witness_id(lane))).size() > int(was[3]),
			"hit": hits[int(was[2])] if hits.size() > int(was[2]) else {},
		}
	return out


## The `&"hit"` events whose victim is `body`, oldest first.
static func hits_on(t: TestContext, body: Node) -> Array:
	return t.events_of(&"hit", func(d): return d["victim"] == body)


## How many `BloodSplat`s have been spawned so far.
static func splats(t: TestContext) -> int:
	return t.spawned("BloodSplat").size()


# --- The drawing ----------------------------------------------------------------------------------------

## The character's `Visuals` child (the body's drawing).
static func visuals(c: Node) -> Node:
	return c.get_node_or_null(^"Visuals")


## Whether the drawing can be read (`Visuals.drawn_art()`).
static func can_read_art(c: Node) -> bool:
	var v := visuals(c)
	return v != null and v.has_method("drawn_art")


## The instance ids of the textures the body's last draw painted, in order ([] when the body cannot report them). Art is cached by
## what it depicts, so the same drawing gives the same ids and a changed part a new one.
static func art(c: Node) -> Array:
	if not can_read_art(c):
		return []
	var out: Array = []
	for tex in visuals(c).call("drawn_art"):
		out.append((tex as Object).get_instance_id() if tex is Object else 0)
	return out
