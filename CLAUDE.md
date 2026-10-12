# RetroLauncher-online: guía para Claude

App de macOS (SwiftUI, un solo archivo) que abre juegos de **Wii/GameCube con Dolphin** y de **Super Nintendo con RetroArch**. Tiene 2 jugadores locales (teclado + DualSense), portadas automáticas, selector de calidad y modo online con enlace de invitación `wii://`.

Estado actual, historial y pendientes: **[HANDOFF.md](HANDOFF.md)**. Léelo antes de seguir trabajando.

## Convenciones

- **Todo en español**: la interfaz, los comentarios, los mensajes de commit y el README.
- La interfaz debe ser **minimalista, sencilla y fácil de entender**. Es el requisito principal del usuario.
- El README es para usuarios finales: cercano, sin lo obvio y sin mencionar el tipo de chip. Su sección "Instrucciones para Claude Code" la siguen otras instancias de Claude para instalar la app, así que debe estar al día.
- Nunca subir juegos. El `.gitignore` excluye `.rvz .iso .wbfs .wia .gcz .ciso .sfc .smc`.

## Compilar y probar

```sh
./build.sh   # binario universal (arm64 + x86_64) → build/Wii.app → copia a /Applications/Wii.app
pkill -x Wii; open /Applications/Wii.app
```

- `swiftc` necesita `-target <arch>-apple-macos14.0`. Sin él usa un SDK más nuevo que el sistema y la app no abre (error -10825).
- Para probar lógica sin interfaz: extrae secciones de `main.swift` con `sed -n '/^enum X/,/^}/p'` a un directorio de `mktemp -d`, añade un `main.swift` de prueba y compila con `swiftc`. Así se probaron el descifrado de NetPlay, la configuración de mandos online, el CRC y el ida y vuelta de los enlaces.
- No hay permiso de captura de pantalla: la interfaz no se puede ver desde Claude. Pide al usuario que la revise.
- En zsh, `set -- $VAR` **no separa palabras**. Usa expansión de parámetros (`${J%% *}`).

## Estructura de `main.swift` (secciones `// MARK:`)

| Sección | Qué hace |
|---|---|
| Rutas (`Paths`) | Dolphin/RetroArch en `/Applications`, juegos en `~/Downloads/Wii Roms` (ruta fija), datos en `~/Library/Application Support/Wii Lanzador/` |
| Juegos (`Platform`, `Game`) | Escanea la carpeta. ID de Wii/GC leído de la cabecera del disco (RVZ/WIA en 0x58, WBFS en 0x200, CISO en 0x8000, ISO en 0). Distingue Wii de GC por los números mágicos en +0x18 / +0x1C. SNES: ID = `SNES-<CRC32 del archivo>` |
| Tipo de control (`ControlMode`) | `sideways` / `nunchuk` / `gamecube` / `snes`. Automático según plataforma y una lista de IDs que usan Nunchuk. El usuario lo cambia por juego (se guarda en `UserDefaults` `controlModes`) |
| Configuración de Dolphin (`DolphinConfig`) | Reescribe `WiimoteNew.ini` y `GCPadNew.ini` en cada partida. `Dolphin.ini` solo se escribe la primera vez. En online combina teclado y DualSense en el Jugador 1 |
| Calidad gráfica (`Quality`) | Presets que se pasan con `-C` (resolución interna, anisotrópico, MSAA, reescalado). Siempre Metal, doble núcleo, ubershaders asíncronos y carga rápida |
| Online (`Invite`, `NetPlay`, `HostSession`) | Enlace `wii://unirse?...`. Para Dolphin, busca la sala en el índice de NetPlay y descifra el código de anfitrión |
| RetroArch (`RetroArch`) | Descarga el núcleo snes9x, escribe `retroarch.cfg`, elige servidor de retransmisión y busca la sala en el lobby de libretro |
| Portadas (`CoverStore`) | Las incluidas en `covers/`, luego la caché y por último GameTDB (Wii/GC, por región) o libretro-thumbnails (SNES, por nombre No-Intro) |
| Estado (`Launcher`) | Vigila la carpeta (`DispatchSource` + 1,5 s de espera), detecta el DualSense (`GameController`), lanza procesos y lleva la lógica de alojar/unirse |
| Interfaz | `ContentView` (cuadrícula), `GameCard`, `HostView`, `JoinView`, `ControlsView` |

