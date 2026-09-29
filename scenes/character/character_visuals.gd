extends Node2D

## Character DRAW layer. Renders the body circle and the hands the held item wants shown,
## then lets the item draw its own weapon. Reads the body radius from the character, hand
## positions/size from the hands sibling, and the held item from the character. Appearance
## only — no item-specific weapon logic lives here (that's each Item's draw_weapon()).

@export var body_color: Color = Color(0.32549, 0.65098, 1.0)  ## Body circle fill.
@export var hand_color: Color = Color(1.0, 0.85, 0.4)         ## Hand circle fill.

@onready var _character := get_parent()   ## Character — body radius, held item.
@onready var _hands := $"../Hands"        ## Sibling — hand positions / size.


func _process(_delta: float) -> void:
	queue_redraw()  # facing / items change continuously.


func _draw() -> void:
	# Body: the flesh silhouette deformed by any shots (dents/chunks/cracks + damage
	# darkening), drawn from the character's Deformable impacts like furniture is.
	var r: float = _character.radius
	var deformable = _character._deformable
	var impacts: Array = deformable.impacts if deformable else []
	var damage_total: float = deformable.damage_total if deformable else 0.0
	# Dark-red crack/hole/scorch marks so bullet wounds read as bloody gashes (config-driven).
	Deformation.draw_shape(self, "circle", Vector2(r * 2.0, r * 2.0), body_color, Color.WHITE,
		impacts, damage_total, CharacterConfig.flesh_crack_color, CharacterConfig.flesh_hole_color,
		CharacterConfig.flesh_scorch_color)

	var item: Item = _character.current_item()
	if item == null:
		return
	for hand in item.visible_hands():
		_draw_hand(hand)
	item.draw_weapon(self, _character)


## Draw a single hand circle at the given index (0=left, 1=right).
func _draw_hand(hand: int) -> void:
	var p: Vector2 = _hands.hand_position(hand)
	draw_circle(p, _hands.hand_radius, hand_color)
	draw_arc(p, _hands.hand_radius, 0.0, TAU, 24, Color.WHITE, 1.5, true)
