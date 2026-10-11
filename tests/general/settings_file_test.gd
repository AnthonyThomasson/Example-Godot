extends GameTest

## Settings keeps the Debug switch and the key bindings that differ from the defaults in one JSON file:
## every change saves at once, only differences are written, a reload restores them, and a missing or
## unreadable file just means the defaults. Runs against a scratch file, never the real one.

const SCRATCH := "user://settings_test.json"


func describe() -> Dictionary:
	return {
		"name": "Settings save and reload the debug switch and key bindings",
		"description": "Each change is written at once (differences only); a reload restores it; a missing, partial or corrupt file falls back to the defaults.",
		"tags": ["settings", "keybinds", "persistence"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"debug", true)


func run(t: TestContext) -> void:
	Keybinds.reset_all()
	_remove_scratch()

	# No file: the defaults stand.
	Settings.load_file()
	t.check(Keybinds.overrides().is_empty(), "no file leaves the default bindings")
	t.expect_eq(Settings.debug, true, "no file leaves Debug as it was")

	# Changes save immediately, and only the differences are written.
	Settings.set_debug(false)
	t.check(FileAccess.file_exists(SCRATCH), "changing Debug writes the file")
	t.check(Settings.rebind(Keybinds.PUNCH, _key(KEY_G)), "a rebind is accepted")
	t.check(not Settings.rebind(Keybinds.PUNCH, InputEventMouseMotion.new()), "an unbindable event is refused")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCRATCH))
	if not t.require(saved is Dictionary, "the file is a JSON object"):
		return
	t.expect_eq(saved["debug"], false, "the file records Debug")
	t.expect_eq(saved["keybinds"].keys(), [Keybinds.PUNCH], "only the changed binding is written")

	# A reload (a new launch) restores both.
	Settings.debug = true
	Keybinds.reset_all()
	Settings.load_file()
	t.expect_eq(Settings.debug, false, "a reload restores Debug")
	t.check(_key(KEY_G).is_action(Keybinds.PUNCH), "a reload restores the rebinding")

	# The page's rows reflect the live state.
	var rows := Settings.binding_rows()
	t.expect_eq(rows.size(), Keybinds.LABELS.size(), "one row per rebindable action")
	var punch: Dictionary = rows.filter(func(r): return r["action"] == Keybinds.PUNCH)[0]
	t.expect_eq(punch["changed"], true, "the rebound row is marked changed")
	t.expect_eq(punch["group"], "Combat", "rows carry their group")
	Settings.rebind(Keybinds.MOVE_UP, _key(KEY_G))
	rows = Settings.binding_rows()
	punch = rows.filter(func(r): return r["action"] == Keybinds.PUNCH)[0]
	t.expect_eq(punch["conflicts"], [Keybinds.LABELS[Keybinds.MOVE_UP]], "a shared binding is listed by label")

	# Reset saves too.
	Settings.reset(Keybinds.PUNCH)
	Settings.reset(Keybinds.MOVE_UP)
	Keybinds.reset_all()
	Settings.load_file()
	t.check(Keybinds.overrides().is_empty(), "a reset binding stays reset after a reload")
	Settings.rebind(Keybinds.PUNCH, _key(KEY_G))
	Settings.reset_all()
	Settings.load_file()
	t.check(Keybinds.overrides().is_empty(), "reset_all is saved")
	t.expect_eq(Settings.debug, false, "reset_all leaves Debug alone")

	# A file that names only some things changes only those.
	_write('{ "keybinds": { "move_up": { "key": %d } } }' % KEY_UP)
	Settings.debug = true
	Settings.load_file()
	t.expect_eq(Settings.debug, true, "a file without Debug leaves it as it was")
	t.check(_key(KEY_UP).is_action(Keybinds.MOVE_UP), "the bindings it names are applied")

	# An unreadable file is a warning and the defaults.
	t.expect_log("not a readable settings file")
	_write("{ this is not json")
	Settings.load_file()
	t.check(Keybinds.overrides().is_empty(), "a corrupt file falls back to the default bindings")
	await t.seconds(0.2)  # let the log watcher see the warning

	Keybinds.reset_all()
	_remove_scratch()


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


func _write(text: String) -> void:
	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string(text)


func _remove_scratch() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
