extends RayCast3D

@onready var prompt = $Prompt

func _physics_process(delta: float) -> void:
	# Initial prompt text
	prompt.text = ""
	
	# Check if InteractRay is colliding with an object
	if is_colliding():
		# Get the object InteractRay is colliding with
		var collider = get_collider()
		
		# Check if the object is interactable
		if collider is Interactable:
			# Get the object's prompt text
			prompt.text = collider.get_prompt()

			# Interact with the object when its interact key is pressed
			if Input.is_action_just_pressed(collider.prompt_input):
				collider.interact(owner)
