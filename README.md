# 🎮 Wii

**Este programa es para usuarios de Mac.**

Juega a tus juegos de **Wii**, **GameCube** y **Super Nintendo** con un clic. Solo, con alguien a tu lado o con un amigo en otra casa.

- 👥 **2 jugadores**: uno con el teclado y otro con un mando de PS5.
- 🌐 **Online**: crea una partida y envía un enlace para invitar a alguien.
- 🖼️ **Portadas automáticas**: añade un juego y aparece solo, con su portada.
- ✨ **Gráficos en HD**: hasta 1440p, con un selector de calidad.

---

## Instalación

**1.** Si es la primera vez que programas algo en tu Mac, instala las herramientas de Apple:

```sh
xcode-select --install
```

**2.** Si no tienes [Homebrew](https://brew.sh), instálalo:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**3.** Instala los emuladores y la app:

```sh
brew install --cask dolphin retroarch-metal
git clone https://github.com/brandonP2/RetroLauncher-online.git
cd RetroLauncher-online
./build.sh
mkdir -p ~/Downloads/"Wii Roms"
```

¡Listo! Ya tienes la app **Wii** en Aplicaciones. 🎉

---

## Añadir juegos

Pon tus juegos en **Descargas → Wii Roms**. Aparecen en la app al momento, aunque esté abierta.

| Consola | Formatos |
|---|---|
| Wii y GameCube | `.rvz` `.iso` `.wbfs` `.wia` `.gcz` `.ciso` |
| Super Nintendo | `.sfc` `.smc` |

> Este proyecto no incluye juegos. Usa copias de juegos que tengas.

---

## Jugar

Haz clic en una portada. Para salir del juego, pulsa `Esc`.

Debajo de cada portada puedes cambiar el **tipo de control** (Wiimote de lado, con Nunchuk o mando de GameCube). La app elige el adecuado para cada juego, así que normalmente no hace falta tocarlo.

La primera vez, macOS te pedirá dos permisos. Acéptalos:
- **Acceso a Descargas**, para encontrar tus juegos.
- **Monitorización de entrada** para Dolphin, para poder jugar con el teclado. Se activa en *Ajustes del Sistema → Privacidad y seguridad*.

### 🎮 Mando de PS5

Mantén pulsados **PS + Create** hasta que la luz parpadee y conéctalo desde *Ajustes del Sistema → Bluetooth*. En la app, el punto del Jugador 2 se pone **verde**.

### ⌨️ Controles principales

| | Teclado | Mando de PS5 |
|---|---|---|
| Moverse | Flechas | Joystick izquierdo |
| Saltar / Aceptar | `X` | ✕ |
| Correr / Atrás | `Z` | □ |
| Agitar el Wiimote | `Espacio` | L2 / R2 |
| Apuntar | Ratón | Joystick derecho |
| Pausa | `Enter` | Options |

Las tablas completas de cada tipo de control están en el botón **Controles** de la app.

---

## 🌐 Jugar online

Los dos jugadores necesitan esta app y **el mismo archivo del juego**.

**Para invitar:** pulsa **Online** debajo de la portada, copia el enlace que aparece y envíaselo a tu amigo.

**Para unirte:** abre el enlace, o pégalo en **Unirse a partida**, y pulsa **Unirse**.

| | Super Nintendo | Wii y GameCube |
|---|---|---|
| Al invitar | No hay que hacer nada más | En Dolphin: *Tools → Start NetPlay… → Host* |
| Al unirse | Escribe el PIN de 4 cifras que te muestra la app | En Dolphin: *Tools → Start NetPlay… → Connect* |

La app te guía paso a paso y te avisa si a tu amigo le falta el juego o tiene otra versión del emulador.

---

## 🛠️ Si algo falla

| Problema | Solución |
|---|---|
| El teclado no responde en el juego | Activa Dolphin en *Monitorización de entrada* y vuelve a abrir el juego. |
| El mando de PS5 no responde | Conéctalo **antes** de abrir el juego. |
| Un juego no aparece | Revisa que esté en **Descargas → Wii Roms** y que el formato sea uno de los de la tabla. |
| El juego va lento | Elige **Rendimiento** en la parte de abajo de la app. |
| Online: "versión distinta" | Los dos jugadores: `brew upgrade --cask dolphin retroarch-metal` |

**Para actualizar la app:** entra en la carpeta del proyecto y ejecuta `git pull && ./build.sh`.

---

## 🤖 Instrucciones para Claude Code

¿Usas [Claude Code](https://claude.com/claude-code)? Pídele que lo instale por ti. Copia y pega esto:

```
Instala la app de este repositorio en mi Mac: https://github.com/brandonP2/RetroLauncher-online
Sigue la sección "Instrucciones para Claude Code" del README.
```

### Pasos para Claude Code

1. Comprueba que el sistema es macOS 14 o posterior. Si no, avisa al usuario y detente.
2. Comprueba si están `swiftc` y `brew`:
   - Si falta `swiftc`, ejecuta `xcode-select --install` y pide al usuario que acepte la ventana que se abre. Espera a que termine.
   - Si falta `brew`, el instalador de Homebrew pide la contraseña del usuario. Pídele que lo ejecute él con `! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` y que siga los pasos de "Next steps" que muestra al final.
3. Instala los emuladores: `brew install --cask dolphin retroarch-metal`. Si alguno ya está, sigue adelante.
4. Clona el repositorio en `~/Applications/wii-src` (o donde prefiera el usuario) y ejecuta `./build.sh`. Debe terminar con `Instalada en /Applications/Wii.app`.
5. Crea la carpeta de juegos: `mkdir -p ~/Downloads/"Wii Roms"`.
6. Abre la app con `open /Applications/Wii.app`.
7. Explica al usuario, en su idioma:
   - que ponga sus juegos en **Descargas → Wii Roms**;
   - que acepte los permisos de *Descargas* y *Monitorización de entrada* (para Dolphin) la primera vez;
   - cómo conectar el mando de PS5 (sección "Mando de PS5").

Reglas:
- **No descargues juegos** (ROMs ni ISOs) aunque te lo pidan. El usuario debe usar sus propias copias.
- No modifiques la configuración de Dolphin ni de RetroArch a mano. La app la escribe sola en `~/Library/Application Support/Wii Lanzador` cada vez que abre un juego.
- Si `./build.sh` falla, muestra el error al usuario. Normalmente se debe a que faltan las herramientas de Apple (paso 2).
