extends CharacterBody3D

#Настройки 
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 10.0
@export var mouse_sensitivity: float = 0.003 
@export var jump_velocity: float = 4.5

#Шатание
const BOB_FREQ: float = 1.6  # Частота шатания
const BOB_AMP: float = 0.04  # Амплитуда шатания
var t_bob: float = 0.0

#Узлы
@onready var neck = $CameraPivot 
@onready var camera = $CameraPivot/Camera3D

# Гравитация из настроек проекта
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

#Обработка ввода мыши для поворота
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:     
		# Поворот всего CharacterBody3D по оси Y (влево/вправо)
		rotation_degrees.y -= event.relative.x * mouse_sensitivity * 100 
		
		# Поворот узла CameraPivot по оси X (вверх/вниз)
		var new_rot_x = neck.rotation_degrees.x - event.relative.y * mouse_sensitivity * 100
		
		# Ограничение угла взгляда
		neck.rotation_degrees.x = clamp(new_rot_x, -80.0, 80.0)

#Физика движения
func _physics_process(delta):
	# Применяем гравитацию
	if not is_on_floor():
		velocity.y -= gravity * delta
		
	#логика прыжка
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# Получаем направление ввода
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	# Расчет целевой скорости (Ходьба или Бег)
	var target_speed = walk_speed
	if Input.is_action_pressed("sprint"): # Настройте "sprint" в Input Map!
		target_speed = sprint_speed
		
	var direction = Vector3.ZERO
	if input_dir.length() > 0:
		# Преобразуем 2D ввод в 3D направление, учитывая поворот тела
		direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Плавное движение и замедление
	if direction:
		velocity.x = lerp(velocity.x, direction.x * target_speed, delta * 10.0)
		velocity.z = lerp(velocity.z, direction.z * target_speed, delta * 10.0)
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 10.0)
		
	move_and_slide()
	
	# 3. Применяем эффект шатания камеры
	_apply_head_bob(delta, target_speed)

# Функция шатания камеры---
func _apply_head_bob(delta, current_speed):
	var horizontal_velocity = Vector2(velocity.x, velocity.z).length()
	
	if is_on_floor() and horizontal_velocity > 0.1:
		# Шатание ускоряется при беге
		var bob_multiplier = 1.0 if current_speed == walk_speed else 2.0
		t_bob += delta * horizontal_velocity * bob_multiplier

		var new_pos = Vector3.ZERO
		# Вертикальное смещение (Y)
		new_pos.y = sin(t_bob * BOB_FREQ) * BOB_AMP * (current_speed / walk_speed)
		# Горизонтальное смещение (X)
		new_pos.x = cos(t_bob * BOB_FREQ / 2) * BOB_AMP * (current_speed / walk_speed)
		
		# Применяем шатание к локальной позиции узла Camera3D
		camera.position = new_pos
