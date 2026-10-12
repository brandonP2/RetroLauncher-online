import AppKit
import GameController
import SwiftUI

// MARK: - Rutas

enum Paths {
    static let dolphin = URL(fileURLWithPath: "/Applications/Dolphin.app/Contents/MacOS/Dolphin")
    static let romsFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads/Wii Roms")
    static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Wii Lanzador")
    static var dolphinUser: URL { support.appendingPathComponent("Dolphin") }
    static var config: URL { dolphinUser.appendingPathComponent("Config") }
    static var covers: URL { support.appendingPathComponent("covers") }
    static var netplayGames: URL { support.appendingPathComponent("NetPlay") }
    static let retroarch = URL(fileURLWithPath: "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
    static var retroarchConfig: URL { support.appendingPathComponent("RetroArch/retroarch.cfg") }
    static var snesCore: URL { support.appendingPathComponent("RetroArch/cores/snes9x_libretro.dylib") }
}

// MARK: - Juegos

enum Platform {
    case wii, gamecube, snes

    /// Wii y GameCube van con Dolphin; Super Nintendo con RetroArch.
    var usesRetroArch: Bool { self == .snes }
}

struct Game: Identifiable, Equatable {
    let id: String  // ID del disco (p. ej. SMNE01) o el nombre del archivo si no se puede leer
    let title: String
    let url: URL
    let platform: Platform
    var coverName = ""  // nombre del archivo sin etiquetas, para buscar portadas de RetroArch

    var hasDiscID: Bool { id.count == 6 && id.allSatisfy { $0.isLetter || $0.isNumber } }

    static let extensions: Set<String> = ["rvz", "wia", "iso", "wbfs", "gcz", "ciso"]
    static let snesExtensions: Set<String> = ["sfc", "smc"]

    static func scan(_ folder: URL) -> [Game] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return files
            .compactMap { url -> Game? in
                let ext = url.pathExtension.lowercased()
                if snesExtensions.contains(ext) {
                    // El ID es el CRC32 del archivo: así dos personas con la misma ROM coinciden.
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return Game(id: String(format: "SNES-%08X", crc32(data)), title: cleanTitle(url),
                                url: url, platform: .snes, coverName: coverName(url))
                }
                guard extensions.contains(ext) else { return nil }
                let header = readHeader(url)
                return Game(id: header?.id ?? url.lastPathComponent, title: cleanTitle(url),
                            url: url, platform: header?.platform ?? .wii)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    // Cada formato guarda la cabecera del disco en un sitio distinto. GCZ va comprimido: no se lee.
    private static func readHeader(_ url: URL) -> (id: String, platform: Platform)? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let magic = String(data: (try? h.read(upToCount: 4)) ?? Data(), encoding: .ascii) ?? ""
        let offset: UInt64
        switch magic {
        case "RVZ\u{1}", "WIA\u{1}": offset = 0x58
        case "WBFS": offset = 0x200
        case "CISO": offset = 0x8000
        default: offset = 0
        }
        try? h.seek(toOffset: offset)
        let d = [UInt8]((try? h.read(upToCount: 0x20)) ?? Data())
        guard d.count == 0x20, let id = String(bytes: d[0..<6], encoding: .ascii),
              id.allSatisfy({ $0.isLetter || $0.isNumber })
        else { return nil }
        let wiiMagic: [UInt8] = [0x5D, 0x1C, 0x9E, 0xA3]
        let gcMagic: [UInt8] = [0xC2, 0x33, 0x9F, 0x3D]
        if Array(d[0x18..<0x1C]) == wiiMagic { return (id, .wii) }
        if Array(d[0x1C..<0x20]) == gcMagic { return (id, .gamecube) }
        return nil
    }

    // "Super Bomberman 4 (Japan) [T-En by Svambo v1.0]" -> "Super Bomberman 4 (Japan)"
    private static func coverName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    }

    static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crcTable[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) }
    }

    // "New Super Mario Bros. Wii (USA) (En,Fr,Es) (Rev 1)" -> "New Super Mario Bros. Wii"
    private static func cleanTitle(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let clean = name.replacingOccurrences(of: #"\s*[\(\[].*$"#, with: "", options: .regularExpression)
        return clean.isEmpty ? name : clean
    }
}

// MARK: - Tipo de control

enum ControlMode: String, CaseIterable, Identifiable {
    case sideways, nunchuk, gamecube, snes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sideways: "Wiimote de lado"
        case .nunchuk: "Wiimote + Nunchuk"
        case .gamecube: "Mando de GameCube"
        case .snes: "Mando de Super Nintendo"
        }
    }

    // Juegos de Wii conocidos que se juegan con Nunchuk (primeras 3 letras del ID, cualquier región)
    private static let nunchukGames: Set<String> = [
        "RMG",  // Super Mario Galaxy
        "SB4",  // Super Mario Galaxy 2
        "RZD",  // Zelda: Twilight Princess
        "RM3",  // Metroid Prime 3
        "R3M",  // Metroid Prime Trilogy
        "RSB",  // Super Smash Bros. Brawl
        "RUU",  // Animal Crossing: City Folk
    ]

    static func automatic(for game: Game) -> ControlMode {
        if game.platform == .gamecube { return .gamecube }
        if game.platform == .snes { return .snes }
        return nunchukGames.contains(String(game.id.prefix(3))) ? .nunchuk : .sideways
    }

    static func options(for game: Game) -> [ControlMode] {
        switch game.platform {
        case .gamecube: [.gamecube]
        case .snes: [.snes]
        case .wii: [.sideways, .nunchuk, .gamecube]
        }
    }
}

// MARK: - Configuración de Dolphin

enum DolphinConfig {
    static let keyboardDevice = "Quartz/0/Keyboard & Mouse"
    static let dualsenseDevice = "SDL/0/DualSense Wireless Controller"

    // Wiimote de lado — Jugador 1: teclado
    static let sidewaysKeyboard = """
        Buttons/A = C
        Buttons/B = V
        Buttons/1 = Z
        Buttons/2 = X
        Buttons/- = Backspace
        Buttons/+ = Return
        Buttons/Home = H
        D-Pad/Up = `Up Arrow`
        D-Pad/Down = `Down Arrow`
        D-Pad/Left = `Left Arrow`
        D-Pad/Right = `Right Arrow`
        Shake/X = Space
        Shake/Y = Space
        Shake/Z = Space
        Tilt/Left = A
        Tilt/Right = D
        IR/Up = `Cursor Y-`
        IR/Down = `Cursor Y+`
        IR/Left = `Cursor X-`
        IR/Right = `Cursor X+`
        Options/Sideways Wiimote = True
        Extension = None
        """

