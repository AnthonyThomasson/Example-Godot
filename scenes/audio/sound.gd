extends Node

## Audio domain: the sound service, autoloaded as `Sound`. It listens to the EventBus and turns the events other
## domains post into positional sound, so emitters never reference it (and it never references them):
##   &"shot"      a gun fired        { position, gun, attacker, power }
##   &"hit"       a bullet or punch landed (only those carrying an `outcome`: blocked / penetrate / ricochet /
##                punch)             { position, outcome, material, power, speed_factor, damage, … }
##   &"footfall"  a foot landed      { position, foot, speed, running }
##   &"reload"    a reload began (stage &"start": the magazine comes out) or finished (stage &"done": the new one is
##                seated and the action racked)   { position, gun, stage, power }
##   &"throw"     a grenade left a hand           { position, kind }
##   &"grenade"   a thrown grenade bounced (stage &"bounce"; &"rest" is silent)   { position, kind, stage }
##   &"explosion" a grenade went off              { position, kind }
##   &"stun"      a character was flashed / banged; only a deafening of `focus` is voiced   { character, deaf }
##   &"vehicle"   a vehicle's ignition, door (open / close / slide_open / slide_close), crash (+ speed, material) or a
##                character struck (bump_character, + speed)   { position, kind, stage }
##   &"engine"    a vehicle's engine started / stopped   { vehicle, kind, stage }
##   &"skid"      a vehicle's tyres began / stopped sliding   { vehicle, stage }
## Each becomes a *profile* (SoundBank), a rendered variant of it, and a voice: a pooled AudioStreamPlayer2D, capped
## per category with the oldest cut off first. The surface under a footfall comes from SoundSurface.
## Everything accepted is announced back on the bus as &"sound" { kind, profile, variant, position, volume_db,
## pitch } — what tests assert on and what a debug view could show.
##
## `focus` is the character whose ears this is (Main sets the human; nothing hears for an AI). While it is deafened
## (`stun_view().deaf`) `muffled()` is true: game audio goes through a low-pass on its own bus, closing at once and lifting
## slowly, and a tinnitus whine (a looping voice that follows the deafness and is cut when it ends) plays once per stun.
##
## A running engine and a sliding vehicle's tyres are loops: one looping voice per vehicle and kind (`loop_of`), started by
## the `engine` / `skid` start event and following the vehicle every frame, duck-typed like the focus (its position, and
## `engine_state()` rpm and load for the engine's pitch and level, `slip()` and `speed()` for the squeal's), until the stop
## event, the vehicle's engine stopping or the vehicle being freed.
##
## Randomness (which variant, pitch and volume jitter) comes from this node's own RNG, never the gameplay one.
## Voice lifetimes are counted in simulated time (`_now`), not read from the players, so a fixed-FPS test run
## that outpaces the clock frees them correctly.

const SHOT := &"shot"
const IMPACT := &"impact"
const FOOTSTEP := &"footstep"
const RELOAD := &"reload"
const THROW := &"throw"
const GRENADE := &"grenade"
const EXPLOSION := &"explosion"
const TINNITUS := &"tinnitus"
const ENGINE := &"engine"
const VEHICLE := &"vehicle"
const SKID := &"skid"
## The bus every game voice plays on, with the muffling low-pass on it; the tinnitus plays on the master bus, above the muffle.
const GAME_BUS := &"GameSound"
## Real milliseconds to give the audio mixer at shutdown (see `_exit_tree`).
const MIXER_DRAIN_MS := 80

## The character whose hearing the player has (a deafened `focus` muffles the game and hears tinnitus); null = nobody's.
var focus: Node = null
## The tinnitus voice while it plays ({} when none) and the level it started at.
var _tinnitus: Dictionary = {}
var _tinnitus_db := 0.0
## How far the muffle is closed (0 open .. 1 shut) and the game bus's index (-1: none).
var _muffle := 0.0
var _bus := -1
var _bus_made := false  ## Whether this service added the game bus (and so removes it at exit).
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
## The loops following a vehicle, by `_loop_key`: { vehicle, kind (`engine` / `skid`), profile, voice, pitch, volume_db }.
var _loops: Dictionary = {}


