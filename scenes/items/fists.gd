class_name FistsItem extends Item

## Both fists. F throws a punch, alternating hands each press (the alternation state lives
## here, in the item). No secondary action.

## Which hand punches next: 0 = left, 1 = right.
var _next_hand := 0


func _init() -> void:
	display_name = "Fists"
	reach = 28.0


## Both hands are shown.
func visible_hands() -> Array:
	return [0, 1]


## Punch with the next hand, then swap which hand is next.
func primary(user) -> void:
	user.punch(_next_hand)
	_next_hand = 1 - _next_hand
