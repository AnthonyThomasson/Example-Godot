extends GameTest

## R1 (ticket #61, styles by side): a character carries a `style` (`zenitex` / `trauma` for the invaders, `merc` / `borg` for the
## defenders), set through `Character.set_style(style, seed)`; the look of what it wears comes from the garment *and* the style,
## while what the outfit does stays the same. Five bodies in the same outfit, held perfectly still (no breath, no glance), so a
## drawing is the same textures frame after frame and two bodies drawn alike paint the very same textures:
## - unstyled, the five draw alike (the premise: nothing else tells them apart);
## - each style draws the outfit differently from every other style (plated kit and plain clothes);
## - each style's armour layers (`outfit().layer` over every zone and side), `outfit().weight()` and `get_surface_at` at every zone's
##   height from every side are the unstyled body's;
## - a character never given a style is a `zenitex` and draws as one (the same look seed);
## - the rank marks (`docs/outfits.md`, styles): in the plated kit a police unit's sergeant (rank 1, chevrons) and lead (rank 2, the
##   helmet stripe) each draw differently from a trooper (rank 0), while a crew (`merc`, `borg`) draws the same at every rank.
## The drawing is read through `Visuals.drawn_art()` (`OutfitProbe.art`).

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const STYLES: Array[StringName] = [&"zenitex", &"trauma", &"merc", &"borg"]
## The styles that are police units, which draw their rank; the others are crews, which have none.
const POLICE: Array[StringName] = [&"zenitex", &"trauma"]
## A trooper, the sergeant and the lead.
const RANKS: Array[int] = [0, 1, 2]
## The look seed every body gets (set before `_ready`, and handed to `set_style`), so only the style tells them apart.
const SEED := 4242
## The outfits each style is drawn in.
const OUTFITS := [["the plated kit", OutfitProbe.PLATED_KIT], ["plain clothes", OutfitProbe.PLAIN_CLOTHES]]
const ZONES: Array[StringName] = [&"feet", &"legs", &"torso", &"head"]
const SIDES: Array[StringName] = [&"front", &"flank", &"back"]
## Where a round comes from, against a body facing down (+y): its front, its flank and its back.
const DIRECTIONS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN]
const Y := 250.0
## Each body aims straight down from where it stands, so all face the same way.
const AIM_AHEAD := Vector2(0, 650)