    // Wiimote de lado — Jugador 2: DualSense
    static let sidewaysDualSense = """
        Buttons/A = `Button E`
        Buttons/B = `Button N`
        Buttons/1 = `Button W`
        Buttons/2 = `Button S`
        Buttons/- = `Back`
        Buttons/+ = `Start`
        Buttons/Home = `Guide`
        D-Pad/Up = `Pad N` | `Left Y+`
        D-Pad/Down = `Pad S` | `Left Y-`
        D-Pad/Left = `Pad W` | `Left X-`
        D-Pad/Right = `Pad E` | `Left X+`
        Shake/X = `Trigger L` | `Trigger R`
        Shake/Y = `Trigger L` | `Trigger R`
        Shake/Z = `Trigger L` | `Trigger R`
        Tilt/Left = `Shoulder L`
        Tilt/Right = `Shoulder R`
        IR/Up = `Right Y+`
        IR/Down = `Right Y-`
        IR/Left = `Right X-`
        IR/Right = `Right X+`
        IR/Relative Input = True
        Rumble/Motor = `Motor L` | `Motor R`
        Options/Sideways Wiimote = True
        Extension = None
        """

    // Wiimote + Nunchuk — Jugador 1: teclado
    static let nunchukKeyboard = """
        Buttons/A = X
        Buttons/B = C
        Buttons/1 = 1
        Buttons/2 = 2
        Buttons/- = Backspace
        Buttons/+ = Return
        Buttons/Home = H
        D-Pad/Up = W
        D-Pad/Down = S
        D-Pad/Left = A
        D-Pad/Right = D
        Shake/X = Space
        Shake/Y = Space
        Shake/Z = Space
        IR/Up = `Cursor Y-`
        IR/Down = `Cursor Y+`
        IR/Left = `Cursor X-`
        IR/Right = `Cursor X+`
        Options/Sideways Wiimote = False
        Extension = Nunchuk
        Nunchuk/Buttons/C = V
        Nunchuk/Buttons/Z = Z
        Nunchuk/Stick/Up = `Up Arrow`
        Nunchuk/Stick/Down = `Down Arrow`
        Nunchuk/Stick/Left = `Left Arrow`
        Nunchuk/Stick/Right = `Right Arrow`
        """

    // Wiimote + Nunchuk — Jugador 2: DualSense
    static let nunchukDualSense = """
        Buttons/A = `Button S`
        Buttons/B = `Trigger R`
        Buttons/1 = `Button E`
        Buttons/2 = `Button N`
        Buttons/- = `Back`
        Buttons/+ = `Start`
        Buttons/Home = `Guide`
        D-Pad/Up = `Pad N`
        D-Pad/Down = `Pad S`
        D-Pad/Left = `Pad W`
        D-Pad/Right = `Pad E`
        Shake/X = `Button W`
        Shake/Y = `Button W`
        Shake/Z = `Button W`
        IR/Up = `Right Y+`
        IR/Down = `Right Y-`
        IR/Left = `Right X-`
        IR/Right = `Right X+`
        IR/Relative Input = True
        Rumble/Motor = `Motor L` | `Motor R`
        Options/Sideways Wiimote = False
        Extension = Nunchuk
        Nunchuk/Buttons/C = `Shoulder L`
        Nunchuk/Buttons/Z = `Trigger L`
        Nunchuk/Stick/Up = `Left Y+`
        Nunchuk/Stick/Down = `Left Y-`
        Nunchuk/Stick/Left = `Left X-`
        Nunchuk/Stick/Right = `Left X+`
        """

    // Mando de GameCube — Jugador 1: teclado
    static let gamecubeKeyboard = """
        Buttons/A = X
        Buttons/B = Z
        Buttons/X = C
        Buttons/Y = V
        Buttons/Z = Space
        Buttons/Start = Return
        Main Stick/Up = `Up Arrow`
        Main Stick/Down = `Down Arrow`
        Main Stick/Left = `Left Arrow`
        Main Stick/Right = `Right Arrow`
        C-Stick/Up = I
        C-Stick/Down = K
        C-Stick/Left = J
        C-Stick/Right = L
        Triggers/L = Q
        Triggers/R = E
        Triggers/L-Analog = Q
        Triggers/R-Analog = E
        D-Pad/Up = W
        D-Pad/Down = S
        D-Pad/Left = A
        D-Pad/Right = D
        """

    // Mando de GameCube — Jugador 2: DualSense
    static let gamecubeDualSense = """
        Buttons/A = `Button S`
        Buttons/B = `Button W`
        Buttons/X = `Button E`
        Buttons/Y = `Button N`
        Buttons/Z = `Shoulder R`
        Buttons/Start = `Start`
        Main Stick/Up = `Left Y+`
        Main Stick/Down = `Left Y-`
        Main Stick/Left = `Left X-`
        Main Stick/Right = `Left X+`
        C-Stick/Up = `Right Y+`
        C-Stick/Down = `Right Y-`
        C-Stick/Left = `Right X-`
        C-Stick/Right = `Right X+`
        Triggers/L = `Trigger L`
        Triggers/R = `Trigger R`
        Triggers/L-Analog = `Trigger L`
        Triggers/R-Analog = `Trigger R`
        D-Pad/Up = `Pad N`
        D-Pad/Down = `Pad S`
        D-Pad/Left = `Pad W`
        D-Pad/Right = `Pad E`
        Rumble/Motor = `Motor L` | `Motor R`
        """

    static let main = """
        [Interface]
        ConfirmStop = False
        PauseOnFocusLost = False
        [Analytics]
        PermissionAsked = True
        Enabled = False
        [AutoUpdate]
        UpdateTrack =

        """

