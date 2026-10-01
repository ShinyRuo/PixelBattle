# Godot 上手笔记（写给 UE / C++ 出身的人）

从 UE5 转过来，语法是小问题，**心智模型才是**。这份笔记按「哪里不一样」组织，
不重复官方文档能查到的 API 细节。

---

## 一句话心智模型

> **UE**：Actor 是容器，Component 挂在上面提供能力，Level 摆 Actor，Blueprint 是可实例化的类。
> **Godot**：万物皆 Node，能力靠**子节点**提供，Scene 是一棵 Node 树——它既是关卡，也是预制体，
> 二者没有区别。

「场景即预制体」是最大的一处认知切换。UE 里 `.umap`（关卡）和 `BP_Enemy`（蓝图类）
是两种东西；Godot 里它们都是 `.tscn`，可以互相嵌套，一个场景可以被实例化进另一个场景。

---

## 概念对照表

| UE5                         | Godot 4                                          | 备注                                  |
| --------------------------- | ------------------------------------------------ | ------------------------------------- |
| `AActor`                  | `Node` / `Node2D`                            | 没有 Actor/Component 二分，全是 Node  |
| `UActorComponent`         | 子 Node                                          | 组合靠父子关系，不是`AddComponent`  |
| Level`.umap`              | Scene`.tscn`                                   |                                       |
| Blueprint 类`BP_Enemy`    | Scene`.tscn` + 脚本                            | **同一种东西**                  |
| `SpawnActor<T>()`         | `preload(...).instantiate()` + `add_child()` | 两步，显式                            |
| `UPROPERTY(EditAnywhere)` | `@export`                                      |                                       |
| `Tick(DeltaTime)`         | `_process(delta)`                              | 每渲染帧                              |
| 物理 Tick                   | `_physics_process(delta)`                      | 固定 60Hz                             |
| `BeginPlay()`             | `_ready()`                                     | 子节点全就绪后调用一次                |
| 构造函数                    | `_init()`                                      | 此时还没进场景树                      |
| `EndPlay` / `Destroyed` | `_exit_tree()`                                 |                                       |
| Event Dispatcher / Delegate | `signal`                                       | 语法轻得多                            |
| `Cast<AEnemy>(Obj)`       | `obj as Enemy` / `obj is Enemy`              |                                       |
| `Destroy()`               | `queue_free()`                                 | **不是 `free()`**，见下方坑位 |
| `UDataTable`              | `Resource` (`.tres`) 或 JSON                 |                                       |
| `TSharedPtr<T>` 管的对象  | `RefCounted`                                   | 引用计数，自动释放。见下节            |
| 裸`new` / `delete`      | `Object`                                       | 必须自己`free()`，日常别用          |
| `UGameInstance` 单例      | Autoload（自动加载的单例节点）                   |                                       |
| Overlap Volume              | `Area2D`                                       |                                       |
| `UGameplayStatics`        | `get_tree()` / 全局单例                        |                                       |
| `Content/`                | `res://`                                       | 只读，打包后进 pck                    |
| `Saved/`                  | `user://`                                      | 可写，存档放这                        |
| `.uasset`（二进制）       | `.tscn` / `.tres`（**文本**）          | 可 diff、可 merge、可手改             |
| C++ 模块 + 编译             | GDScript（免编译）或 GDExtension（C++）          |                                       |

---

## 三种内存模型：`Object` / `RefCounted` / `Node`

教程里满屏都是 `Node`，容易以为 Godot 只有这一种对象。其实有三条继承线，
**选错了要么泄漏、要么白白背上场景树的开销**。

```
Object                    ← 手动管理，必须自己 free()
├── RefCounted            ← 自动引用计数，没人引用就自动没了
│   └── Resource          ← + 能存成 .tres、能 load()
│       ├── PackedScene / Texture2D / …
│       └──（你自己的数据表类）
└── Node                  ← 进场景树，用 queue_free()
    ├── Node2D → Sprite2D / CharacterBody2D / …
    └── Control → Button / Label / …
```

|                | 需要场景树 | 怎么释放                   | 创建开销                       |
| -------------- | ---------- | -------------------------- | ------------------------------ |
| `Object`     | 否         | **手动 `free()`**  | 小                             |
| `RefCounted` | 否         | **自动**（引用计数） | 小                             |
| `Node`       | 是         | `queue_free()`           | 大（名字、分组、树簿记、信号） |

