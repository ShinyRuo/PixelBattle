extends CharacterBody2D
## 玩家角色：八向移动。
##
## 这是最小可跑示例，用来验证「改代码 → 命令行自检 → 看到结果」的闭环。
## 注意 GDScript 用 Tab 缩进（gdformat 会强制），别用空格。

## 移动速度（像素/秒）。@export 让它出现在编辑器 Inspector 面板里，
## 相当于 UE 的 UPROPERTY(EditAnywhere)。
@export var speed: float = 220.0


## 每物理帧调用，相当于 UE 的 Tick（固定 60Hz，不受帧率影响）。
func _physics_process(_delta: float) -> void:
	# ui_left/right/up/down 是 Godot 内置输入动作，WASD 和方向键都已绑定。
	# 自定义动作（如 attack）请在编辑器 Project Settings > Input Map 里加，
	# 不要手写进 project.godot —— 那段序列化格式跨版本很脆。
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * speed
	move_and_slide()
