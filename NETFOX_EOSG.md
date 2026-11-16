# netfox + EOSG en la reescritura

Este documento describe cómo queda la capa de red del recode cuando se integra
`netfox` (rollback de movimiento) y `EOSG` (Epic Online Services Godot) como
proveedor online adicional a Steam.

El árbol sigue aislado: este archivo documenta los cambios de proyecto/escenas
que hay que aplicar al integrar. El código de red, gameplay y la capa de jugador
ya están adaptados en `Network/`, `Core/`, `Gameplay/` y `Session/`.

## 1. Dependencias

- `addons/netfox` + `addons/netfox.internals` (probado con 1.35.3).
- `addons/phantom_camera` (0.11.0.4) para el `CameraRig`. Ver `PHANTOM_CAMERA.md`.
- `addons/epic-online-services-godot` (EOSG 2.3.1 o superior).
- Godot 4.7.x.

EOSG es opcional en runtime: si no está instalado o no hay credenciales, el
proveedor `EOSGProvider` no se lista y el resto del juego sigue funcionando.

## 2. Autoloads de `project.godot`

Además de los autoloads del recode (`SessionState`, `NetworkManager`,
`LobbyManager`, etc.) hay que registrar netfox:

```ini
[autoload]
NetworkTime="*res://addons/netfox/network-time.gd"
NetworkTimeSynchronizer="*res://addons/netfox/network-time-synchronizer.gd"
NetworkRollback="*res://addons/netfox/rollback/network-rollback.gd"
NetworkEvents="*res://addons/netfox/network-events.gd"
NetworkPerformance="*res://addons/netfox/network-performance.gd"
```

Y los autoloads que agrega EOSG al habilitar el plugin:

```ini
EOSGRuntime="*res://addons/epic-online-services-godot/runtime.gd"
HPlatform="*res://addons/epic-online-services-godot/heos/hplatform.gd"
HAuth="*res://addons/epic-online-services-godot/heos/hauth.gd"
HAchievements="*res://addons/epic-online-services-godot/heos/hachievements.gd"
HFriends="*res://addons/epic-online-services-godot/heos/hfriends.gd"
HStats="*res://addons/epic-online-services-godot/heos/hstats.gd"
HLeaderboards="*res://addons/epic-online-services-godot/heos/hleaderboards.gd"
HLobbies="*res://addons/epic-online-services-godot/heos/hlobbies.gd"
HP2P="*res://addons/epic-online-services-godot/heos/hp2p.gd"
HSessions="*res://addons/epic-online-services-godot/heos/hsessions.gd"
```

`NetworkEvents` es quien arranca `NetworkTime` al asignar el `MultiplayerPeer`.
No lo desactives (`netfox/events/enabled=true`).

## 3. Settings de netfox

```ini
[netfox]
time/tickrate=30
time/sync_to_physics=true
time/max_time_stretch=1.25
rollback/enabled=true
rollback/history_limit=64
rollback/input_redundancy=3
rollback/input_delay=0
rollback/display_offset=0
rollback/enable_diff_states=true
events/enabled=true
```

Notas:

- `NetConfig.NETWORK_TICK_HZ` (60) sigue siendo la frecuencia del polling manual
  de `NetworkManager`. No es el tick de netfox.
- `time/tickrate=30` y física a 60: el movimiento usa
  `NetworkTime.physics_factor` para que un tick de red cubra los pasos de física
  necesarios.
- Si subís `run/max_fps` a 60 o más, `TickInterpolator` suaviza la posición de
  jugadores remotos.

## 4. Escena del jugador

En `player.tscn` hay que eliminar los dos `MultiplayerSynchronizer`
(`Synchronizer` y `SynchronizerAnim`) y dejar esta estructura:

```text
Player (CharacterBody2D, script Gameplay/player/Player.gd)
├── AnimatedSprite2D
├── PlayerInteractionComponent
├── PlayerAnimationComponent
├── PlayerInputComponent
├── PlayerMovementComponent
├── NetInput (Node, script Gameplay/player/PlayerNetInput.gd)
├── RollbackSynchronizer (Node, script addons/netfox/rollback/rollback-synchronizer.gd)
├── TickInterpolator (Node, script addons/netfox/tick-interpolator.gd)
├── VisionCircle / VisionCone / NameTag / ...
```

