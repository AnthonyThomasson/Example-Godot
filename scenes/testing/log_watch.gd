extends RefCounted

## Testing domain: picks up engine errors and warnings as they are logged, so a test that causes one
## fails. Godot 4.4 has no in-process hook for them (`Logger` / `OS.add_logger` arrive in 4.5), but
## every error and warning — `push_error`/`push_warning`, script runtime errors, engine `ERROR:` /
## `WARNING:` output — is written to the log file (`debug/file_logging/log_path`, on by default on
## desktop, headless included). This tails that file from a marked offset and parses the new lines.

## Header → severity. Longest first so "SCRIPT ERROR:" isn't read as "ERROR:".
const HEADERS := [
	["USER SCRIPT ERROR:", "error"], ["SCRIPT ERROR:", "error"], ["SHADER ERROR:", "error"],
	["USER ERROR:", "error"], ["ERROR:", "error"],
	["USER SCRIPT WARNING:", "warning"], ["SCRIPT WARNING:", "warning"], ["SHADER WARNING:", "warning"],
	["USER WARNING:", "warning"], ["WARNING:", "warning"],
]
## Lines no test is blamed for: engine noise outside any test's control.
const GLOBAL_ALLOWED := [
	"[von] ",  # the Von launcher's diagnostics; a requires_von test is SKIPPED without a live server
]

## Set to watch a log other than the project's (a run started with `--log-file`).
var path_override := ""
## The log file being tailed, and the byte offset read up to.
var _path := ""
var _offset := 0
## A trailing line not yet terminated by a newline (kept until the rest arrives).
var _partial := ""
## The last parsed entry, held back one line so a following "at: file:line" can be attached.
var _pending: Dictionary = {}


## Whether the log file exists (false = errors cannot be watched; callers should say so).
func available() -> bool:
	return FileAccess.file_exists(_log_path())


## Start watching. By default everything already in the log is ignored; `from_start` also takes in what the
## engine logged before this call (startup errors), for a run whose log file is fresh (`--log-file`).
func begin(from_start := false) -> void:
	_path = _log_path()
	_offset = 0 if from_start else _length()
	_partial = ""
	_pending = {}


## How many bytes of the log have been read so far: what a run reports as `log_end`, so the part of the log
## written after it (engine shutdown) can be checked by whoever started the process (tools/scan_godot_log.py).
func consumed() -> int:
	return _offset - _partial.length()


## The error/warning entries logged since the last poll: `{ severity, message, location, line }`.
## `flush` also releases an entry still waiting for its location line.
func poll(flush := false) -> Array:
	var out: Array = []
	var length := _length()
	if length < _offset:
		_offset = 0  # rotated/truncated
	if length > _offset:
		var f := FileAccess.open(_path, FileAccess.READ)
		if f != null:
			f.seek(_offset)
			var text := _partial + f.get_buffer(length - _offset).get_string_from_utf8()
			_offset = length
			var lines := text.split("\n")
			_partial = lines[lines.size() - 1]
			lines.remove_at(lines.size() - 1)
			for line in lines:
				_feed(line.trim_suffix("\r"), out)
	if flush and not _pending.is_empty():
		out.append(_pending)
		_pending = {}
	return out


## Whether `entry` matches one of `patterns` (regex strings) or the global allow-list.
static func matches_any(entry: Dictionary, patterns: Array) -> bool:
	var text: String = "%s %s" % [entry.get("message", ""), entry.get("location", "")]
	for p in GLOBAL_ALLOWED:
		if text.contains(p):
			return true
	for p in patterns:
		var re := RegEx.create_from_string(String(p))
		if re != null and re.search(text) != null:
			return true
	return false


## Parse one log line into `out`: a header opens an entry, its "at:" line completes it.
func _feed(line: String, out: Array) -> void:
	var stripped := line.strip_edges()
	if not _pending.is_empty() and stripped.begins_with("at:"):
		_pending["location"] = stripped.substr(3).strip_edges()
		out.append(_pending)
		_pending = {}
		return
	for h in HEADERS:
		if line.begins_with(h[0]):
			if not _pending.is_empty():
				out.append(_pending)
			_pending = { "severity": h[1], "message": line.substr(h[0].length()).strip_edges(), "location": "", "line": line }
			return
	if not _pending.is_empty() and not line.begins_with(" ") and not line.begins_with("\t"):
		out.append(_pending)
		_pending = {}


## The absolute path of the engine log file.
func _log_path() -> String:
	if path_override != "":
		return path_override
	return ProjectSettings.globalize_path(String(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")))


## The log file's current size in bytes (0 when it is missing).
func _length() -> int:
	var f := FileAccess.open(_path if _path != "" else _log_path(), FileAccess.READ)
	return 0 if f == null else f.get_length()
