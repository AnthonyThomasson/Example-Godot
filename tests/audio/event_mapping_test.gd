extends GameTest

## The Sound service turns EventBus events into `sound` events with the right profile: &"shot" by gun,
## &"hit" by material, outcome and the round's weight (an event without an outcome is not a sound), &"footfall" by
## the floor under it and gait (faster steps are louder, the feet differ in pitch), &"reload" by gun and stage.
## Synthetic events are posted straight on the bus, so this is the service alone: no gun, bullet or walker.

const Probe := preload("res://tests/_audio/sound_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Bus events become the right sounds",
		"description": "Posting shot / hit / footfall / reload events yields `sound` events with the expected profile, kind, position and loudness ordering; incomplete hits make none.",
		"tags": ["sound", "service", "eventbus"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.set_static(SoundConfig, &"category_range", Probe.EVERYWHERE)
	s.set_static(SoundConfig, &"pitch_jitter", 0.0)
	s.set_static(SoundConfig, &"volume_jitter_db", 0.0)


## Post `data` on `topic` and return the `sound` events it caused (the new ones only).
func _post(t: TestContext, topic: StringName, data: Dictionary) -> Array:
	var before := Probe.sounds(t).size()
	EventBus.post(topic, data)
	return Probe.sounds(t).slice(before)


## The width of the pitch range over 40 posts of the same event, with the jitter on.
func _spread(t: TestContext, topic: StringName, data: Dictionary) -> float:
	SoundConfig.pitch_jitter = 0.06
	var lo := 9.0
	var hi := 0.0
	for i in 40:
		var p: float = _post(t, topic, data)[0]["pitch"]
		lo = minf(lo, p)
		hi = maxf(hi, p)
	SoundConfig.pitch_jitter = 0.0
	return hi - lo


func run(t: TestContext) -> void:
	Sound.reset()

	var at := Vector2(123, 234)
	var shot := _post(t, &"shot", { "position": at, "gun": &"rifle", "power": 2.2 })
	t.expect_eq(shot.size(), 1, "a shot makes one sound")
	if not t.require(shot.size() == 1, "the shot sounded"):
		return
	t.expect_eq(shot[0]["kind"], &"shot", "of the shot kind")
	t.expect_eq(shot[0]["profile"], &"shot/rifle", "voiced as the rifle")
	t.expect_eq(shot[0]["position"], at, "where it was fired")
	t.expect_eq(_post(t, &"shot", { "position": at, "gun": &"pistol" })[0]["profile"], &"shot/pistol", "a pistol shot")
	t.expect_eq(_post(t, &"shot", { "position": at })[0]["profile"], &"shot/pistol", "a shot with no gun and no power is a medium round")

	for case in [
		[{ "outcome": &"ricochet", "material": "metal", "power": 2.2 }, &"impact/metal/ricochet/heavy"],
		[{ "outcome": &"penetrate", "material": "", "power": 1.0 }, &"impact/wall/penetrate/medium"],
		[{ "outcome": &"blocked", "material": "fabric", "power": 0.8 }, &"impact/fabric/blocked/light"],
		[{ "outcome": &"blocked", "material": "unobtainium", "power": 1.0 }, &"impact/default/blocked/medium"],
		[{ "outcome": &"penetrate", "material": "flesh", "power": 1.0 }, &"impact/flesh/penetrate/medium"],
		[{ "outcome": &"punch", "material": "flesh", "damage": 10.0 }, &"impact/flesh/punch"],
		[{ "outcome": &"punch", "material": "" }, &"impact/wall/punch"],
	]:
		var data: Dictionary = case[0].duplicate()
		data["position"] = at
		var sounds := _post(t, &"hit", data)
		if t.check(sounds.size() == 1, "%s makes one sound" % [case[0]]):
			t.expect_eq(sounds[0]["profile"], case[1], "%s / %s" % [case[0]["outcome"], case[0]["material"]])
			t.expect_eq(sounds[0]["kind"], &"impact", "an impact")
	t.expect_eq(_post(t, &"hit", { "position": at, "damage": 10.0, "victim": null }).size(), 0, "a hit with no outcome (someone else's) is silent")
	t.expect_eq(_post(t, &"hit", { "position": at, "outcome": &"flyover", "material": "wood" }).size(), 0, "an outcome nobody voices is silent")

	# Impact loudness: a faster round and a harder punch are louder.
	var slow: Dictionary = _post(t, &"hit", { "position": at, "outcome": &"blocked", "material": "wood", "power": 1.0, "speed_factor": 0.4 })[0]
	var fast: Dictionary = _post(t, &"hit", { "position": at, "outcome": &"blocked", "material": "wood", "power": 1.0, "speed_factor": 1.0 })[0]
	t.check(fast["volume_db"] > slow["volume_db"] + 3.0, "a fast round hits louder than a slow one (%.1f vs %.1f dB)" % [fast["volume_db"], slow["volume_db"]])
	var soft: Dictionary = _post(t, &"hit", { "position": at, "outcome": &"punch", "material": "flesh", "damage": 4.0 })[0]
	var hard: Dictionary = _post(t, &"hit", { "position": at, "outcome": &"punch", "material": "flesh", "damage": 12.0 })[0]
	t.check(hard["volume_db"] > soft["volume_db"] + 3.0, "a hard punch lands louder than a soft one (%.1f vs %.1f dB)" % [hard["volume_db"], soft["volume_db"]])

	# Footfalls: the floor under the foot and the gait pick the sound.
	var inside := Vector2(400, 250)
	var outside := Vector2(-300, 250)
	t.expect_eq(_post(t, &"footfall", { "position": inside, "foot": 0, "speed": 150.0, "running": false })[0]["profile"],
		&"footstep/wood/walk", "walking on the arena floor")
	t.expect_eq(_post(t, &"footfall", { "position": inside, "foot": 0, "speed": 250.0, "running": true })[0]["profile"],
		&"footstep/wood/run", "running on it")
	t.expect_eq(_post(t, &"footfall", { "position": outside, "foot": 1, "speed": 150.0, "running": false })[0]["profile"],
		&"footstep/outdoor/walk", "walking outside the house")
	var quiet: Dictionary = _post(t, &"footfall", { "position": inside, "foot": 0, "speed": 75.0, "running": false })[0]
	var loud: Dictionary = _post(t, &"footfall", { "position": inside, "foot": 0, "speed": 225.0, "running": false })[0]
	t.check(loud["volume_db"] > quiet["volume_db"] + 6.0, "a brisk step is louder than a slow one (%.1f vs %.1f dB)" % [loud["volume_db"], quiet["volume_db"]])
	var left: Dictionary = _post(t, &"footfall", { "position": inside, "foot": 0, "speed": 150.0 })[0]
	var right: Dictionary = _post(t, &"footfall", { "position": inside, "foot": 1, "speed": 150.0 })[0]
	t.check(right["pitch"] > left["pitch"], "the right foot rings a touch higher than the left (%.2f vs %.2f)" % [right["pitch"], left["pitch"]])

	# A casing landing is not a sound.
	t.expect_eq(_post(t, &"casing", { "position": inside, "gun": &"rifle", "power": 2.2 }).size(), 0, "a casing landing makes no sound")

	# Reloads: the magazine out when it starts, in when it finishes; anything else makes no sound.
	t.expect_eq(_post(t, &"reload", { "position": at, "gun": &"rifle", "stage": &"start", "power": 2.2 })[0]["profile"], &"reload/rifle/out", "a rifle reload starting")
	t.expect_eq(_post(t, &"reload", { "position": at, "gun": &"pistol", "stage": &"done" })[0]["profile"], &"reload/pistol/in", "a pistol reload finishing")
	t.expect_eq(_post(t, &"reload", { "position": at, "gun": &"railgun", "stage": &"done", "power": 0.8 })[0]["profile"], &"reload/smg/in", "an unknown light gun reloads like the SMG")
	t.expect_eq(_post(t, &"reload", { "position": at, "gun": &"pistol", "stage": &"cancelled" }).size(), 0, "an unknown stage is silent")
	t.expect_eq(_post(t, &"reload", { "position": at, "gun": &"pistol" }).size(), 0, "so is no stage")
	t.expect_eq(_post(t, &"reload", { "position": at, "gun": &"pistol", "stage": &"start" })[0]["kind"], &"reload", "of the reload kind")

	# Steps swing wider than shots: many identical steps spread further than many identical shots.
	var step_pitch := _spread(t, &"footfall", { "position": inside, "foot": 0, "speed": 150.0 })
	var shot_pitch := _spread(t, &"shot", { "position": at, "gun": &"pistol" })
	t.check(step_pitch > shot_pitch, "steps vary more in pitch than shots (%.3f vs %.3f)" % [step_pitch, shot_pitch])

	# Other topics are none of its business.
	t.expect_eq(_post(t, &"callout", { "speaker": null }).size(), 0, "a radio callout makes no sound")
	t.expect_eq(_post(t, &"sound", { "kind": &"shot", "profile": &"shot/rifle" }).size(), 1, "and a `sound` event is only itself (it is not played again)")
