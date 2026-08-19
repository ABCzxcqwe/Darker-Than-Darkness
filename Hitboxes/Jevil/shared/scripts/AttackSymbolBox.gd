# AttackSymbolBox.gd
# Recuadro con el símbolo del ataque (corazón/trébol/carrusel) que aparece en
# los laterales del área de combate como telegraph. Puro visual: no colisiona.
extends Node2D

# ── Visual (se sincronizan por SceneReplicationConfig) ──────────────────
var symbol: String = "diamond"
var symbol_color: Color = Color(1, 1, 1)

# ── Estado interno ──────────────────────────────────────────────────────
var _elapsed: float = 0.0
var _last_symbol: String = ""
var _last_color: Color = Color(1, 1, 1)

const LIFETIME: float = 2.0
const FADE_START: float = 1.4


func setup(sym: String, col: Color, angle: float) -> void:
	symbol = sym
	symbol_color = col
	rotation = angle
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta

	if symbol != _last_symbol or symbol_color != _last_color:
		_last_symbol = symbol
		_last_color = symbol_color
		queue_redraw()

	if _elapsed >= FADE_START:
		modulate.a = clampf(1.0 - (_elapsed - FADE_START) / (LIFETIME - FADE_START), 0.0, 1.0)

	if _elapsed >= LIFETIME:
		queue_free()


func _draw() -> void:
	PlaceholderSymbol.draw_symbol(self, symbol, symbol_color, 30.0)
