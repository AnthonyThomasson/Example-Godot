class_name ObjectInfo

## One spawned object's data record: material, color, a coverage rating (0–100, a
## height/cover proxy) and a penetration value (resistance to being shot through),
## plus a reference back to the live node and its footprint. Built by
## ObjectInfo.from_node() from a spawned EnvironmentObject and collected per
## building by BuildingInventory. The later penetration/coverage system reads
## coverage/penetration to resolve hits.

const EnvironmentObject = preload("res://scenes/objects/environment_object.gd")

var node: EnvironmentObject   ## The live object in the scene.
var name: String              ## Display name (EnvironmentObject.object_name).
var material: String          ## e.g. "wood", "fabric", "metal", "glass", ...
var color: Color              ## Final (possibly palette-recolored) color.
var coverage: float           ## 0–100 height/cover proxy.
var penetration: float        ## Resistance to being shot through.
var position: Vector2         ## World position of the object's center.
var size: Vector2             ## Footprint.


## Build a record from a spawned EnvironmentObject node.
static func from_node(obj: EnvironmentObject) -> ObjectInfo:
	var info := ObjectInfo.new()
	info.node = obj
	info.name = obj.object_name
	info.material = obj.object_material
	info.color = obj.color
	info.coverage = obj.coverage
	info.penetration = obj.penetration
	info.position = obj.global_position
	info.size = obj.size
	return info


func _to_string() -> String:
	return "%s [%s] cover=%.0f pen=%.0f" % [name, material, coverage, penetration]
