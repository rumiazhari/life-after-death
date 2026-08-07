class_name ObjectPool
extends RefCounted
## Generic allocation-conscious pool for frequently spawned/despawned nodes.
##
## Avoids per-shot instantiate()/queue_free() churn (used by the projectile
## manager). Pooled instances are reparented under a single container and
## toggled active/inactive instead of being freed and recreated.

var _scene: PackedScene
var _parent: Node
var _available: Array[Node] = []
var _capacity: int = 0

func _init(scene: PackedScene, parent: Node, prewarm_count: int = 0) -> void:
	_scene = scene
	_parent = parent
	for i in range(prewarm_count):
		_available.append(_create_instance())

func _create_instance() -> Node:
	var instance: Node = _scene.instantiate()
	_parent.add_child(instance)
	_deactivate(instance)
	_capacity += 1
	return instance

func acquire() -> Node:
	var instance: Node
	if _available.is_empty():
		instance = _create_instance()
	else:
		instance = _available.pop_back()
	instance.set_process(true)
	instance.set_physics_process(true)
	if instance is CanvasItem:
		(instance as CanvasItem).visible = true
	if instance.has_method("on_pool_acquire"):
		instance.call("on_pool_acquire")
	return instance

func release(instance: Node) -> void:
	if not is_instance_valid(instance):
		return
	_deactivate(instance)
	_available.append(instance)

func _deactivate(instance: Node) -> void:
	instance.set_process(false)
	instance.set_physics_process(false)
	if instance is CanvasItem:
		(instance as CanvasItem).visible = false
	if instance.has_method("on_pool_release"):
		instance.call("on_pool_release")

func available_count() -> int:
	return _available.size()

## Total instances ever created by this pool (available + currently in use).
func capacity() -> int:
	return _capacity
