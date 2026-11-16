class_name NetScenes
extends RefCounted
## Rutas y grupos de escenas que usa la capa de red.
##
## Al integrar la reescritura en el proyecto principal, estas rutas deben
## coincidir con las escenas reales. `MAIN_UID` se carga con `load()` (no
## `preload`) para que estos scripts se puedan validar sin el proyecto completo.

const MAIN_UID := "uid://c4oma0j4cetoj"
const WORLD_UID := "uid://dy3ln7lsee4qh"
const PLAYER_UID := "uid://djw510qiudh6e"
const GAME_HUD_UID := "uid://cvjakwoxx54w4"
const GAME_HUD_MOCK := "res://ui/GameUI/Mock/GameHUDMock.tscn"
const DEV_MENU := "res://ui/InGameMenu/DevMenu.tscn"
const SCOREBOARD := "res://ui/GameUI/Scenes/Scoreboard.tscn"
const CHARACTER_SELECT := "res://ui/GameUI/Scenes/CharacterSelect.tscn"
const HUB_AVATAR := "res://core/player/HubAvatar.tscn"
const TEST_MAP := "res://Maps/Test/TestMap.tscn"
const SESSION := "res://Maps/Session.tscn"
const MATCH_STATS := "res://ui/GameUI/Scenes/MatchStats.tscn"
const MAIN_MENU := "res://ui/MainMenu/scenes/MainMenu.tscn"

const HUB_SESSION_GROUP := "hub_session"
