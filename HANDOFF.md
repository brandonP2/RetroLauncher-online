# Handoff: estado del proyecto

*Última actualización: 18 de octubre de 2026*

Documento para retomar el trabajo en una sesión nueva. Los detalles técnicos están en [CLAUDE.md](CLAUDE.md).

## Resumen

Lanzador para Mac llamado **"Wii"**. Repositorio: **https://github.com/brandonP2/RetroLauncher-online** (público). Instalado en `/Applications/Wii.app`. Usa Dolphin 2609a y RetroArch 1.22.2, instalados con Homebrew (`dolphin`, `retroarch-metal`).

## Qué se construyó, en orden

1. App mínima con portadas: abre los juegos con Dolphin en modo batch. Teclado como Jugador 1, DualSense como Jugador 2, Wiimote de lado.
2. Calidad gráfica: presets Rendimiento / Equilibrada / Máxima (720p / 1080p / 1440p) y ajustes de rendimiento. *Error corregido:* los ajustes usaban el prefijo `GFX.` y Dolphin los ignoraba. El correcto es `Graphics.`.
3. Cuatro mejoras: detección de juegos en vivo, portadas automáticas, cuadrícula con scroll y tipo de control por juego (de lado / Nunchuk / GameCube).
4. README para usuarios finales, con instrucciones para Claude Code.
5. Online con Dolphin NetPlay: botón "Online", enlace `wii://`, descifrado del código de anfitrión, avisos si falta el juego o no coincide la versión.
6. Super Nintendo con RetroArch: el usuario añadió *Super Bomberman 4* (`.sfc`). Online casi automático por servidor de retransmisión, con PIN.
7. Compilación universal (Apple + Intel), escaneo de datos sensibles y publicación en GitHub.
8. (16 oct) El usuario añadió *Super Mario 64* (`.z64`) y una carpeta `DOOM/` (versión de DOS) y la app no los detectaba. Se añadieron **Nintendo 64** (núcleo mupen64plus_next, con online igual que SNES) y **DOOM** (núcleo prboom, un jugador, sin online). La caché de CRC evita releer las ROM en cada escaneo.
   - Mario 64 salía en **negro**: GLideN64 no dibuja en Mac. Se cambió a ParaLLEl-RDP/RSP por Vulkan; el selector de calidad elige el reescalado (1x/2x/4x).
   - En DOOM la **demo de presentación no se quitaba**: PrBoom ignora el teclado salvo que el puerto 1 sea `RETRO_DEVICE_KEYBOARD`. Ahora se elige Teclado o DualSense debajo de la portada.
   - El `DOOM.WAD` del usuario es DOOM v1.9 registrada (MD5 `1cd63c5ddff1bf8ce844237f580e9cf3`). El resto de la carpeta (EXE, drivers de sonido de DOS) no se usa.
9. (18 oct) La ventana de **Controles** se cortaba: crecía según la pestaña y quedaba más alta que la ventana principal. Ahora la tabla tiene altura fija (300 pt) con scroll. El usuario lo confirmó.
10. (18 oct) **Push a GitHub.** En el remoto había un commit que no estaba en local (`9004b8f`, "Carpeta de juegos configurable desde la app", hecho desde otro clon). Se combinó con rebase sin conflictos. Ese commit tenía de autor un nombre real y una dirección de la red local, en vez de la identidad del repositorio: con permiso del usuario se reescribió el autor de los commits con la identidad brandonP2 y se hizo `push --force-with-lease`. El historial remoto ahora es `668d989 → 3dd8356 → 21476ca → 247a356`. **Antes de cada push, revisa también el autor de los commits remotos** (`git log origin/main --format='%an <%ae>'`), no solo los archivos.

## Qué está probado y qué no

