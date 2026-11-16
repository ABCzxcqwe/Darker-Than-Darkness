class_name AbilityTp
extends RefCounted
## Resolución de coste de TP de una habilidad (incluye fase 2 y escalables).


func resolve_tp_cost(ability_data: AbilityData, peer_id: int, slot_index: int, abs_svc: Node) -> float:
	if ability_data.is_scalable and abs_svc != null and abs_svc.has_method("get_dynamic_tp_cost"):
		return abs_svc.get_dynamic_tp_cost(peer_id, slot_index)

	# En fase 2 el coste real es el de disparo (la fase 1 siempre cuesta 0).
	if abs_svc != null and abs_svc.has_method("is_mode_active"):
		if abs_svc.is_mode_active(peer_id, slot_index):
			var md: Dictionary = abs_svc.get_mode_data(peer_id, slot_index)
			if md.get("fase2", false) and "fase2_fire_tp_cost" in ability_data:
				return ability_data.fase2_fire_tp_cost

	return ability_data.tp_cost