## Datos verificados en el código fuente (no adivinar)

Comprobados en Dolphin **2609a** y RetroArch **v1.22.2**. Si cambian las versiones, vuelve a comprobarlos en sus repositorios.

**Dolphin**
- Prefijos de `-C <Sistema>.<Sección>.<Clave>=<valor>`: `Dolphin.` (Main), `Graphics.` (**no** `GFX.`, que se ignora sin avisar), `Wiimote.`, `GCPad.`, `SYSCONF.`.
- Dispositivos: teclado `Quartz/0/Keyboard & Mouse`, mando `SDL/0/DualSense Wireless Controller`.
- Nombres de entradas SDL: `Button S/E/W/N`, `Shoulder L/R`, `Trigger L/R`, `Pad N/S/W/E`, `Left X+`… (Y+ = arriba), `Back`, `Start`, `Guide`, `Motor L/R`. Teclado: `` `Up Arrow` ``, `Return`, `Space`, `Backspace`, `` `Cursor X-` ``…
- Para combinar dispositivos en una expresión: `` X | `SDL/0/DualSense Wireless Controller:Button S` ``.
- Con `Options/Sideways Wiimote = True`, Dolphin rota solo la cruceta y la inclinación.
- Nunchuk: `Extension = Nunchuk` y claves `Nunchuk/Buttons/C`, `Nunchuk/Stick/Up`… `Extension/Attach MotionPlus = False`.
- Puertos de GC: `Dolphin.Core.SIDevice0..3` (6 = mando, 0 = nada). En modo Wiimote se ponen a 0 para que no haya doble señal.
- Atajos por defecto: `Esc` para parar, ⌥+Enter para pantalla completa. Con `-b` (modo batch), parar cierra Dolphin.
- **NetPlay no se puede iniciar por línea de comandos.** Se rellenan `Dolphin.NetPlay.*` (TraversalChoice, HostCode, Nickname, UseIndex, IndexName, IndexPassword, IndexRegion) y el usuario pulsa Host/Connect.
- El código de anfitrión solo es legible en `https://lobby.dolphin-emu.org/v0/list`. Con contraseña, `server_id` va cifrado (XOR + suma de control, codificado en nibbles desde 'A'; ver `NetPlay.decrypt`).
- La lista de juegos del anfitrión se reduce a un solo juego mediante un enlace duro en `Application Support/Wii Lanzador/NetPlay`.
- El servidor asigna automáticamente mando y Wiimote a quien se une.

**RetroArch**
- CLI: `-L <núcleo> --config <cfg> -H` (alojar) / `-C <host> --port <p> --mitm-session <id>` (unirse) y `--nick`.
- El lobby `http://lobby.libretro.com/list/` **solo funciona por http**: https se cuelga. Necesita la excepción ATS de `build.sh`.
- El anfitrión con `netplay_use_mitm_server = true` aparece en unos 6 s con `mitm_ip`, `mitm_port` y `mitm_session`. Se busca por `username` (apodo único `Nombre-xxxx`).
- **El que se une siempre tiene que escribir la contraseña en un cuadro de diálogo**: `netplay_password` se ignora en el cliente. Por eso se usa un PIN de 4 cifras, que la app muestra al que se une.
- Probado de punta a punta con dos RetroArch en la misma Mac: conexión directa y por retransmisión. Sin contraseña entra como Jugador 2.
- Con varias instancias, RetroArch carga el juego dos veces al arrancar. Es normal.
- El núcleo se descarga de `buildbot.libretro.com/nightly/apple/osx/<arm64|x86_64>/latest/snes9x_libretro.dylib.zip`.

## Commits en este repositorio

Usa la identidad local del repositorio (ya configurada): `brandonP2 <103422988+brandonP2@users.noreply.github.com>`. **No** uses el correo global de git, que es personal. Termina los mensajes con la línea `Co-Authored-By` que indique el sistema.
