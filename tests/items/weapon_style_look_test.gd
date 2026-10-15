extends GameTest

## R3 (ticket #61, weapon style follows the wielder): a gun or grenade is drawn in its weapon style (`Item.style`: `police` issue,
## taped `scrap` or `pipe`), and an item never given one is drawn as `police`. For each gun (pistol, SMG, rifle) and grenade (frag,
## stun), one item per style and one never given a style, each drawn on its own probe in the same frame by the same holder:
## - two `police` items of a kind draw alike (the comparison's premise: the same look paints the same textures);
## - held (`draw_weapon`, in a still holder's hand) and lying with either side up (`draw_dropped`, as a dropped gun lies and a
##   grenade flies and rests), each style draws the item differently from every other style;
## - the item never given a style has the style `police` and draws as the `police` one, held and lying.
## Read through `Item.drawn_art()` (`tests/_items/weapon_style_probe.gd`).

const StyleProbe := preload("res://tests/_items/weapon_style_probe.gd")
const HOLDER_AT := Vector2(400, 250)
## The holder aims straight down from where it stands, so its weapon facing is steady.
const AIM_AHEAD := Vector2(0, 650)
## The angle every lying item is drawn along.
const LYING_ANGLE := 0.4
## The drawings compared for each item: held, and lying with each side up.
const VIEWS := [&"held", &"lying", &"lying_flipped"]


func describe() -> Dictionary:
	return {
		"name": "A weapon style changes how a gun or grenade is drawn",
		"description": "Each gun and grenade draws differently in police, scrap and pipe, held and lying either side up; an item with no style draws as police.",
		"tags": ["style", "item", "gun", "grenade", "art"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"nav.rebake", false)
	# Held still, so every held drawing is lit for the same angle.
	s.set_static(CharacterConfig, &"pose_breath", 0.0)
	s.set_static(CharacterConfig, &"pose_glance", 0.0)
	# Bare-handed: the holder's own drawing holds no item; the probes draw the items in its hand.
	s.actor(&"holder", &"puppet", HOLDER_AT, { "start_slot": 1, "facing": Vector2.DOWN, "aim_point": HOLDER_AT + AIM_AHEAD })
	s.camera_follow([&"holder"])


func run(t: TestContext) -> void:
	var holder := t.actor(&"holder")
	t.puppet(&"holder").aim_at(HOLDER_AT + AIM_AHEAD)
	await t.seconds(0.5)

	var kinds := {}  # name -> slot
	kinds.merge(StyleProbe.GUNS)
	kinds.merge(StyleProbe.GRENADES)
	# name -> style (&"" = never given one, &"twin" = a second police item) -> view -> probe
	var probes := {}
	var styles: Array = StyleProbe.STYLES + [&"", &"twin"]
	for kind: StringName in kinds:
		probes[kind] = {}
		for style: StringName in styles:
			var as_style := StyleProbe.DEFAULT_STYLE if style == &"twin" else style
			var slot: int = kinds[kind]
			var item := StyleProbe.make(slot, as_style)
			if style == &"":
				t.expect_eq(item.style, StyleProbe.DEFAULT_STYLE, "a %s never given a style has the style police (Item.style)" % kind)
			probes[kind][style] = {
				&"held": StyleProbe.probe(t, item, HOLDER_AT, true, holder),
				&"lying": StyleProbe.probe(t, StyleProbe.make(slot, as_style), HOLDER_AT, false, null, LYING_ANGLE, { "flip": false }),
				&"lying_flipped": StyleProbe.probe(t, StyleProbe.make(slot, as_style), HOLDER_AT, false, null, LYING_ANGLE, { "flip": true }),
			}
	await t.frames(2)

	for kind: StringName in kinds:
		var drawn := {}  # style -> view -> set
		for style: StringName in styles:
			drawn[style] = {}
			for view: StringName in VIEWS:
				drawn[style][view] = StyleProbe.drawn(probes[kind][style][view].item)
				t.check(not drawn[style][view].is_empty(), "the %s (%s) is drawn %s" % [kind, _name(style), view])
		for view: StringName in VIEWS:
			if not t.check(drawn[&"twin"][view] == drawn[&"police"][view],
					"two police %ss draw alike %s (the comparison's premise)" % [kind, view]):
				continue
			for i in StyleProbe.STYLES.size():
				for j in range(i + 1, StyleProbe.STYLES.size()):
					var a := StyleProbe.STYLES[i]
					var b := StyleProbe.STYLES[j]
					t.check(drawn[a][view] != drawn[b][view], "%s, a %s %s and a %s %s are drawn differently" % [view, a, kind, b, kind])
			t.check(drawn[&""][view] == drawn[&"police"][view], "%s, a %s never given a style draws as a police one" % [view, kind])


## How a style is named in a message.
func _name(style: StringName) -> String:
	match style:
		&"":
			return "no style"
		&"twin":
			return "a second police"
	return String(style)
