# Mockup Deltarune — Flujo JUGAR v3 (6 columnas + Mock_CreateRoom)

Sandbox visual fiel Deltarune Ch1 retro, teclado-only por VHS, soul rojo sin shader, solo letras amarillas. **No toca menú original.**

## Estructura 4 mocks + fixes

- `theme/DeltaruneBox.tres` negro borde blanco 3px `corner 0` `AA false`.
- `Mock_MainMenu` `JUGAR/OPCIONES/EXTRAS/SALIR` (fix viewport null guard `get_viewport()==null`).
- `Mock_PlayMode` `ONLINE/LAN/VOLVER` guarda `user://mock_playmode.cfg`.
- `Mock_ServerBrowser` **casi fullscreen** `MarginContainer 60/40/60/40`, header `NOMBRE | HOST | MAPA | JUG. | MODO | PING` 12px gris, `ListBox 0x380 v_expand 3`, cada fila `HBox` 6 `Label` (170/130/145/70/85/80 13px) con `*   ` / `    ` toggle amarillo; `_mock_rooms: Array[Dictionary]` mock 2 salas; `EmptyLabel "* NO SE ENCONTRARON PARTIDAS"` amarillo; botones siempre visibles `ACTUALIZAR [C] / CREAR SALA / CONECTAR POR IP / VOLVER [X]`; fix `set_input_as_handled` null guard + `@onready .../MarginList/VBoxList/...`.
- `Mock_CreateRoom` nuevo `Margin 80/60`, `NOMBRE LineEdit / MAPA ◀ Card Castle ▶ / MODO ONLINE / CREAR [Z] / VOLVER [X]`, `←→` cambia mapa `MAPS[]`, `Z` mock crea.

## Controles
- `Z/Enter/menu_accept` confirmar, `X/Esc/menu_cancel` volver (`Browser→PlayMode→MainMenu`), `C` refrescar (toggle vacío↔2 salas), `↑↓` mover, `←→` en CrearRoom mapa. Soul rojo tex `Soul.png` tween 0.08s.

## Probar
- `F6` cada `Mock_*.tscn` → flujo `JUGAR → ONLINE → Browser (C) → CREAR SALA → Mock_CreateRoom`.
- Headless `validate_mocks2.gd` → `OK loaded ×4` sin `Node not found` ni `set_input_as_handled` null.

## Validación actual
- `godot --headless` 4 mocks OK, solo warning `Purieta.tres:5` pre-existente.
