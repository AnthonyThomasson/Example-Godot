extends GameTest

## The human's fire button, pressed through the real input action (the path a click takes): holding it keeps an
## automatic gun (the rifle) firing at its rate, and a semi-automatic one (the pistol) fires once per press, however
## long it is held.

## How long the button is held (s).
const HOLD := 1.0


func describe() -> Dictionary:
	return {
		"name": "The player holds the trigger for an automatic gun",
		"description": "Holding the fire action fires the rifle at its rate and the pistol only once; releasing stops it.",
		"tags": ["player", "input", "gun", "automatic", "rifle", "pistol"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"nav.rebake", false)
	s.actor(&"you", &"player", Vector2(400, 250), { "start_slot": 6 })


func run(t: TestContext) -> void:
	var you := t.actor(&"you")
	await t.seconds(0.3)
	t.check(not you.weapon_blocked(), "the barrel is clear in the open arena")

	# The rifle: held, it fires for as long as the button is down, at its own rate.
	var before: int = you.ammo()
	Input.action_press(Keybinds.FIRE)
	await t.seconds(HOLD)
	Input.action_release(Keybinds.FIRE)
	var fired: int = before - you.ammo()
	var want := HOLD / float(GunConfig.row(&"rifle")["fire_interval"])
	t.check(absf(fired - want) <= 2.0, "holding the button fires the rifle about %.1f rounds in %.1f s (fired %d)" % [want, HOLD, fired])

	# Released: nothing more.
	var after: int = you.ammo()
	await t.seconds(0.4)
	t.expect_eq(you.ammo(), after, "releasing the button stops the rifle")

	# The pistol: one round per press, however long it is held.
	you.select_slot(3)
	await t.seconds(0.2)
	before = you.ammo()
	Input.action_press(Keybinds.FIRE)
	await t.seconds(HOLD)
	Input.action_release(Keybinds.FIRE)
	t.expect_eq(before - you.ammo(), 1, "holding the button fires a semi-automatic pistol once")
