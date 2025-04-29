# Interactable class that extends CollisionObject3D
extends CollisionObject3D
class_name Interactable

# Interaction signal
signal interacted(body)

# Export variables to inspector
@export var prompt_message = "Interact"
@export var prompt_input = "interact"

# Function for getting the Interactable's prompt
func get_prompt():
	var key_name = ""
	# Get Interactable's "ineract" key
	for action in InputMap.action_get_events(prompt_input):
		if action is InputEventKey:
			key_name = action.as_text_physical_keycode()
	# Return custom prompt message with Interactable's "interact" key
	return prompt_message + " [" + key_name + "]"

# Base Interactable interact function
func interact(body):
	print(body.name, " interacted with ", name)
	interacted.emit(body) # Emit the interacted signal with the body as parameter

# Function to dynamically set the prompt message
func set_prompt(new_prompt_message: String):
	prompt_message = new_prompt_message
