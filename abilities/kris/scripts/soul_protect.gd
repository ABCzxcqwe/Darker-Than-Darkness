# res://abilities/kris/scripts/soul_protect.gd
# Habilidad 3 de Kris — Soul Protect
#
# Kris elige a un aliado y absorbe la mitad del daño que reciba
# durante 10 segundos. Ambos tienen piso de 1 HP.
extends AbilityBase

const DURATION: float = 10.0
const SHARE_PCT: float = 0.5


func activate(player_node: Node, _data: AbilityData, direction: Vector2) -> void:
	if not is_instance_valid(player_node):
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	var part_high: int = int(round(direction.x))
	var part_low: int  = int(round(direction.y))
	var target_peer_id: int = (part_high << 16) | (part_low & 0xFFFF)

	if target_peer_id <= 0 or target_peer_id == caster_id:
		return

	var health_svc = GameServiceLocator.get_service("HealthService")
	if not health_svc:
		return

	# Registrar protección de daño compartido por 10s
	health_svc.register_protection(target_peer_id, caster_id,
		health_svc.ProtectionType.DAMAGE_SHARE, { "share_pct": SHARE_PCT })

	print("[SoulProtect] Kris(", caster_id, ") protege a ", target_peer_id,
		  " por ", DURATION, "s | comparte ", SHARE_PCT * 100, "% del daño")

	# Auto-expiracion
	var timer := player_node.get_tree().create_timer(DURATION)
	timer.timeout.connect(func() -> void:
		if health_svc:
			health_svc.unregister_protection(target_peer_id, caster_id,
				health_svc.ProtectionType.DAMAGE_SHARE)
			print("[SoulProtect] Proteccion expirada para ", target_peer_id)
	)