func _ready() -> void:
	_rng.seed = SoundConfig.rng_seed
	_make_bus()
	EventBus.posted.connect(_on_posted)
	if SoundConfig.prewarm and DisplayServer.get_name() != "headless":
		_warm = library()


func _process(delta: float) -> void:
	_now += delta
	_prewarm()
	_hear_stun(delta)
	_follow_loops(delta)


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
	if _bus_made and _bus >= 0 and _bus < AudioServer.bus_count and AudioServer.get_bus_name(_bus) == GAME_BUS:
		AudioServer.remove_bus(_bus)


## Voices of `category` (all categories when empty) still sounding.
func active(category: StringName = &"") -> int:
	var n := 0
	for v: Dictionary in _voices:
		if v["until"] > _now and (category == &"" or v["category"] == category):
			n += 1
	return n


## True while `focus` is deafened: the game audio is muffled.
func muffled() -> bool:
	return _deaf_left() > 0.0


## The loop of `kind` (`engine` or `skid`) following `vehicle`: { profile, pitch, volume_db } as it plays now, or {} when none.
func loop_of(vehicle: Node, kind: StringName) -> Dictionary:
	var loop: Dictionary = _loops.get(_loop_key(vehicle, kind), {})
	if loop.is_empty():
		return {}
	return { "profile": loop["profile"], "pitch": loop["pitch"], "volume_db": loop["volume_db"] }


## Cut every voice off and forget what was played (a fresh start for the next match or test).
func reset() -> void:
	for v: Dictionary in _voices:
		(v["player"] as AudioStreamPlayer2D).stop()
		v["until"] = 0.0
		v["loop"] = ""
	_last_variant.clear()
	_tinnitus = {}
	_loops.clear()
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
		&"throw":
			var profile := SoundBank.throw_profile(data.get("kind", &""))
			if profile != &"":
				_play(THROW, profile, data)
		&"grenade":
			# A bounce clatters, voiced by the floor it lands on; the rest that follows it is silent.
			if data.get("stage", &"") == &"bounce":
				var profile := SoundBank.grenade_profile(data.get("kind", &""), SoundSurface.at(data.get("position", Vector2.ZERO)))
				if profile != &"":
					_play(GRENADE, profile, data)
		&"explosion":
			var profile := SoundBank.explosion_profile(data.get("kind", &""))
			if profile != &"":
				_play(EXPLOSION, profile, data)
		&"stun":
			if data.get("character") == focus and focus != null and float(data.get("deaf", 0.0)) > 0.0:
				_start_tinnitus(data)
		&"vehicle":
			_vehicle_sound(data)
		&"engine":
			var vehicle: Variant = data.get("vehicle")
			if data.get("stage") == &"start":
				_start_loop(ENGINE, vehicle, SoundBank.engine_profile(data.get("kind", &"")))
			elif data.get("stage") == &"stop":
				_stop_loop(vehicle, ENGINE)
		&"skid":
			var vehicle: Variant = data.get("vehicle")
			if data.get("stage") == &"start":
				_start_loop(SKID, vehicle, SoundBank.skid_profile())
			elif data.get("stage") == &"stop":
				_stop_loop(vehicle, SKID)


## A one-shot vehicle sound: the ignition, a door, a crash (louder the faster, by what was struck) or a character struck.
func _vehicle_sound(data: Dictionary) -> void:
	var kind: StringName = data.get("kind", &"")
	var stage: StringName = data.get("stage", &"")
	var speed := float(data.get("speed", 0.0))
	var profile := &""
	var extra_db := 0.0
	match stage:
		&"ignition":
			profile = SoundBank.ignition_profile(kind)
		&"door_open", &"door_close", &"slide_open", &"slide_close":
			profile = SoundBank.door_profile(kind, StringName(String(stage).trim_prefix("door_")))
		&"crash", &"bump_character":
			var material := "flesh" if stage == &"bump_character" else String(data.get("material", ""))
			profile = SoundBank.crash_profile(material, speed)
			extra_db = linear_to_db(clampf(speed / SoundConfig.crash_speed_ref, 0.5, 1.6))
	if profile != &"":
		_play(VEHICLE, profile, data, extra_db)


