# Pixelwisch

Screenshots auf dem Mac aufnehmen und mit der Maus über alles wischen, was niemand sehen soll.

## Was die App kann

- **Screenshot per Tastenkürzel `⌃⌥⌘P`**, und zwar systemweit. Alternativ über das Raster-Symbol in der Menüleiste oder per Klick aufs Dock-Symbol. Bereich, Fenster, ganzer Bildschirm oder mit 5 Sekunden Verzögerung.
- **Wischen zum Verpixeln.** Ein runder Pinsel zeigt, was erfasst wird, und die Vorschau läuft live mit.
- **Drei Effekte:** Verpixeln, Unscharf, Schwärzen. Stärke und Pinselgröße lassen sich einstellen.
- **Rechteck-Werkzeug** für saubere Kästen. `⇧` gedrückt halten wechselt beim Wischen kurz dorthin.
- **Automatisch** (läuft komplett lokal über Apples Vision):
  - Gesichter finden und unkenntlich machen
  - sensible Daten finden: E-Mail-Adressen, Telefonnummern, IBANs, Kreditkartennummern, IP-Adressen, URLs, lange Tokens und API-Schlüssel
  - allen Text unkenntlich machen
- **`⌥` gedrückt halten** zeigt kurz das Original zum Vergleich.
- **Unbegrenztes Widerrufen** mit `⌘Z` und `⇧⌘Z`.
- **Ausgabe:** `⌘C` kopiert, `⌘S` sichert als PNG oder JPEG, `⌘↩` kopiert und schließt. Mit gedrückter `⌘`-Taste lässt sich das Bild direkt aus dem Fenster nach Mail, Finder oder Slack ziehen.
- Bilder aus dem Finder lassen sich aufs Fenster oder Dock-Symbol ziehen. `⌘V` öffnet ein Bild aus der Zwischenablage. Fotos werden dabei richtig gedreht.

### Tasten im Editor

| Taste | Wirkung |
|---|---|
| `B` / `R` | Pinsel / Rechteck |
| `1` `2` `3` | Verpixeln / Unscharf / Schwärzen |
| `+` / `−` | Pinsel größer / kleiner |
| `⌥` halten | Original zeigen |
| `⇧⌘F` / `⇧⌘D` / `⇧⌘T` | Gesichter / sensible Daten / allen Text automatisch |

## Installieren (ohne Xcode)

1. Auf GitHub unter **Actions → „Mac-App bauen“** den neuesten Lauf öffnen und unten das Artefakt **Pixelwisch** herunterladen.
2. Entpacken, bis `Pixelwisch.app` erscheint, und die App in den Ordner *Programme* ziehen.
3. Die App ist nicht von Apple beglaubigt. Deshalb beim ersten Öffnen: Doppelklick, die Warnung schließen, dann **Systemeinstellungen → Datenschutz & Sicherheit → „Trotzdem öffnen“**.
   Alternativ im Terminal: `xattr -dr com.apple.quarantine /Applications/Pixelwisch.app`
4. Beim ersten Screenshot fragt macOS nach der Erlaubnis für **Bildschirmaufnahme**. Erlauben und Pixelwisch neu starten.

## Selbst bauen

Dazu braucht es Xcode oder die Command Line Tools (`xcode-select --install`):

```bash
./build-app.sh            # → build/Pixelwisch.app
```

## Sicherheitshinweis

Gespeichert und kopiert wird immer ein neues, flaches Bild. Der Originalinhalt unter verpixelten Stellen ist darin nicht mehr enthalten. Trotzdem gilt: Bei sehr kurzem Text, etwa Passwörtern oder PINs, kann Verpixeln oder Weichzeichnen mit Rechenaufwand teilweise erraten werden. Für wirklich Geheimes deshalb **Schwärzen (3)** nehmen.
