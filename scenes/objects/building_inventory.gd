class_name BuildingInventory

## Stores information about all the objects spawned in a building: one ObjectInfo
## record per EnvironmentObject, gathered by scanning a spawned house. Exposes
## simple aggregate/lookup helpers so the later penetration/coverage system (and
## debugging) can do calculations over a building's furnishings.
##
## Built once after HouseSpawner.spawn (see main.gd) via `from_house()`. Objects
## are found by the "environment_object" group they join at spawn (object_spawner.gd).

const EnvironmentObject = preload("res://scenes/objects/environment_object.gd")

var objects: Array[ObjectInfo] = []


## Collect every EnvironmentObject under `house` into a fresh inventory.
static func from_house(house: Node) -> BuildingInventory:
	var inv := BuildingInventory.new()
	for child in house.find_children("*", "", true, false):
		if child.is_in_group("environment_object"):
			inv.objects.append(ObjectInfo.from_node(child as EnvironmentObject))
	return inv


func size() -> int:
	return objects.size()


## All records made of a given material (e.g. "wood").
func with_material(material: String) -> Array[ObjectInfo]:
	var out: Array[ObjectInfo] = []
	for info in objects:
		if info.material == material:
			out.append(info)
	return out


## Summed coverage of every object — a rough "how furnished / how much cover".
func total_coverage() -> float:
	var sum := 0.0
	for info in objects:
		sum += info.coverage
	return sum


## Mean penetration resistance across all objects (0 when empty).
func average_penetration() -> float:
	if objects.is_empty():
		return 0.0
	var sum := 0.0
	for info in objects:
		sum += info.penetration
	return sum / objects.size()


## Record for a specific scene node, or null if it isn't tracked. The future hit
## system uses this to look up what a projectile struck.
func for_node(n: Node) -> ObjectInfo:
	for info in objects:
		if info.node == n:
			return info
	return null
