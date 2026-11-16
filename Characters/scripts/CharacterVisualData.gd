class_name CharacterVisualData
extends Resource

@export var layer_0: SpriteFrames
@export var layer_1: SpriteFrames
@export var layer_2: SpriteFrames
@export var layer_3: SpriteFrames
@export var layer_4: SpriteFrames
@export var layer_5: SpriteFrames
@export var layer_6: SpriteFrames
@export var layer_7: SpriteFrames
@export var layer_8: SpriteFrames

@export var layer_offsets: Array[Vector2] = [
	Vector2.ZERO,
	Vector2.ZERO,
	Vector2.ZERO,
	Vector2.ZERO,
	Vector2.ZERO,
	Vector2.ZERO,
	Vector2.ZERO,
	Vector2.ZERO,
	Vector2.ZERO,
]
@export var layer_visible: Array[bool] = [
	true,
	true,
	true,
	true,
	true,
	true,
	true,
	true,
	true,
]


func get_layers() -> Array[SpriteFrames]:
	return [layer_0, layer_1, layer_2, layer_3, layer_4, layer_5, layer_6, layer_7, layer_8]


func get_layer(index: int) -> SpriteFrames:
	match index:
		0: return layer_0
		1: return layer_1
		2: return layer_2
		3: return layer_3
		4: return layer_4
		5: return layer_5
		6: return layer_6
		7: return layer_7
		8: return layer_8
	return null


func get_offset(index: int) -> Vector2:
	if index >= 0 and index < layer_offsets.size():
		return layer_offsets[index]
	return Vector2.ZERO


func is_layer_enabled(index: int) -> bool:
	if index >= 0 and index < layer_visible.size():
		return layer_visible[index]
	return true
