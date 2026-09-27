extends Node

## General object despawner / counter.
##
## Autoloaded as `Despawner` (see project.godot [autoload]). Any system that
## spawns transient world debris (spent casings today; particles, decals, ... in
## future) hands the node to `track()`. The despawner keeps them in spawn order
## and, once the live count passes `Config.max_scene_objects`, frees the oldest —
## so the scene never accumulates debris without bound. Objects that free
## themselves for other reasons auto-drop out via their `tree_exited` signal.

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


func _enforce_cap() -> void:
	var limit: int = Config.max_scene_objects
	while _objects.size() > limit:
		var oldest: Node = _objects.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _on_object_exited(node: Node) -> void:
	_objects.erase(node)