No hace falta configurar las listas en el inspector: `Player._setup_netfox_authority()`
las escribe por código y llama a `process_settings()`.

La cámara ya no está en `player.tscn`: `World.tscn` y `Session.tscn` usan
`Gameplay/camera/CameraRig.tscn` (Phantom Camera). Ver `PHANTOM_CAMERA.md`.

Autoridades (las fija `Session/world.gd` y `Player._ready()`):

- `Player` y `RollbackSynchronizer`: peer `1` (servidor), dueños del estado.
- `NetInput`: `owner_peer_id` (jugador dueño), dueño del input.
- `Player.owner_peer_id`: identidad lógica usada por servicios/UI.
- `TickInterpolator`: activo solo en clientes para jugadores remotos.

Propiedades de estado que configura el código:

```text
:position
:velocity
:move_state
:facing_right
:move_facing_down
:sprint_allowed
:movement_locked
```

Input:

```text
NetInput:move
NetInput:sprint
NetInput:aim_dir
```

## 5. Movimiento y servicios

- `PlayerMovementComponent._rollback_tick()` simula el movimiento autoritativo.
- `PlayerNetInput` llena `move`, `sprint` y `aim_dir` en `NetworkTime.before_tick_loop`.
- El servidor resuelve `sprint_allowed`/`movement_locked` desde stamina y
  status effects antes de simular.
- El drenaje/regeneración de stamina y los estados siguen fuera del rollback;
  solo se publican los flags que afectan al movimiento.
- Las habilidades, daño, hitboxes, stats y VFX siguen por RPC autoritativo. No
  se predicen en rollback.
- Si un efecto externo cambia un flag de movimiento, el servidor puede llamar a
  `NetworkRollback.mutate(player)` para forzar la resimulación desde ese tick.

`PlayerLifecycleManager` usa `RollbackSynchronizer.visibility_filter`:

- El peer no recibe estados hasta confirmar `_peer_world_ready`.
- El dueño **sí** recibe el estado del servidor (netfox lo necesita para
  reconciliar). Ya no se oculta el Synchronizer al dueño.
- El servidor no oculta el estado a espectadores; el catch-up sigue por
  `World._peer_world_ready`.

## 6. EOSG

### 6.1. Instalación

Copiar `addons/epic-online-services-godot` y habilitar el plugin. El plugin
agrega los autoloads de la sección 2.

### 6.2. Credenciales

`EOSGProvider` lee `user://eosg.cfg` (nunca versionar este archivo) o variables
de entorno `EOS_PRODUCT_ID`, `EOS_SANDBOX_ID`, `EOS_DEPLOYMENT_ID`,
`EOS_CLIENT_ID`, `EOS_CLIENT_SECRET`.

Ejemplo `eosg.cfg`:

```ini
[eos]
product_name="Darker Than Darkness"
product_version="1.0.0"
product_id="..."
sandbox_id="..."
deployment_id="..."
client_id="..."
client_secret="..."
# Opcional. Si falta, EOSG usa cifrado interno.
encryption_key="..."
# anonymous | devtool | account_portal | launcher
login_mode="anonymous"
devtool_host="localhost:4545"
devtool_credential="DarkerPlayer"
```

Sin credenciales el proveedor queda oculto (`is_available() == false`).

### 6.2.1 Fallback para builds

`EOSGProvider` busca primero `user://eosg.cfg`. Si no existe o está incompleto,
usa `res://eosg.cfg`, que se incluye en el build mediante `include_filter` en
`export_presets.cfg`.

- `user://` permite override local sin recompilar.
- `res://` es el default empaquetado para que EOSG funcione en otra PC.
- El `client_secret` queda dentro del build y puede extraerse. Para builds
  públicos conviene una Client Policy mínima, un launcher/configuración de
  primer arranque o un backend de confianza.
- `eosg.cfg` está en `.gitignore`; no se versiona, pero sí se exporta.

### 6.3. Lobby y peer

- Socket EOS: `NetConfig.EOSG_SOCKET` (`DarkerThanDarkness`). EOSG exige un
  socket alfanumérico de hasta 32 caracteres; no puede llevar `_`.
