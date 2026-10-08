class_name Events

# An event is a plain Dictionary: { "type": String, "audience": Array, ...data }.
# audience = the player ids who may see it; an empty array means everyone.
# The server builds events from what happened and sends each player only what they may see.
static func make(type: String, data: Dictionary = {}, audience: Array = []) -> Dictionary:
	var event: Dictionary = data.duplicate()
	event["type"] = type
	event["audience"] = audience
	return event
