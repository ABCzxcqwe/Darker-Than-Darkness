# Phantom Camera en la reescritura

La cámara del recode pasa de `core/player_camera.gd` + una `Camera2D` por
jugador a **Phantom Camera 0.11.x** con **un rig por escena**.

- Partida: `World.tscn` tiene su `CameraRig`.
- Hub: `Session.tscn` tiene su `CameraRig`.
- Espectador: el mismo rig de `World` cambia de target.
- No hay cámaras en jugadores remotos.
- La cámara es visual: no entra en netfox ni en el rollback.

## 1. Dependencia

- `addons/phantom_camera` versión **0.11.0.4** (última estable al momento de
  escribir; requiere Godot 4.4+).
- Habilitar el plugin `Phantom Camera`.
- El plugin agrega el autoload:

```ini
PhantomCameraManager="*res://addons/phantom_camera/scripts/managers/phantom_camera_manager.gd"
```

## 2. Estructura

```text
CameraRig (Node2D, CameraRig.gd)
├── Camera2D
│   └── PhantomCameraHost
├── FollowPCam (PhantomCamera2D)
└── NoiseEmitter (PhantomCameraNoiseEmitter2D)
```

`CameraRig.tscn` ya viene armado en `Gameplay/camera/`. Se instancia en
`World.tscn` y `Session.tscn`.

Configuración base:

- `FollowPCam.follow_mode = SIMPLE`.
- `FollowPCam.follow_damping = true`.
- `PhantomCameraHost.interpolation_mode = IDLE` para seguir la posición
  interpolada/predicha sin pelear con netfox.
- `noise_emitter_layer = 1` en PCam y en el emisor.
- `tween_on_load = false`.

## 3. API del rig

```gdscript
CameraRig.get_active()                       # rig de la escena
rig.set_follow_target(player, snap := false)
rig.set_spectate_target(player, snap := true)
rig.set_view_mode("play" | "spectate" | "hub" | "disabled")
rig.set_local_player_camera(enabled)          # compatibilidad
rig.set_map_bounds(rect)
rig.shake(intensity, duration)
rig.snap_to_target()
```

Uso:

- `WorldView.set_local_player_camera(true)`:
  target = jugador local, modo `play`.
- `WorldView.set_local_player_camera(false)`:
  modo `disabled`; el espectador luego pone `spectate`.
- `SpectatorController`:
  modo `spectate`, target = jugador espectado.
- `Session._set_local_avatar_hub_visible()`:
  target = avatar local, modo `hub`.

## 4. Mouse peek y zoom

`PlayerCameraController.gd` porta la lógica de `core/player_camera.gd`:

- mouse peek con `input_component.get_aim_position()`;
- `follow_offset` del PCam;
- zoom base/sprint/ceguera;
- lectura de `CharacterData.camera_*`;
- damping derivado de `camera_smooth_speed`.

No se modifica la cámara en `Player.gd`: el jugador solo aporta posición,
input y `character_data`.

## 5. Shake

Se reemplaza el shake propio por `PhantomCameraNoiseEmitter2D` +
`PhantomCameraNoise2D`:

- `CameraRig.shake(intensity, duration)` ajusta `amplitude`, `duration` y
  `decay_time`, y llama `emit()`;
- `ClientRelay.camera_shake` sigue existiendo;
- `Player._on_camera_shake()` y el shake de `_sync_state()` llaman al rig
  activo.

El shake es local; no se sincroniza por red.

## 6. Compatibilidad con netfox

- La cámara no es estado de netfox.
- El PCam sigue la posición del jugador local predicha por netfox.
- `PhantomCameraHost.interpolation_mode = IDLE` evita mezclar el tick de física
  de netfox con el render de la cámara.
- Para remotos/espectador sigue la posición interpolada por `TickInterpolator`.
- El shake se dispara por RPC/render, nunca dentro de `_rollback_tick`.

## 7. Copias adaptadas

Se copiaron y adaptaron dentro del recode:

- `Gameplay/camera/SpectatorController.gd` desde `core/SpectatorController.gd`.
  - Elimina su `Camera2D`.
  - Usa `CameraRig.set_spectate_target()`.
  - Usa `PlayerLifecycleManager.get_owner_peer_id()` como identidad.
- `Gameplay/player/HubAvatar.gd` desde `core/player/HubAvatar.gd`.
  - Elimina la `Camera2D` y sus toggles.
  - La cámara del hub la maneja el rig de `Session.tscn`.

## 8. Escenas a cambiar al integrar

- `player.tscn`:
  - quitar `Camera2D` y el script `core/player_camera.gd`;
  - apuntar el Player a `Gameplay/player/Player.gd`.
- `World.tscn`:
  - instanciar `Gameplay/camera/CameraRig.tscn`;
  - quitar cámaras de jugadores.
- `Session.tscn`:
  - instanciar `Gameplay/camera/CameraRig.tscn`.
- `HubAvatar.tscn`:
  - quitar `Camera2D`;
  - apuntar a `Gameplay/player/HubAvatar.gd`.
- `Main.tscn`:
  - verificar que no quede una `Camera2D` activa compitiendo.

## 9. Validación

Harness usado:

```bash
/tmp/opencode/recode_parse/          # parse + CameraRig runtime
/tmp/opencode/netfox_player_parse/   # parse del módulo de jugador
```

Comprobado:

- parse del recode con netfox + Phantom Camera;
- instancia de `CameraRig.tscn`;
- `set_follow_target`, `set_view_mode("play")`, `set_map_bounds` y `shake`
  sin errores de propiedades.

Pendiente de probar en juego:

- LAN/dedicado con cámara siguiendo al jugador local;
- espectador con ciclado de targets;
- hub con cámara del avatar local;
- shake con valores finales de amplitud/frecuencia.

## 10. Limitaciones

- Phantom Camera 0.11.x requiere Godot 4.4+; validar en 4.7.x.
- El shake por noise no es idéntico al shake anterior; hay que calibrar.
- Los límites de cámara solo se aplican si el mapa expone `get_camera_bounds()`.
- La cámara no se sincroniza por red; cada cliente renderiza la suya.
- Si se agrega un segundo rig en la misma escena, `CameraRig.get_active()` toma
  el primero; el diseño espera uno por escena.
