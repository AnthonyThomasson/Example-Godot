class_name ColliderCuts
extends RefCounted

## Objects domain: the convex cuts of dented colliders that wait for their deferred rebuild, cut side by side on worker threads.
## Cutting a dented silhouette into convex pieces (`Deformation.cut_shape` / `cut_wall`) is the costly part of a collider rebuild,
## and a blast dents a room's worth of furniture and wall segments at once, each queueing its rebuild deferred (shapes cannot
## change mid-physics). When the first of those rebuilds runs, the dents are final (no hit lands between deferred calls): it
## starts every other waiting cut on a worker thread, each from a copy of its dents as they stand then, and cuts its own meanwhile;
## each later rebuild takes its finished cut. The same pieces, swapped in at the same moment, one rebuild after another; a
## piece hit several times in a frame is cut once, from all its dents.

## The cuts queued and not started, in the order queued.
static var _waiting: Array[ColliderCuts] = []
## How many cuts have been started on a worker thread (for tests).
static var started := 0

## () -> Callable, called on the main thread as the cut starts: reads the dents and returns the job, pure (a worker may run it),
## () -> [polygon, its convex pieces].
var _make: Callable
## The worker task cutting it, -1 when none.
var _task := -1
var _result: Array = []  ## The worker's [polygon, convex pieces], read only once its task is waited for.


## A cut prepared by `make` (see `_make`), waiting for the first rebuild to start it.
static func queue(make: Callable) -> ColliderCuts:
	var cut := ColliderCuts.new()
	cut._make = make
	_waiting.append(cut)
	return cut


## This cut's [polygon, convex pieces], waited for if a worker is cutting it. One not started is the caller's to cut (it holds
## the silhouette already): it gets [] and every other waiting cut starts on a worker thread, from the dents as they stand now.
func take() -> Array:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		return _result
	_waiting.erase(self)
	for other in _waiting:
		other._start()
	_waiting.clear()
	return []


## Drop this cut (its piece leaves the tree before its rebuild): a running one is waited for, as every worker task must be.
func cancel() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_waiting.erase(self)


## Start this cut on a worker thread: its job made now, on the main thread, from the dents as they stand.
func _start() -> void:
	var job: Callable = _make.call()
	started += 1
	_task = WorkerThreadPool.add_task(func() -> void: _result = job.call(), true, "collider cut")
