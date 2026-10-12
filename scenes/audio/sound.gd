extends Node

## Audio domain: the sound service, autoloaded as `Sound`. It listens to the EventBus and turns the events other
## domains post into positional sound, so emitters never reference it (and it never references them):
##   &"shot"      a gun fired        { position, gun, attacker, automatic, damage, power }
##   &"hit"       a bullet or punch landed (only those carrying an `outcome`: blocked / penetrate / ricochet /
##                punch)             { position, outcome, material, power, speed_factor, damage, … }
##   &"footfall"  a foot landed      { position, foot, speed, running }
##   &"reload"    a reload began (stage &"start": the magazine comes out) or finished (stage &"done": the new one is
##                seated and the action racked)   { position, gun, stage, power }
## Each becomes a *profile* (SoundBank), a rendered variant of it, and a voice: a pooled AudioStreamPlayer2D, capped
## per category with the oldest cut off first. The surface under a footfall comes from SoundSurface.
## Everything accepted is announced back on the bus as &"sound" { kind, profile, variant, position, volume_db,
## pitch } — what tests assert on and what a debug view could show.
##
## Randomness (which variant, pitch and volume jitter) comes from this node's own RNG, never the gameplay one.
## Voice lifetimes are counted in simulated time (`_now`), not read from the players, so a fixed-FPS test run
## that outpaces the clock frees them correctly.

const SHOT := &"shot"
const IMPACT := &"impact"
const FOOTSTEP := &"footstep"
const RELOAD := &"reload"
## Real milliseconds to give the audio mixer at shutdown (see `_exit_tree`).
const MIXER_DRAIN_MS := 80

## Picks variants and jitter (seeded from `SoundConfig.rng_seed`; never the gameplay RNG).
var _rng := RandomNumberGenerator.new()
## Simulated seconds since the service started (advances with the tree, so it stops when the game pauses).
var _now := 0.0
## Every voice built so far: [{ player: AudioStreamPlayer2D, category: StringName, until: float, started: float }].
var _voices: Array = []
## Last variant played per profile, so the same one is not repeated back to back.
var _last_variant: Dictionary = {}
## `[profile, variant]` pairs still to pre-render in the background (empty once the library is warm).
var _warm: Array = []


func _ready() -> void:
	_rng.seed = SoundConfig.rng_seed
	EventBus.posted.connect(_on_posted)
	if SoundConfig.prewarm and DisplayServer.get_name() != "headless":
		_warm = library()


func _process(delta: float) -> void:
	_now += delta
	_prewarm()


## On quit, stop and free every voice. The engine's mixer thread only lets go of a stopped playback on its next
## pass, which a process that exits straight away never gives it (and a fixed-FPS test run outruns it), so any
## voice that ever played would be reported as a leaked object; a short pause lets it run once.
func _exit_tree() -> void:
	for v: Dictionary in _voices:
		var player: AudioStreamPlayer2D = v["player"]
		player.stop()
		player.stream = null
		player.free()
	if not _voices.is_empty():
		OS.delay_msec(MIXER_DRAIN_MS)
	_voices.clear()


## Voices of `category` (all categories when empty) still sounding.
func active(category: StringName = &"") -> int:
	var n := 0
	for v: Dictionary in _voices:
		if v["until"] > _now and (category == &"" or v["category"] == category):
			n += 1
	return n


## Cut every voice off and forget what was played (a fresh start for the next match or test).
func reset() -> void:
	for v: Dictionary in _voices:
		(v["player"] as AudioStreamPlayer2D).stop()
		v["until"] = 0.0
	_last_variant.clear()
	_rng.seed = SoundConfig.rng_seed


## Turn an EventBus event into a sound when it is one the service voices (see the topics above).
func _on_posted(topic: StringName, data: Dictionary) -> void:
	if not SoundConfig.enabled:
		return
	match topic:
		&"shot":
			_play(SHOT, SoundBank.shot_profile(data.get("gun", &""), float(data.get("power", 1.0))), data)
		&"hit":
			var outcome := StringName(data.get("outcome", &""))
			if outcome != &"":
				var profile := SoundBank.impact_profile(String(data.get("material", "")), outcome, float(data.get("power", 1.0)))
				if profile != &"":
					_play(IMPACT, profile, data, _impact_db(outcome, data))
		&"footfall":
			var at: Vector2 = data.get("position", Vector2.ZERO)
			var profile := SoundBank.footstep_profile(SoundSurface.at(at), bool(data.get("running", false)))
			var pace := clampf(float(data.get("speed", 150.0)) / 150.0, 0.5, 1.5)
			# Left and right feet differ a touch in pitch.
			_play(FOOTSTEP, profile, data, linear_to_db(pace), 0.97 if int(data.get("foot", 0)) == 0 else 1.03)
		&"reload":
			# The event says "start" / "done"; the sound is the magazine going out / coming in.
			var stage := &"out" if data.get("stage", &"") == &"start" else (&"in" if data.get("stage", &"") == &"done" else &"")
			var profile := SoundBank.reload_profile(data.get("gun", &""), stage, float(data.get("power", 1.0)))
			if profile != &"":
				_play(RELOAD, profile, data)


