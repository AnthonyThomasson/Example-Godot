extends Node2D

## Floor CONTROL layer (Objects domain): one room's floor, or a piece of the street round a house — a rect covered in a
## repeating pixel-art tile, drawn beneath everything else in the house. It has no collider, so shots, navigation and
## perception all pass over it. Built by FloorFactory; drawing lives in floor_visuals.gd, which reads these fields. It tells
## the Physics blood flow where its grooves are and, unless `sound_surface` is off (the street: footsteps out there stay the
## open ground's), the Audio domain what it is made of. A floor of the street (`light_layer` `street`) is drawn, with
## everything under it, on the street's light layer (General's `LightMasks.STREET`).

@export var size: Vector2 = Vector2(100.0, 100.0)  ## Floor extent (px) from this node's origin.
@export var art: String = "floor"  ## Tiling painter id.
@export var color: Color = Color(0.6, 0.5, 0.4)  ## Base color the tile is painted in.
@export var floor_material: String = ""  ## Material tag (the tile's surface finish).
@export var art_opts: Dictionary = {}  ## Painter options, e.g. { "pattern": "planks" }.
@export var sound_surface: bool = true  ## Registers with SoundSurface (off: footsteps on it sound like the open ground).
## World-placed marks over the floor (the street's: `{ seed, lane, edges }`, see street_marks.gd); empty = none.
@export var marks: Dictionary = {}
## How far (px) into the repeating tile the floor's corner falls: 0 starts the tile at the corner (a room's floor); the
## street's pieces share one grid, so their slab joints meet.
@export var tile_offset: Vector2 = Vector2.ZERO
## The light layer it is drawn on: `""` the house's (Godot's default), `street` the street's, lit only by the street lamps,
## the flashes and the street's own sky, so a floor spanning the whole house is never crowded by the house's lights.
@export var light_layer: String = ""


const ObjectArt = preload("res://scenes/objects/art/object_art.gd")

var _surface_id := -1  ## BloodSurface registration of this floor.
var _sound_id := -1  ## SoundSurface registration of this floor.


func _ready() -> void:
	z_index = ObjectArtConfig.floor_z_index
	if light_layer == "street":
		# Every canvas item of the floor (its visuals, marks and light-source overlay: children, so ready by now).
		light_mask = LightMasks.STREET
		for item in find_children("*", "CanvasItem", true, false):
			(item as CanvasItem).light_mask = LightMasks.STREET
	# Tell the Physics blood flow where this floor's grooves are, so blood follows grout and seams.
	_surface_id = BloodSurface.register(Rect2(global_position, size), flow_groove, ObjectArt.porous(art, art_opts))
	# And the Audio domain what it is made of, so footsteps sound like it.
	if sound_surface:
		_sound_id = SoundSurface.register(Rect2(global_position, size), floor_material, String(art_opts.get("pattern", "")))


func _exit_tree() -> void:
	BloodSurface.unregister(_surface_id)
	SoundSurface.unregister(_sound_id)


## 1 where world point `at` is on a groove of this floor's pattern (BloodSurface callback).
func flow_groove(at: Vector2, half_width: float) -> float:
	return ObjectArt.groove(art, at - global_position, art_opts, half_width)