## How loud a hit is beyond its profile's own level: a faster bullet hits harder, a punch by its damage.
func _impact_db(outcome: StringName, data: Dictionary) -> float:
	if outcome == &"punch":
		return linear_to_db(clampf(float(data.get("damage", 10.0)) / 10.0, 0.3, 1.5))
	return linear_to_db(clampf(float(data.get("speed_factor", 1.0)), 0.25, 1.3))


## Play one sound of `profile` for the category at `data.position` on `bus`: pick a variant, find a voice, post the event.
## Returns the voice, or {} when nothing played.
func _play(category: StringName, profile: StringName, data: Dictionary, extra_db: float = 0.0, pitch_scale: float = 1.0,
		bus: StringName = GAME_BUS) -> Dictionary:
	var at: Vector2 = data.get("position", Vector2.ZERO)
	var reach := _reach(category, at)
	if reach <= 0.0:
		return {}  # out of earshot
	var variant := _pick_variant(category, profile)
	var entry := SoundBank.sound(profile, variant)
	if entry.is_empty():
		return {}
	var swing := float(SoundConfig.category_jitter_scale.get(category, 1.0))
	var pitch := pitch_scale * (1.0 + _rng.randf_range(-SoundConfig.pitch_jitter, SoundConfig.pitch_jitter) * swing)
	var volume := _level(category, entry) + extra_db \
		+ _rng.randf_range(-SoundConfig.volume_jitter_db, SoundConfig.volume_jitter_db) * swing
	return _voice(category, profile, variant, entry["stream"], at, volume, pitch, reach, bus)


## A sound's level before what the event adds: its profile's own, the master's and its category's.
func _level(category: StringName, entry: Dictionary) -> float:
	return float(entry["level_db"]) + SoundConfig.master_db + float(SoundConfig.category_db.get(category, 0.0))


## Start `stream` (variant `variant` of `profile`) on a voice of `category` at `at`, heard up to `reach`, and announce it.
func _voice(category: StringName, profile: StringName, variant: int, stream: AudioStreamWAV, at: Vector2, volume: float,
		pitch: float, reach: float, bus: StringName = GAME_BUS) -> Dictionary:
	var voice := _acquire(category)
	var player: AudioStreamPlayer2D = voice["player"]
	player.stream = stream
	player.volume_db = volume
	player.pitch_scale = pitch
	player.max_distance = reach
	player.bus = bus
	player.global_position = at
	player.play()
	voice["started"] = _now
	voice["until"] = _now + stream.get_length() / pitch + 0.02
	EventBus.post(&"sound", { "kind": category, "profile": profile, "variant": variant, "position": at,
		"volume_db": volume, "pitch": pitch })
	return voice


## The focus's ears ring: a looping whine at its position that lasts as long as it is deaf (`_hear_stun` keeps it to that).
func _start_tinnitus(data: Dictionary) -> void:
	var deaf := _deaf_left()
	if deaf <= 0.0:
		return
	var loudness := linear_to_db(clampf(deaf / SoundConfig.tinnitus_full_s, 0.3, 1.0))
	var at: Vector2 = (focus as Node2D).global_position if focus is Node2D else data.get("position", Vector2.ZERO)
	var voice := _play(TINNITUS, SoundBank.tinnitus_profile(), { "position": at }, loudness, 1.0, &"Master")
	if voice.is_empty():
		return
	voice["until"] = _now + deaf
	_tinnitus = voice
	_tinnitus_db = (voice["player"] as AudioStreamPlayer2D).volume_db


