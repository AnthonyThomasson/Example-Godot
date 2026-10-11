extends RefCounted

## Character FOOTSTEPS (Character domain, animate layer): spots the instant each foot lands in the walk
## cycle and reports it to the Physics domain's BloodFootprints, which decides whether the sole prints
## blood. A foot lands when its lift (max(-cos(phase), 0), see character_rig.gd) returns to the floor,
## i.e. cos(phase) rises through zero, at the forward end of its stride. Stepped by character.gd after
## the pose each physics frame; one rig solve per footfall, none otherwise.

const CharacterRig = preload("res://scenes/character/character_rig.gd")

## Below this walk amount (0..1) a shuffle makes no steps.
const MIN_WALK := 0.2

## Per foot: cos(phase) last frame.
var _last_cos := [1.0, 1.0]


## Check both feet of `character` and report any footfall to `footprints`.
func update(character, footprints: BloodFootprints) -> void:
	var pose = character.pose
	var phase: float = pose.stride_phase()
	for i in 2:
		var c := cos(phase + (0.0 if i == 0 else PI))
		var landed: bool = _last_cos[i] < 0.0 and c >= 0.0 and pose.walk_amount() >= MIN_WALK
		_last_cos[i] = c
		if landed:
			_report(character, footprints, i)


## Solve the rig for a foot that has just landed and hand its sole's geometry to `footprints`.
func _report(character, footprints: BloodFootprints, foot: int) -> void:
	var rig: CharacterRig = character.rig()
	var r: float = character.radius
	var ankle := rig.point(CharacterRig.ANKLE[foot])
	var toes := rig.toes(foot)
	var dir := Vector2(toes.x, toes.y)
	var length := CharacterConfig.body_foot * r
	var width: float = CharacterConfig.body_shoe_widths[0] * r
	var at: Vector2 = character.global_position + Vector2(ankle.x, ankle.y) + dir * length * 0.25
	# Left foot (0) has its arch toward +y of the toe frame, right foot toward -y.
	var inner := 1.0 if foot == 0 else -1.0
	footprints.step(foot, at, dir, length, width, inner, character.get_real_velocity().length())
