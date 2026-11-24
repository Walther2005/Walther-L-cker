import Foundation
import Vision

/// Automatische Erkennung über Apples Vision-Framework – läuft komplett lokal auf dem Mac.
enum Detector {
    enum Kind {
        case faces, sensitive, allText

        var searching: String {
            switch self {
            case .faces: return "Suche Gesichter …"
            case .sensitive: return "Suche E-Mails, Telefonnummern, IBANs, Tokens …"
            case .allText: return "Suche Text …"
            }
        }

        var nothingFound: String {
            switch self {
            case .faces: return "Keine Gesichter gefunden."
            case .sensitive: return "Keine sensiblen Daten gefunden."
            case .allText: return "Kein Text gefunden."
            }
        }

        func found(_ n: Int) -> String {
            switch self {
            case .faces: return n == 1 ? "1 Gesicht unkenntlich gemacht." : "\(n) Gesichter unkenntlich gemacht."
            case .sensitive: return n == 1 ? "1 Fundstelle unkenntlich gemacht." : "\(n) Fundstellen unkenntlich gemacht."
            case .allText: return n == 1 ? "1 Textzeile unkenntlich gemacht." : "\(n) Textzeilen unkenntlich gemacht."
            }
        }
    }

    static func detect(_ kind: Kind, in image: CGImage, completion: @escaping ([CGRect]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let rects = (try? run(kind, on: image)) ?? []
            DispatchQueue.main.async { completion(rects) }
        }
    }

    private static func run(_ kind: Kind, on image: CGImage) throws -> [CGRect] {
        let w = image.width, h = image.height
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        func pixels(_ normalized: CGRect, pad: CGFloat) -> CGRect {
            let r = VNImageRectForNormalizedRect(normalized, w, h)
            let p = min(r.width, r.height) * pad + 2
            return r.insetBy(dx: -p, dy: -p)
        }

        switch kind {
        case .faces:
            let request = VNDetectFaceRectanglesRequest()
            try handler.perform([request])
            return (request.results ?? []).map { face in
                // Etwas großzügiger, damit Stirn, Kinn und Haare mit drin sind.
                let r = VNImageRectForNormalizedRect(face.boundingBox, w, h)
                return r.insetBy(dx: -r.width * 0.18, dy: -r.height * 0.25)
            }

        case .sensitive, .allText:
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            if let supported = try? request.supportedRecognitionLanguages() {
                request.recognitionLanguages = ["de-DE", "en-US"].filter { supported.contains($0) }
            }
            try handler.perform([request])

            var rects: [CGRect] = []
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                if kind == .allText {
                    rects.append(pixels(observation.boundingBox, pad: 0.15))
                    continue
                }
                for range in SensitivePatterns.matches(in: candidate.string) {
                    if let box = try? candidate.boundingBox(for: range) {
                        rects.append(pixels(box.boundingBox, pad: 0.2))
                    }
                }
            }
            return rects
        }
    }
}

/// Muster für Daten, die man in Screenshots meist nicht zeigen will.
enum SensitivePatterns {
    private static func rx(_ pattern: String, caseInsensitive: Bool = true) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    private static let email = rx(#"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#)
    private static let iban = rx(#"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\b"#)
    private static let phone = rx(#"(?:\+|\b00|\b0)\d[\d \t/().\-]{5,}\d"#)
    private static let card = rx(#"\b(?:\d[ \-]?){13,19}\b"#)
    private static let ipv4 = rx(#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#)
    private static let url = rx(#"\bhttps?://\S+"#)
    /// Lange Zeichenketten aus Buchstaben UND Ziffern – typisch für API-Schlüssel, Passwörter, Tokens.
    private static let token = rx(#"\b(?=[A-Za-z0-9_\-]*\d)(?=[A-Za-z0-9_\-]*[A-Za-z])[A-Za-z0-9_\-]{20,}\b"#, caseInsensitive: false)

    static func matches(in string: String) -> [Range<String.Index>] {
        let all = NSRange(string.startIndex..., in: string)
        var result: [Range<String.Index>] = []

        func collect(_ regex: NSRegularExpression, filter: ((String) -> Bool)? = nil) {
            for m in regex.matches(in: string, range: all) {
                guard let r = Range(m.range, in: string) else { continue }
                if let filter, !filter(String(string[r])) { continue }
                result.append(r)
            }
        }

        let digitCount: (String) -> Int = { $0.filter(\.isNumber).count }
        collect(email)
        collect(iban)
        collect(phone) { (7...15).contains(digitCount($0)) }
        collect(card) { (13...19).contains(digitCount($0)) }
        collect(ipv4)
        collect(url)
        collect(token)
        return result
    }
}
