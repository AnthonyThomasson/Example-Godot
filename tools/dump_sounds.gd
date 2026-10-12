extends SceneTree

## Dev aid (Audio domain): renders every sound the SoundBank can voice to .wav files, so they can be auditioned
## (and their cost and level checked) without playing the game. Run from the project root:
##
##   godot --headless --path . -s tools/dump_sounds.gd -- --out=/some/dir [--variants=2] [--filter=impact/metal]
##
## `--out` defaults to `user://sound_dump`; `--variants` is how many renders per profile to write (default 1);
## `--filter` keeps only profiles whose name contains that text. Prints one line per sound — length, peak and the
## milliseconds the render took — and a total.


func _init() -> void:
	var out := "user://sound_dump"
	var variants := 1
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--variants="):
			variants = maxi(int(arg.substr(11)), 1)
		elif arg.begins_with("--filter="):
			filter = arg.substr(9)
	DirAccess.make_dir_recursive_absolute(out)
	var total_ms := 0.0
	var worst_ms := 0.0
	var count := 0
	for profile in SoundBank.profiles():
		if filter != "" and not String(profile).contains(filter):
			continue
		for v in variants:
			var t0 := Time.get_ticks_usec()
			var entry := SoundBank.sound(profile, v)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var stream: AudioStreamWAV = entry["stream"]
			var file := "%s/%s_v%d.wav" % [out, String(profile).replace("/", "_"), v]
			var err := stream.save_to_wav(file)
			print("%-40s %.3fs  peak %.2f  %.1f ms%s" % [profile, stream.get_length(), SoundSynth.peak_of(stream), ms,
				"" if err == OK else "  SAVE FAILED %d" % err])
			total_ms += ms
			worst_ms = maxf(worst_ms, ms)
			count += 1
	print("%d sounds, %.0f ms total, %.1f ms worst, written to %s" % [count, total_ms, worst_ms, ProjectSettings.globalize_path(out)])
	quit()
