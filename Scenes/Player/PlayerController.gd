## ProtoController v1.0 by Brackeys
## CC0 License
## Intended for rapid prototyping of first-person games.
## Happy prototyping!

extends CharacterBody3D

# -------------------------------------------------------------
# -- EXPORTS: Tuning Variables
# -------------------------------------------------------------

@export var can_move : bool = true
@export var has_gravity : bool = true
@export var can_jump : bool = true
@export var can_sprint : bool = false
@export var can_crouch : bool = false
@export var can_freefly : bool = false

@export_group("View Bob")
@export var enable_bobbing : bool = false
@export var bob_frequency : float = 4.0
@export var crouch_bob_frequency : float = 3.0
@export var bob_amplitude : float = 0.2

@export_group("Speeds")
@export var look_speed : float = 0.002
@export var base_speed : float = 7.0
@export var jump_velocity : float = 5.5
@export var sprint_speed : float = 10.0
@export var crouch_speed: float = 4.0
@export var freefly_speed : float = 25.0

@export_group("Input Actions")
@export var input_left : String = "ui_left"
@export var input_right : String = "ui_right"
@export var input_forward : String = "ui_up"
@export var input_back : String = "ui_down"
@export var input_jump : String = "ui_accept"
@export var input_sprint : String = "sprint"
@export var input_freefly : String = "freefly"
@export var input_crouch : String = "crouch"

@export_group("Crouch")
@export var crouch_height : float = 0.8
@export var crouch_transition_speed : float = 6.0

@export_group("Gravity")
@export var fall_multiplier := 2.0

# -------------------------------------------------------------
# -- INTERNAL STATE
# -------------------------------------------------------------

# Mouse and look
var mouse_captured : bool = false
var look_rotation : Vector2

# Movement
var move_speed : float = 0.0
var freeflying : bool = false
var is_crouching : bool = false

# Head bobbing
var bob_timer : float = 0.0

# Head positions
var default_head_pos : Vector3
var crouch_head_pos : Vector3

# Step snapping
const MAX_STEP_HEIGHT = 0.5
var _snapped_to_stairs_last_frame := false
var _last_frame_was_on_floor = -INF

# Standing shape for crouch checks
var stand_shape: CapsuleShape3D
var stand_query: PhysicsShapeQueryParameters3D

# -------------------------------------------------------------
# -- NODES (Cached References)
# -------------------------------------------------------------

@onready var head: Node3D = $Head
@onready var standing_collider: CollisionShape3D = $StandingCollider
@onready var crouch_collider: CollisionShape3D = $CrouchCollider

# -------------------------------------------------------------
# -- READY
# -------------------------------------------------------------

func _ready() -> void:
	check_input_mappings()
	
	# Initialize look rotation
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x
	
	# Setup head positions
	default_head_pos = head.position
	crouch_head_pos = default_head_pos + Vector3(0, -crouch_height, 0)

	# Setup standing collider duplicate for crouch standing test
	stand_shape = (standing_collider.shape as CapsuleShape3D).duplicate()
	stand_query = PhysicsShapeQueryParameters3D.new()
	stand_query.shape = stand_shape
	stand_query.collision_mask = collision_layer
	stand_query.collide_with_areas = false
	stand_query.collide_with_bodies = true
	stand_query.exclude = [self]

# -------------------------------------------------------------
# -- INPUT HANDLING
# -------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Capture/release mouse
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		capture_mouse()
	if Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()
	
	# Mouse look
	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)
	
	# Toggle freefly mode
	if can_freefly and Input.is_action_just_pressed(input_freefly):
		if not freeflying:
			enable_freefly()
		else:
			disable_freefly()

# -------------------------------------------------------------
# -- PHYSICS PROCESS
# -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_on_floor(): 
		_last_frame_was_on_floor = Engine.get_physics_frames()

	if can_freefly and freeflying:
		handle_freefly_movement(delta)
		return

	handle_crouching()
	handle_gravity(delta)
	handle_jumping()
	handle_movement()

	handle_head_bobbing(delta)
	
	if not _snap_up_stairs_check(delta):
		move_and_slide()
		_snap_down_to_stairs_check()

# -------------------------------------------------------------
# -- MOVEMENT HELPERS
# -------------------------------------------------------------

func handle_freefly_movement(delta: float) -> void:
	var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
	var motion := (head.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	motion *= freefly_speed * delta
	move_and_collide(motion)

func handle_crouching() -> void:
	var holding_crouch = can_crouch and Input.is_action_pressed(input_crouch)
	var should_crouch = holding_crouch or (is_crouching and not can_stand())
	
	if should_crouch != is_crouching:
		is_crouching = should_crouch
		standing_collider.disabled = is_crouching
		crouch_collider.disabled = not is_crouching

func handle_gravity(delta: float) -> void:
	if has_gravity and not (is_on_floor() or _snapped_to_stairs_last_frame):
		velocity += get_gravity() * delta
		# Uncomment if you want stronger gravity when falling:
		#if velocity.y < 0:
		#	velocity += get_gravity() * (fall_multiplier - 1) * delta

func handle_jumping() -> void:
	if can_jump and Input.is_action_just_pressed(input_jump) and not is_crouching and (is_on_floor() or _snapped_to_stairs_last_frame):
		velocity.y = jump_velocity

func handle_movement() -> void:
	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		if move_dir:
			move_speed = crouch_speed if is_crouching else (sprint_speed if (Input.is_action_pressed(input_sprint) and can_sprint)else base_speed)
			velocity.x = move_dir.x * move_speed
			velocity.z = move_dir.z * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)
	else:
		velocity.x = 0
		velocity.y = 0

