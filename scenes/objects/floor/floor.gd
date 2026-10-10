extends Node2D

## Floor CONTROL layer (Objects domain): one room's floor — a rect covered in a repeating pixel-art
## tile, drawn beneath everything else in the house. It has no collider, so shots, navigation and
## perception all pass over it. Built by FloorFactory; drawing lives in floor_visuals.gd, which
## reads these fields.

@export var size: Vector2 = Vector2(100.0, 100.0)  ## Floor extent (px) from this node's origin.
@export var art: String = "floor"  ## Tiling painter id.
@export var color: Color = Color(0.6, 0.5, 0.4)  ## Base color the tile is painted in.
@export var floor_material: String = ""  ## Material tag (the tile's surface finish).
@export var art_opts: Dictionary = {}  ## Painter options, e.g. { "pattern": "planks" }.


func _ready() -> void:
	z_index = ObjectArtConfig.floor_z_index