### `RefCounted` 用起来就是「不用管」

```gdscript
var wave := PBWave.new()
# ……用完不管它。变量出作用域 → 引用计数归零 → 立刻析构
```

没有对应的 `free()`。引擎自带的 `RandomNumberGenerator`、`Image`、
`Mutex` 之类也都是 `RefCounted`，`.new()` 出来就不用再操心。

**本项目 `src/core/` 全部是 `RefCounted`**，所以一行释放代码都没有 ——
跑一次批量模拟会创建几十万个对象，全靠引用计数收掉。
理由见 [代码导读.md](代码导读.md) 第 0 节。

### 不写 `extends` 默认就是 `RefCounted`

```gdscript
class_name Foo        # 没有 extends 这一行 → 隐式 extends RefCounted
```

### 和 UE 的 GC 有一个本质差别

UE 的 `UObject` 走**标记-清除式 GC**，能回收循环引用。
Godot 的 `RefCounted` 是**引用计数**，**收不掉环** —— 见下方坑位。

---

## 节点与场景：三个反直觉的点

### 1. 「加个组件」= 「加个子节点」

UE 里给角色加碰撞是 `CreateDefaultSubobject<UCapsuleComponent>`。
Godot 里就是在场景树里挂一个 `CollisionShape2D` 子节点：

```
Player (CharacterBody2D)      ← 脚本挂在这
├── Body (Polygon2D)          ← 外观
├── Collision (CollisionShape2D)  ← 碰撞
├── Camera (Camera2D)         ← 跟随相机
└── AttackTimer (Timer)       ← 定时器也是节点
```

节点自带能力，**没有单独的 Component 概念**。想复用一组节点，就把它们存成一个 `.tscn`。

### 2. 场景可以无限嵌套，且能「局部覆盖」

把 `Enemy.tscn` 拖进 `Level.tscn`，就是一个实例。在实例上改属性（比如血量），
改动只写进 `Level.tscn`（记为 override），`Enemy.tscn` 本身不动——和 UE 的
Blueprint 实例覆盖是一个意思，但它是纯文本，你能直接看到改了什么。

### 3. 脚本 `extends` 的是节点类型，不是自定义基类

```gdscript
extends CharacterBody2D    # 这个脚本"就是"一个 CharacterBody2D
class_name Player          # 可选：注册全局类名，别处能直接 `Player.new()`
```

没有 .h/.cpp 分离，没有反射宏，没有 CDO。一个文件就是一个类。

---

## 生命周期

```gdscript
func _init() -> void:            # 构造。还没进场景树，$子节点 全是 null
func _enter_tree() -> void:      # 进入场景树
func _ready() -> void:           # 所有子节点就绪，只调一次 ← 初始化写这里
func _process(delta) -> void:    # 每渲染帧（帧率不固定）
func _physics_process(delta):    # 每物理帧（固定 60Hz）← 移动、碰撞写这里
func _input(event) -> void:      # 输入事件
func _exit_tree() -> void:       # 离开场景树
```

`@onready var x = $Child` 的赋值时机在 `_ready()` **之前**，所以 `_init()` 里访问不到。

---

## 2D 常用节点速查

| 节点                                | 用途                                              |
| ----------------------------------- | ------------------------------------------------- |
| `Node2D`                          | 2D 基类，有 position / rotation / scale           |
| `CharacterBody2D`                 | 玩家、敌人。配`velocity` + `move_and_slide()` |
| `RigidBody2D`                     | 交给物理引擎推的物体                              |
| `StaticBody2D`                    | 墙、地面                                          |
| `Area2D`                          | 触发器。信号`body_entered` / `area_entered`   |
| `CollisionShape2D`                | 碰撞形状，必须是上面几种 Body 的子节点            |
| `Sprite2D` / `AnimatedSprite2D` | 静态图 / 帧动画                                   |
| `TileMapLayer`                    | 瓦片地图（4.3 起取代了旧的`TileMap`）           |
| `Camera2D`                        | 相机，挂在玩家下面就自动跟随                      |
| `CanvasLayer`                     | UI 层，不受相机移动影响                           |
| `Control`                         | 所有 UI 控件的基类                                |
| `Timer`                           | 定时器，信号`timeout`                           |
| `AnimationPlayer`                 | 关键帧动画，能驱动**任意属性**（不止变换）  |

