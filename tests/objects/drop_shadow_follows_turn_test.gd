extends GameTest

## A piece's drop shadow falls a fixed way in the world, away from the light, however the piece is turned
## (environment_object_visuals.gd). It is drawn behind the piece by the visuals' `DropShadow` child, in the piece's own frame,
## and a turn moves that child to the shadow's offset rather than repainting the piece. This checks the shadow lies
## `coverage x drop_shadow_per_coverage` px (capped at `drop_shadow_max`) from the piece, straight away from the light, at
## several turns, the frame after each, and that the child draws behind the piece.

const TURNS := [0.0, 0.7, 1.9, -2.6, 3.1]


func describe() -> Dictionary:
	return {
		"name": "A piece's drop shadow stays away from the light as it turns",
		"description": "The DropShadow child behind a shoved sofa sits its shadow's length straight away from the light at every turn, the frame after it.",
		"tags": ["art", "shadow", "furniture"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.object(&"sofa", "sofa", Vector2(300, 200))


func run(t: TestContext) -> void:
	var sofa := t.object(&"sofa") as RigidBody2D
	var visuals := sofa.get_node("EnvironmentObjectVisuals") as Node2D
	var shadow := visuals.get_node_or_null("DropShadow") as Node2D
	if not t.require(shadow != null, "the sofa's visuals have a DropShadow child"):
		return
	t.check(shadow.show_behind_parent, "drawn behind the piece")
	var length := minf(float(sofa.get("coverage")) * ArtConfig.drop_shadow_per_coverage, ArtConfig.drop_shadow_max)
	if not t.require(length > 0.0, "the sofa casts a drop shadow (%.1f px)" % length):
		return
	var away := -ArtConfig.light_from.normalized() * length
	sofa.freeze = true  # turned by hand: a free body is put back by the next physics step
	for turn: float in TURNS:
		sofa.rotation = turn
		await t.frames(1)
		var offset := shadow.global_position - visuals.global_position
		t.check(offset.distance_to(away) < 0.01, "turned %.1f rad, the shadow lies %s off the piece (want %s)" % [turn, offset, away])