    private static func section(_ name: String, device: String?, source: Int? = nil,
                                body: String = "") -> String {
        var lines = ["[\(name)]"]
        if let device { lines.append("Device = \(device)") }
        if let source { lines.append("Source = \(source)") }
        if !body.isEmpty { lines.append(body) }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Escribe la configuración de mandos para el tipo de control elegido y devuelve los
    /// argumentos que conectan (o desconectan) los puertos de GameCube.
    /// En online cada computadora controla a un solo jugador: une teclado y DualSense en el
    /// Jugador 1 para que se pueda usar cualquiera de los dos.
    private static func combined(_ keyboard: String, _ dualsense: String) -> String {
        func parse(_ body: String) -> [(key: String, value: String)] {
            body.split(separator: "\n").compactMap { line in
                guard let r = line.range(of: " = ") else { return nil }
                return (String(line[..<r.lowerBound]), String(line[r.upperBound...]))
            }
        }
        func qualify(_ expr: String) -> String {
            expr.replacingOccurrences(of: "`([^`]+)`", with: "`\(dualsenseDevice):$1`",
                                      options: .regularExpression)
        }
        let settings: Set = ["Options/Sideways Wiimote", "Extension"]
        let kb = parse(keyboard), ds = parse(dualsense)
        let kbMap = Dictionary(kb, uniquingKeysWith: { a, _ in a })
        let dsMap = Dictionary(ds, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var lines: [String] = []
        for key in (kb + ds).map(\.key) where seen.insert(key).inserted {
            if key == "IR/Relative Input" { continue }  // el ratón necesita puntero absoluto
            let value = settings.contains(key)
                ? (kbMap[key] ?? dsMap[key])!
                : [kbMap[key], dsMap[key].map(qualify)].compactMap { $0 }.joined(separator: " | ")
            lines.append("\(key) = \(value)")
        }
        return lines.joined(separator: "\n")
    }

    static func write(for mode: ControlMode, online: Bool = false) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.config, withIntermediateDirectories: true)

        // Los controles se reescriben siempre para que nunca se desconfiguren.
        let wiimotes: String
        let gcpads: String
        switch mode {
        case .sideways, .nunchuk:
            let (kb, ds) = mode == .sideways
                ? (sidewaysKeyboard, sidewaysDualSense) : (nunchukKeyboard, nunchukDualSense)
            let common = "\nExtension/Attach MotionPlus = False"
            let player1 = online ? combined(kb, ds) : kb
            wiimotes = section("Wiimote1", device: keyboardDevice, source: 1, body: player1 + common)
                + section("Wiimote2", device: dualsenseDevice, source: 1, body: ds + common)
            gcpads = section("GCPad1", device: keyboardDevice) + section("GCPad2", device: dualsenseDevice)
        case .gamecube, .snes:
            wiimotes = section("Wiimote1", device: keyboardDevice, source: 0)
                + section("Wiimote2", device: dualsenseDevice, source: 0)
            let player1 = online ? combined(gamecubeKeyboard, gamecubeDualSense) : gamecubeKeyboard
            gcpads = section("GCPad1", device: keyboardDevice, body: player1)
                + section("GCPad2", device: dualsenseDevice, body: gamecubeDualSense)
        }
        let unused = ["Wiimote3", "Wiimote4", "BalanceBoard"]
            .map { section($0, device: nil, source: 0) }.joined()
        try (wiimotes + unused).write(
            to: Paths.config.appendingPathComponent("WiimoteNew.ini"), atomically: true, encoding: .utf8)
        try gcpads.write(
            to: Paths.config.appendingPathComponent("GCPadNew.ini"), atomically: true, encoding: .utf8)

        // Dolphin.ini solo la primera vez, para respetar ajustes que hagas después.
        let mainIni = Paths.config.appendingPathComponent("Dolphin.ini")
        if !fm.fileExists(atPath: mainIni.path) {
            try main.write(to: mainIni, atomically: true, encoding: .utf8)
        }

        // Puertos de GameCube: 6 = mando estándar, 0 = nada. En modo Wiimote se desconectan
        // para que el teclado y el DualSense no manden doble señal.
        let pad = mode == .gamecube ? 6 : 0
        return (0..<4).flatMap { port in
            ["-C", "Dolphin.Core.SIDevice\(port)=\(port < 2 ? pad : 0)"]
        }
    }
}

// MARK: - Calidad gráfica

enum Quality: String, CaseIterable, Identifiable {
    case performance = "Rendimiento"
    case balanced = "Equilibrada"
    case max = "Máxima"

    var id: String { rawValue }

    // Resolución interna (múltiplo de 640×528), filtrado anisotrópico (0…4 = 1x…16x),
    // MSAA (muestras) y reescalado de salida (4 = Catmull-Rom nítido, 6 = Area Sampling)
    private var settings: (scale: Int, aniso: Int, msaa: Int, resampling: Int) {
        switch self {
        case .performance: (2, 3, 1, 4)  // ~720p, 8x, sin MSAA, reescalado nítido
        case .balanced: (3, 4, 2, 4)  // ~1080p, 16x, MSAA 2x, reescalado nítido
        case .max: (4, 4, 4, 6)  // ~1440p (pantalla nativa), 16x, MSAA 4x, supermuestreo
        }
    }

    var arguments: [String] {
        let s = settings
        let overrides = [
            // Gráficos
            "Graphics.Settings.InternalResolution=\(s.scale)",
            "Graphics.Enhancements.MaxAnisotropy=\(s.aniso)",
            "Graphics.Settings.MSAA=\(s.msaa)",
            "Graphics.Enhancements.OutputResampling=\(s.resampling)",
            "Graphics.Enhancements.ArbitraryMipmapDetection=True",
            "Graphics.Hardware.VSync=True",
            // Rendimiento: Metal nativo, shaders sin tirones, carga rápida
            "Dolphin.Core.GFXBackend=Metal",
            "Dolphin.Core.CPUThread=True",
            "Dolphin.Core.FastDiscSpeed=True",
            "Graphics.Settings.ShaderCompilationMode=2",
            "Graphics.Settings.WaitForShadersBeforeStarting=True",
        ]
        return overrides.flatMap { ["-C", $0] }
    }
}

// MARK: - Online (NetPlay de Dolphin)

/// Enlace de invitación.
/// Wii/GameCube (Dolphin): wii://unirse?codigo=…&juego=…&titulo=…&v=…&anfitrion=…
/// Super Nintendo (RetroArch): además sistema=snes, relay, puerto y clave; «codigo» es la sesión.
struct Invite: Equatable {
    var system = "wii"  // "wii" (Dolphin) o "snes" (RetroArch)
    let code: String  // código de anfitrión de Dolphin, o sesión del servidor de RetroArch
    let gameID: String
    let title: String
    let version: String  // versión del emulador del anfitrión
    let host: String
    var relay: String?
    var port: Int?
    var password: String?

    var usesRetroArch: Bool { system == "snes" }

    var url: URL {
        var c = URLComponents()
        c.scheme = "wii"
        c.host = "unirse"
        var items: [URLQueryItem] = [
            .init(name: "codigo", value: code), .init(name: "juego", value: gameID),
            .init(name: "titulo", value: title), .init(name: "v", value: version),
            .init(name: "anfitrion", value: host),
        ]
        if usesRetroArch {
            items += [
                .init(name: "sistema", value: system), .init(name: "relay", value: relay),
                .init(name: "puerto", value: port.map(String.init)), .init(name: "clave", value: password),
            ]
        }
        c.queryItems = items
        return c.url!
    }

    init(system: String = "wii", code: String, gameID: String, title: String, version: String,
         host: String, relay: String? = nil, port: Int? = nil, password: String? = nil) {
        (self.system, self.code, self.gameID, self.title, self.version, self.host) =
            (system, code, gameID, title, version, host)
        (self.relay, self.port, self.password) = (relay, port, password)
    }

    init?(url: URL) {
        guard url.scheme == "wii", url.host == "unirse",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let code = value("codigo"), !code.isEmpty, let game = value("juego") else { return nil }
        self.init(system: value("sistema") ?? "wii", code: code, gameID: game,
                  title: value("titulo") ?? game, version: value("v") ?? "",
                  host: value("anfitrion") ?? "Tu amigo", relay: value("relay"),
                  port: value("puerto").flatMap { Int($0) }, password: value("clave"))
        if usesRetroArch && (relay == nil || port == nil) { return nil }
    }

