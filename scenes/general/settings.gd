class_name Settings

## General domain: the player's saved settings — the debug switch and the key bindings that differ from
## the defaults, and the last match-setup choices — kept in one JSON file. A `class_name` holder of `static var`s and static functions, read
## as `Settings.<name>`; there is no instance and no autoload.
##
## Main loads it once at startup (`load_file()`), so the headless test runner, which never loads
## `main.tscn`, never reads a developer's real file. The settings page's changes come back through the
## mutators here (`set_debug`, `rebind`, `reset`, `reset_all`), each of which saves at once.
## Bindings live in `Keybinds`; this file only persists them and reshapes them for the page.

## Where the settings are stored. A test points it at a scratch file.
static var path: String = "user://settings.json"
## Master switch for the AI debug overlays and their in-game toggle bar. Main seeds it from its own
## export before `load_file()`, so a file that doesn't name it leaves that value standing.
static var debug: bool = true
## The match-setup window's last choices (`{ side, seed, defenders, invaders }`, plain data as the window emits
## them), so it reopens the way it was left. Empty until something has been chosen.
static var setup: Dictionary = {}


## Read the file: reset every binding to its default, then apply the saved differences, and take the
## saved `debug` and `setup`. A missing file leaves the defaults; an unreadable one warns and does the same; entries
## that aren't understood are skipped one by one.
static func load_file() -> void:
	Keybinds.reset_all()
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_warning("Settings: %s is not a readable settings file; using the defaults." % path)
		return
	var data: Dictionary = json.data
	if data.get("debug") is bool:
		debug = data["debug"]
	if data.get("setup") is Dictionary:
		setup = data["setup"]
	if data.get("keybinds") is Dictionary:
		Keybinds.apply_overrides(data["keybinds"])


## Write the current debug switch and the key bindings that differ from the defaults.
static func save() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Settings: could not write %s (error %d)." % [path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify({
		"debug": debug,
		"setup": setup,
		"keybinds": Keybinds.overrides(),
	}, "  "))


## Set the Debug switch and save.
static func set_debug(on: bool) -> void:
	debug = on
	save()


## Remember the setup window's choices (`config`, as its `start_requested` carries them; only the parameters
## it reopens with are kept, not the start `mode`) and save.
static func set_setup(config: Dictionary) -> void:
	setup = {}
	for key in ["side", "seed", "defenders", "invaders"]:
		if config.has(key):
			setup[key] = config[key]
	save()


## Bind `action` to the key or mouse button in `event` and save. Returns false (and changes nothing) when
## the event isn't something that can be bound.
static func rebind(action: String, event: InputEvent) -> bool:
	if not Keybinds.bind(action, event):
		return false
	save()
	return true


## Put `action` back on its default binding and save.
static func reset(action: String) -> void:
	Keybinds.reset(action)
	save()


## Put every binding back on its default and save. `debug` is left alone.
static func reset_all() -> void:
	Keybinds.reset_all()
	save()


## One plain dict per rebindable action, in display order, for the settings page:
## `{ action, label, group, text, conflicts: [labels of actions sharing the binding], changed }`.
static func binding_rows() -> Array:
	var changed := Keybinds.overrides()
	var rows := []
	for action in Keybinds.LABELS:
		var conflicts := []
		for other in Keybinds.conflicts_of(action):
			conflicts.append(Keybinds.LABELS[other])
		rows.append({
			"action": action,
			"label": Keybinds.LABELS[action],
			"group": Keybinds.GROUPS[action],
			"text": Keybinds.text_of(action),
			"conflicts": conflicts,
			"changed": changed.has(action),
		})
	return rows
