# CastleTown - sprites organizados

Recortes de `sprites/CastleTown.png` organizados en **5 hojas por categoría**
para nodos/UI, más un **TileSet de 8 hojas uniformes** para pintar en un
`TileMapLayer`. El PNG original no se modificó: sigue siendo la fuente de verdad.

Cada sprite conserva su **bounding box lógico completo**, incluyendo las piezas
separadas (cartel de la panadería, vapor del café, carteles del Party Dojo).
Cada recorte tiene **1 px transparente** en los cuatro lados.

---

## Archivos

```
sprites/CastleTown/
├── sheets/                     Las 5 hojas empaquetadas para nodos/UI
│   ├── buildings.png
│   ├── buildings_winter.png
│   ├── landmarks.png
│   ├── decor.png
│   └── walls.png
├── tileset/                    Hojas uniformes + TileSet para TileMap
│   ├── buildings.png
│   ├── buildings_winter.png
│   ├── landmarks.png
│   ├── decor.png
│   ├── walls_bands.png
│   ├── walls_panels.png
│   ├── modular.png
│   ├── cara.png
│   ├── castletown.tres
│   └── tileset_manifest.json
├── atlas/                      AtlasTexture listos para Godot (43)
│   ├── buildings/
│   ├── buildings_winter/
│   ├── landmarks/
│   ├── decor/
│   └── walls/
├── manifest.json               Coordenadas exactas de cada sprite
├── reference.png               Catálogo visual con nombre y tamaño del dibujo
├── source_map.png              Hoja original con los rectángulos marcados
└── README.md
```

---

## Hojas

| Hoja | Tamaño | Sprites | Contenido |
|---|---:|---:|---|
| `buildings.png` | 657×296 | 12 | Edificios normales: Café, Panadería, Party Dojo, Música, TV, Shop y torre del castillo, con sus variantes `plain` / `alt` |
| `buildings_winter.png` | 420×284 | 6 | Variantes navideñas de los edificios |
| `landmarks.png` | 778×360 | 6 | Castillo frontal, casa grande, ascensor, cueva, torreón y cartel TV |
| `decor.png` | 483×221 | 13 | Árbol, corona, bastón, banners, escalera, letrero RACING, TVs arcade, mostrador rosa y máquina azul |
| `walls.png` | 644×736 | 6 | 2 paneles de castillo + 4 bandas de muralla |

Total: **43 sprites**.

Las hojas de `sheets/` **no usan una grilla uniforme**. Cada celda mide lo que
mide su sprite más 2 px (1 px de margen por lado). Así no hay celdas vacías ni
recortes desalineados. Para seleccionar un sprite en un nodo, usá las
coordenadas del `manifest.json`, no una grilla fija.

Para TileMap se agregó `tileset/` con **8 hojas de celdas uniformes**. Son
archivos separados: no reemplazan a `sheets/` ni a `atlas/`. Ahí cada tile ocupa
una celda fija y el `texture_origin` ya está calculado para alinear la base.

---

## Uso en Godot

### Opción A - AtlasTexture (para nodos/UI)

Cada archivo de `atlas/` es un `AtlasTexture` que apunta a la región exacta de
su hoja. En el editor se comporta como una textura individual:

1. Abrí el proyecto para que Godot importe las hojas.
2. Arrastrá, por ejemplo, `atlas/buildings/cafe.tres` a la escena.
3. Listo: no hace falta tocar `region_rect` ni calcular píxeles.

Los `.tres` no duplican imágenes: los píxeles siguen estando solo en las 5 hojas.
Si no los querés usar, podés borrar la carpeta `atlas/` y trabajar con las hojas.

### Opción B - Hoja + región manual

En el `manifest.json`, cada sprite tiene:

- `sheet_file`: la hoja donde vive.
- `sheet_rect`: `[x, y, w, h]` de la celda **incluyendo el margen de 1 px**.
  Es el rectángulo recomendado para un `AtlasTexture`.
- `content_rect`: `[x, y, w, h]` del dibujo exacto, sin el margen.
- `source_rect`: de dónde salió en `sprites/CastleTown.png`.

Ejemplo de `cafe`:

```json
{
  "sheet_file": "sheets/buildings.png",
  "sheet_rect": [75, 0, 133, 161],
  "content_rect": [76, 1, 131, 159],
  "source_rect": [791, 350, 131, 159]
}
```

### Opción C - TileSet para TileMap

Para pintar un mapa, usá `tileset/castletown.tres`. Está armado sobre una grilla
**20×20** y tiene 8 sources (214 tiles):

| Source | Celda | Tiles | Pivote |
|---|---:|---:|---|
| Edificios | 144×180 | 12 | base |
| Edificios invierno | 144×180 | 6 | base |
| Landmarks | 326×228 | 6 | base |
| Decoración | 140×110 | 13 | base |
| Muros | 320×80 | 4 | superior izquierda |
| Paneles | 320×580 | 2 | superior izquierda |
| Modular | 20×20 | 170 | celda |
| Cara del castillo | 320×200 | 1 | superior izquierda |

