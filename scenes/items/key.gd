class_name KeyItem extends Item

## Items domain: a plain carryable key: the arms hang at the sides, F and LMB do nothing. It exists only to
## be present in the inventory, gating interactions that list `requires_item` for its slot.

func _init() -> void:
	display_name = "Key"
	reach = 28.0
