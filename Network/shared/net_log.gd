class_name NetLog
extends RefCounted
## Logger mínimo de la capa de red. Ningún otro archivo usa `print` directo.

static var verbose: bool = OS.is_debug_build()


static func debug(tag: String, message: String) -> void:
	if verbose:
		print("[%s] %s" % [tag, message])


static func info(tag: String, message: String) -> void:
	print("[%s] %s" % [tag, message])


static func warn(tag: String, message: String) -> void:
	push_warning("[%s] %s" % [tag, message])


static func error(tag: String, message: String) -> void:
	push_error("[%s] %s" % [tag, message])


## Variantes para logs con múltiples partes (equivalen a print(...) con args).
static func debug_parts(tag: String, parts: Array) -> void:
	if verbose:
		print("[%s] %s" % [tag, _join(parts)])


static func warn_parts(tag: String, parts: Array) -> void:
	push_warning("[%s] %s" % [tag, _join(parts)])


static func error_parts(tag: String, parts: Array) -> void:
	push_error("[%s] %s" % [tag, _join(parts)])


static func _join(parts: Array) -> String:
	var text := ""
	for part in parts:
		text += str(part)
	return text
