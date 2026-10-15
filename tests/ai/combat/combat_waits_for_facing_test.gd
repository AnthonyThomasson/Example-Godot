extends GameTest

## Desired (docs/gaze-and-fire.md W2): the fight shoots once the NPC faces its contact, and a peek ducks only after a shot.
## `Combat` is driven here with a stand-in character and perception (no world): a peek with the body turned away holds its fire
## and stays in the peek phase; facing the contact it fires and ducks to cover; a shot the gun refuses (a reload under way) keeps
## it peeking; the click of an empty gun ducks (the cover phase reloads); an ambush waits for the facing as well.

const Combat := preload("res://scenes/ai/behavior/combat.gd")

const CONTACT := Vector2(400, 0)

## The stand-in nodes built so far, freed when the test ends.
var _nodes: Array = []


## A character with just what `Combat` asks of one: where it stands and faces, and a gun that can be loaded, refused or empty.
class FakeCharacter extends RefCounted:
	var global_position := Vector2.ZERO
	var facing := Vector2.RIGHT
	var move_input := Vector2.ZERO
	var rounds := 12
	var reloading := false
	var shots := 0

	func gun_slot() -> int:
		return 3

	func ammo(_slot := -1) -> int:
		return rounds

	func select_slot(_slot: int) -> void:
		pass

	func is_running() -> bool:
		return false

	func is_reloading() -> bool:
		return reloading

	func weapon_blocked() -> bool:
		return false

	func is_automatic() -> bool:
		return false

	func shoot() -> bool:
		if reloading or rounds == 0:
			return false
		rounds -= 1
		shots += 1
		return true


## Perception with a clear line to everything.
class FakePerception extends Node:
	func has_line_to(_node, _point: Vector2) -> bool:
		return true

	func note_engaged() -> void:
		pass


## Locomotion that goes nowhere.
class FakeLoco extends Node:
	func move_to(_dest: Vector2) -> void:
		pass


func describe() -> Dictionary:
	return {
		"name": "A fight shoots only once the NPC faces its contact",
		"description": "Combat driven with a stand-in character: a peek and an ambush hold fire until the facing settles, and a peek ducks only after a shot (or an empty click).",
		"tags": ["ai", "gaze", "combat", "unit"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	# Peek-and-cover.
	var rig := _rig()
	var combat: RefCounted = rig[0]
	var me: FakeCharacter = rig[1]
	me.facing = Vector2.LEFT
	combat.peek_cover(me, 0.016, null, CONTACT, false)
	t.expect_eq(me.shots, 0, "peek: turned away, it holds its fire")
	t.expect_eq(combat.phase, "peek", "peek: and keeps peeking")
	me.facing = Vector2.RIGHT
	combat.peek_cover(me, 0.016, null, CONTACT, false)
	t.expect_eq(me.shots, 1, "peek: facing the contact, it fires")
	t.expect_eq(combat.phase, "cover", "peek: and ducks to cover after the shot")

	# A shot the gun refuses (a reload under way) is not a shot: it keeps peeking.
	rig = _rig()
	combat = rig[0]
	me = rig[1]
	me.reloading = true
	combat.peek_cover(me, 0.016, null, CONTACT, false)
	t.expect_eq(combat.phase, "peek", "peek: a refused shot does not send it ducking")
	me.reloading = false
	combat.peek_cover(me, 0.016, null, CONTACT, false)
	t.expect_eq(combat.phase, "cover", "peek: it ducks once the shot leaves")

	# An empty gun ducks: the cover phase is where it is reloaded.
	rig = _rig()
	combat = rig[0]
	me = rig[1]
	me.rounds = 0
	combat.peek_cover(me, 0.016, null, CONTACT, false)
	t.expect_eq(combat.phase, "cover", "peek: the click of an empty gun ducks to reload")

	# Ambush.
	rig = _rig()
	combat = rig[0]
	me = rig[1]
	me.facing = Vector2.UP
	combat.ambush(me, null, CONTACT)
	t.expect_eq(me.shots, 0, "ambush: turned away, it holds its fire")
	me.facing = Vector2.RIGHT
	combat.ambush(me, null, CONTACT)
	t.expect_eq(me.shots, 1, "ambush: facing the contact, it fires")
	for n in _nodes:
		n.free()


## A fresh `Combat` wired to the stand-ins, with a stand-in character at the origin.
func _rig() -> Array:
	var loco := FakeLoco.new()
	var perception := FakePerception.new()
	_nodes.append_array([loco, perception])
	var combat := Combat.new()
	combat.setup(loco, perception)
	return [combat, FakeCharacter.new()]
