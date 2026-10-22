# Codex Usage

Eine native macOS-Menüleisten-App: Die Zahl oben zeigt den **verbleibenden** Anteil deines Codex-Limits. Ein Klick öffnet ein kompaktes, dunkles Detailfenster mit Balken und Reset-Zeiten.

- Wochenlimit für alle Konten, bei denen Codex ein Wochenlimit liefert.
- 5-Stunden-Limit **ausschließlich für ChatGPT Plus**, sofern Codex es liefert.
- Bei Plus stehen beide Werte in der Menüleiste, zum Beispiel `40% WL / 20% 5h` (Wochenlimit zuerst, dann 5-Stunden-Limit). Nicht übermittelte Werte erscheinen als `—%`. Andere Abos zeigen die einzelne Wochen-Prozentzahl.
- Aktualisierung alle 15 Sekunden (1 Sekunde Timer-Toleranz), beim Öffnen und nach dem Aufwachen des Macs. Laufende Abfragen werden nicht überlappt.
- Sobald ein Abruf einen Sprung von unter 100 % auf 100 % verbleibendes Wochen- oder 5-Stunden-Kontingent bestätigt, erscheint eine macOS-Mitteilung mit Hinweiston – auch bei geöffnetem Popover. Gleichzeitige Resets werden zusammengefasst. Bei weiterhin 100 % und beim ersten Abruf gibt es keine Meldung.
- Optionaler Autostart im Zahnrad-Menü; standardmäßig ausgeschaltet.
- Kein Dock-Symbol, keine externen Swift-Abhängigkeiten.

## Starten

Voraussetzungen: macOS 13 oder neuer und eine installierte Codex-App oder Codex-CLI mit bestehender **ChatGPT-Anmeldung**. Ein OpenAI-API-Key liefert keine Abo-Limits.

Nach dem Klonen zuerst `bash scripts/build.sh` ausführen. Die gebaute App liegt anschließend unter `dist/Codex Usage.app`; Build-Artefakte sind nicht im Repository enthalten. Doppelklicken oder:

```sh
open "dist/Codex Usage.app"
```

Für dauerhafte Nutzung die App in `~/Applications` oder `/Applications` verschieben. Anschließend kann „Beim Anmelden starten“ aktiviert werden.

Beim ersten regulären Start der `.app` bitte Mitteilungen erlauben. Banner und Töne lassen sich unter macOS-Systemeinstellungen → Mitteilungen → Codex Usage aktivieren. Fokus und die macOS-Toneinstellungen können Hinweise unterdrücken. Die Erkennung erfolgt beim nächsten erfolgreichen Abruf (normalerweise bis zu 15 Sekunden plus Timer-Toleranz und Antwortzeit), nicht exakt zum Reset-Zeitpunkt. Die App muss dafür laufen; reine CLI- und Demo-Aufrufe senden keine Mitteilungen.

Für einen einmaligen Test die App beenden und mit `open "dist/Codex Usage.app" --args --test-reset-notification` starten. Nach erteilter Mitteilungserlaubnis werden Beispielwerte über dieselbe Reset-Erkennung auf 100 % gesetzt und eine als Test markierte Mitteilung mit Ton gesendet. Die echten Kontodaten und angezeigten Werte bleiben unverändert; danach läuft die Überwachung regulär weiter.

Die App findet die Codex-Datei in der Codex-App, Homebrew und üblichen CLI-Verzeichnissen. Andere Installationen lassen sich unter „Codex-CLI auswählen …“ angeben. Die vorhandene Codex-Anmeldung wird genutzt; bei CLI-only-Installationen zuerst `codex login` im Terminal ausführen. `CODEX_HOME` wird aus der Prozessumgebung übernommen, sofern gesetzt. Finder-Starts verwenden normalerweise `~/.codex`.

## Bauen und testen

Mit Xcode oder den Xcode Command Line Tools (Swift 5.9+):

```sh
bash scripts/build.sh
swift test
```

Das Build-Skript erstellt eine lokal ad-hoc-signierte `.app` für die Architektur des Macs. Für eine öffentliche Verteilung sind Developer-ID-Signatur und Notarisierung separat erforderlich.

Diagnose mit echten Kontodaten, ohne E-Mail-Adresse oder Tokens auszugeben:

```sh
.build/release/CodexUsage --check
```

UI-Vorschau mit ausdrücklich markierten Beispieldaten:

```sh
swift run CodexUsage --demo --show
.build/debug/CodexUsage --render-preview /tmp/codex-usage.png
```

Mit `--render-preview /tmp/codex-usage-live.png --live` wird die Vorschau mit echten Kontodaten gerendert.

## Datenquelle und Verhalten

Die App nutzt die [offizielle Codex-App-Server-Schnittstelle](https://learn.chatgpt.com/docs/app-server#auth-endpoints): `initialize`, `account/read` und `account/rateLimits/read` über einen kurzlebigen lokalen `codex app-server`-Kindprozess. Sie startet keine Threads oder Modellanfragen. Anmeldung und Tokenverwaltung übernimmt Codex. Die App liest oder speichert selbst keine Zugangsdaten; gespeichert werden nur der optionale CLI-Pfad und die macOS-Autostart-Einstellung.

`100 − usedPercent` ergibt die verbleibenden Prozente, auf ganze Prozent abgerundet und auf 0–100 begrenzt. Die Fenster werden nach ihrer tatsächlichen Dauer erkannt (300 bzw. 10080 Minuten), nicht nach ihrer Position im API-Ergebnis. Andere Zeitfenster und modellspezifische Zusatzkontingente werden nicht als Wochen- oder 5-Stunden-Limit ausgegeben.

Bei Verbindungsfehlern zeigt die Menüleiste `—%`; letzte bekannte Werte bleiben im Popover abgeblendet und mit Hinweis sichtbar. Ein Reset wird erst durch neue Serverdaten bestätigt, nicht lokal als 100 % angenommen. Nach Abmeldung werden die vorherigen Kontodaten entfernt. Kontowechsel und Tarifänderungen werden beim nächsten Abruf übernommen.

Die Tests prüfen Prozentberechnung, Tarifregeln, wechselnde Fensterpositionen, Auswahl des richtigen Codex-Kontingents sowie den echten stdio-Transport mit lokalen Testprozessen einschließlich Timeout, Abmeldung und Serverfehlern.
