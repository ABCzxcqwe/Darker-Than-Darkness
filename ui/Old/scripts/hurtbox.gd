# hurtbox.gd
# Zona de daño del jugador. Es un Area2D pasivo:
# NO tiene lógica de detección propia.
# El slash_hitbox detecta esta Hurtbox por el grupo "hurtbox"
# y notifica a SlashAbility vía callback.
#
# Configuración requerida en el editor:
#   - Collision Layer:  capa 2  (players)
#   - Collision Mask:   capa 3  (hitboxes)
extends Area2D


func _ready() -> void:
	add_to_group("hurtbox")