| Función | Estado |
|---|---|
| Compilar / abrir la app | ✅ Probado |
| Detectar juegos nuevos y descargar portadas (Wii/GC) | ✅ Probado con un archivo falso de GameCube |
| Descifrado del código de NetPlay de Dolphin | ✅ Probado contra el algoritmo de Dolphin |
| Configuración online de mandos (teclado y DualSense en el Jugador 1) | ✅ Probado: el INI generado es correcto |
| Enlaces `wii://` abren la app | ✅ Probado (LaunchServices) |
| SNES: crear sala + lobby + unirse por retransmisión | ✅ Probado con dos RetroArch en la misma Mac |
| SNES: CRC/ID del juego coincide con el de RetroArch | ✅ `SNES-4C58462D` |
| Jugar Wii en local con teclado + DualSense | ⚠️ El usuario confirmó que la calidad mejora; los controles no se han confirmado explícitamente |
| Nunchuk / mando de GameCube | ❌ Sin probar en partida |
| SNES en local (teclado = J1, DualSense = J2) | ❌ Sin probar |
| N64 y DOOM: detección y arranque del núcleo | ✅ Probado (RetroArch carga los dos juegos) |
| N64: imagen | ✅ Arreglado: con GLideN64 salía negro; con ParaLLEl + Vulkan llega a «PRESS START» (captura con `--max-frames-ss`) |
| DOOM: teclado | ⚠️ Arreglado según el código del núcleo (antes la demo no se quitaba); falta que el usuario lo confirme |
| N64 y DOOM: controles en partida | ❌ Sin confirmar por el usuario |
| N64 online | ❌ Sin probar (mismo flujo que SNES) |
| Online real entre dos casas (Dolphin y SNES) | ❌ Sin probar: hace falta una segunda Mac |
| SNES: PIN escrito en el cuadro de RetroArch | ❌ Sin probar a mano (es el flujo estándar de RetroArch) |
| Mac Intel | ❌ Compila (x86_64) pero sin probar |
| Ventana de Controles | ✅ Confirmado por el usuario |
| Elegir la carpeta de juegos | ⚠️ Compila tras el rebase; no probado en esta sesión |
| Interfaz | ⚠️ No se puede ver desde Claude (no hay permiso de captura de pantalla). Para ver la imagen de un juego de RetroArch, usa `--max-frames-ss` |

## Decisiones tomadas (y por qué)

- **Dolphin y RetroArch como motores**: escribir un emulador propio no es viable. La app solo los configura y los abre.
- **Configuración aislada** en `~/Library/Application Support/Wii Lanzador/`, para no tocar la configuración personal de Dolphin o RetroArch.
- **NetPlay de Dolphin con pasos manuales**: Dolphin no permite iniciarlo desde fuera. La app rellena todo y guía al usuario.
- **Sala de Dolphin publicada con contraseña** en el índice público: es la única forma de que la app lea el código. Nadie puede entrar sin el enlace.
- **PIN de 4 cifras en SNES**: RetroArch obliga a escribir la contraseña a mano, y sin ella cualquiera del lobby podría entrar. Además, `netplay_max_connections = 1`.
- **Un jugador por computadora en online**: no está preparada una partida de 3 (2 locales + 1 remoto).
- **README sin mencionar el chip**: el usuario lo pidió. Por eso la compilación es universal.
- **Identificador de la app `local.wii-lanzador`**: se quitó el nombre del usuario.
- **N64 con ParaLLEl + Vulkan** en vez de GLideN64: es lo único que muestra imagen en Mac con chip Apple, y además usa la GPU.
- **DOOM: Teclado o DualSense, no los dos**: limitación de PrBoom. Teclado por defecto. `Esc` es el menú de DOOM, así que no cierra el juego (se sale con *Quit Game* o cerrando la ventana).
- **Historial de git reescrito el 18 oct** para quitar datos personales del autor. Si alguien tenía un clon anterior, tiene que hacer `git fetch && git reset --hard origin/main`.

## Limitaciones conocidas

- Solo DualSense como mando: el nombre del dispositivo está fijo en la configuración de Dolphin.
- DOOM es de un jugador y sin online. Nintendo 64 online está sin probar.
- El commit antiguo `9004b8f` puede seguir accesible en GitHub por su enlace directo hasta que GitHub lo limpie (se puede pedir a su soporte).
- Juegos que necesitan movimiento real (Wii Sports, Skyward Sword) no se juegan bien.
- WhatsApp e iMessage pueden no hacer clicable `wii://`. Para eso existe "Unirse a partida", que lee el portapapeles.
- La versión del emulador debe coincidir entre jugadores. Homebrew puede actualizarla y romper la compatibilidad.

## Ideas pendientes (sugeridas al usuario, no pedidas todavía)

- Packs de texturas HD (Dolphin `HiresTextures`) para acercarse a una "remasterización".
- Filtros de imagen opcionales (opción "Mejorado").
- Aceptar cualquier mando (PS4, Xbox, Switch Pro) con detección automática.
- Que la app ofrezca instalar Dolphin o RetroArch si faltan.
- Publicar la app ya compilada en GitHub Releases (la app no está firmada: Gatekeeper la bloquea la primera vez).
- Más consolas con RetroArch (NES, GBA…).
- DOOM: ratón para apuntar (opción `prboom-mouse_on`) y cargar mods (`.wad` extra).
