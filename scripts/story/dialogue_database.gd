class_name DialogueDatabase
extends RefCounted
## Authored story content. Pure data: every conversation is a dictionary in
## DIALOGUES keyed by stable StringName id. No parsing, no file IO -- the
## campaign grows by adding entries here (or swapping in a JSON-backed
## subclass later without touching the runtime).

const DIALOGUES := {
	&"safehouse_first_night": {
		"speaker": &"marcus",
		"lines": [
			"That was too close. They followed us for three streets.",
			"Board the windows. Anything that moans stays outside tonight.",
		],
		"choices": [
			{"text": "I'll take first watch.", "next": &"", "set_flag": &"story_watch_taken"},
			{"text": "We should keep moving at dawn.", "next": &"safehouse_dawn_plan", "set_flag": &"story_moving_on"},
		],
	},
	&"safehouse_dawn_plan": {
		"speaker": &"marcus",
		"lines": [
			"Dawn it is. The old tram depot might have supplies.",
			"Stay near the walls -- the streets belong to them after dark.",
		],
		"choices": [],
	},
	&"trader_vaclav_greeting": {
		"speaker": &"vaclav",
		"lines": [
			"You look like someone who still pays in batteries.",
			"Bandages, canned peaches, half a rifle. Take your pick.",
		],
		"choices": [
			{"text": "What do you want for the rifle?", "next": &"trader_rifle_price", "set_flag": &""},
			{"text": "Just passing through.", "next": &"", "set_flag": &"story_snubbed_vaclav"},
		],
	},
	&"trader_rifle_price": {
		"speaker": &"vaclav",
		"lines": [
			"Two med kits and we forget you ever pointed that thing at me.",
		],
		"choices": [],
	},
	&"survivor_plea": {
		"speaker": &"stranger",
		"lines": [
			"Please -- they're inside the pharmacy with my brother.",
			"I can pay. I can pay anything.",
		],
		"choices": [
			{"text": "Show me the pharmacy.", "next": &"", "set_flag": &"quest_pharmacy_accepted"},
			{"text": "Not my problem.", "next": &"", "set_flag": &"quest_pharmacy_refused"},
		],
	},
}

## Validates referential integrity: every next-id must resolve.
static func validate() -> Array[String]:
	var errors: Array[String] = []
	for id: StringName in DIALOGUES:
		var entry: Dictionary = DIALOGUES[id]
		if (entry["lines"] as Array).is_empty():
			errors.append("dialogue %s has no lines" % String(id))
		for choice_variant: Variant in entry["choices"]:
			var choice: Dictionary = choice_variant
			var next: StringName = choice["next"]
			if next != &"" and not DIALOGUES.has(next):
				errors.append("dialogue %s branches to unknown %s" % [String(id), String(next)])
	return errors

static func has(id: StringName) -> bool:
	return DIALOGUES.has(id)

static func get_entry(id: StringName) -> Dictionary:
	return DIALOGUES.get(id, {})
