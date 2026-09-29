extends Node

## Autoloaded as `Despawner`. Any system that spawns transient world debris (casings,
## chips) hands the node to `track()`; once the live count passes `max_scene_objects` the
## oldest are freed, so the scene never accumulates debris without bound. Nodes that free
## themselves auto-drop out via their `tree_exited` signal.

## Max number of tracked debris objects allowed at once. Spawning past this frees
## the oldest. Owned here (the despawner is the only thing that reads it).
@export var max_scene_objects: int = 1000

## Live tracked objects, oldest first.
var _objects: Array[Node] = []


## Register a freshly spawned debris node. Enforces the cap immediately, so the
## oldest are freed the moment a new spawn pushes the count over the limit.
func track(node: Node) -> void:
	_objects.append(node)
	# Drop it from the list if it disappears on its own (avoids stale entries).
	node.tree_exited.connect(_on_object_exited.bind(node))
	_enforce_cap()


## Number of objects currently tracked.
func count() -> int:
	return _objects.size()


## Free the oldest tracked nodes until the count is within the cap.
func _enforce_cap() -> void:
	var limit: int = max_scene_objects
	while _objects.size() > limit:
		var oldest: Node = _objects.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


## Drop a node from tracking when it leaves the tree.
func _on_object_exited(node: Node) -> void:
	_objects.erase(node)
