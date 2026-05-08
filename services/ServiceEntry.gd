# ServiceEntry.gd
# Resource que describe un servicio del juego.
# Se configura en el Inspector dentro de GameServices.tres
extends Resource
class_name ServiceEntry

## Nombre único del servicio. Se usa para buscarlo:
##   GameServiceLocator.get_service("HitboxService")
@export var service_name: String = ""

## Script del servicio. Debe ser un Node (extends Node).
@export var service_script: GDScript = null
