# Cockpit – Trainings-Dashboard für iOS

Projektspezifikation · App-UI Deutsch, Code und Kommentare Englisch

---

## 1. Ziel

Cockpit ist eine persönliche iOS-App zur **Erfassung und Rückmeldung** im eigenen Training. Das Dashboard zeigt:

- Schlaf, HRV und Ruhepuls aus Apple Health im Vergleich zur **eigenen Norm**
- das **anstehende Training** aus einem importierten Wochenplan
- einen kurzen, **personalisierbaren Wohlbefinden-Fragebogen**

Die Daten werden als **versionierter Wochenbericht** (JSON + Markdown) exportiert und dienen als saubere Grundlage für die Trainingsplanung.

**Zweitziel:** Die Daten bilden die Grundlage für ein Data-Science-Projekt (Abschnitt 9).

**Nicht-Ziele:** Social-Funktionen, Cloud-Sync, Accounts, KI-Coach in der App, eigener Server, App-Store-Veröffentlichung.

---

## 2. Architekturentscheidungen

| Thema | Entscheidung | Begründung |
|---|---|---|
| Trainingsplan | Bleibt in einer externen Tabelle; die App importiert nur die aktuelle Woche (CSV) | Keine zweite Quelle der Wahrheit |
| Sync | Keine Zwei-Wege-Synchronisation in v1 | Häufigste Fehlerquelle |
| Datenhaltung | Lokal auf dem Gerät (SwiftData), kein Backend, keine Cloud | Gesundheitsdaten |
| Readiness-Score | Nicht in v1; zuerst nur Rohabweichungen | Ein ungeprüfter Score täuscht Genauigkeit vor |
| Regeln | Vom Nutzer konfigurierbar, erscheinen als **Hinweis**, nie als Entscheidung | Keine medizinischen Aussagen |
| Fragebogen | Fester Kern mit stabiler Skala + bedingte Zusatzfragen | Vergleichbarkeit über die Zeit |
| Export | Datei (JSON/Markdown); Schreiben in die Plan-Tabelle frühestens Phase 3 | Erst einfach, dann ausbauen |

**Tech-Stack:** iOS 17+, SwiftUI, SwiftData, Swift Charts, HealthKit (nur lesen). Keine externen Abhängigkeiten in v1.

---

## 3. Datenquelle: Apple Health

Ein Fitness-Tracker schreibt über seine Hersteller-App in Apple Health. Welche Metriken in welcher Form ankommen, wird zuerst mit einem **Health Explorer** (Debug-Ansicht) geprüft.

Zu lesende Typen: `sleepAnalysis`, `heartRateVariabilitySDNN`, `restingHeartRate`, optional `heartRate` und Workouts.

- **Mehrere Quellen** können parallel schreiben → Quelle je Messwert speichern, Duplikate vermeiden, Quellen nicht mischen.
- **Schlaf** kommt als `asleepUnspecified` oder in Phasen (`core/deep/REM`, `awake`, `inBed`) → beides robust behandeln. Eine Nacht zählt zum **Aufwach-Tag**.
- **HRV** vom Handgelenk ist verrauscht → Trends statt Einzelwerte; Metrik im UI klar benennen.
- Datum immer als **lokaler Kalendertag** (Zeitzone, Sommerzeit).
- Sync-Verzögerung einplanen: „Daten noch nicht da“ ist ein normaler Zustand.

---

## 4. Dashboard (Tageskarte)

1. Schlaf letzte Nacht + Abweichung von der Norm
2. HRV + Abweichung
3. Ruhepuls + Abweichung
4. Fragebogen-Status (heute ausgefüllt?) + Button
5. Anstehendes Training
6. Hinweise aus konfigurierten Regeln, klar als Hinweis markiert

**Baselines** (mit Unit-Tests abgesichert):
- Fenster 7 Tage (kurz) und 30 Tage (Norm); **Median** und Streuung (MAD oder SD)
- HRV vor z-Score ggf. log-transformieren
- Abweichungen erst ab ca. 14 Tagen Daten, sonst „zu wenig Daten“
- Fehlende Werte sichtbar machen, nie still interpolieren
- Ampelfarben nur mit transparenter Schwelle, keine medizinische Bewertung

---

## 5. Fragebogen

Täglich unter 30 Sekunden.

- **Fester Kern** (stabile IDs, Skala 1–7, angelehnt an den Hooper-Index): `sleep_quality`, `fatigue`, `muscle_soreness`, `stress`, optional `mood`
- **Bedingte Zusatzfragen:** Beschwerden je Körperregion (0–10, Regionen konfigurierbar), Alkohol, Freitext
- **Nach jeder Einheit:** Session-RPE (0–10) und Dauer
- **Wöchentlich:** längerer Check (Motivation, Gesamtbelastung, Besonderheiten)

Regeln: Fragen-IDs und Skalen nie stillschweigend ändern; jede Änderung erhöht `schemaVersion`, alte Antworten bleiben. Fehlende Antworten bleiben `null`.

---

## 6. Datenmodell (Skizze)

