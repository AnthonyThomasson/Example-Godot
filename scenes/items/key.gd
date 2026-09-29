class_name KeyItem extends Item

## A plain carryable key: no hands drawn, F and LMB do nothing. It exists only to be present in
## the inventory, gating interactions that list `requires_item` for its slot.

func _init() -> void:
	display_name = "Key"
	reach = 28.0
