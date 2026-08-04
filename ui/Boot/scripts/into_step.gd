extends Resource
class_name IntroStep
## Un paso individual de la secuencia de introducción (la "profecía").
## Cada paso puede tener texto, una imagen/silueta, o ambos.
## Arma la lista de pasos desde el Inspector en Intro.tscn (propiedad "steps"
## del nodo Intro) sin tocar código: solo agrega elementos, en el orden
## que quieras que aparezcan.

## Texto a mostrar (dejar vacío para un paso solo de imagen).
@export_multiline var text: String = ""

## Imagen o silueta a mostrar (dejar vacío para un paso solo de texto).
@export var image: Texture2D = null

## Desplazamiento de la imagen respecto al centro de la pantalla.
@export var image_offset: Vector2 = Vector2.ZERO

## Escala de la imagen.
@export var image_scale: Vector2 = Vector2(1, 1)

## Si es true, la imagen se dibuja como silueta negra en vez de a color.
## Útil para siluetas tipo "figura oscura" antes de revelar algo.
@export var image_as_silhouette: bool = false

## Cuánto tiempo (segundos) permanece visible este paso antes de pasar
## al siguiente automáticamente. Si es 0, el paso espera input manual
## (Espacio) para avanzar en vez de avanzar solo.
@export var hold_time: float = 3.0

## Duración del fundido de entrada/salida de este paso.
@export var fade_time: float = 0.6

## Reproducir un sonido/sfx al iniciar este paso (opcional, id de SfxId).
@export var sfx_id: int = -1