func describe() -> Dictionary:
	return {
		"name": "A style changes the look, not the outfit",
		"description": "The same outfit draws differently per style (zenitex, trauma, merc, borg) with the same armour, weight and surfaces; a character with no style draws as zenitex.",
		"tags": ["style", "outfit", "art", "character"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"nav.rebake", false)
	# Held still: a breathing or glancing body paints a few more textures as it moves, which two bodies would not share.
	s.set_static(CharacterConfig, &"pose_breath", 0.0)
	s.set_static(CharacterConfig, &"pose_glance", 0.0)
	for i in STYLES.size():
		var at := Vector2(280 + i * 60, Y)
		s.actor(STYLES[i], &"puppet", at, { "facing": Vector2.DOWN, "aim_point": at + AIM_AHEAD, "look_seed": SEED })
	s.actor(&"plain", &"puppet", Vector2(520, Y), { "facing": Vector2.DOWN, "aim_point": Vector2(520, Y) + AIM_AHEAD, "look_seed": SEED })
	s.camera_follow(STYLES + [&"plain"])


func run(t: TestContext) -> void:
	var plain := t.actor(&"plain")
	if not OutfitProbe.require_api(t, plain):
		return
	if not t.require(OutfitProbe.can_read_art(plain), "Visuals.drawn_art() reads the textures the body's last draw painted"):
		return
	for id in STYLES + [&"plain"]:
		t.puppet(id).aim_at(t.actor(id).global_position + AIM_AHEAD)

	# The premise: unstyled, in the same outfit, the bodies draw alike.
	_dress_all(t, OutfitProbe.PLATED_KIT)
	await t.seconds(1.0)
	var unstyled := OutfitProbe.art(plain)
	if not t.require(not unstyled.is_empty(), "the body is drawn"):
		return
	for style in STYLES:
		if not t.require(OutfitProbe.art(t.actor(style)) == unstyled,
				"unstyled, the body standing where %s will stand draws as the others (the comparison's premise)" % style):
			return

	# A character never given a style is a zenitex.
	t.expect_eq(plain.style, &"zenitex", "a character with no style has the style zenitex (Character.style)")
	t.expect_eq(plain.look_seed, SEED, "its look seed is the one it was given (Character.look_seed)")

	for style in STYLES:
		var c := t.actor(style)
		c.set_style(style, SEED)
		t.expect_eq(c.style, style, "set_style(%s) sets Character.style" % style)

	for outfit: Array in OUTFITS:
		_dress_all(t, outfit[1])
		await t.seconds(0.5)
		var drawn := {}  # style -> its textures, as a set
		for style in STYLES:
			drawn[style] = _set_of(OutfitProbe.art(t.actor(style)))
			t.check(not drawn[style].is_empty(), "%s in %s is drawn" % [style, outfit[0]])
		for i in STYLES.size():
			for j in range(i + 1, STYLES.size()):
				t.check(drawn[STYLES[i]] != drawn[STYLES[j]], "in %s, %s and %s are drawn differently" % [outfit[0], STYLES[i], STYLES[j]])
		t.check(OutfitProbe.art(plain) == OutfitProbe.art(t.actor(&"zenitex")),
				"in %s, the character with no style draws as the zenitex with its look seed" % outfit[0])

		# What the outfit does is the unstyled body's.
		for style in STYLES:
			_check_same_function(t, t.actor(style), plain, "%s in %s" % [style, outfit[0]])

	# The rank marks, in the plated kit (the lead's stripe is on the helmet): each body drawn at every rank.
	_dress_all(t, OutfitProbe.PLATED_KIT)
	var by_rank := {}  # style -> [its textures as a set, per rank]
	for style in STYLES:
		by_rank[style] = []
	for rank in RANKS:
		for style in STYLES:
			t.actor(style).set_style(style, SEED, rank)
		await t.seconds(0.5)
		for style in STYLES:
			t.expect_eq(t.actor(style).rank, rank, "set_style(%s, seed, %d) sets Character.rank" % [style, rank])
			by_rank[style].append(_set_of(OutfitProbe.art(t.actor(style))))
	for style in STYLES:
		var trooper: Dictionary = by_rank[style][0]
		for rank in [1, 2]:
			if style in POLICE:
				t.check(by_rank[style][rank] != trooper, "%s rank %d draws differently from rank 0" % [style, rank])
			else:
				t.check(by_rank[style][rank] == trooper, "%s rank %d draws the same as rank 0 (a crew has no rank marks)" % [style, rank])


## Dress every body in `ids`.
func _dress_all(t: TestContext, ids: Dictionary) -> void:
	for id in STYLES + [&"plain"]:
		OutfitProbe.wear(t.actor(id), ids)


## Check that `c`'s outfit protects, weighs and is struck as `plain`'s: every zone and side's armour layer, the weight, and the
## surface a round meets at each zone's standing height from the front, the flank and the back.
func _check_same_function(t: TestContext, c: Node, plain: Node, what: String) -> void:
	for zone in ZONES:
		for side in SIDES:
			t.expect_eq(c.outfit().layer(zone, side), plain.outfit().layer(zone, side), "%s: the armour layer at %s %s is unchanged" % [what, zone, side])
	t.expect_eq(c.outfit().weight(), plain.outfit().weight(), "%s: the outfit weighs the same" % what)
	for zone in ZONES:
		for direction in DIRECTIONS:
			var height: float = OutfitProbe.STAND[zone]
			t.expect_eq(c.get_surface_at(height, direction), plain.get_surface_at(height, direction),
					"%s: a round at %s height from %s meets the same surface" % [what, zone, direction])


## `ids` as a set (id -> true).
func _set_of(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[id] = true
	return out