## How loud a hit is beyond its profile's own level: a faster bullet hits harder, a punch by its damage.
func _impact_db(outcome: StringName, data: Dictionary) -> float:
	if outcome == &"punch":
		return linear_to_db(clampf(float(data.get("damage", 10.0)) / 10.0, 0.3, 1.5))
	return linear_to_db(clampf(float(data.get("speed_factor", 1.0)), 0.25, 1.3))


## Play one sound of `profile` for the category at `data.position`: pick a variant, find a voice, post the event.
func _play(category: StringName, profile: StringName, data: Dictionary, extra_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var at: Vector2 = data.get("position", Vector2.ZERO)
	var reach := _reach(category, at)
	if reach <= 0.0:
		return  # out of earshot
	var variant := _pick_variant(category, profile)
	var entry := SoundBank.sound(profile, variant)
	if entry.is_empty():
		return
	var stream: AudioStreamWAV = entry["stream"]
	var swing := float(SoundConfig.category_jitter_scale.get(category, 1.0))
	var pitch := pitch_scale * (1.0 + _rng.randf_range(-SoundConfig.pitch_jitter, SoundConfig.pitch_jitter) * swing)
	var volume := float(entry["level_db"]) + SoundConfig.master_db + float(SoundConfig.category_db.get(category, 0.0)) \
		+ extra_db + _rng.randf_range(-SoundConfig.volume_jitter_db, SoundConfig.volume_jitter_db) * swing
	var voice := _acquire(category)
	var player: AudioStreamPlayer2D = voice["player"]
	player.stream = stream
	player.volume_db = volume
	player.pitch_scale = pitch
	player.max_distance = reach
	player.global_position = at
	player.play()
	voice["started"] = _now
	voice["until"] = _now + stream.get_length() / pitch + 0.02
	EventBus.post(&"sound", { "kind": category, "profile": profile, "variant": variant, "position": at,
		"volume_db": volume, "pitch": pitch })


## How far from `at` the category can still be heard by whoever is looking (the current camera): its range, or 0
## when `at` is beyond it. With no camera (nothing is looking), everything is in range.
func _reach(category: StringName, at: Vector2) -> float:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return float(SoundConfig.category_range.get(category, 1000.0))
	return reach_from(category, at, camera.get_screen_center_position(), camera.zoom.x)


## `category`'s range (px) for a view centred on `center` at camera `zoom`, or 0 when `at` is beyond it. The range
## grows as the camera zooms out when SoundConfig.range_follows_zoom is on.
static func reach_from(category: StringName, at: Vector2, center: Vector2, zoom: float = 1.0) -> float:
	var reach: float = SoundConfig.category_range.get(category, 1000.0)
	if SoundConfig.range_follows_zoom and zoom > 0.0:
		reach /= zoom
	return reach if center.distance_to(at) <= reach else 0.0


## A variant of `profile` other than the one played last; a category may have more takes than the default.
func _pick_variant(category: StringName, profile: StringName) -> int:
	var n := maxi(int(SoundConfig.category_variants.get(category, SoundConfig.variants)), 1)
	var v := _rng.randi() % n
	if n > 1 and _last_variant.get(profile, -1) == v:
		v = (v + 1) % n
	_last_variant[profile] = v
	return v


## A voice for `category`: the oldest of its own if it is at its cap, else a free one, else a new player.
func _acquire(category: StringName) -> Dictionary:
	var cap: int = SoundConfig.category_voices.get(category, 4)
	var count := 0
	var oldest: Dictionary = {}
	var free: Dictionary = {}
	for v: Dictionary in _voices:
		if v["until"] > _now:
			if v["category"] == category:
				count += 1
				if oldest.is_empty() or v["started"] < oldest["started"]:
					oldest = v
		elif free.is_empty():
			free = v
	if count >= cap and not oldest.is_empty():
		(oldest["player"] as AudioStreamPlayer2D).stop()
		oldest["category"] = category
		return oldest
	if not free.is_empty():
		free["category"] = category
		return free
	var player := AudioStreamPlayer2D.new()
	player.name = "Voice%d" % _voices.size()
	add_child(player)
	var voice := { "player": player, "category": category, "until": 0.0, "started": 0.0 }
	_voices.append(voice)
	return voice


## Every `[profile, variant]` the service can play: the first variant of each profile, then the others. A variant
## nobody has rendered yet is synthesized when it first plays, a hitch of several frames in the middle of a fight.
func library() -> Array:
	var profiles := SoundBank.profiles()
	var out: Array = []
	for profile in profiles:
		out.append([profile, 0])
	for profile in profiles:
		for variant in range(1, _variants_of(profile)):
			out.append([profile, variant])
	return out


## How many variants `_pick_variant` chooses between for `profile` (its category is the profile id's first part).
func _variants_of(profile: StringName) -> int:
	var category := StringName(String(profile).get_slice("/", 0))
	return maxi(int(SoundConfig.category_variants.get(category, SoundConfig.variants)), 1)


## Render the library a little at a time (a few ms a frame) so no sound hitches the first time it plays.
func _prewarm() -> void:
	if _warm.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	while not _warm.is_empty() and (Time.get_ticks_usec() - t0) / 1000.0 < SoundConfig.prewarm_budget_ms:
		var next: Array = _warm.pop_front()
		SoundBank.sound(next[0], next[1])