---

## GDScript 语法速查

缩进即代码块（**Tab**），无分号无大括号。

```gdscript
extends Node2D
class_name Enemy

# ── 信号（相当于 Event Dispatcher）────────────────────────
signal died(cause: String)

# ── 枚举 ──────────────────────────────────────────────────
enum State { IDLE, CHASE, ATTACK }

# ── 常量 ──────────────────────────────────────────────────
const MAX_HP := 100                          # := 类型推断
const BulletScene := preload("res://scenes/bullet.tscn")   # 编译期加载

# ── 导出到 Inspector ──────────────────────────────────────
@export var speed: float = 120.0
@export_range(0, 10) var damage: int = 3
@export var target: Node2D                   # 可以直接在编辑器里拖引用

# ── 成员变量 ──────────────────────────────────────────────
var hp: int = MAX_HP
var _state: State = State.IDLE               # _ 前缀 = 私有约定

# ── @onready：等场景树就绪后才求值 ────────────────────────
@onready var sprite: Sprite2D = $Sprite2D
@onready var hitbox: Area2D = %Hitbox        # % = 场景唯一名，不怕改路径


func _ready() -> void:
	hitbox.body_entered.connect(_on_hitbox_body_entered)


func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		died.emit("damage")                  # 发信号
		queue_free()


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body is Player:                       # 类型判断
		(body as Player).take_damage(damage) # 类型转换
```

### 和 C++ 的差异点

| 事项       | GDScript                                                      |
| ---------- | ------------------------------------------------------------- |
| 分支       | `if / elif / else`，`match`（比 switch 强，能匹配模式）   |
| 循环       | `for i in range(10):`、`for node in children:`、`while` |
| 数组       | `var a: Array[int] = [1, 2, 3]`（带类型的数组有性能收益）   |
| 字典       | `var d := {"hp": 10}`，`d["hp"]` 或 `d.hp`              |
| 空值       | `null`。没有指针，对象一律是引用                            |
| 三元       | `var x = a if cond else b`（顺序和 C 反着）                 |
| 字符串插值 | `"血量 %d / %d" % [hp, MAX_HP]`                             |
| 协程       | `await`，见下                                               |

### `await`——比 UE 的 Latent Action 好用得多

```gdscript
await get_tree().create_timer(1.5).timeout    # 等 1.5 秒
await animation_player.animation_finished     # 等动画播完
await some_node.some_signal                   # 等任意信号
```

任何 `await` 的函数都自动成为协程，不需要额外声明。

### `preload` vs `load`

- `preload("res://x.tscn")`——**编译期**加载，路径必须是字面量，启动即占内存，访问零延迟
- `load("res://x.tscn")`——**运行时**加载，路径可以是变量

常用资源用 `preload` 存成 `const`，动态决定的用 `load`。

---

## 常用操作片段

```gdscript
# 取子节点
var s := $Sprite2D                    # 相对路径简写
var s2 := get_node("Path/To/Node")
var s3 := %UniqueName                 # 场景唯一名（编辑器里右键 > Access as Unique Name）

# 实例化
const EnemyScene := preload("res://scenes/enemy.tscn")
var e := EnemyScene.instantiate()
e.position = Vector2(100, 50)
add_child(e)

# 删除（一定用 queue_free）
e.queue_free()

# 分组（相当于 UE 的 Tag + GetAllActorsOfClass）
add_to_group("enemy")
for enemy in get_tree().get_nodes_in_group("enemy"):
	enemy.take_damage(10)

# 切场景
get_tree().change_scene_to_file("res://scenes/level_2.tscn")

# 暂停
get_tree().paused = true              # 节点的 process_mode 决定它是否被暂停影响

# 输入
if Input.is_action_just_pressed("attack"):
	attack()
var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

# 随机
randomize()                            # 播种；要确定性就用 RandomNumberGenerator + seed
var n := randi_range(1, 6)
```

---

## 信号：Godot 的事件系统

比 UE 的 Delegate 轻得多，没有 `DECLARE_DYNAMIC_MULTICAST_DELEGATE` 那套宏。

