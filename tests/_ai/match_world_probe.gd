extends RefCounted

## Shared helper for the tests that need a world built the way `main.gd` builds a match (not a test itself): the house,
## its navmesh and re-baker, then the NPCs and the human, all in the same frame, with no wait for the navigation maps
## in between. A test world waits for its navmesh (and the steering map's) to be in the maps before an actor spawns, so
## an NPC there never starts on a map that has not synchronized yet; an NPC in a match always does.
##
## The match gets a world of its own (a `SubViewport` with its own `World2D`, so its own physics space and navigation
## maps, made fresh as each match's are), under the test world, which frees it with everything else. Its characters are
## not test actors: the test holds the nodes `build` returns.

const MatchSpawner := preload("res://scenes/match_spawner.gd")
const LayoutBuilder := preload("res://scenes/testing/layout_builder.gd")
const PlayerController := preload("res://scenes/character/player_controller.gd")
const NavUpdater := preload("res://scenes/navigation/nav_updater.gd")
const PLAYER_SCENE := "res://scenes/character/character_base.tscn"


## Build a match on the layout a `TestSetup` describes (`layout.world`, e.g. after `Maps.house(TestSetup.new(), false)`)
## under `parent`: walls, navmesh, re-baker, then one invader NPC per point of `invaders` (`MatchSpawner.add_npc`) and,
## when `human` is not INF, the human as Main joins it (an invader with the player's controller, given its stack radio
## through `MatchSpawner.bind_player`). Returns `{ world, house, rooms, openings, npcs: Array, human, stack }`.
static func build(layout: TestSetup, parent: Node, invaders: Array, human := Vector2.INF) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "MatchViewport"
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(viewport)
	var world := Node2D.new()
	world.name = "World"
	viewport.add_child(world)
	var house := LayoutBuilder.build(layout.world, world)
	var rooms := WorldGen.get_rooms(house)
	var spawner = MatchSpawner.new()
	spawner.world = world
	spawner.openings = WorldGen.get_openings(house)
	var region := NavBuilder.build(house, rooms, world)
	var updater: Node = NavUpdater.new()
	updater.name = "NavUpdater"
	world.add_child(updater)
	updater.setup(region, house, rooms)
	for i in invaders.size():
		spawner.add_npc(MatchSpawner.INVADER_SCENE, spawner.npc_name("Invader", i), invaders[i], rooms)
	var player: Node2D = null
	var stack: Node = null
	if human != Vector2.INF:
		player = (load(PLAYER_SCENE) as PackedScene).instantiate()
		player.name = "Player"
		var brain: Node = PlayerController.new()
		brain.name = "PlayerController"
		player.add_child(brain)
		player.set("faction", &"invader")
		player.set("max_health", 1000000.0)
		player.position = human
		world.add_child(player)
		stack = spawner.bind_player(player, rooms)
	return { "world": world, "house": house, "rooms": rooms, "openings": spawner.openings, "npcs": spawner.combatants,
			"human": player, "stack": stack }


## The entry callouts radioed so far by `speaker` (a character node), optionally only step `step`.
static func calls(t: TestContext, speaker: Node, step := "") -> Array:
	return t.events_of(&"callout", func(d):
		return d.get("speaker") == speaker and String(d.get("entry_step", "")) != "" \
				and (step == "" or String(d.get("entry_step", "")) == step))
