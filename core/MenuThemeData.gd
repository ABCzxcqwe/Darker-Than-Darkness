extends Resource
class_name MenuThemeData

@export var id: String = ""
@export var label: String = ""
@export var bg_color: Color = Color.BLACK
@export var border_color: Color = Color(0, 0.5019608, 0, 1)
@export var title_color: Color = Color(0, 1, 0, 1)
@export var hint_color: Color = Color(0, 1, 0, 1)
@export var dim_color: Color = Color(0, 0.5019608, 0, 1)
@export var selected_color: Color = Color(0, 1, 0, 1)
@export var separator_color: Color = Color(0, 0.5019608, 0, 1)
@export var music: AudioStream
@export var background_scene: PackedScene
@export var font: FontFile
@export var soul_texture: Texture2D
@export var sfx_profile: String = "deltarune"
