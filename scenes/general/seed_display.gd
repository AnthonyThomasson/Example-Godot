extends CanvasLayer

## General domain, seed readout: a small always-on label in the bottom-right corner showing the
## seed the current level is built from, so a layout you like can be read off and re-entered in the
## setup window. Built in code like the other General HUDs; a decoupled piece that knows nothing of
## the domains — Main calls `show_seed(level_seed)` once the world is built.

var _label: Label  ## The corner readout; filled by `show_seed`.


func _ready() -> void:
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.offset_left = -16.0
	_label.offset_top = -12.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.modulate = Color(1, 1, 1, 0.6)
	add_child(_label)


## Show `level_seed` as the level's seed. Called by Main after the world is built.
func show_seed(level_seed: int) -> void:
	_label.text = "seed: %d" % level_seed