func handle_head_bobbing(delta: float) -> void:
	var base_pos : Vector3 = crouch_head_pos if is_crouching else default_head_pos
	var bob_offset : float = 0.0
	
	if enable_bobbing and (is_on_floor() or _snapped_to_stairs_last_frame):
		var horiz_speed = Vector2(velocity.x, velocity.z).length()
		if horiz_speed > 0.1:
			bob_timer += delta * (bob_frequency if not is_crouching else crouch_bob_frequency)
			bob_offset = sin(bob_timer * TAU) * bob_amplitude
		else:
			bob_timer = 0.0
	else:
		bob_timer = 0.0
	
	var target_pos : Vector3 = base_pos + Vector3(0, bob_offset, 0)
	head.position = head.position.lerp(target_pos, crouch_transition_speed * delta)

# -------------------------------------------------------------
# -- ROTATION
# -------------------------------------------------------------

func rotate_look(rot_input: Vector2) -> void:
	look_rotation.x -= rot_input.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85), deg_to_rad(85))
	look_rotation.y -= rot_input.x * look_speed
	
	transform.basis = Basis()
	rotate_y(look_rotation.y)
	
	head.transform.basis = Basis()
	head.rotate_x(look_rotation.x)

# -------------------------------------------------------------
# -- FREEFLY MODE
# -------------------------------------------------------------

func enable_freefly():
	standing_collider.disabled = true
	crouch_collider.disabled = true
	freeflying = true
	velocity = Vector3.ZERO

func disable_freefly():
	standing_collider.disabled = false
	crouch_collider.disabled = false
	freeflying = false

# -------------------------------------------------------------
# -- MOUSE CAPTURE
# -------------------------------------------------------------

func capture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true

func release_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false

# -------------------------------------------------------------
# -- CROUCH STAND CHECK
# -------------------------------------------------------------

func can_stand() -> bool:
	stand_query.transform = standing_collider.global_transform
	var hits = get_world_3d().direct_space_state.intersect_shape(stand_query, 1)
	return hits.size() == 0

# -------------------------------------------------------------
# -- STEP HANDLING
# -------------------------------------------------------------

func _snap_down_to_stairs_check() -> void:
	var did_snap := false
	%StairsBelowRayCast3D.force_raycast_update()
	var floor_below = %StairsBelowRayCast3D.is_colliding() and not is_surface_too_steep(%StairsBelowRayCast3D.get_collision_normal())
	var was_on_floor_last_frame = Engine.get_physics_frames() == _last_frame_was_on_floor
	
	if not is_on_floor() and velocity.y <= 0 and (was_on_floor_last_frame or _snapped_to_stairs_last_frame) and floor_below:
		var body_test_result = KinematicCollision3D.new()
		if self.test_move(self.global_transform, Vector3(0, -MAX_STEP_HEIGHT, 0), body_test_result):
			self.position.y += body_test_result.get_travel().y
			apply_floor_snap()
			did_snap = true
	
	_snapped_to_stairs_last_frame = did_snap

func _snap_up_stairs_check(delta: float) -> bool:
	if not is_on_floor() and not _snapped_to_stairs_last_frame: return false
	if velocity.y > 0 or (velocity * Vector3(1,0,1)).length() == 0: return false
	
	var expected_move_motion = velocity * Vector3(1,0,1) * delta
	var step_pos_with_clearance = global_transform.translated(expected_move_motion + Vector3(0, MAX_STEP_HEIGHT * 2, 0))
	var down_check_result = KinematicCollision3D.new()

	if self.test_move(step_pos_with_clearance, Vector3(0, -MAX_STEP_HEIGHT * 2, 0), down_check_result) and (down_check_result.get_collider().is_class("StaticBody3D") or down_check_result.get_collider().is_class("CSGShape3D")):
		var step_height = ((step_pos_with_clearance.origin + down_check_result.get_travel()) - global_position).y
		if step_height > MAX_STEP_HEIGHT or step_height <= 0.01 or (down_check_result.get_position() - global_position).y > MAX_STEP_HEIGHT:
			return false
		
		%StairsAheadRayCast3D.global_position = down_check_result.get_position() + Vector3(0, MAX_STEP_HEIGHT, 0) + expected_move_motion.normalized() * 0.1
		%StairsAheadRayCast3D.force_raycast_update()

		if %StairsAheadRayCast3D.is_colliding() and not is_surface_too_steep(%StairsAheadRayCast3D.get_collision_normal()):
			global_position = step_pos_with_clearance.origin + down_check_result.get_travel()
			apply_floor_snap()
			_snapped_to_stairs_last_frame = true
			return true

	return false

func is_surface_too_steep(normal: Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > self.floor_max_angle

# -------------------------------------------------------------
# -- INPUT MAPPING VALIDATION
# -------------------------------------------------------------

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
	if can_crouch and not InputMap.has_action(input_crouch):
		push_error("Crouch disabled. No InputAction found for input_crouch: " + input_crouch)
		can_crouch = false
