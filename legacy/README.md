# Legacy

Archivos de la etapa anterior que ya no están activos en el proyecto.

- `core/NetworkManager.gd`, `LobbyManager.gd`, `MatchCoordinator.gd`,
  `ChatService.gd`, `CoordinatorClient.gd`, `DedicatedServer.gd`,
  `AbilityRouter.gd` y `ClientRelay.gd` fueron reemplazados por los módulos de
  `Network/` y `Gameplay/`.
- `core/player_camera.gd` fue reemplazado por `Gameplay/camera/`.
- `Characters/player.tscn` era una escena duplicada del jugador viejo.

Esta carpeta tiene `.gdignore`, por lo que Godot no la importa ni ejecuta.
No borrar sin revisar el backup de la integración.