```gdscript
# 声明
signal health_changed(new_hp: int, max_hp: int)

# 发射
health_changed.emit(hp, MAX_HP)

# 订阅
player.health_changed.connect(_on_player_health_changed)

# 一次性订阅
player.died.connect(_on_died, CONNECT_ONE_SHOT)

# 取消
player.health_changed.disconnect(_on_player_health_changed)
```

**场景内部的连线可以在编辑器里点**（会写进 `.tscn` 的 `[connection]` 段，是可读文本）；
**跨场景或动态的连接写在代码里**。

---

## 资源（Resource）：Godot 版的 DataAsset

数据驱动的东西用 `Resource`，相当于 UE 的 `UDataAsset` / `UDataTable` 行：

```gdscript
# res://src/data/weapon_data.gd
extends Resource
class_name WeaponData

@export var display_name: String = ""
@export var damage: int = 10
@export var fire_rate: float = 0.2
@export var icon: Texture2D
```

在编辑器里 右键 > New Resource > WeaponData，填好存成 `res://assets/data/pistol.tres`。
`.tres` 是文本，可以 diff，也可以直接手写。

---

## 命令行速查

一律用 `godot_console.exe`（PATH 里已有，直接写 `godot_console`）。

```powershell
godot_console --path .                          # 跑主场景
godot_console --path . res://scenes/x.tscn      # 跑指定场景
godot_console --editor --path .                 # 开编辑器
godot_console --headless --path . --import      # 只导入资源 + 解析脚本
godot_console --headless --path . --quit-after 120   # 无窗口跑 120 帧后退出
godot_console --headless --path . -s res://tool.gd   # 跑一次性脚本
godot_console --path . --debug-collisions       # 显示碰撞体
godot_console --version
```

日常不用记这些，跑 `.\scripts\check.ps1` 就够了。

---

## 容易踩的坑

- **条件表达式里的空数组不一定继承目标元素类型。**
  `var team: Array[PBAttacker] = [] if context == null else context.team`
  在空分支可能运行时报类型不匹配。先声明类型明确的空数组，再用 `if` 赋另一分支。
  这是运行时问题，需用例实际走到空分支，不能只看导入解析通过。

- **`queue_free()` 不是 `free()`。** `free()` 立即释放，正在遍历或信号回调里调用会崩；
  `queue_free()` 在帧末安全释放。除非你非常确定，否则永远用 `queue_free()`。
  （这条只针对 `Node`。`RefCounted` 两个都不用调。）
- **`RefCounted` 的循环引用会泄漏。** 引用计数收不掉环，这是它和 UE 的 GC
  最本质的差别：

  ```gdscript
  a.partner = b
  b.partner = a    # 两边计数都不归零，永远不释放
  ```

  症状是退出时控制台报 `ObjectDB instances leaked at exit`（只在调试版报，
  发布版静默泄漏）。破环的办法是其中一边改用 `weakref(other)`，
  取值时 `.get_ref()`。父子结构一律「父持子用强引用，子指父用弱引用」。
- **别直接 `extends Object`。** 不 `free()` 就是纯泄漏，而且没有任何提示。
  要么 `RefCounted`（自动），要么 `Node`（进树）。
- **`_init()` 里访问不到 `$子节点` 和 `@onready` 变量**，初始化逻辑写 `_ready()`。
- **移动写 `_physics_process`**，不是 `_process`。写错了帧率一变手感就变。
- **Tab 缩进**，不是空格。gdformat 强制，混用会被 gdlint 拦下。
- **不要手写 `uid://`。** 新增 `ext_resource` 只写 `path="res://..."`，
  跑一次 `--import` 让引擎补 uid。
- **`.gd.uid` 边车文件要提交进 git**，漏了会让别人机器上的场景引用断掉。
- **Input Map 不要手写进 `project.godot`**，那段序列化格式跨版本会变，
  用编辑器 Project Settings > Input Map 加。
- **`res://` 只读**（打包后是 pck 里的内容），存档写 `user://`。

更多项目相关的约定见 [CLAUDE.md](../CLAUDE.md)。

---

## 官方文档

在线文档不通的话，MCP 的 `godot_docs` 工具能拉版本匹配的文档（需编辑器开着）；
或者按 F1 在 Godot 编辑器里查内置文档——离线、版本永远对得上。
