extends GameTest

## R3 (ticket #61): a dropped gun and a thrown grenade keep the weapon style they were held in.
## - Three gunmen armed in `scrap` (pistol, SMG, rifle; `Character.set_loadout(..., weapon_style)`) die; the `DroppedItem` each one's
##   gun leaves is drawn in scrap while it skids and once at rest: every texture it paints is one the scrap gun paints lying at some
##   lighting step either side up, and none is one the police or pipe gun paints so.
## - A thrower armed with a `pipe` frag throws it; the `ThrownGrenade` is drawn in pipe in flight (`DrawLayers.ABOVE`) and at rest
##   (`DrawLayers.LYING`): every texture is one the pipe frag paints lying at some step, none one the police or scrap frag paints.
## The reference drawings are the published `draw_dropped` of fresh items on the test's probes; every drawing is read through
## `Item.drawn_art()` of the `DroppedItem`'s / `ThrownGrenade`'s `item` (`tests/_items/weapon_style_probe.gd`).

const StyleProbe := preload("res://tests/_items/weapon_style_probe.gd")
## The gunmen, by gun: where each stands.
const GUNMEN := { &"pistol": Vector2(560, 120), &"smg": Vector2(700, 120), &"rifle": Vector2(840, 120) }
const KEPT_GUN_STYLE := &"scrap"
const THROWER_AT := Vector2(150, 460)
const THROW_TO := Vector2(550, 460)
const KEPT_GRENADE_STYLE := &"pipe"
## Where the reference probes lie (off to one side, under the camera's framing).
const PROBES_AT := Vector2(500, 300)
## Frames between samples of a moving drawing.
const SAMPLE_FRAMES := 3
## Frames a lob may stay aloft before the test stops watching it fly (a throw to `THROW_TO` lands in well under a second).
const MAX_FLIGHT_FRAMES := 180


