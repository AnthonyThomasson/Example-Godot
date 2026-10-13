extends GameTest

## Grenades are heard: the throw (a whoosh at the hand), each bounce (a clatter voiced by the floor it lands on), the frag's
## explosion (big, low, a long tail) and the stun's bang (sharp, very loud, short), all `&"sound"` events. A character a bang
## deafens gets a muffle of the game audio and a tinnitus whine for as long as it is deaf, but only the one `Sound.focus` names
## (the human); a blind-only stun, or a deafened character that is not the focus, adds neither.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const SoundProbe := preload("res://tests/_audio/sound_probe.gd")
const FROM := Vector2(60, 300)
const AIM := Vector2(400, 300)


func describe() -> Dictionary:
	return {
		"name": "Grenades sound: throw, bounce, explosion, bang and tinnitus",
		"description": "A frag and a stun are thrown: throw, floor-voiced bounce, explosion/frag and explosion/stun sounds at the right places; the bang's recipe is shorter and brighter than the blast's; the deaf focus character gets a tinnitus event once and a muffle while deaf, nobody else does.",
		"tags": ["sound", "grenade", "explosion", "tinnitus"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 600))
	s.set_static(SoundConfig, &"category_range", Probe.everywhere(SoundProbe.EVERYWHERE))
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })
	s.actor(&"human", &"puppet", Vector2(900, 100), { "max_health": 100000.0 })
	s.actor(&"other", &"puppet", Vector2(900, 500), { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	var service: Node = Sound
	Probe.arm(thrower, 1, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1 and Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a stun and a frag"):
		return
	if not t.require("focus" in service and service.has_method("muffled"), "Sound.focus and Sound.muffled() exist"):
		return

	# --- The frag: a throw, bounces, an explosion.
	await Probe.throw_at(t, &"thrower", Probe.FRAG, AIM)
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag goes off"):
		return
	await t.frames(3)
	var throws := SoundProbe.sounds(t, &"throw", "throw/")
	t.check(not throws.is_empty(), "the throw is heard (a throw/ sound)")
	if not throws.is_empty():
		t.check((throws[0]["position"] as Vector2).distance_to(thrower.global_position) < 60.0, "at the thrower's hand")
	var clatter := SoundProbe.sounds(t, &"grenade", "grenade/")
	t.check(not clatter.is_empty(), "the grenade clatters when it lands (a grenade/ sound)")
	for c in clatter:
		var floor_name := String(SoundSurface.at(c["position"]))
		t.check(String(c["profile"]).ends_with("/" + floor_name), "%s is voiced by the floor under it (%s)" % [c["profile"], floor_name])
	var boom_at: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
	var frag_sounds := SoundProbe.sounds(t, &"explosion", "explosion/frag")
	t.check(frag_sounds.size() == 1 and (frag_sounds[0]["position"] as Vector2).distance_to(boom_at) < 30.0, "the frag explosion is heard once, where it went off (explosion/frag)")

	# --- The stun: its bang.
	await Probe.throw_at(t, &"thrower", Probe.STUN, AIM)
	if not t.require(await Probe.wait_boom(t, &"stun", 5.0), "the stun goes off"):
		return
	await t.frames(3)
	var bang := SoundProbe.sounds(t, &"explosion", "explosion/stun")
	t.check(bang.size() == 1, "the stun's bang is heard once (explosion/stun)")
	t.check(SoundProbe.sounds(t, &"tinnitus").is_empty(), "with no focus character set nobody gets a tinnitus whine, though the thrower was deafened")

	# --- What the two sound like: the blast is long and low, the bang short and bright.
	if t.require(SoundBank.profiles().has(&"explosion/frag") and SoundBank.profiles().has(&"explosion/stun"), "both explosion profiles are in the sound bank"):
		var blast := SoundProbe.samples(&"explosion/frag")
		var crack := SoundProbe.samples(&"explosion/stun")
		t.check(blast.size() > crack.size() * 1.5, "the blast rings on much longer than the bang (%d against %d samples)" % [blast.size(), crack.size()])
		t.check(SoundProbe.low_share(blast) > SoundProbe.low_share(crack), "and carries more of its energy low down")
		t.check(SoundProbe.brightness(crack) > SoundProbe.brightness(blast), "while the bang is the sharper sound")

	# --- Tinnitus and the muffle, for the focus only.
	service.set("focus", t.actor(&"human"))
	var human := t.actor(&"human")
	var other := t.actor(&"other")
	var tinnitus_before := SoundProbe.sounds(t, &"tinnitus").size()
	Probe.stun(human, 1.0, 0.0, Vector2(500, 100))
	await t.frames(3)
	t.check(SoundProbe.sounds(t, &"tinnitus").size() == tinnitus_before and not service.muffled(), "a flash that deafens nobody brings no whine and no muffle")
	Probe.stun(other, 0.0, 2.0, Vector2(500, 500))
	await t.frames(3)
	t.check(SoundProbe.sounds(t, &"tinnitus").size() == tinnitus_before and not service.muffled(), "a deafened character that is not the focus brings none either")
	Probe.stun(human, 0.0, 2.0, Vector2(500, 100))
	await t.frames(3)
	var whines := SoundProbe.sounds(t, &"tinnitus", "tinnitus/")
	t.check(whines.size() == tinnitus_before + 1, "the deafened focus hears one tinnitus whine")
	if not whines.is_empty():
		t.check((whines[-1]["position"] as Vector2).distance_to(human.global_position) < 40.0, "at its own ears")
	t.check(service.muffled(), "and the game audio is muffled while it is deaf")
	await t.seconds(2.4)
	t.check(not service.muffled(), "the muffle lifts when its deafness ends")
	service.set("focus", null)
