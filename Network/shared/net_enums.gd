class_name NetEnums
extends RefCounted
## Enums y conversiones compartidas por la capa de red.
##
## `Provider` mantiene valores para futuros transportes. Un provider que no
## está registrado en NetworkManager simplemente no se muestra ni se puede
## inicializar.

enum Provider { STEAM, EOSG, P2P, CUSTOM, DISABLE }
enum Mode { LAN, ONLINE }
enum Phase { LOBBY, CHARACTER_SELECT, PLAYING, ENDED }


static func provider_to_id(provider: Provider) -> String:
	match provider:
		Provider.STEAM:
			return "steam"
		Provider.EOSG:
			return "eosg"
		Provider.P2P:
			return "p2p"
		Provider.CUSTOM:
			return "custom"
		_:
			return "disable"


static func provider_from_id(id: String) -> Provider:
	match id.strip_edges().to_lower():
		"steam":
			return Provider.STEAM
		"eosg", "eos", "epic", "epic_online":
			return Provider.EOSG
		"p2p":
			return Provider.P2P
		"custom":
			return Provider.CUSTOM
		_:
			return Provider.DISABLE


static func provider_label_key(provider: Provider) -> String:
	match provider:
		Provider.STEAM:
			return "NET_PROVIDER_STEAM"
		Provider.EOSG:
			return "NET_PROVIDER_EOSG"
		Provider.P2P:
			return "NET_PROVIDER_P2P"
		Provider.CUSTOM:
			return "NET_PROVIDER_CUSTOM"
		_:
			return "NET_PROVIDER_DISABLED"
