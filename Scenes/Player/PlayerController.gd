# ProtoController v1.0 by Brackeys
# CC0 License
# Intended for rapid prototyping of first-person games.
# Happy prototyping!

extends CharacterBody3D

## Can we move around?
@export var can_move : bool = true
## Are we affected by gravity?
@export var has_gravity : bool = true
## Can we press to jump?
@export var can_jump : bool = true
## Can we hold to run?
@export var can_sprint : bool = false
## Can we hold to crouch?
@export var can_crouch : bool = false
## Can we press to enter freefly mode (noclip)?
@export var can_freefly : bool = false

@export_group("View Bob")
## Enable or disable head bobbing
@export var enable_bobbing : bool  = false
## How fast the head bobs (cycles per second of movement)
@export var bob_frequency : float = 4.0
## How tall each bob is
@export var bob_amplitude : float = 0.2
# Internal timer for head bobbing
var bob_timer : float = 0.0

@export_group("Speeds")
## Look around rotation speed.
@export var look_speed : float = 0.002
## Normal speed.
@export var base_speed : float = 7.0
## Speed of jump.
@export var jump_velocity : float = 5.5
## How fast do we run?
@export var sprint_speed : float = 10.0
## How fast do we move when crouched?
@export var crouch_speed: float = 4.0
## How fast do we freefly?
@export var freefly_speed : float = 25.0

@export_group("Input Actions")
## Name of Input Action to move Left.
@export var input_left : String = "ui_left"
## Name of Input Action to move Right.
@export var input_right : String = "ui_right"
## Name of Input Action to move Forward.
@export var input_forward : String = "ui_up"
## Name of Input Action to move Backward.
@export var input_back : String = "ui_down"
## Name of Input Action to Jump.
@export var input_jump : String = "ui_accept"
## Name of Input Action to Sprint.
@export var input_sprint : String = "sprint"
## Name of Input Action to toggle freefly mode.
@export var input_freefly : String = "freefly"
## Name of Input Action to crouch.
@export var input_crouch : String = "crouch"

@export_group("Crouch")
## How far to lower the camera when crouching
@export var crouch_height : float = 0.8
## How quickly to transition in/out of crouch
@export var crouch_transition_speed : float = 6.0

@export_group("Gravity")
## How quickly the player descends when falling
@export var fall_multiplier := 2.0

var mouse_captured : bool = false
var look_rotation : Vector2
var move_speed : float = 0.0
var freeflying : bool = false
var is_crouching : bool = false
var default_head_pos : Vector3
var crouch_head_pos  : Vector3

## IMPORTANT REFERENCES
@onready var head: Node3D = $Head
@onready var standing_collider: CollisionShape3D = $StandingCollider
@onready var crouch_collider: CollisionShape3D = $CrouchCollider

# variables for crouching and standing
var stand_shape: CapsuleShape3D
var stand_query: PhysicsShapeQueryParameters3D

func _ready() -> void:
	check_input_mappings()
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x

	# Head positions for standing and crouching states
	default_head_pos = head.position
	crouch_head_pos  = default_head_pos + Vector3(0, -crouch_height, 0)
	
	# Duplicate the standing collider’s shape for detecting collisions
	stand_shape = (standing_collider.shape as CapsuleShape3D).duplicate()

	# Prepare a reusable query parameters object for checking if the player can stand
	stand_query = PhysicsShapeQueryParameters3D.new()
	stand_query.shape = stand_shape
	stand_query.collision_mask = collision_layer
	stand_query.collide_with_areas = false
	stand_query.collide_with_bodies = true
	stand_query.exclude = [self]


# Function for checking if the character can stand
func can_stand() -> bool:
	# Keep the query transform synced to where the stand collider *would* be
	stand_query.transform = standing_collider.global_transform
	# Check if character's standing mesh is intersecting with any object
	# Any intersection means the character can't stand
	var hits = get_world_3d().direct_space_state.intersect_shape(stand_query, 1)
	return hits.size() == 0

func _unhandled_input(event: InputEvent) -> void:
	# Mouse capturing
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		capture_mouse()
	if Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()
	
	# Look around
	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)
	
	# Toggle freefly mode
	if can_freefly and Input.is_action_just_pressed(input_freefly):
		if not freeflying:
			enable_freefly()
		else:
			disable_freefly()