    /// Busca un enlace dentro de un texto pegado (p. ej. un mensaje de WhatsApp).
    init?(text: String) {
        guard let r = text.range(of: #"wii://unirse\?\S+"#, options: .regularExpression),
              let url = URL(string: String(text[r]))
        else { return nil }
        self.init(url: url)
    }
}

enum NetPlay {
    static let lobby = URL(string: "https://lobby.dolphin-emu.org/v0/list")!

    static var dolphinVersion: String {
        let plist = Paths.dolphin.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        let info = NSDictionary(contentsOf: plist)
        return info?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var nickname: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? "Jugador"
    }

    static func randomToken(_ length: Int) -> String {
        let chars = Array("abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    /// Región para la lista de salas de Dolphin (solo informativa).
    static var region: String {
        let tz = TimeZone.current.identifier
        let southAmerica: Set = ["AR", "BO", "BR", "CL", "CO", "EC", "PY", "PE", "UY", "VE"]
        if tz.hasPrefix("Europe/") { return "EU" }
        if tz.hasPrefix("Asia/") { return "EA" }
        if tz.hasPrefix("Africa/") { return "AF" }
        if tz.hasPrefix("Australia/") || tz.hasPrefix("Pacific/") { return "OC" }
        if let r = Locale.current.region?.identifier, southAmerica.contains(r) { return "SA" }
        return "NA"
    }

    /// Dolphin publica el código de la sala cifrado con la contraseña (XOR + suma de control).
    /// Misma lógica que NetPlaySession::DecryptID en Dolphin.
    static func decrypt(_ encrypted: String, password: String) -> String? {
        let e = Array(encrypted.utf8), pw = Array(password.utf8)
        guard !pw.isEmpty, !e.isEmpty, e.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = stride(from: 0, to: e.count, by: 2).map {
            (e[$0] &- 65) << 4 | (e[$0 + 1] &- 65)
        }
        for i in bytes.indices { bytes[i] = (bytes[i] &- UInt8(truncatingIfNeeded: i)) ^ pw[i % pw.count] }
        let checksum = bytes.removeLast()
        guard bytes.reduce(UInt8(0), &+) == checksum else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }

    /// Busca nuestra sala en la lista pública por su nombre y devuelve el código de anfitrión.
    static func findHostCode(name: String, password: String) async -> String? {
        var request = URLRequest(url: lobby)
        request.setValue("1", forHTTPHeaderField: "X-Is-Dolphin")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessions = json["sessions"] as? [[String: Any]],
              let session = sessions.first(where: { $0["name"] as? String == name }),
              let serverID = session["server_id"] as? String
        else { return nil }
        return session["password"] as? Bool == true ? decrypt(serverID, password: password) : serverID
    }
}

struct HostSession {
    let game: Game
    let name: String  // nombre de la sala (Dolphin) o apodo del anfitrión (RetroArch)
    let password: String
    var invite: Invite?
}

// MARK: - RetroArch (Super Nintendo)

enum RetroArch {
    static let lobby = URL(string: "http://lobby.libretro.com/list/")!  // el servidor no tiene https
    #if arch(arm64)
    private static let arch = "arm64"
    #else
    private static let arch = "x86_64"
    #endif
    static let coreZip = URL(string:
        "https://buildbot.libretro.com/nightly/apple/osx/\(arch)/latest/snes9x_libretro.dylib.zip")!

    static var installed: Bool { FileManager.default.fileExists(atPath: Paths.retroarch.path) }

    static var version: String {
        let plist = Paths.retroarch.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        return NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Descarga el núcleo Snes9x la primera vez que se juega a Super Nintendo.
    static func ensureCore() async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: Paths.snesCore.path) { return }
        let (zip, _) = try await URLSession.shared.download(from: coreZip)
        let folder = Paths.snesCore.deletingLastPathComponent()
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, folder.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard fm.fileExists(atPath: Paths.snesCore.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "No se pudo descargar el núcleo de Super Nintendo."])
        }
    }

    /// Servidor de retransmisión más cercano (así nadie tiene que abrir puertos en el router).
    static var relayServer: String {
        switch NetPlay.region {
        case "EU", "AF": "madrid"
        case "SA": "saopaulo"
        case "EA", "OC": "singapore"
        default: "nyc"
        }
    }

    /// Escribe la configuración. En local: Jugador 1 teclado, Jugador 2 DualSense.
    /// En online cada computadora controla a un jugador, con teclado o DualSense.
    static func writeConfig(fullscreen: Bool, online: Bool, netplay: [String: String] = [:]) throws {
        var values: [String: String] = [
            "config_save_on_exit": "false",
            "video_fullscreen": fullscreen ? "true" : "false",
            "pause_nonactive": "false",
            "quit_press_twice": "false",
            "input_exit_emulator": "escape",
            "input_toggle_fast_forward": "nul",
            "input_hold_fast_forward": "nul",
            "input_rewind": "nul",
            "input_player1_up": "up", "input_player1_down": "down",
            "input_player1_left": "left", "input_player1_right": "right",
            "input_player1_a": "x", "input_player1_b": "z",
            "input_player1_x": "s", "input_player1_y": "a",
            "input_player1_l": "q", "input_player1_r": "w",
            "input_player1_start": "enter", "input_player1_select": "rshift",
            // Mando 0 = DualSense. En local va al Jugador 2; en online al Jugador 1.
            "input_player1_joypad_index": online ? "0" : "1",
            "input_player2_joypad_index": online ? "1" : "0",
            "netplay_start_as_spectator": "false",
        ]
        values.merge(netplay) { _, new in new }
        let text = values.sorted { $0.key < $1.key }
            .map { "\($0.key) = \"\($0.value)\"" }.joined(separator: "\n") + "\n"
        try FileManager.default.createDirectory(
            at: Paths.retroarchConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: Paths.retroarchConfig, atomically: true, encoding: .utf8)
    }

    /// Busca la sala del anfitrión (por su apodo) en la lista pública de RetroArch.
    static func findSession(nickname: String) async -> (relay: String, port: Int, session: String)? {
        guard let (data, _) = try? await URLSession.shared.data(from: lobby),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        for entry in list {
            guard let f = entry["fields"] as? [String: Any], f["username"] as? String == nickname,
                  let relay = f["mitm_ip"] as? String, !relay.isEmpty,
                  let port = f["mitm_port"] as? Int, let session = f["mitm_session"] as? String,
                  !session.isEmpty
            else { continue }
            return (relay, port, session)
        }
        return nil
    }
}

// MARK: - Portadas

