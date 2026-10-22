# Darker Than Darness
Este es un juego multijugador asimetrico que debes sobrevivir con tus amigos (o escapar de uno de ellos), en un juego de rol asimetrico...
###### ya no se que poner

## Builds y modo desarrollador

El menú de exportación está agrupado en tres bloques:

- **TEST**: para testers/alfa. No permite personajes de test ni con `--dev`.
- **DEV**: para desarrollo. Los personajes de test se activan lanzando el juego con `--dev`.
- **RELEASE**: público. Bloquea el modo dev siempre, incluso con `--dev`.

En el editor, el modo dev está activo por defecto.

Con el modo dev activo, en la pantalla de selección de personaje se pulsa **L1 + Select** en el mando para abrir el panel de personajes de test. El panel muestra ambos bandos; al elegir un personaje del otro equipo, el rol del jugador se ajusta automáticamente. El servidor también debe permitir el modo dev (build DEV lanzada con `--dev`, o el editor).

No se usa F8: el editor de Godot lo reserva para detener la instancia, así que el juego nunca lo recibe cuando se ejecuta desde el editor.

Ejemplos:

```bash
# Cliente/host DEV con personajes de test
./DarkerThanDarkness -- --dev

# Servidor dedicado DEV con personajes de test
./DarkerThanDarkness --headless -- --server --dev
```

Los builds se generan en `../../Builds/<TEST|DEV|RELEASE>/<plataforma>/`.

### Menú Dev in-game

Con DevMode activo y jugando como **host local**, **L1 + Select** abre el menú de herramientas dentro de la partida. No pausa el mundo y solo existe para el host; en TEST/RELEASE y en clientes no aparece.

- Selector de objetivo entre los jugadores no espectadores.
- Cura, daño, invulnerabilidad, TP y stamina con campos numéricos.
- Añadir o quitar tiempo de la partida.
- Los valores se clampean a los máximos correspondientes.
