import Foundation

/// Wie ein Bereich unkenntlich gemacht wird.
enum Effect: Int, CaseIterable {
    case pixelate = 0
    case blur = 1
    case blackout = 2

    var actionName: String {
        switch self {
        case .pixelate: return "Verpixeln"
        case .blur: return "Weichzeichnen"
        case .blackout: return "Schwärzen"
        }
    }
}

/// Womit man malt.
enum Tool: Int {
    case brush = 0
    case rect = 1
}

/// Einstellungen, die zwischen Starts erhalten bleiben.
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    var effect: Effect {
        get { Effect(rawValue: defaults.integer(forKey: "effect")) ?? .pixelate }
        set { defaults.set(newValue.rawValue, forKey: "effect") }
    }

    var tool: Tool {
        get { Tool(rawValue: defaults.integer(forKey: "tool")) ?? .brush }
        set { defaults.set(newValue.rawValue, forKey: "tool") }
    }

    /// Pinseldurchmesser in Bildschirmpunkten.
    var brushSize: Double {
        get { defaults.object(forKey: "brushSize") as? Double ?? 40 }
        set { defaults.set(newValue, forKey: "brushSize") }
    }

    /// Blockgröße (Verpixeln) bzw. Radius (Weichzeichnen) in Bildpixeln.
    var strength: Double {
        get { defaults.object(forKey: "strength") as? Double ?? 22 }
        set { defaults.set(newValue, forKey: "strength") }
    }

    var welcomeShown: Bool {
        get { defaults.bool(forKey: "welcomeShown") }
        set { defaults.set(newValue, forKey: "welcomeShown") }
    }
}