@MainActor
final class CoverStore: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]
    private var requested: Set<String> = []

    func load(_ game: Game) {
        guard game.hasDiscID || game.platform == .snes, !requested.contains(game.id) else { return }
        requested.insert(game.id)

        // 1) Portadas incluidas en la app, 2) ya descargadas, 3) GameTDB
        if let path = Bundle.main.path(forResource: game.id, ofType: "png", inDirectory: "covers"),
           let image = NSImage(contentsOfFile: path) {
            images[game.id] = image
            return
        }
        let cached = Paths.covers.appendingPathComponent("\(game.id).png")
        if let image = NSImage(contentsOf: cached) {
            images[game.id] = image
            return
        }
        Task { await download(game, to: cached) }
    }

    private func download(_ game: Game, to file: URL) async {
        let id = game.id
        for url in Self.coverURLs(for: game) {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data)
            else { continue }
            try? FileManager.default.createDirectory(at: Paths.covers, withIntermediateDirectories: true)
            try? data.write(to: file)
            images[id] = image
            return
        }
    }

    private static func coverURLs(for game: Game) -> [URL] {
        if game.platform == .snes {
            // Portadas de libretro-thumbnails, por nombre No-Intro ("&*/:`<>?\\|\"" se cambian por "_")
            let name = game.coverName.replacingOccurrences(
                of: #"[&*/:`<>?\\|"]"#, with: "_", options: .regularExpression)
            let base = "https://thumbnails.libretro.com/Nintendo - Super Nintendo Entertainment System"
            return ["Named_Boxarts", "Named_Titles"].compactMap {
                URL(string: "\(base)/\($0)/\(name).png"
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
            }
        }
        return regions(for: game.id).compactMap {
            URL(string: "https://art.gametdb.com/wii/cover/\($0)/\(game.id).png")
        }
    }

    // La 4.ª letra del ID indica la región del disco.
    private static func regions(for id: String) -> [String] {
        let first: String
        switch id.dropFirst(3).first {
        case "E", "N": first = "US"
        case "J": first = "JA"
        case "K", "Q", "T": first = "KO"
        case "S": first = "ES"
        case "F": first = "FR"
        case "D": first = "DE"
        case "I": first = "IT"
        default: first = "EN"
        }
        var list = [first]
        for r in ["US", "EN", "ES", "FR", "DE", "JA"] where !list.contains(r) { list.append(r) }
        return list
    }
}

// MARK: - Estado

@MainActor
final class Launcher: ObservableObject {
    @Published var games: [Game] = []
    @Published var playing: String?
    @Published var dualSenseConnected = false
    @Published var error: String?
    @Published private var modeOverrides: [String: String] =
        UserDefaults.standard.dictionary(forKey: "controlModes") as? [String: String] ?? [:]

    let covers = CoverStore()
    private var watcher: DispatchSourceFileSystemObject?
    private var rescanTask: Task<Void, Never>?

    init() {
        rescan()
        watchFolder()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in Task { @MainActor in self.rescan() } }

        refreshController()
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in self.refreshController() }
            }
        }
        GCController.startWirelessControllerDiscovery {}
    }

    // MARK: Juegos

    func rescan() {
        let found = Game.scan(Paths.romsFolder)
        if found != games { games = found }
        games.forEach(covers.load)
    }

    /// Vigila la carpeta: cuando se añade, borra o renombra un archivo, vuelve a escanear.
    /// Espera un momento para no leer archivos a medio copiar en cada cambio.
    private func watchFolder() {
        let fd = Darwin.open(Paths.romsFolder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleRescan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func scheduleRescan() {
        rescanTask?.cancel()
        rescanTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            rescan()
        }
    }

    // MARK: Tipo de control

    func mode(for game: Game) -> ControlMode {
        if let raw = modeOverrides[game.id], let mode = ControlMode(rawValue: raw),
           ControlMode.options(for: game).contains(mode) {
            return mode
        }
        return .automatic(for: game)
    }

    func setMode(_ mode: ControlMode, for game: Game) {
        modeOverrides[game.id] = mode == .automatic(for: game) ? nil : mode.rawValue
        UserDefaults.standard.set(modeOverrides, forKey: "controlModes")
    }

    // MARK: Mandos

    func refreshController() {
        dualSenseConnected = GCController.controllers().contains {
            $0.vendorName?.localizedCaseInsensitiveContains("DualSense") == true
        }
    }

    // MARK: Jugar

    func play(_ game: Game, fullscreen: Bool, quality: Quality) {
        if game.platform.usesRetroArch {
            launchRetroArch(game) {
                try RetroArch.writeConfig(fullscreen: fullscreen, online: false)
                return []
            }
            return
        }
        launchDolphin(id: game.id, fullscreen: fullscreen, quality: quality) {
            try DolphinConfig.write(for: mode(for: game)) + ["-b", "-e", game.url.path]
        }
    }

    /// Escribe la configuración y abre Dolphin. `extraArguments` devuelve lo propio de cada modo.
    private func launchDolphin(id: String, fullscreen: Bool, quality: Quality,
                               extraArguments: () throws -> [String]) {
        guard FileManager.default.fileExists(atPath: Paths.dolphin.path) else {
            error = "No se encontró Dolphin en /Applications. Instálalo con «brew install --cask dolphin»."
            return
        }
        run(Paths.dolphin, id: id) {
            ["-u", Paths.dolphinUser.path,
             "-C", "Dolphin.Display.Fullscreen=\(fullscreen ? "True" : "False")"]
                + quality.arguments + (try extraArguments())
        }
    }

    /// Descarga el núcleo si hace falta y abre RetroArch con el juego.
    private func launchRetroArch(_ game: Game, onLaunch: (() -> Void)? = nil,
                                 extraArguments: @escaping () throws -> [String]) {
        guard RetroArch.installed else {
            error = "No se encontró RetroArch en /Applications. "
                + "Instálalo con «brew install --cask retroarch-metal»."
            return
        }
        guard playing == nil else { return }
        playing = game.id  // bloquea la interfaz mientras se prepara
        Task {
            do {
                try await RetroArch.ensureCore()
            } catch {
                self.playing = nil
                self.error = error.localizedDescription
                return
            }
            self.playing = nil
            run(Paths.retroarch, id: game.id) {
                ["-L", Paths.snesCore.path, "--config", Paths.retroarchConfig.path]
                    + (try extraArguments()) + [game.url.path]
            }
            if self.playing == game.id { onLaunch?() }
        }
    }

    private func run(_ executable: URL, id: String, arguments: () throws -> [String]) {
        guard playing == nil else { return }
        do {
            let p = Process()
            p.executableURL = executable
            p.arguments = try arguments()
            p.terminationHandler = { _ in
                Task { @MainActor in
                    self.playing = nil
                    self.hostSession = nil
                }
            }
            try p.run()
            playing = id
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Online

    @Published var hostSession: HostSession?
    @Published var joinRequest: Invite?
    @Published var joined = false

    func host(_ game: Game, fullscreen: Bool, quality: Quality) {
        game.platform.usesRetroArch
            ? hostRetroArch(game, fullscreen: fullscreen)
            : hostDolphin(game, fullscreen: fullscreen, quality: quality)
    }

    /// Abre Dolphin listo para alojar una partida: la sala se publica (con contraseña) en la lista
    /// de Dolphin, y así la app puede leer el código de anfitrión y crear el enlace.
    private func hostDolphin(_ game: Game, fullscreen: Bool, quality: Quality) {
        let session = HostSession(game: game, name: "WiiLanzador-\(NetPlay.randomToken(6))",
                                  password: NetPlay.randomToken(12))
        launchDolphin(id: game.id, fullscreen: fullscreen, quality: quality) {
            // Lista de juegos de Dolphin con solo este juego, para que elegirlo sea un clic.
            let fm = FileManager.default
            try? fm.removeItem(at: Paths.netplayGames)
            try fm.createDirectory(at: Paths.netplayGames, withIntermediateDirectories: true)
            let link = Paths.netplayGames.appendingPathComponent(game.url.lastPathComponent)
            do { try fm.linkItem(at: game.url, to: link) }
            catch { try fm.createSymbolicLink(at: link, withDestinationURL: game.url) }

            return try DolphinConfig.write(for: mode(for: game), online: true) + netplayArguments(
                games: Paths.netplayGames,
                [
                    "UseIndex=True", "IndexName=\(session.name)",
                    "IndexPassword=\(session.password)", "IndexRegion=\(NetPlay.region)",
                ])
        }
        guard playing == game.id else { return }
        hostSession = session
        Task { await waitForInvite(session) }
    }

    /// RetroArch aloja la sala a través de un servidor de retransmisión y la anuncia en su lista
    /// pública (con contraseña). La app la encuentra por el apodo y crea el enlace.
    private func hostRetroArch(_ game: Game, fullscreen: Bool) {
        // RetroArch no deja pasar la contraseña al que se une: la tiene que escribir. Por eso es un
        // PIN corto, que su app le muestra. Sin él, cualquiera de la lista pública podría entrar.
        let pin = String(format: "%04d", Int.random(in: 0...9999))
        let session = HostSession(game: game, name: "\(NetPlay.nickname)-\(NetPlay.randomToken(4))",
                                  password: pin)
        launchRetroArch(game, onLaunch: {
            self.hostSession = session
            Task { await self.waitForInvite(session) }
        }) {
            try RetroArch.writeConfig(fullscreen: fullscreen, online: true, netplay: [
                "netplay_nickname": session.name,
                "netplay_password": session.password,
                "netplay_use_mitm_server": "true",
                "netplay_mitm_server": RetroArch.relayServer,
                "netplay_public_announce": "true",
                "netplay_max_connections": "1",
            ])
            return ["-H", "--nick", session.name]
        }
    }

    private func waitForInvite(_ session: HostSession) async {
        for _ in 0..<600 {  // ~30 minutos
            guard hostSession?.name == session.name else { return }
            let game = session.game
            var invite: Invite?
            if game.platform.usesRetroArch {
                if let s = await RetroArch.findSession(nickname: session.name) {
                    invite = Invite(system: "snes", code: s.session, gameID: game.id, title: game.title,
                                    version: RetroArch.version, host: NetPlay.nickname,
                                    relay: s.relay, port: s.port, password: session.password)
                }
            } else if let code = await NetPlay.findHostCode(name: session.name, password: session.password) {
                invite = Invite(code: code, gameID: game.id, title: game.title,
                                version: NetPlay.dolphinVersion, host: NetPlay.nickname)
            }
            if let invite, hostSession?.name == session.name {
                hostSession?.invite = invite
                return
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    /// Recibe un enlace (desde el navegador, Mensajes, WhatsApp…) y muestra la ventana para unirse.
    func open(_ url: URL) {
        guard let invite = Invite(url: url) else { return }
        NSApp.activate()
        joined = false
        joinRequest = invite
    }

    /// Problema que impide unirse, o nil si todo está bien.
    func problem(joining invite: Invite) -> String? {
        if playing != nil { return "Cierra el juego que tienes abierto antes de unirte." }
        let (name, installed, version, cask) = invite.usesRetroArch
            ? ("RetroArch", RetroArch.installed, RetroArch.version, "retroarch-metal")
            : ("Dolphin", FileManager.default.fileExists(atPath: Paths.dolphin.path),
               NetPlay.dolphinVersion, "dolphin")
        if !installed {
            return "Necesitas \(name). Instálalo con «brew install --cask \(cask)»."
        }
        if !invite.version.isEmpty, invite.version != version {
            return "Tu \(name) es la versión \(version) y el de \(invite.host) es la "
                + "\(invite.version). Tenéis que tener la misma: actualizad los dos con "
                + "«brew upgrade --cask \(cask)»."
        }
        if !games.contains(where: { $0.id == invite.gameID }) {
            return "Necesitas «\(invite.title)» en tu carpeta de juegos. "
                + "Tiene que ser exactamente el mismo archivo que el de \(invite.host)."
        }
        return nil
    }

    func join(_ invite: Invite, fullscreen: Bool, quality: Quality) {
        guard problem(joining: invite) == nil,
              let game = games.first(where: { $0.id == invite.gameID })
        else { return }
        if invite.usesRetroArch, let relay = invite.relay, let port = invite.port {
            launchRetroArch(game, onLaunch: { self.joined = true }) {
                try RetroArch.writeConfig(fullscreen: fullscreen, online: true, netplay: [
                    "netplay_nickname": NetPlay.nickname,
                    "netplay_use_mitm_server": "false",
                    "netplay_public_announce": "false",
                ])
                return ["-C", relay, "--port", String(port), "--mitm-session", invite.code,
                        "--nick", NetPlay.nickname]
            }
            return
        }
        launchDolphin(id: game.id, fullscreen: fullscreen, quality: quality) {
            try DolphinConfig.write(for: mode(for: game), online: true)
                + netplayArguments(games: Paths.romsFolder, ["HostCode=\(invite.code)"])
        }
        joined = playing == game.id
    }

    private func netplayArguments(games folder: URL, _ netplay: [String]) -> [String] {
        let general = ["ISOPaths=1", "ISOPath0=\(folder.path)", "RecursiveISOPaths=False"]
            .map { "Dolphin.General.\($0)" }
        let common = ["TraversalChoice=traversal", "Nickname=\(NetPlay.nickname)"] + netplay
        return (general + common.map { "Dolphin.NetPlay.\($0)" }).flatMap { ["-C", $0] }
    }
}

// MARK: - Interfaz

struct ContentView: View {
    @StateObject private var launcher = Launcher()
    @State private var showControls = false
    @State private var showJoin = false
    @AppStorage("fullscreen") private var fullscreen = true
    @AppStorage("quality") private var quality = Quality.balanced

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 200), spacing: 28, alignment: .top)]

    var body: some View {
        VStack(spacing: 0) {
            Text("Wii")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .padding(.top, 28)
                .padding(.bottom, 20)

            if launcher.games.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "opticaldisc").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("Pon tus juegos en ~/Downloads/Wii Roms").foregroundStyle(.secondary)
                    Text("Aparecerán aquí automáticamente.").font(.callout).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 32) {
                        ForEach(launcher.games) { game in
                            GameCard(
                                game: game,
                                mode: launcher.mode(for: game),
                                playing: launcher.playing == game.id,
                                disabled: launcher.playing != nil,
                                setMode: { launcher.setMode($0, for: game) },
                                play: { launcher.play(game, fullscreen: fullscreen, quality: quality) },
                                playOnline: { launcher.host(game, fullscreen: fullscreen, quality: quality) }
                            )
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                }
            }

            Divider()

            VStack(spacing: 16) {
                HStack(spacing: 28) {
                    PlayerBadge(number: 1, device: "Teclado", ready: true)
                    PlayerBadge(number: 2, device: "DualSense", ready: launcher.dualSenseConnected)
                }
                HStack(spacing: 20) {
                    Picker("Calidad", selection: $quality) {
                        ForEach(Quality.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                    .help("Rendimiento ≈ 720p · Equilibrada ≈ 1080p · Máxima ≈ 1440p")
                    Toggle("Pantalla completa", isOn: $fullscreen)
                        .toggleStyle(.checkbox)
                    Button("Controles") { showControls = true }
                        .buttonStyle(.link)
                    Button("Unirse a partida") { showJoin = true }
                        .buttonStyle(.link)
                        .disabled(launcher.playing != nil)
                }
                .font(.callout)
            }
            .padding(.vertical, 20)
        }
        .frame(minWidth: 620, idealWidth: 820, minHeight: 560, idealHeight: 720)
        .environmentObject(launcher.covers)
        .sheet(isPresented: $showControls) { ControlsView() }
        .sheet(isPresented: Binding(get: { launcher.hostSession != nil },
                                    set: { if !$0 { launcher.hostSession = nil } })) {
            if let session = launcher.hostSession { HostView(session: session) }
        }
        .sheet(isPresented: $showJoin) {
            JoinView(launcher: launcher, fullscreen: fullscreen, quality: quality)
        }
        .onChange(of: launcher.joinRequest) { _, invite in
            if invite != nil { showJoin = true }
        }
        .onOpenURL { launcher.open($0) }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .alert("Error", isPresented: Binding(get: { launcher.error != nil },
                                             set: { if !$0 { launcher.error = nil } })) {
            Button("OK") {}
        } message: {
            Text(launcher.error ?? "")
        }
    }
}

struct GameCard: View {
    let game: Game
    let mode: ControlMode
    let playing: Bool
    let disabled: Bool
    let setMode: (ControlMode) -> Void
    let play: () -> Void
    let playOnline: () -> Void
    @EnvironmentObject private var covers: CoverStore  // redibuja cuando llega una portada
    @State private var hover = false

    var body: some View {
        VStack(spacing: 10) {
            Button(action: play) {
                ZStack {
                    if let cover = covers.images[game.id] {
                        if game.platform == .snes {
                            // Las cajas de Super Nintendo son apaisadas: se ven enteras sobre un fondo
                            // hecho con la misma portada, desenfocada.
                            Image(nsImage: cover).resizable().scaledToFill().blur(radius: 18)
                                .overlay(.black.opacity(0.25))
                            Image(nsImage: cover).resizable().interpolation(.high).scaledToFit()
                                .shadow(radius: 6)
                        } else {
                            Image(nsImage: cover).resizable().interpolation(.high)
                        }
                    } else {
                        Rectangle().fill(.quaternary)
                            .overlay(Image(systemName: "gamecontroller").font(.largeTitle)
                                .foregroundStyle(.secondary))
                    }
                    if playing {
                        Rectangle().fill(.black.opacity(0.45))
                        Text("Jugando…").font(.headline).foregroundStyle(.white)
                    } else if hover && !disabled {
                        Rectangle().fill(.black.opacity(0.25))
                        Image(systemName: "play.fill").font(.system(size: 34)).foregroundStyle(.white)
                    }
                }
                .frame(width: 160, height: 224)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(hover ? 0.35 : 0.15), radius: hover ? 14 : 6, y: 4)
                .scaleEffect(hover && !disabled ? 1.04 : 1)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .onHover { hover = $0 }

            Text(game.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 180)

            HStack(spacing: 6) {
                modeMenu
                Text("·").foregroundStyle(.tertiary)
                Button(action: playOnline) {
                    Label("Online", systemImage: "globe")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(disabled)
                .help("Jugar online: crea una sala y un enlace para invitar a alguien")
            }
            .font(.subheadline)
        }
        .opacity(disabled && !playing ? 0.4 : 1)
        .animation(.easeOut(duration: 0.15), value: hover)
    }

    @ViewBuilder private var modeMenu: some View {
        let options = ControlMode.options(for: game)
        Group {
            if options.count > 1 {
                Menu {
                    ForEach(options) { option in
                        Button {
                            setMode(option)
                        } label: {
                            if option == mode { Label(option.label, systemImage: "checkmark") }
                            else { Text(option.label) }
                        }
                    }
                } label: {
                    Text(mode.label)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Cambiar el tipo de control de este juego")
            } else {
                Text(mode.label)
            }
        }
        .foregroundStyle(.secondary)
    }
}

struct PlayerBadge: View {
    let number: Int
    let device: String
    let ready: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(ready ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text("Jugador \(number)").fontWeight(.medium)
            Text(ready ? device : "\(device) no conectado").foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

// MARK: - Ventanas online

/// Pasos numerados, iguales para alojar y para unirse.
struct Steps: View {
    let steps: [Text]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(steps.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.quaternary))
                    steps[i].fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct HostView: View {
    let session: HostSession
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Jugar online").font(.title2.weight(.semibold))
                Text(session.game.title).foregroundStyle(.secondary)
            }

            if session.game.platform.usesRetroArch {
                Steps(steps: [
                    Text("Espera unos segundos a que se cree la sala."),
                    Text("Envía el enlace de abajo a tu amigo."),
                    Text("Tu amigo escribirá un PIN que ya va en el enlace. La partida empieza sola "
                         + "cuando se une: ¡no tienes que hacer nada más!"),
                ])
            } else {
                Steps(steps: [
                    Text("En Dolphin, abre **Tools → Start NetPlay…**\n")
                        + Text("(Herramientas → Comenzar juego en red…)").foregroundStyle(.secondary),
                    Text("Pestaña **Host**: haz clic en **\(session.game.title)** y pulsa **Host**.\n")
                        + Text("Todo lo demás ya está rellenado.").foregroundStyle(.secondary),
                    Text("Envía el enlace de abajo a tu amigo."),
                    Text("Cuando aparezca en la sala, pulsa **Start** (Comenzar)."),
                ])
            }

            GroupBox {
                if let invite = session.invite {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(invite.url.absoluteString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                        HStack {
                            Button(copied ? "¡Copiado!" : "Copiar enlace") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(invite.url.absoluteString, forType: .string)
                                copied = true
                            }
                            .keyboardShortcut("c")
                            Spacer()
                            if !invite.usesRetroArch {
                                Text("Código: \(invite.code)").font(.callout.monospaced())
                                    .foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                    .padding(6)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(session.game.platform.usesRetroArch
                             ? "Creando la sala… el enlace aparecerá aquí."
                             : "El enlace aparecerá aquí cuando abras la sala (pasos 1 y 2).")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
            }

            Text("Tu amigo necesita esta app, el mismo juego y la misma versión de "
                 + (session.game.platform.usesRetroArch ? "RetroArch. " : "Dolphin. ")
                 + "Cada uno juega con su teclado o su DualSense.")
                .font(.footnote).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: 500)
    }
}

struct JoinView: View {
    @ObservedObject var launcher: Launcher
    let fullscreen: Bool
    let quality: Quality
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var invite: Invite? { Invite(text: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Unirse a partida").font(.title2.weight(.semibold))

            if launcher.joined, let invite, invite.usesRetroArch {
                Steps(steps: [
                    Text("RetroArch se abre y se conecta a la sala de \(invite.host)."),
                    Text("Cuando te pida la contraseña, escribe este PIN y pulsa **Enter**:"),
                    Text("La partida empieza sola. ¡A jugar!"),
                ])
                if let pin = invite.password {
                    Text(pin)
                        .font(.system(size: 40, weight: .semibold, design: .monospaced))
                        .tracking(8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
                        .textSelection(.enabled)
                }
            } else if launcher.joined, let invite {
                Steps(steps: [
                    Text("En Dolphin, abre **Tools → Start NetPlay…**\n")
                        + Text("(Herramientas → Comenzar juego en red…)").foregroundStyle(.secondary),
                    Text("Pestaña **Connect**: el código ya está puesto. Pulsa **Connect**."),
                    Text("Espera a que \(invite.host) pulse **Start**. ¡A jugar!"),
                ])
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pega el enlace que te enviaron:").foregroundStyle(.secondary)
                    TextField("wii://unirse?codigo=…", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout.monospaced())
                }

                if let invite {
                    if let problem = launcher.problem(joining: invite) {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label("\(invite.host) te invita a jugar **\(invite.title)**",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else if !text.isEmpty {
                    Text("Ese enlace no es válido.").foregroundStyle(.orange)
                }
            }

            HStack {
                Spacer()
                Button(launcher.joined ? "Cerrar" : "Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !launcher.joined {
                    Button("Unirse") {
                        if let invite { launcher.join(invite, fullscreen: fullscreen, quality: quality) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(invite.map { launcher.problem(joining: $0) != nil } ?? true)
                }
            }
        }
        .padding(28)
        .frame(width: 480)
        .onAppear {
            // Rellena con el enlace recibido, o con el que haya en el portapapeles.
            if let request = launcher.joinRequest {
                text = request.url.absoluteString
            } else if let clip = NSPasteboard.general.string(forType: .string), Invite(text: clip) != nil {
                text = clip
            }
        }
        .onDisappear {
            launcher.joinRequest = nil
            launcher.joined = false
        }
    }
}

struct ControlsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode = ControlMode.sideways

    private var rows: [(String, String, String)] {
        switch mode {
        case .sideways: [
            ("Moverse", "Flechas", "Joystick izq. / Cruceta"),
            ("Saltar · Aceptar (2)", "X", "✕"),
            ("Correr · Atrás (1)", "Z", "□"),
            ("Botón A", "C", "○"),
            ("Botón B", "V", "△"),
            ("Agitar el mando", "Espacio", "L2 / R2"),
            ("Inclinar izq. / der.", "A / D", "L1 / R1"),
            ("Apuntar", "Ratón", "Joystick der."),
            ("Pausa (+)", "Enter", "Options"),
            ("Botón −", "Borrar", "Create"),
            ("HOME", "H", "PS"),
        ]
        case .nunchuk: [
            ("Moverse (Nunchuk)", "Flechas", "Joystick izq."),
            ("Botón A", "X", "✕"),
            ("Botón B", "C", "R2"),
            ("Botón Z (Nunchuk)", "Z", "L2"),
            ("Botón C (Nunchuk)", "V", "L1"),
            ("Agitar el mando", "Espacio", "□"),
            ("Apuntar", "Ratón", "Joystick der."),
            ("Cruceta", "W A S D", "Cruceta"),
            ("Botones 1 / 2", "1 / 2", "○ / △"),
            ("Pausa (+)", "Enter", "Options"),
            ("Botón −", "Borrar", "Create"),
            ("HOME", "H", "PS"),
        ]
        case .snes: [
            ("Moverse", "Flechas", "Cruceta / Joystick izq."),
            ("A", "X", "○"),
            ("B", "Z", "✕"),
            ("X", "S", "△"),
            ("Y", "A", "□"),
            ("L / R", "Q / W", "L1 / R1"),
            ("Start", "Enter", "Options"),
            ("Select", "Mayús derecha", "Create"),
        ]
        case .gamecube: [
            ("Stick principal", "Flechas", "Joystick izq."),
            ("Stick C", "I J K L", "Joystick der."),
            ("A", "X", "✕"),
            ("B", "Z", "□"),
            ("X", "C", "○"),
            ("Y", "V", "△"),
            ("Z", "Espacio", "R1"),
            ("L / R", "Q / E", "L2 / R2"),
            ("Cruceta", "W A S D", "Cruceta"),
            ("Start", "Enter", "Options"),
        ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Controles").font(.title2.weight(.semibold))
            Picker("Tipo de control", selection: $mode) {
                ForEach(ControlMode.allCases) {
                    Text($0 == .snes ? "Super Nintendo" : $0.label).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                GridRow {
                    Text("")
                    Text("Jugador 1 · Teclado").fontWeight(.semibold)
                    Text("Jugador 2 · DualSense").fontWeight(.semibold)
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(rows, id: \.0) { row in
                    GridRow {
                        Text(row.0).foregroundStyle(.secondary)
                        Text(row.1)
                        Text(row.2)
                    }
                }
            }
            .font(.callout)
            Text("Salir del juego: Esc · Pantalla completa: ⌥ + Enter\nEl tipo de control de cada juego se cambia debajo de su portada.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Listo") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 540)
    }
}

@main
struct WiiApp: App {
    var body: some Scene {
        WindowGroup("Wii") { ContentView() }
            .windowResizability(.contentMinSize)
            .defaultSize(width: 820, height: 720)
    }
}