- La base de los edificios queda en el **borde inferior** de la celda 20×20.
  Pintás la celda del piso y el edificio crece hacia arriba.
- Cada tile ocupa **una celda** en el TileMap, pero se dibuja a tamaño nativo.
  Los edificios, los paneles y la cara grande se superponen a celdas vecinas;
  es intencional.
- Los paneles miden exactamente 16×29 celdas; las bandas, 16×4; la cara, 16×10.
- `Modular` contiene **169 celdas de 20×20** extraídas de la sección modular del
  PNG original y **1 tile sintético** `cuadrado_blanco` (blanco con borde negro
  de 1 px), en las coordenadas `(26,0)`. La grilla de esa sección no tenía líneas
  pintadas: eran separadores **transparentes** de 1 px, que se descartaron al
  extraer las celdas. La hoja conserva el arreglo original de las piezas.
- `Cara del castillo` es una sola tile de **320×200** (16×10 celdas). Se pinta
  desde la celda superior izquierda; la cara crece hacia la derecha y abajo.
- La cueva, el castle front, los paneles y las bandas ya estaban en sus sources;
  no se duplicaron.
- No hay colisión ni y-sort configurados. Las tiendas son decoración.
- `tileset_manifest.json` tiene el mapeo source/coordenadas/nombre/origen para
  inspeccionar o regenerar el TileSet.

Escena de prueba: `Maps/Hub/CastleTownTilesDemo.tscn`

- Tiene dos `TileMapLayer` vacías: `Fondo` y `Props`.
- Ambas usan el mismo TileSet, filtro nearest y `rendering_quadrant_size = 128`.
- `Fondo` va primero para paneles/bandas; `Props` va arriba para edificios,
  decoración, módulos y la cara.
- Abrí la escena, seleccioná una capa, abrí el panel **TileSet** y pintá. El
  palette ya muestra los 214 tiles.

No se modificó `HubMap.tscn`: la escena demo es independiente.

---

## Alinear la base de los edificios

Los edificios incluyen `ground_inset_bottom` y `anchor_offset` en el manifest.
La base (línea de piso) está:

- **1 px** sobre el borde inferior de `sheet_rect` en casi todos.
- **6 px** en `bakery`, porque el cartel separado sobresale 5 px hacia abajo.

Con un `Sprite2D` centrado (el modo por defecto):

```gdscript
sprite.centered = true
sprite.offset = Vector2(0, anchor_offset_y)
```

`anchor_offset_y` ya viene calculado en el manifest. Ejemplos:

| Sprite | `anchor_offset_y` |
|---|---:|
| `cafe` | -79.5 |
| `bakery` | -53.5 |
| `shop` | -56.5 |
| `castle_tower` | -86.5 |

Así la línea de piso queda exactamente en la posición del nodo.

Si preferís `centered = false`, ubicá el nodo en la esquina superior izquierda y
usá `offset.y = -(size.y - ground_inset_bottom)`.

En el TileSet no hace falta calcular esto: `castletown.tres` ya tiene el
`texture_origin` de cada tile.

---

## Notas importantes

- **No hacer chroma-key del negro.** El negro es parte del dibujo (contornos,
  ventanas, paneles). El alpha original ya está limpio y es binario.
- **`castle_panel_a` y `castle_panel_b` tienen fondo negro opaco.** No son
  capas transparentes: si se ponen detrás de otros sprites, los van a tapar.
- La sección **modular de muros** ya está incluida como sources `Modular` y
  `Cara del castillo`. La grilla de 20×20 no tenía líneas pintadas: eran
  separadores transparentes de 1 px; se quitaron al extraer las celdas. El
  `cuadrado_blanco` es un tile sintético agregado a pedido, no proviene del PNG.
- La sección modular no trae piso tileado: solo las piezas de muro, la cara y
  los módulos de 20×20.
- La **UI de tienda** (botones BUY/LOOK/DEALS/ADD, trofeos, tarjetas) tampoco
  está incluida por ahora.
- Las hojas de `tileset/` son para el TileMap; las de `sheets/` y los
  `AtlasTexture` siguen siendo para `Sprite2D`, UI y props individuales.
- El TileSet no incluye piso tileado ni colisiones.
- Godot genera un `.import` por cada hoja al abrir el editor (incluidas las de
  `tileset/`). Conviene commitearlos junto con los PNGs, igual que el `.import`
  de `CastleTown.png`.

---

## Referencias visuales

- `reference.png`: catálogo de los 43 sprites, con nombre y tamaño del dibujo
  (sin contar el margen de 1 px).
- `source_map.png`: la hoja original con los 43 rectángulos numerados y una
  leyenda al costado. Sirve para verificar que ningún recorte quedó descuadrado.

Los números de `source_map.png` coinciden con el orden de `reference.png` y con
el listado de `manifest.json`.
