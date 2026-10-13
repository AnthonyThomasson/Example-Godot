extends Node

## General domain: a minimal generic publish/subscribe event bus (autoload). Any domain posts a
## topic + data dict; any domain connects to `posted` and filters by topic. It keeps emitters and
## listeners decoupled — like Despawner, a cross-cutting General autoload every domain may touch
## without a direct reference. Topics in use: &"hit" — the Projectile System posts one per damaging
## hit and the Character one per landed punch (`{ position, victim, source, direction, damage,
## attacker }` plus `outcome`, `material` and, for bullets, `normal`, `speed_factor`, `gun`, `power`),
## consumed by the AI for combat awareness, by the match HUD and by Audio for impacts; &"shot" (a gun
## fired), &"footfall" (a foot landed) and &"reload" (a reload started or finished), consumed by Audio;
## &"sound" —
## what Audio posts for each sound it makes; and &"callout" — an AI controller's team radio when it
## adopts a combat or investigation decision, consumed by allied AIs.

## A notification: `topic` names the kind of event, `data` carries its payload.
signal posted(topic: StringName, data: Dictionary)


## Broadcast `data` under `topic` to every connected listener.
func post(topic: StringName, data: Dictionary) -> void:
	posted.emit(topic, data)