## Seconds `focus` stays deaf (0 with no focus, a dead or freed one, or one that cannot be stunned).
func _deaf_left() -> float:
	if focus == null or not is_instance_valid(focus) or not focus.has_method("stun_view"):
		return 0.0
	return float(focus.call("stun_view").get("deaf", 0.0))


## Every frame: the muffle closes while `focus` is deaf and lifts when it is not, and the tinnitus voice fades with the
## deafness and is cut when it ends.
func _hear_stun(delta: float) -> void:
	var deaf := _deaf_left()
	var target := 1.0 if deaf > 0.0 else 0.0
	var rate := SoundConfig.muffle_attack if target > _muffle else SoundConfig.muffle_release
	_muffle = move_toward(_muffle, target, rate * delta)
	if _bus >= 0:
		var filter := AudioServer.get_bus_effect(_bus, 0) as AudioEffectLowPassFilter
		AudioServer.set_bus_effect_enabled(_bus, 0, _muffle > 0.0)
		filter.cutoff_hz = exp(lerpf(log(SoundConfig.muffle_open_hz), log(SoundConfig.muffle_cutoff_hz), _muffle))
	if _tinnitus.is_empty():
		return
	var player: AudioStreamPlayer2D = _tinnitus["player"]
	if deaf <= 0.0:
		player.stop()
		_tinnitus["until"] = 0.0
		_tinnitus = {}
		return
	_tinnitus["until"] = _now + deaf
	player.volume_db = _tinnitus_db + linear_to_db(clampf(deaf / SoundConfig.tinnitus_tail, 0.001, 1.0))
	if focus is Node2D:
		player.global_position = (focus as Node2D).global_position


## The bus the game's voices play on: a low-pass the muffle closes (left open at its start).
func _make_bus() -> void:
	_bus = AudioServer.get_bus_index(GAME_BUS)
	if _bus >= 0:
		return
	AudioServer.add_bus()
	_bus = AudioServer.bus_count - 1
	_bus_made = true
	AudioServer.set_bus_name(_bus, GAME_BUS)
	AudioServer.set_bus_send(_bus, &"Master")
	AudioServer.add_bus_effect(_bus, AudioEffectLowPassFilter.new())
	AudioServer.set_bus_effect_enabled(_bus, 0, false)


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
		oldest["loop"] = ""  # A loop cut off for a newer voice is over (`_follow_loops` lets it go).
		return oldest
	if not free.is_empty():
		free["category"] = category
		free["loop"] = ""
		return free
	var player := AudioStreamPlayer2D.new()
	player.name = "Voice%d" % _voices.size()
	add_child(player)
	var voice := { "player": player, "category": category, "until": 0.0, "started": 0.0, "loop": "" }
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


# --- Loops that follow a vehicle -------------------------------------------------------------

## The key of `vehicle`'s loop of `kind`.
static func _loop_key(vehicle: Variant, kind: StringName) -> String:
	return "%d/%s" % [(vehicle as Object).get_instance_id() if vehicle is Object else 0, kind]


## Start `vehicle`'s loop of `category` (`engine` / `skid`) playing `profile`, unless it already has one. It is not culled
## by range (it lasts, and the listener may come closer): its voice is heard up to the category's range, kept current.
func _start_loop(category: StringName, vehicle: Variant, profile: StringName) -> void:
	if not is_instance_valid(vehicle) or not (vehicle is Node2D) or profile == &"":
		return
	var key := _loop_key(vehicle, category)
	if _loops.has(key):
		return
	var entry := SoundBank.sound(profile, _pick_variant(category, profile))
	if entry.is_empty():
		return
	var loop := { "vehicle": vehicle, "kind": category, "profile": profile, "level": _level(category, entry) }
	var aim := _loop_aim(loop)
	if aim.is_empty():
		return
	loop["pitch"] = aim["pitch"]
	loop["volume_db"] = aim["volume_db"]
	var at := (vehicle as Node2D).global_position
	var voice := _voice(category, profile, int(_last_variant.get(profile, 0)), entry["stream"], at, loop["volume_db"],
		loop["pitch"], _range(category))
	voice["until"] = INF  # It plays until it is stopped.
	voice["loop"] = key
	loop["voice"] = voice
	_loops[key] = loop