func describe() -> Dictionary:
	return {
		"name": "A dropped gun and a thrown grenade keep their weapon style",
		"description": "A gunman armed in scrap dies: the dropped gun draws scrap while it skids and at rest. A pipe frag thrown draws pipe in flight and at rest.",
		"tags": ["style", "item", "gun", "grenade", "drop", "art"],
		"timeout": 16.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	for gun: StringName in GUNMEN:
		s.actor(gun, &"puppet", GUNMEN[gun], { "facing": Vector2.DOWN, "aim_point": GUNMEN[gun] + Vector2(0, 300) })
	s.actor(&"thrower", &"puppet", THROWER_AT, { "facing": Vector2.RIGHT, "aim_point": THROW_TO, "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var refs := {}  # kind -> style -> the set of textures it paints lying at every step either side up
	var probes := {}
	for gun: StringName in GUNMEN:
		probes[gun] = {}
		for style in StyleProbe.STYLES:
			probes[gun][style] = StyleProbe.lying_everywhere(t, StyleProbe.GUNS[gun], style, PROBES_AT)
	probes[&"frag"] = {}
	for style in StyleProbe.STYLES:
		probes[&"frag"][style] = StyleProbe.lying_everywhere(t, StyleProbe.GRENADES[&"frag"], style, PROBES_AT)
	for gun: StringName in GUNMEN:
		var slot: int = StyleProbe.GUNS[gun]
		t.actor(gun).set_loadout([1, slot], slot, [], &"", {}, KEPT_GUN_STYLE)
	var frag_slot: int = StyleProbe.GRENADES[&"frag"]
	t.actor(&"thrower").set_loadout([1, frag_slot], frag_slot, [], &"", { frag_slot: 1 }, KEPT_GRENADE_STYLE)
	await t.seconds(0.5)
	for kind: StringName in probes:
		refs[kind] = {}
		for style in StyleProbe.STYLES:
			refs[kind][style] = StyleProbe.union(probes[kind][style])
			if not t.require(not refs[kind][style].is_empty(), "the %s %s is drawn lying (the reference)" % [style, kind]):
				return

	# The gunmen die holding their scrap guns.
	var held := {}  # gun -> the item its gunman holds
	for gun: StringName in GUNMEN:
		var c := t.actor(gun)
		held[gun] = c.current_item()
		t.expect_eq(held[gun].style, KEPT_GUN_STYLE, "the %s's gunman holds it in scrap (the premise)" % gun)
		c.take_damage(100000.0)
	var dropped := {}  # gun -> its DroppedItem
	var found := await t.until(func() -> bool:
		for n in t.world.get_children():
			if n is DroppedItem:
				for gun: StringName in held:
					if n.item == held[gun]:
						dropped[gun] = n
		return dropped.size() == GUNMEN.size(), 2.0)
	if not t.require(found, "each dead gunman's gun lies in the world as a DroppedItem (found %s)" % [dropped.keys()]):
		return
	var skidding := {}  # gun -> what it drew while it moved
	for i in 6:
		await t.frames(SAMPLE_FRAMES)
		for gun: StringName in dropped:
			skidding[gun] = skidding.get(gun, {}).merged(StyleProbe.drawn(dropped[gun].item))
	await t.seconds(1.5)
	for gun: StringName in dropped:
		var item: Item = dropped[gun].item
		t.expect_eq(item.style, KEPT_GUN_STYLE, "the dropped %s keeps the style scrap (Item.style)" % gun)
		_check_drawn(t, skidding[gun], refs[gun], KEPT_GUN_STYLE, "the dropped %s, skidding," % gun)
		_check_drawn(t, StyleProbe.drawn(item), refs[gun], KEPT_GUN_STYLE, "the dropped %s, at rest," % gun)

	# The thrower throws its pipe frag.
	var thrower := t.actor(&"thrower")
	t.expect_eq(thrower.current_item().style, KEPT_GRENADE_STYLE, "the thrower holds its frag in pipe (the premise)")
	t.puppet(&"thrower").aim_at(THROW_TO)
	await t.seconds(0.4)
	t.puppet(&"thrower").shoot()
	if not t.require(await t.until(func() -> bool: return not _live(t).is_empty(), 1.5), "the frag leaves the hand as a ThrownGrenade"):
		return
	var grenade: ThrownGrenade = _live(t)[0]
	var aloft := {}
	var frames := 0
	while is_instance_valid(grenade) and grenade.z_index != DrawLayers.LYING and frames < MAX_FLIGHT_FRAMES:
		await t.frames(1)
		frames += 1
		if is_instance_valid(grenade) and grenade.z_index == DrawLayers.ABOVE:
			aloft.merge(StyleProbe.drawn(grenade.item))
	if not t.require(await t.until(func() -> bool: return t.happened(&"grenade", func(d: Dictionary) -> bool: return d.get("stage") == &"rest"), 2.5),
			"the frag comes to rest"):
		return
	if not t.require(is_instance_valid(grenade), "the frag has not burst yet at rest"):
		return
	await t.frames(2)
	var lying := StyleProbe.drawn(grenade.item)
	t.expect_eq(grenade.item.style, KEPT_GRENADE_STYLE, "the thrown frag keeps the style pipe (Item.style)")
	_check_drawn(t, aloft, refs[&"frag"], KEPT_GRENADE_STYLE, "the thrown frag, in flight,")
	_check_drawn(t, lying, refs[&"frag"], KEPT_GRENADE_STYLE, "the thrown frag, at rest,")


## Check that `drawn` (what a dropped or thrown item painted) is drawn in `style`: not empty, every texture one the `style` item paints
## lying (`refs[style]`), none one another style's paints.
func _check_drawn(t: TestContext, drawn: Dictionary, refs: Dictionary, style: StringName, what: String) -> void:
	if not t.check(not drawn.is_empty(), "%s is drawn" % what):
		return
	t.check(StyleProbe.within(drawn, refs[style]), "%s paints only what the %s one paints lying" % [what, style])
	for other in StyleProbe.STYLES:
		if other != style:
			t.check(StyleProbe.apart(drawn, refs[other]), "%s paints nothing the %s one paints lying" % [what, other])


## The live grenades (the group `live_grenades`).
func _live(t: TestContext) -> Array:
	return t.world.get_tree().get_nodes_in_group("live_grenades")
