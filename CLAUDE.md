# Projekt: Trainings-Dashboard „Cockpit“ (iOS)

Siehe DASHBOARD_APP_SPEC.md für Ziele, Architektur und Phasen.
Lokal liegt zusätzlich `private/DASHBOARD_APP_SPEC_full.md` mit persönlichem Kontext (nicht im Repo). Inhalte daraus nie in eingecheckte Dateien übernehmen.

Das Repository ist öffentlich (Portfolio). Keine Namen von persönlichen Dokumenten/Tabellen, keine echten Messwerte, keine privaten Details in Code, Commits oder Doku.

## Arbeitsregeln
- Beginne mit Phase 1. Kein Scope-Creep: Alles aus "Nicht-Ziele" ist tabu.
- Plan bleibt im Google Sheet; keine Zwei-Wege-Synchronisation in v1.
- Keine echten Gesundheitsdaten committen. Testdaten sind synthetisch.
- Fragen-IDs und Export-Schemata sind versioniert; nie rückwirkend ändern.
- Fehlende Werte sind `null`, niemals 0 oder interpoliert.
- Baseline-Berechnungen mit Unit-Tests absichern.
- Bei Unklarheit zu Datenquellen/HealthKit-Typen zuerst verifizieren (Testansicht), dann bauen.
- Große Architekturänderungen vorher vorschlagen und auf Freigabe warten.
- UI-Texte Deutsch, Code und Kommentare Englisch.

## Setup und Werkzeuge
- Entwickelt wird in VS Code (Swift-Extension + SweetPad), Xcode läuft nur im Hintergrund.
- Das Xcode-Projekt wird aus `project.yml` erzeugt und nicht eingecheckt. Nach Änderungen an `project.yml` oder neuen Dateien: `xcodegen generate`.
- iOS 17+, Swift 6, Standard-Isolation `MainActor` (Approachable Concurrency).
- Keine externen Abhängigkeiten in der App.

## Befehle
- Projekt erzeugen: `xcodegen generate`
- Bauen und testen (Simulator): `scripts/test.sh`
- Auf das iPhone spielen (auch nach Ablauf der 7-Tage-Signatur): `scripts/deploy-device.sh`

## Ordner
- `Cockpit/App` – Einstiegspunkt
- `Cockpit/Features/<Feature>` – Views und Logik je Feature
- `Cockpit/Core` – geteilte Hilfen (Datum, später HealthKit, Modelle)
- `CockpitTests` – Unit-Tests (Swift Testing)
- `private/` – echte Daten (CSV-Exporte, Berichte), von Git ignoriert
