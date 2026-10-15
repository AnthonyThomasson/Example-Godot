extends GameTest

## R10 (ticket #61): light sources are drawn unshaded. What gives light (a screen's face, a neon tube, a bulb, a street lamp's
## lens) is drawn by each visuals node's child `Emissive` overlay (Objects' `emissive_layer()`); with the lighting on, every
## such overlay in a generated house draws unshaded (a CanvasItemMaterial in LIGHT_MODE_UNSHADED, so neither the dusk ambient
## nor the lights change it), while the art under it (the visuals node) stays lit.
##
## It reads (tests/_lighting/lighting_probe.gd) `WorldLighting` in the group `world_lighting` (checked, not required: the overlays
## are read either way), and the overlays through each visuals node's `emissive_layer()`.

const Probe := preload("res://tests/_lighting/lighting_probe.gd")
const SEED := 4


func describe() -> Dictionary:
	return {
		"name": "Light sources draw unshaded",
		"description": "Every Emissive overlay of a lit house draws through an unshaded CanvasItemMaterial; the art beneath it does not.",
		"tags": ["lighting"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	t.check(Probe.lighting(t) != null, "the test world is lit (a WorldLighting under it)")
	var layers: Array = []
	for node in t.world.find_children("*", "", true, false):
		if node.has_method(&"emissive_layer"):
			var layer: Node2D = node.emissive_layer()
			if layer != null:
				layers.append(layer)
	if not t.require(layers.size() >= 3, "the house has light sources drawn by Emissive overlays (%d)" % layers.size()):
		return
	for layer: CanvasItem in layers:
		var where := t.world.get_path_to(layer)
		t.check(_unshaded(layer), "%s draws unshaded" % where)
		var art := layer.get_parent() as CanvasItem
		if art != null:
			t.check(not _unshaded(art), "the art under %s is lit (not unshaded)" % where)


## Whether `item` draws unshaded: its own material (or, with `use_parent_material`, its parent's) is a CanvasItemMaterial in
## LIGHT_MODE_UNSHADED.
func _unshaded(item: CanvasItem) -> bool:
	var at: CanvasItem = item
	while at != null and at.use_parent_material:
		at = at.get_parent() as CanvasItem
	if at == null:
		return false
	var mat := at.material as CanvasItemMaterial
	return mat != null and mat.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED
