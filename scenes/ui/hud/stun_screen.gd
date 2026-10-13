extends CanvasLayer

## UI domain: the stunned player's screen (G14 of `docs/grenades.md`). At the burst of a flash the screen goes white and
## fades back over the blind time, through a frozen afterimage of the frame at the moment of the flash: the afterimage holds
## solid while the white is strong, then gives way to the live view as the white thins. A bang that only deafens whitens
## nothing, and the screen watches the one character it is given, so someone else's flash changes nothing.
##
## A decoupled observer like the other HUDs: `watch(character)` then it reads the character's `stun_view()`
## (`{ blind, blind_total, deaf, level }`) and listens to the `&"stun"` events for the moment a flash lands (to take the
## afterimage). `drawn()` is what is shown: `{ white, afterimage, remaining }` (what the test reads). Main builds it for the human.

## The layer it draws on, over the HUD (the whole point is that it hides everything).
const LAYER := 90
## The white's colour, a touch warm like a real flash.
const WHITE := Color(1.0, 0.99, 0.95)
## A new flash takes a fresh afterimage only when the white of the last one has thinned below this (otherwise the frame it
## would capture is itself mostly white).
const RETAKE_BELOW := 0.2

var _character: Node = null  ## The human whose stun it shows (`watch`).
var _canvas: Control = null   ## The full-rect control the white is drawn on.
## The frozen frame of the flash; null when the display cannot give one (headless) or none is held.
var _image: Texture2D = null
var _afterimage := false   ## An afterimage is held (its texture may be missing when there is no display).
var _remaining := 0.0      ## Blind seconds left, as last read.
var _white := 0.0          ## 0..1, how white the screen is.


func _init() -> void:
	layer = LAYER
	name = "StunScreen"


func _ready() -> void:
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_screen)
	add_child(_canvas)
	EventBus.posted.connect(_on_posted)


## Show the stun of `character` (anything with `stun_view()`).
func watch(character: Node) -> void:
	_character = character
	_refresh()


## What is shown now: how white the screen is (0..1), whether the frozen afterimage is held, and the blind seconds left.
func drawn() -> Dictionary:
	return { "white": _white, "afterimage": _afterimage, "remaining": _remaining }


func _process(_delta: float) -> void:
	_refresh()


## Read the character: the white is the share of the blind time still to run (so it falls steadily from 1 at the burst to 0
## as the blindness ends); with no blindness the screen is clear and the afterimage is let go.
func _refresh() -> void:
	var was := _white
	var view: Dictionary = {}
	if _character != null and is_instance_valid(_character) and _character.has_method("stun_view"):
		view = _character.call("stun_view")
	_remaining = float(view.get("blind", 0.0))
	var total := float(view.get("blind_total", 0.0))
	_white = clampf(_remaining / total, 0.0, 1.0) if _remaining > 0.0 and total > 0.0 else 0.0
	if _white <= 0.0:
		_afterimage = false
		_image = null
	if _canvas != null and (_white != was or _white > 0.0):
		_canvas.queue_redraw()


## A flash landed on the watched character: freeze the frame it interrupted. The stun is already applied (the character
## posts after it), so the white is read from it on the next refresh; the frame to freeze is the one on screen now.
func _on_posted(topic: StringName, data: Dictionary) -> void:
	if topic != &"stun" or _character == null or data.get("character") != _character or float(data.get("blind", 0.0)) <= 0.0:
		return
	if _afterimage and _white >= RETAKE_BELOW:
		return  # still white from the last flash: keep the frame already frozen
	_afterimage = true
	_image = _grab()
	_refresh()


## The frame on screen, or null when there is no display to read it from.
func _grab() -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var image := get_viewport().get_texture().get_image()
	return ImageTexture.create_from_image(image) if image != null else null


## Draw the white (over the frozen afterimage while one is held) on the canvas.
func _draw_screen() -> void:
	if _white <= 0.0:
		return
	var rect := Rect2(Vector2.ZERO, _canvas.size)
	# The frozen frame stays solid until the white is half gone, then lets the live view through.
	if _image != null:
		_canvas.draw_texture_rect(_image, rect, false, Color(1.0, 1.0, 1.0, clampf(_white * 2.0, 0.0, 1.0)))
	_canvas.draw_rect(rect, Color(WHITE, _white))
