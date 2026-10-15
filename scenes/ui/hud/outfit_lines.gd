extends RefCounted

## UI hud: the lines that list what a character wears, shared by the player debug panel and the spectator inspector. Built
## from the character's `outfit_view()` alone (each garment slot -> its name, each plate slot -> `{ type, name, condition }`),
## one line per slot in the view's order: `Head: Helmet`, `Front plate: Ceramic IV plate 68%`, "—" for nothing worn.


## The outfit lines of `view` (a character's `outfit_view()`); none for an empty view.
static func of(view: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for slot: String in view:
		var label := slot.capitalize()
		label = label.left(1) + label.substr(1).to_lower()  # "Front plate"
		var worn: Variant = view[slot]
		if worn is Dictionary:
			var plate_name := str(worn.get("name", ""))
			var condition := float(worn.get("condition", 0.0))
			out.append("%s: %s" % [label, "%s %d%%" % [plate_name, roundi(condition * 100.0)] if plate_name != "" else "—"])
		else:
			out.append("%s: %s" % [label, str(worn) if str(worn) != "" else "—"])
	return out
