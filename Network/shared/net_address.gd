class_name NetAddress
extends RefCounted
## Utilidades de direcciones LAN, independientes del transporte.


## IP local preferida (LAN). Filtra IPv6, loopback y link-local, y prioriza
## rangos privados (192.168.x / 10.x / 172.16-31.x).
static func local_ip() -> String:
	var candidates: Array[String] = []
	for addr in IP.get_local_addresses():
		if addr.contains(":"):
			continue
		if addr.begins_with("127.") or addr.begins_with("169.254."):
			continue
		candidates.append(addr)
	for addr in candidates:
		if addr.begins_with("192.168.") or addr.begins_with("10.") or _is_private_172(addr):
			return addr
	return candidates[0] if not candidates.is_empty() else "127.0.0.1"


static func _is_private_172(addr: String) -> bool:
	if not addr.begins_with("172."):
		return false
	var parts := addr.split(".")
	if parts.size() < 2 or not parts[1].is_valid_int():
		return false
	var n := int(parts[1])
	return n >= 16 and n <= 31


## Dirección "host:puerto" que un cliente debe tipear para unirse.
static func lan_address(port: int = -1) -> String:
	var resolved_port := port if port > 0 else NetConfig.PORT
	return "%s:%d" % [local_ip(), resolved_port]


## Separa "host:puerto". Si no hay puerto válido, usa el puerto por defecto.
static func parse_host_port(text: String, default_port: int = -1) -> Dictionary:
	var host := text.strip_edges()
	var port := default_port if default_port > 0 else NetConfig.PORT
	if host.contains(":"):
		var parts := host.rsplit(":", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			host = parts[0].strip_edges()
			port = int(parts[1])
	if host.is_empty():
		host = "127.0.0.1"
	return {"host": host, "port": port}