- Bucket de búsqueda: `NetConfig.EOSG_BUCKET`.
- `EOSGMultiplayerPeer.create_server()` usa peer `1` para el host, igual que
  ENet/Steam, así que `rpc_id(1, ...)`, `LobbyManager.server_peer_id` y netfox
  funcionan sin cambios.
- Los clientes se conectan por PUID del dueño del lobby (`owner_product_user_id`).
  Se intenta desactivar host migration (`allow_host_migration=false`); si la
  versión de HLobby/EOS no lo soporta, una migración de dueño invalidaría el
  PUID usado por los clientes y la partida debería reiniciarse.
- La lista de lobbies se entrega a la UI como summaries neutrales
  `{id, provider, name, host, map, mode, players, max_players}`.

### 6.4. Puente opcional

`Network/providers/eosg_bridge.gd` no tiene `class_name` y solo se carga con
`load()` si el addon/GDExtension de EOSG está presente. Eso
permite que el resto del recode parsee y funcione sin EOSG.

## 7. Cambios de API del proveedor

```gdscript
OnlineProviderService.initialize_async() -> bool
OnlineProviderService.is_configured() -> bool
OnlineProviderService.join_lobby(lobby_id: String) -> bool
OnlineProviderService.create_host_peer(lobby_id: String) -> MultiplayerPeer
OnlineProviderService.create_client_peer(lobby_id: String) -> MultiplayerPeer
OnlineProviderService.get_lobby_data(lobby_id: String, key: String) -> String
OnlineProviderService.is_lobby_owner(lobby_id: String) -> bool
OnlineProviderService.get_lobby_id() -> String
OnlineProviderService.get_current_lobby_summary() -> Dictionary
```

`NetworkManager`:

```gdscript
initialize_online_async(provider, timeout := 15.0) -> bool
join_online_lobby(player_name: String, lobby_id: String) -> bool
join_steam_lobby(...)  # wrapper de compatibilidad
online_lobby_id: String
online_lobby_list_updated(lobbies: Array)
steam_lobby_list_updated(lobbies: Array)  # alias de compatibilidad
```

La UI usa summaries, no el singleton de Steam.

## 8. Limitaciones conocidas

- El servidor dedicado sigue siendo ENet/coordinador. Un dedicado EOS requiere
  EOS Sessions/Connect y queda fuera de este cambio.
- El rollback cubre movimiento; las habilidades siguen siendo RPC autoritativos.
- La animación de movimiento de remotos se deriva de `move_state`/facing; no se
  replica el frame exacto. Las animaciones de habilidad siguen por RPC.
- La stamina se sincroniza a 10 Hz; puede haber micro-correcciones al empezar o
  terminar un sprint.
- Los flags de movilidad (`sprint_allowed`, `movement_locked`) se calculan con el
  estado actual de stamina/status. En una resimulación de ticks viejos no se
  reconstruye el histórico de stamina/status; puede haber correcciones menores.
- `state`, fase2 y salud no se rebobinan; una habilidad que empieza después de
  un tick viejo puede bloquear esa resimulación. Es una limitación aceptada del
  primer corte (solo movimiento en rollback).
- EOSG necesita el cliente de Epic/Dev Auth Tool para probar `devtool`; el modo
  `anonymous` no requiere interacción.
- La compatibilidad de los binarios de EOSG con Godot 4.7.x hay que verificarla
  al instalar; si falla, compilar el GDExtension desde fuente.
- El recode no contiene escenas ni assets. Los cambios de `player.tscn` y
  `World.tscn` se aplican al integrar o en un proyecto temporal de validación.

## 9. Validación

Harness temporal recomendado:

```bash
/tmp/opencode/recode_parse/   # parse con netfox + Phantom Camera + stubs
/tmp/opencode/netfox_player_parse/  # parse del módulo de jugador
```

Para probar en juego hace falta un proyecto temporal con las escenas/assets del
proyecto principal o la integración real. Los smokes pendientes son:

1. LAN: host + cliente, `NetworkTime` sincronizado, movimiento con rollback.
2. Dedicado: ENet + cliente, room host correcto.
3. Latencia simulada con `netfox.extras` `NetworkSimulator`.
4. EOSG con credenciales: crear/unir lobby, movimiento, chat y desconexión.
