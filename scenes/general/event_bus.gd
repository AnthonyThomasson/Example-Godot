extends Node

## General domain: a minimal generic publish/subscribe event bus (autoload). Any domain posts a
## topic + data dict; any domain connects to `posted` and filters by topic. It keeps emitters and
## listeners decoupled — like Despawner, a cross-cutting General autoload every domain may touch
## without a direct reference. The only topic in use is &"hit": the Projectile System posts one per
## damaging hit (`{ position, victim, source, direction, damage }`) and the AI consumes it for
## combat awareness.

## A notification: `topic` names the kind of event, `data` carries its payload.
signal posted(topic: StringName, data: Dictionary)


## Broadcast `data` under `topic` to every connected listener.
func post(topic: StringName, data: Dictionary) -> void:
	posted.emit(topic, data)
