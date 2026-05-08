# GameServicesConfig.gd
# Resource que contiene la lista de servicios del juego.
# Se guarda como GameServices.tres y se asigna al GameServiceLocator
# desde el Inspector.
#
# ¿Por qué este wrapper?
# Godot no permite exportar Array[ServiceEntry] directamente en un .tres
# sin un Resource que lo contenga. Este script es ese contenedor.
extends Resource
class_name GameServicesConfig

@export var entries: Array[ServiceEntry] = []


func get_entries() -> Array[ServiceEntry]:
	return entries
