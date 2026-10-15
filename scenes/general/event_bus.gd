extends Node

## General domain: a minimal generic publish/subscribe event bus (autoload). Any domain posts a
## topic + data dict; any domain connects to `posted` and filters by topic. It keeps emitters and
## listeners decoupled — like Despawner, a cross-cutting General autoload every domain may touch
## without a direct reference. Topics in use (payloads and consumers: architecture interface 10):
## &"hit" (a damaging hit or a landed punch), &"shot" (a gun fired), &"footfall" (a foot landed),
## &"reload" (a reload started or finished), the grenades' &"throw", &"grenade" (a bounce or rest),
## &"explosion" and &"stun", the vehicles' &"vehicle", &"engine" and &"skid", &"sound" (what Audio
## posts for each sound it makes) and &"callout" (an AI controller's team radio).

## A notification: `topic` names the kind of event, `data` carries its payload.
signal posted(topic: StringName, data: Dictionary)


## Broadcast `data` under `topic` to every connected listener.
func post(topic: StringName, data: Dictionary) -> void:
	posted.emit(topic, data)