## Stop `vehicle`'s loop of `category`, if it has one.
func _stop_loop(vehicle: Variant, category: StringName) -> void:
	if is_instance_valid(vehicle):
		_end_loop(_loop_key(vehicle, category))


## End the loop `key` and free its voice.
func _end_loop(key: String) -> void:
	var loop: Dictionary = _loops.get(key, {})
	if loop.is_empty():
		return
	_loops.erase(key)
	var voice: Dictionary = loop["voice"]
	if voice.get("loop") == key:
		(voice["player"] as AudioStreamPlayer2D).stop()
		voice["until"] = 0.0
		voice["loop"] = ""


## Every frame each loop follows its vehicle: its position, and its pitch and level glide toward what the vehicle's state
## asks for. A loop whose vehicle is gone (or whose engine no longer runs), or whose voice was cut off, ends.
func _follow_loops(delta: float) -> void:
	if _loops.is_empty():
		return
	var glide := 1.0 - exp(-SoundConfig.loop_ease * delta)
	for key: String in _loops.keys():
		var loop: Dictionary = _loops[key]
		var voice: Dictionary = loop["voice"]
		var vehicle: Variant = loop["vehicle"]
		var aim := _loop_aim(loop) if is_instance_valid(vehicle) else {}
		if aim.is_empty() or voice.get("loop") != key:
			_end_loop(key)
			continue
		loop["pitch"] = lerpf(loop["pitch"], aim["pitch"], glide)
		loop["volume_db"] = lerpf(loop["volume_db"], aim["volume_db"], glide)
		var player: AudioStreamPlayer2D = voice["player"]
		player.pitch_scale = loop["pitch"]
		player.volume_db = loop["volume_db"]
		player.max_distance = _range(loop["kind"])
		player.global_position = (vehicle as Node2D).global_position


## What `loop` should sound like now, read off its vehicle (duck-typed): { pitch, volume_db }, or {} once it should stop
## (an engine that no longer runs). The engine climbs in pitch with the revs and is louder on the throttle and high in the
## revs; the squeal is as loud as the slide (and the speed) and a little higher the harder it slides.
func _loop_aim(loop: Dictionary) -> Dictionary:
	var vehicle: Object = loop["vehicle"]
	var level: float = loop["level"]
	if loop["kind"] == ENGINE:
		if not vehicle.has_method("engine_state"):
			return {}
		var state: Dictionary = vehicle.call("engine_state")
		if not state.get("running", false):
			return {}
		var rpm := clampf(float(state.get("rpm", 0.0)), 0.0, 1.0)
		var throttle := clampf(float(state.get("load", 0.0)), 0.0, 1.0)
		return { "pitch": lerpf(SoundConfig.engine_pitch.x, SoundConfig.engine_pitch.y, rpm),
			"volume_db": level - SoundConfig.engine_load_db * (1.0 - throttle) + SoundConfig.engine_rev_db * rpm }
	if not vehicle.has_method("slip"):
		return {}
	var slip := clampf(float(vehicle.call("slip")), 0.0, 1.0)
	var speed := float(vehicle.call("speed")) if vehicle.has_method("speed") else SoundConfig.skid_full_speed
	var amount := clampf(slip / maxf(SoundConfig.skid_full_slip, 0.01), 0.1, 1.0) * clampf(speed / SoundConfig.skid_full_speed, 0.25, 1.0)
	return { "pitch": 1.0 + SoundConfig.skid_pitch * slip, "volume_db": level + linear_to_db(amount) }


## How far `category` carries for whoever is looking now: its range, scaled by the camera's zoom like `reach_from`.
func _range(category: StringName) -> float:
	var reach: float = SoundConfig.category_range.get(category, 1000.0)
	var camera := get_viewport().get_camera_2d()
	if camera != null and SoundConfig.range_follows_zoom and camera.zoom.x > 0.0:
		reach /= camera.zoom.x
	return reach
