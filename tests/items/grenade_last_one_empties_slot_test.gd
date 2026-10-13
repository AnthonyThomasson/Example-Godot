extends GameTest

## G1: a grenade slot is a count. Selecting a slot the character does not carry does nothing; throwing the last grenade
## empties the slot and the character is holding its gun again (else its fists). Grenades are not guns: while one is
## held, `gun_slot()` is still the pistol, `ammo()` reads no ammo and reload does nothing.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const AIM := Vector2(500, 200)


func describe() -> Dictionary:
	return {
		"name": "The last grenade empties its slot",
		"description": "Slot 7 is not carried and selecting it does nothing; a gunman with one frag grenade throws it and holds the pistol again; a gunless one holds its fists. While held the grenade is not the gun.",
		"tags": ["grenade", "slot", "item"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.actor(&"gunman", &"puppet", Vector2(150, 200), { "max_health": 100000.0 })
	# One grenade and no gun: `start_rounds` is what `ItemRegistry.inventory_for` hands a new item (its count for a grenade).
	s.actor(&"bare", &"puppet", Vector2(150, 450), { "max_health": 100000.0, "start_rounds": 1 })


func run(t: TestContext) -> void:
	var gunman := t.actor(&"gunman")
	Probe.arm(gunman, 0, 1)
	if not t.require(Probe.count(gunman, Probe.FRAG) == 1, "the gunman carries one frag grenade (Character.item_count(8) = %d)" % Probe.count(gunman, Probe.FRAG)):
		return
	t.expect_eq(gunman.current_slot(), Probe.PISTOL, "it starts holding the pistol")
	t.puppet(&"gunman").select_slot(Probe.STUN)
	await t.frames(4)
	t.expect_eq(gunman.current_slot(), Probe.PISTOL, "selecting slot 7, which it does not carry, does nothing")
	t.expect_eq(Probe.count(gunman, Probe.STUN), 0, "no stun grenades are carried")

	await Probe.ready(t, &"gunman", Probe.FRAG, AIM)
	t.expect_eq(gunman.current_slot(), Probe.FRAG, "slot 8 is held")
	t.expect_eq(gunman.gun_slot(), Probe.PISTOL, "a grenade is not a gun: the gun it fights with is still the pistol")
	t.expect_eq(gunman.ammo(), -1, "the held grenade has no ammo")
	t.expect_eq(gunman.ammo(Probe.PISTOL), 12, "the pistol keeps its magazine")
	t.puppet(&"gunman").reload()
	await t.frames(4)
	t.check(not gunman.is_reloading(), "reload does nothing with a grenade in the hand")
	t.puppet(&"gunman").shoot()
	if not t.require(await t.until(func(): return t.happened(&"throw"), 1.5), "the click throws it"):
		return
	await t.frames(6)
	t.expect_eq(Probe.count(gunman, Probe.FRAG), 0, "the slot is empty after the last throw")
	t.check(not gunman.has_item(Probe.FRAG), "slot 8 is no longer carried")
	t.expect_eq(gunman.current_slot(), Probe.PISTOL, "the gunman is holding its pistol again")
	t.expect_eq(gunman.current_item().gun_id(), &"pistol", "and the pistol is the item in its hand")
	t.puppet(&"gunman").select_slot(Probe.FRAG)
	await t.frames(4)
	t.expect_eq(gunman.current_slot(), Probe.PISTOL, "an emptied slot cannot be selected again")

	# No gun at all: the fists.
	var bare := t.actor(&"bare")
	bare.set_loadout([ItemRegistry.UNARMED_SLOT, ItemRegistry.FISTS_SLOT, Probe.FRAG], Probe.FRAG, [])
	t.puppet(&"bare").aim_at(Vector2(500, 450))
	await t.seconds(0.4)
	if not t.require(Probe.count(bare, Probe.FRAG) == 1 and bare.current_slot() == Probe.FRAG, "the gunless one holds its single frag grenade"):
		return
	t.puppet(&"bare").shoot()
	await t.seconds(0.8)
	t.expect_eq(Probe.count(bare, Probe.FRAG), 0, "its grenade is spent")
	t.expect_eq(bare.current_slot(), ItemRegistry.FISTS_SLOT, "with no gun it goes back to its fists")