```swift
@Model final class DailyMetrics {
    @Attribute(.unique) var day: Date          // local calendar day (start of day)
    var sleepDurationMin: Int?
    var sleepStagesJSON: Data?
    var hrvMs: Double?
    var hrvSource: String?
    var restingHR: Double?
    var restingHRSource: String?
    var fetchedAt: Date
}

@Model final class QuestionnaireEntry {
    var day: Date
    var schemaVersion: Int
    var coreAnswersJSON: Data                  // {"sleep_quality":5,...}
    var extraAnswersJSON: Data?
    var note: String?
    var completedAt: Date
}

@Model final class PlannedSession {
    var date: Date
    var kind: String                           // "gym" | "team" | "other"
    var title: String
    var exercisesJSON: Data?
    var sourceWeekLabel: String?
}

@Model final class CompletedSession {
    var date: Date
    var kind: String
    var durationMin: Int?
    var sessionRPE: Int?                       // 0-10
    var note: String?
    var plannedSessionID: UUID?
}

@Model final class Rule {                      // user-configured hints, not decisions
    var id: UUID
    var name: String
    var definitionJSON: Data
    var message: String
    var enabled: Bool
}
```

Typen und Beziehungen werden nach dem Health Explorer finalisiert.

---

## 7. Import und Export

**Import (v1):** CSV-Export eines Wochenblatts der Plan-Tabelle per Dateiauswahl. Gelesen werden die Plan-Spalten (Tag, Datum, Einheit, Übung, Sätze×Wdh, RIR/Tempo, Pause, %1RM, Ziel kg). Der Parser toleriert Leerzeilen, Notizzeilen und deutsche Dezimalkommas. Ist-Werte und berechnete Spalten werden nicht importiert.

**Export (Wochenbericht):** `weekly_report_<YYYY>-W<ww>.json` (versioniert) und `.md` (kompakte Zusammenfassung ohne Interpretation).

```json
{
  "schemaVersion": 1,
  "week": { "isoWeek": "2026-W47", "from": "2026-11-16", "to": "2026-11-22" },
  "baselines": { "windowDays": 30, "sleepMedianMin": 440, "hrvMedianMs": 60, "restingHrMedian": 55 },
  "days": [
    {
      "date": "2026-11-16",
      "sleep": { "durationMin": 432, "stages": null },
      "hrv": { "ms": 58, "source": "Tracker", "zVsBaseline": -0.3 },
      "restingHr": { "bpm": 54 },
      "questionnaire": { "schemaVersion": 1, "core": { "sleep_quality": 5, "fatigue": 3 }, "extra": null, "note": null },
      "sessions": [ { "kind": "gym", "durationMin": 70, "sessionRPE": 7 } ]
    }
  ],
  "dataQuality": { "missingDays": [], "notes": [] }
}
```
*(Beispielwerte, synthetisch)*

Regeln: Schema nur additiv erweitern; fehlende Werte `null`, nie 0; Qualitätshinweise (fehlende Tage, Quellenwechsel) immer mitliefern.

---

## 8. Phasen

**Phase 1 – Daten und Tageskarte:** HealthKit-Zugriff und Health Explorer, Baselines mit Tests, Tageskarte, Fragebogen-Kern, JSON-Export.
*Abnahme:* Eine Woche Realdaten ohne Absturz; Werte stimmen stichprobenartig mit Apple Health überein; „zu wenig Daten“ und „nicht synchronisiert“ werden sauber angezeigt.

**Phase 2 – Plan und Bericht:** CSV-Import, anstehendes Training, Session-RPE, Wochenbericht JSON + Markdown, Regel-Hinweise.
*Abnahme:* Ein Wochenbericht ist ohne Nacharbeit für die Planung nutzbar.

**Phase 3 – Ausbau:** Gym-Logging (Ist-Werte, e1RM, Pausen-Timer/Live Activity), Schreiben in die Plan-Tabelle per API, Auswertungen und Charts.

---

## 9. Data-Science-Anschluss

- **Frage:** Sagt ein Readiness-Maß (Schlaf, HRV, Ruhepuls, Belastung) das Befinden am nächsten Tag besser voraus als einfache Baselines?
- **Methode:** gleitende Mittel und z-Scores gegen die eigene Norm vs. kleines ML-Modell (z. B. Ridge, Gradient Boosting); zeitliche Kreuzvalidierung ohne Zukunfts-Leckage.
- **Ehrliche Erwartung:** n = 1, verrauschte Daten; auch „nicht besser als die Baseline“ ist ein gültiges Ergebnis.

Deshalb schon in der App: stabile Fragen-IDs, versionierte Schemata, Quelle je Messwert, fehlende Werte als `null`.

---

## 10. Datenschutz

- Gesundheitsdaten bleiben lokal, keine Cloud, kein Tracking.
- **Keine echten Daten im Repository**; Tests und Beispiele nutzen synthetische Daten.
- Exportdateien sind sensibel und werden bewusst geteilt, nie automatisch hochgeladen.
- Die App trifft **keine medizinischen Aussagen**; Hinweise sind Orientierung.
