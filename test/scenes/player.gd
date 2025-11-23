extends CharacterBody3D

#Настройки 
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 10.0
@export var mouse_sensitivity: float = 0.003 
@export var jump_velocity: float = 4.5

# Рывок (Dash)
@export var dash_speed: float = 25.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 1.5
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO

# Скольжение (Slide) - УВЕЛИЧЕНА СКОРОСТЬ В 1.5 РАЗА
@export var slide_speed: float = 21.0  # Было 12.0, теперь 18.0
@export var slide_duration: float = 1.2
@export var slide_cooldown: float = 2.0
@export var min_slide_velocity: float = 2.0
var is_sliding: bool = false
var slide_timer: float = 0.0
var slide_cooldown_timer: float = 0.0
var original_camera_fov: float
var original_collision_height: float
var original_camera_position: Vector3
var original_neck_position: Vector3
var original_neck_rotation: float

#Шатание
const BOB_FREQ: float = 1.6
const BOB_AMP: float = 0.04
var t_bob: float = 0.0

#Узлы
@onready var neck = $CameraPivot 
@onready var camera = $CameraPivot/Camera3D
@onready var collision_shape = $CollisionShape3D

# Гравитация из настроек проекта
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

#Обработка ввода мыши для поворота
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# СОХРАНЯЕМ ИЗНАЧАЛЬНЫЕ ПОЗИЦИИ ТОЛЬКО ОДИН РАЗ ПРИ ЗАПУСКЕ
	original_camera_fov = camera.fov
	original_collision_height = collision_shape.shape.height
	original_camera_position = camera.position
	original_neck_position = neck.position
	original_neck_rotation = neck.rotation_degrees.x

func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:     
		rotation_degrees.y -= event.relative.x * mouse_sensitivity * 100 
		
		var new_rot_x = neck.rotation_degrees.x - event.relative.y * mouse_sensitivity * 100
		
		if is_sliding:
			neck.rotation_degrees.x = clamp(new_rot_x, -30.0, 30.0)
		else:
			neck.rotation_degrees.x = clamp(new_rot_x, -80.0, 80.0)

#Физика движения
func _physics_process(delta):
	_update_timers(delta)
	_handle_special_actions()
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif not is_dashing and not is_sliding:
		velocity.y = 0
	
	if is_on_floor() and Input.is_action_just_pressed("jump") and not is_dashing and not is_sliding:
		velocity.y = jump_velocity

	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	var target_speed = walk_speed
	if Input.is_action_pressed("sprint") and not is_sliding:
		target_speed = sprint_speed
		
	var direction = Vector3.ZERO
	if input_dir.length() > 0 and not is_dashing:
		direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_dashing:
		velocity.x = dash_direction.x * dash_speed
		velocity.z = dash_direction.z * dash_speed
		velocity.y = 0
		
	elif is_sliding:
		var horizontal_velocity = Vector2(velocity.x, velocity.z)
		
		if direction.length() > 0:
			var target_dir = Vector2(direction.x, direction.z) * slide_speed  # Используем новую увеличенную скорость
			horizontal_velocity = horizontal_velocity.lerp(target_dir, delta * 3.0)
		
		velocity.x = horizontal_velocity.x
		velocity.z = horizontal_velocity.y
		
		velocity.x = lerp(velocity.x, 0.0, delta * 0.8)
		velocity.z = lerp(velocity.z, 0.0, delta * 0.8)
		
	else:
		if direction:
			velocity.x = lerp(velocity.x, direction.x * target_speed, delta * 10.0)
			velocity.z = lerp(velocity.z, direction.z * target_speed, delta * 10.0)
		else:
			velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
			velocity.z = lerp(velocity.z, 0.0, delta * 10.0)
		
	move_and_slide()
	
	if not is_dashing and not is_sliding and is_on_floor():
		_apply_head_bob(delta, target_speed)

# Обновление таймеров
func _update_timers(delta):
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			_end_dash()
	
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta
	
	if is_sliding:
		slide_timer -= delta
		if slide_timer <= 0 or not is_on_floor():
			_end_slide()
	
	if slide_cooldown_timer > 0:
		slide_cooldown_timer -= delta