func _physics_process(delta: float) -> void:
	# If freeflying, handle freefly and nothing else
	if can_freefly and freeflying:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var motion := (head.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		motion *= freefly_speed * delta
		move_and_collide(motion)
		return
	
	# Check if the player is holding crouch
	var holding_crouch = can_crouch and Input.is_action_pressed(input_crouch)
	
	# Check if the player's character should be crouching
	var should_crouch = holding_crouch or (is_crouching and not can_stand())
	
	# Switch collision models when character is crouched/standing
	if should_crouch != is_crouching:
		is_crouching = should_crouch
		standing_collider.disabled = is_crouching
		crouch_collider.disabled = not is_crouching

	# Apply gravity to velocity
	if has_gravity:
		if not is_on_floor():
			# Apply base gravity
			velocity += get_gravity() * delta
			
			# Apply additional acceleration when falling
			#if velocity.y < 0:
				#velocity += get_gravity() * (fall_multiplier - 1) * delta

	# Apply jumping
	if can_jump:
		if Input.is_action_just_pressed(input_jump) and not is_crouching and is_on_floor():
			velocity.y = jump_velocity

	# Modify speed based on crouching
	if is_crouching:
		move_speed = crouch_speed
	# Modify speed based on sprinting
	elif can_sprint and Input.is_action_pressed(input_sprint):
		move_speed = sprint_speed
	else:
		move_speed = base_speed

	# Apply desired movement to velocity
	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if move_dir:
			velocity.x = move_dir.x * move_speed
			velocity.z = move_dir.z * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)
	else:
		velocity.x = 0
		velocity.y = 0

	# Logic for character head bobbing
	var base_pos : Vector3 = crouch_head_pos if is_crouching else default_head_pos
	
	var bob_offset : float = 0.0
	if enable_bobbing and is_on_floor():
		# Only bob if character is moving forward/back/strafe
		var horiz_speed = Vector2(velocity.x, velocity.z).length()
		if horiz_speed > 0.1:
			# Advance timer while player is moving (frequency cycles per second)
			bob_timer += delta * bob_frequency
			# Calculate head bob offset smoothly with sin function
			bob_offset = sin(bob_timer * TAU) * bob_amplitude
		else:
			# Reset timer when you stop
			bob_timer = 0.0
	else:
		bob_timer = 0.0
	
	# Calculate & apply head target position
	var target_pos : Vector3 = base_pos + Vector3(0, bob_offset, 0) # Apply head bob position
	head.position = head.position.lerp(target_pos, crouch_transition_speed * delta)
	
	# Use velocity to actually move
	move_and_slide()


## Rotate us to look around.
## Base of controller rotates around y (left/right). Head rotates around x (up/down).
## Modifies look_rotation based on rot_input, then resets basis and rotates by look_rotation.
func rotate_look(rot_input : Vector2):
	look_rotation.x -= rot_input.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85), deg_to_rad(85))
	look_rotation.y -= rot_input.x * look_speed
	transform.basis = Basis()
	rotate_y(look_rotation.y)
	head.transform.basis = Basis()
	head.rotate_x(look_rotation.x)


func enable_freefly():
	standing_collider.disabled = true
	crouch_collider.disabled = true
	freeflying = true
	velocity = Vector3.ZERO


func disable_freefly():
	standing_collider.disabled = false
	crouch_collider.disabled = false
	freeflying = false


func capture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func release_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false


## Checks if some Input Actions haven't been created.
## Disables functionality accordingly.
func check_input_mappings():
	if can_move and not InputMap.has_action(input_left):
		push_error("Movement disabled. No InputAction found for input_left: " + input_left)
		can_move = false
	if can_move and not InputMap.has_action(input_right):
		push_error("Movement disabled. No InputAction found for input_right: " + input_right)
		can_move = false
	if can_move and not InputMap.has_action(input_forward):
		push_error("Movement disabled. No InputAction found for input_forward: " + input_forward)
		can_move = false
	if can_move and not InputMap.has_action(input_back):
		push_error("Movement disabled. No InputAction found for input_back: " + input_back)
		can_move = false
	if can_jump and not InputMap.has_action(input_jump):
		push_error("Jumping disabled. No InputAction found for input_jump: " + input_jump)
		can_jump = false
	if can_sprint and not InputMap.has_action(input_sprint):
		push_error("Sprinting disabled. No InputAction found for input_sprint: " + input_sprint)
		can_sprint = false
	if can_freefly and not InputMap.has_action(input_freefly):
		push_error("Freefly disabled. No InputAction found for input_freefly: " + input_freefly)
		can_freefly = false
	# New: verify crouch action exists
	if can_crouch and not InputMap.has_action(input_crouch):
		push_error("Crouch disabled. No InputAction found for input_crouch: " + input_crouch)
		can_crouch = false
