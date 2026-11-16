class_name NetConfig
extends RefCounted
## Constantes de la capa de red. Un solo lugar para límites y tiempos.

const PORT := 4242
const MIN_PLAYERS := 2
const MAX_PLAYERS := 10
const MAX_LOBBIES := 16
const GAME_ID := "Darker_Than_Darkness"
const DEFAULT_MODE := "Escape"

## EOSG exige un socket id alfanumérico de hasta 32 caracteres (sin "_").
const EOSG_SOCKET := "DarkerThanDarkness"
## Bucket de EOS para agrupar los lobbies del juego.
const EOSG_BUCKET := "DarkerThanDarkness"
## Ruta de la configuración local de credenciales EOS. Nunca se versiona.
const EOSG_CONFIG_PATH := "user://eosg.cfg"
## Fallback empaquetado en el build. Tiene prioridad menor que user://.
const EOSG_BUNDLED_CONFIG_PATH := "res://eosg.cfg"
## Addon de EOSG. Si no existe, el proveedor no se registra.
const EOSG_ADDON_PATH := "res://addons/epic-online-services-godot"
const EOSG_ADDON_PLUGIN := EOSG_ADDON_PATH + "/plugin.cfg"
const EOSG_BRIDGE_PATH := "res://Network/providers/eosg_bridge.gd"

## Atributos de lobby compartidos entre proveedores.
const LOBBY_ATTR_NAME := "name"
const LOBBY_ATTR_ROOM_NAME := "room_name"
const LOBBY_ATTR_HOST := "host"
const LOBBY_ATTR_MAP := "map"
const LOBBY_ATTR_MODE := "mode"
const LOBBY_ATTR_MAX_PLAYERS := "max_players"
const LOBBY_ATTR_GAME_ID := "game_id"

## Tick de netfox. El polling manual de NetworkManager sigue siendo independiente.
const NETFOX_TICKRATE := 30

## Defaults de conexión que también usa SettingsManager/CoordinatorClient.
const COORDINATOR_URL_DEFAULT := "http://127.0.0.1:8080"
const LAN_SERVER_IP_DEFAULT := "127.0.0.1"

## Heartbeat del servidor dedicado al coordinador.
const HEARTBEAT_INTERVAL := 5.0
const HEARTBEAT_TIMEOUT := 4.0
const HEARTBEAT_FAIL_LIMIT := 6

## Frecuencia de replicación manual (Hz). NetworkManager desactiva
## `multiplayer_poll` del árbol y hace polling a este ritmo.
const NETWORK_TICK_HZ := 60.0

## Cada cuánto se consulta si Steam sigue disponible.
const STEAM_AVAILABILITY_POLL := 1.0
## Si Steam no estaba corriendo al iniciar, se reintenta el init con este
## intervalo (solo si el cliente de Steam ya está corriendo).
const STEAM_RETRY_INTERVAL := 5.0

const CHAT_MAX_LENGTH := 200
## Token bucket del chat: ráfaga máxima y recarga por segundo.
const CHAT_BURST := 5.0
const CHAT_REFILL_PER_SEC := 2.0

const NAME_MAX_LENGTH := 24

const MATCH_START_COUNTDOWN := 10.0
const CHARACTER_SELECT_DURATION := 16.5

## Tiempo para que llegue el RPC de kick antes de desconectar al peer.
const KICK_NOTIFY_DELAY := 0.35
## Tiempo que espera el cliente expulsado antes de volver al menú.
const KICK_RESET_DELAY := 0.4