# Обработка специальных действий
func _handle_special_actions():
	if Input.is_action_just_pressed("dash") and is_on_floor() and not is_dashing and dash_cooldown_timer <= 0 and not is_sliding:
		_start_dash()
	
	if Input.is_action_just_pressed("slide") and _can_slide():
		_start_slide()

# Проверка возможности скольжения
func _can_slide() -> bool:
	if not is_on_floor() or is_sliding or is_dashing or slide_cooldown_timer > 0:
		return false
	
	var horizontal_velocity = Vector2(velocity.x, velocity.z).length()
	if horizontal_velocity < min_slide_velocity:
		return false
	
	return true

# Начало рывка
func _start_dash():
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	if input_dir.length() > 0:
		dash_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	else:
		dash_direction = -transform.basis.z
	
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	
	var tween = create_tween()
	tween.parallel().tween_property(camera, "fov", original_camera_fov + 15.0, 0.1)
	
	Engine.time_scale = 0.7
	await get_tree().create_timer(0.05).timeout
	Engine.time_scale = 1.0

# Завершение рывка
func _end_dash():
	is_dashing = false
	var tween = create_tween()
	tween.tween_property(camera, "fov", original_camera_fov, 0.3)

# Начало скольжения
func _start_slide():
	is_sliding = true
	slide_timer = slide_duration
	slide_cooldown_timer = slide_cooldown
	
	# ОПУСКАЕМ КАМЕРУ ВНИЗ - используем сохраненные изначальные позиции
	var tween = create_tween()
	tween.parallel().tween_property(neck, "position", original_neck_position + Vector3(0, -2.5, 0), 0.2)
	tween.parallel().tween_property(neck, "rotation_degrees:x", 15.0, 0.2)
	tween.parallel().tween_property(camera, "fov", original_camera_fov + 5.0, 0.2)
	
	# Увеличиваем начальную скорость скольжения с новой увеличенной скоростью
	var current_horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var move_dir = Vector2(velocity.x, velocity.z)
	if move_dir.length() == 0:
		move_dir = Vector2(-transform.basis.z.x, -transform.basis.z.z)
	move_dir = move_dir.normalized()
	
	# Используем новую увеличенную slide_speed в расчетах
	var slide_start_speed = max(current_horizontal_speed * 1.2, slide_speed * 0.8)
	velocity.x = move_dir.x * slide_start_speed
	velocity.z = move_dir.y * slide_start_speed

# Завершение скольжения
func _end_slide():
	if not is_sliding:
		return
		
	is_sliding = false
	
	# ВОЗВРАЩАЕМ КАМЕРУ В ИЗНАЧАЛЬНОЕ ПОЛОЖЕНИЕ (которое сохранили в _ready())
	var tween = create_tween()
	tween.parallel().tween_property(neck, "position", original_neck_position, 0.4)
	tween.parallel().tween_property(neck, "rotation_degrees:x", original_neck_rotation, 0.4)
	tween.parallel().tween_property(camera, "fov", original_camera_fov, 0.4)
	
	# Сбрасываем позицию камеры для шатания
	camera.position = original_camera_position

# Функция шатания камеры
func _apply_head_bob(delta, current_speed):
	var horizontal_velocity = Vector2(velocity.x, velocity.z).length()
	
	if horizontal_velocity > 0.1:
		var bob_multiplier = 1.0 if current_speed == walk_speed else 1.8
		t_bob += delta * horizontal_velocity * bob_multiplier

		var new_pos = Vector3.ZERO
		new_pos.y = sin(t_bob * BOB_FREQ) * BOB_AMP * (current_speed / walk_speed)
		new_pos.x = cos(t_bob * BOB_FREQ / 2) * BOB_AMP * (current_speed / walk_speed)
		
		camera.position = original_camera_position + new_pos
	else:
		camera.position = camera.position.lerp(original_camera_position, delta * 5.0)
		t_bob = 0.0
