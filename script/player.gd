extends CharacterBody3D

const  SPEED = 5.0
const RUN = 2
const TURN_SPEED = 0.05
const GRAVITY = 30
const SLIDE = 1.0
const CLIMB = 6.0
var run_time = 0.0
var direction_2D : Vector2
var direction_3D : Vector3
var is_slide = false
var slide_time = 0.0
var slide_direction = Vector3.ZERO
var slide_speed = 0.0
var wall_normal = Vector3.ZERO
var can_wall_run = false
var is_wall_run = false
var boost_wall_run = Vector3.ZERO
var is_climb = false


@onready var timer = $Timer
@onready var animation = $AnimationPlayer
@onready var camera = $Camera3D
@onready var collision = $CollisionShape3D
@onready var camera_slide = $Camera3D.position.y
@onready var rayon_haut = $RayHaut
@onready var rayon_bas = $RayBas

func _physics_process(delta: float): 
	direction_2D = Input.get_vector(
	"move_left",
	"move_right",
	"move_forward",
	"move_backward"
	)
	if direction_2D != Vector2.ZERO:
		run_time += delta
	else : run_time = 0.0
	var speed = SPEED
	var target_fov = 90.0
	if run_time > 1.5:
		speed = SPEED * RUN
		target_fov = 110.0
		camera.fov = lerpf(camera.fov, target_fov, 5*delta)
	else : 
		target_fov = 90.0
		camera.fov = lerpf(camera.fov, target_fov, 5*delta)
	
	direction_3D = transform.basis * Vector3(direction_2D.x, 0, direction_2D.y)
	direction_3D = direction_3D.normalized()
	velocity.x = direction_3D.x * speed 
	velocity.z = direction_3D.z * speed
#	if direction_2D.x < 0:
#		self.rotate_y(TURN_SPEED)
#	if direction_2D.x > 0:
#		self.rotate_y(-TURN_SPEED)
		
	#GRAVITY
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		can_wall_run = false
		is_wall_run = false
		boost_wall_run = Vector3.ZERO
		
	#CLIMB
	if Input.is_action_pressed("jump") and rayon_bas.is_colliding() and rayon_haut.is_colliding() == false:
		is_climb = true
		can_wall_run = false
	if is_climb:
		velocity = Vector3(0, CLIMB, 0)
		if rayon_bas.is_colliding() == false:
			is_climb = false
			boost_wall_run = -transform.basis.z * 4
			
		
	#JUMP
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_climb :
		velocity.y = 10
		can_wall_run = true
	if not is_climb:
		wall_run()
	velocity.x += boost_wall_run.x
	velocity.z += boost_wall_run.z
	boost_wall_run = boost_wall_run.move_toward(Vector3.ZERO, 8 * delta)
		
	#SLIDE
	if Input.is_action_just_pressed("slide") and is_on_floor() and direction_2D != Vector2.ZERO and not is_slide:
		is_slide = true
		slide_time = 0.0
		slide_direction = direction_3D
		slide_speed = speed
	if is_slide:
		slide_time += delta
		velocity.x= slide_direction.x * slide_speed
		velocity.z= slide_direction.z * slide_speed
		if slide_time > SLIDE:
			is_slide = false
	#CAMERA
	var target_height = camera_slide
	if is_slide:
		target_height = camera_slide - 0.8
	camera.position.y = lerp(camera.position.y, target_height, 10*delta)
	#COLLISION
	if is_slide:
		collision.shape.height = 1.0
		collision.position.y = -0.5
	else:
		collision.shape.height = 2.0
		collision.position.y = 0.0
		
	#ANIAMTION
	if is_wall_run:
		animation.play("WallRun/mixamo_com")
	elif is_climb:
		animation.play("Climb/mixamo_com")
	elif is_slide:
		animation.play("Slide/mixamo_com")
	elif not is_on_floor():
		animation.play("Jump/mixamo_com",0.2)
	elif direction_2D == Vector2.ZERO:
		animation.play("Idle/mixamo_com",0.2)
	elif run_time > 1.5:
		animation.play("FastRun/mixamo_com")
	else : animation.play("Walking/mixamo_com")
	
	move_and_slide()
	
func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotation_degrees.y -= event.relative.x * 0.5
		$Camera3D.rotation_degrees.x -= event.relative.y * 0.2
		$Camera3D.rotation_degrees.x = clamp(
		$Camera3D.rotation_degrees.x, -80.0, 80.0
		)
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		

func wall_run():
	var angle = 90 - rad_to_deg(direction_3D.angle_to(-get_wall_normal()))
	
	if can_wall_run and not is_on_floor() and is_on_wall() and angle < 48 and run_time > 1.5 and Input.is_action_pressed("move_forward"):
		is_wall_run = true
		can_wall_run = false
		wall_normal = get_wall_normal()
		timer.start()
	if is_wall_run:
		if Input.is_action_just_pressed("jump"):
			velocity.y = 10
			boost_wall_run = wall_normal * 10
			is_wall_run = false
			timer.stop()
		elif is_on_wall() and Input.is_action_pressed("move_forward"):
			wall_normal = get_wall_normal()
			if velocity.y < 0:
				velocity.y = 0
			velocity += -wall_normal * 2
		else:
			is_wall_run = false
			timer.stop()
			


func _on_timer_timeout() -> void:
	if is_wall_run:
		is_wall_run = false
		boost_wall_run = wall_normal * 8
