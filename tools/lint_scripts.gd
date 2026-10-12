extends Node
## GDScript analyzer lint: loads every project script and lets the engine print the warnings the editor's
## Debugger shows (unused variable, integer division, shadowed identifier, ...). Headless runs are silent about
## them unless the debugger is active, so tools/lint.sh starts this scene with `--debug` and tools/lint_report.py
## reads what it printed. The engine gives no file or line with a warning, hence this protocol on stdout:
## `LINT-PASS2`, then `LINT> <path>` before each script (whatever the engine prints after it belongs to that
## script), then `LINT-DONE <count>`.
##
## `-- --only=res://a.gd,res://b.gd` lints just those scripts (their dependencies are still compiled first).
##
## `-- --divisions=res://a.gd,...` instead finds which `/` in those scripts are integer divisions (the engine
## names no line): it recompiles each script with one `/` turned into `*` (the same result types, so nothing
## else changes) and prints `LINT@ <line> <column>` before each, and `LINT@ base` before the unchanged
## script. A `/` whose recompile has one integer-division warning fewer than the base is an integer division.
##
## Pass 1 only warms the script cache; pass 2 reloads every script on its own (CACHE_MODE_IGNORE), so what it
## prints is that script's own warnings and not those of the scripts it depends on.

const SELF := "res://tools/lint_scripts.gd"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--divisions="):
			for path in a.substr(12).split(","):
				_probe_divisions(path)
			get_tree().quit()
			return
	var paths: Array = []
	_collect("res://", paths)
	paths.sort()
	for p in paths:
		ResourceLoader.load(p)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			paths = Array(a.substr(7).split(","))
	print("LINT-PASS2")
	for p in paths:
		print("LINT> ", p)
		ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
	print("LINT-DONE ", paths.size())
	get_tree().quit()


func _collect(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		if f.ends_with(".gd") and path != SELF:
			out.append(path)
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with(".") and not dir.path_join(d).begins_with("res://addons"):
			_collect(dir.path_join(d), out)


func _probe_divisions(path: String) -> void:
	ResourceLoader.load(path)  # compiles (and caches) what the script depends on, so its warnings are not repeated
	print("LINT-PASS2")
	print("LINT> ", path)
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var named := RegEx.create_from_string("^class_name\\s+\\w+\\s*")  # the copy must not claim the real class's name
	for row in lines.size():
		lines[row] = named.sub(lines[row], "")
	_compile(lines, "base")
	for row in lines.size():
		var quote := ""
		var line := lines[row]
		for col in line.length():
			var ch := line[col]
			if quote != "":
				if ch == "\\":
					col += 1
				elif ch == quote:
					quote = ""
			elif ch == "#":
				break
			elif ch == "\"" or ch == "'":
				quote = ch
			elif ch == "/":
				var mutated := lines.duplicate()
				mutated[row] = line.substr(0, col) + "*" + line.substr(col + 1)
				_compile(mutated, "%d %d" % [row + 1, col + 1])
	print("LINT-DONE")


func _compile(lines: PackedStringArray, label: String) -> void:
	var script := GDScript.new()
	script.source_code = "\n".join(lines)
	print("LINT@ ", label)
	script.reload()
