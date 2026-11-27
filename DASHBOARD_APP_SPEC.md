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

### Erkenntnisse aus dem Health Explorer (30 Tage Realdaten)

| Typ | Befund | Konsequenz |
|---|---|---|
| Schlaf | Eine Quelle; Phasen (Kern/Tief/REM/Wach) und genau ein „Im Bett“-Eintrag pro Nacht | Längster „Im Bett“-Eintrag pro Aufwach-Tag ist die Nacht; Phasen zählen per Mittelpunkt dazu; Nickerchen werden ignoriert |
| HRV | ~3 Werte pro Nacht. Die Tracker-App zeigt **RMSSD**, in Health steht **SDNN**; die Zahlen weichen ab. Apple Health hat keinen RMSSD-Typ, und der Hersteller bietet keine öffentliche API | Eigene Metrik `healthkit_sdnn`, nie mit Werten aus der Tracker-App mischen; Rohwerte der Nacht speichern, Nachtmittel daraus |
| Ruhepuls | Ein Wert pro Tag, Zeitstempel ist ein Datumsstempel (00:00, in der Sommerzeit 01:00) | Zuordnung nach Kalendertag |
| Herzfrequenz | Mehrere tausend Werte pro Tag, im Training dichter | Wird nicht importiert; bei Bedarf später gezielt pro Workout |
| Workouts | Typen brauchbar: Krafttraining = Gym, „Andere“ (automatische Erkennung) = Handball; Spiele werden teils in mehrere Workouts geteilt | Typ nur als Vorschlag; gleiche Art mit < 30 min Abstand = eine Einheit |

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

**Umgesetzt** (`BaselineCalculator`, alle Konstanten an einer Stelle und in der App erklärt):
- **Norm:** Median der 30 Tage *vor* dem Tag (der Tag selbst zählt nicht mit), ab 14 vorhandenen Werten
- **Kurzfristig:** Median der letzten 7 Tage *inklusive* des Tages, ab 4 Werten, als Trend gegen die Norm
- **Abweichung:** Differenz in der Einheit der Metrik und robuster z-Wert `(x − Median) / (1,4826 × MAD)`; HRV auf ln-Skala
- **Einordnung:** |z| < 1 im Normbereich, 1 ≤ |z| < 2 leicht, |z| ≥ 2 deutlich über/unter der Norm; MAD = 0 → „keine Streuung“, kein z
- Fehlende Tage zählen als fehlend (`x von 30`), es wird nichts aufgefüllt

**Tageskarte umgesetzt:**
- **Schlaf:** Dauer und Abweichung zur Norm, dazu der Nachtverlauf der letzten Nacht als Hypnogramm (Tief/Kern/REM/Wach) mit Minuten je Phase. Die Phasen-Intervalle werden dafür pro Nacht gespeichert.
- **HRV und Ruhepuls:** Wert, Abweichung und die letzten 10 Tage (30 Tage wirkten zu flach) mit Normbereich als Band und Median gestrichelt. Jeder Punkt ist gegen die Norm seines eigenen Tages eingefärbt; Lücken bleiben Lücken.
- Darunter das heutige Training aus Apple Health (Art als Vorschlag) und ein Platzhalter für den Fragebogen. Die Methode wird in der App erklärt.
- **Farben nach Auswirkung** (Entscheidung des Nutzers): grün = Normbereich oder günstige Richtung, gelb = leicht ungünstig, orange = deutlich ungünstig. Günstig: mehr Schlaf, höhere HRV, niedrigerer Ruhepuls. Das ist eine Faustregel zur Orientierung; die App sagt das in der Erklärung auch so. Zahlen bleiben neutral gefärbt (Kontrast), die Farbe steckt in Chip und Punkten.

---

## 5. Fragebogen

Täglich unter 30 Sekunden.

- **Fester Kern** (stabile IDs, Skala 1–7, angelehnt an den Hooper-Index): `sleep_quality`, `fatigue`, `muscle_soreness`, `stress`, optional `mood`
- **Bedingte Zusatzfragen:** Beschwerden je Körperregion (0–10, Regionen konfigurierbar), Alkohol, Freitext
- **Nach jeder Einheit:** Session-RPE (0–10) und Dauer
- **Wöchentlich:** längerer Check (Motivation, Gesamtbelastung, Besonderheiten)

Regeln: Fragen-IDs und Skalen nie stillschweigend ändern; jede Änderung erhöht `schemaVersion`, alte Antworten bleiben. Fehlende Antworten bleiben `null`.

**Umgesetzt: Katalog Version 3** (`QuestionCatalog`), Einheiten-Skalen Version 3 (`SessionScales`). Antworten behalten die Version, in der sie gegeben wurden; Antworten auf nicht mehr gestellte Fragen bleiben gespeichert.

| Zeitpunkt | Fragen (ID) | Skala |
|---|---|---|
| Morgen-Check | `sleep_quality`, `energy`, `muscle_soreness`, `stress`, `training_motivation` | 1–7, höher = besser |
| | `illness` → bei „leichte“/„krank“ `symptoms` (Hals, Schnupfen, Husten, Fieber, Magen-Darm, Gliederschmerzen) | Auswahl; Mehrfachauswahl |
| | `pain_<region>_morning` für Knie links/rechts, Schulter links/rechts, Rücken, Ellenbogen | 0–10 (NRS), Schnellwahl „Keine Beschwerden“ |
| | `hrv_rmssd_zepp` (optional), `body_weight` (optional, Wiegetage Mo/Mi/Fr) | ms, kg |
| Mittag (ab 12 Uhr) | `energy_midday` | 1–5, auch direkt aus der Benachrichtigung |
| Abend-Check (ab 17 Uhr, bis 4 Uhr nachts für den Vortag) | `knee_daily_left/right` (Knie im Alltag, ohne Training) | 0–10 |
| | `knee_red_flag` → `knee_red_flag_types` (Wegknicken, Instabil, Schwellung, Drehschmerz, Blockade, Kniescheibe, Nachtschmerz) | ja/nein; Mehrfachauswahl |
| | `symptoms_time` (keine / morgens / ganztags), `long_static_posture` (> 2 h am Stück gestanden/gesessen) | Auswahl; ja/nein |
| | `pain_<region>_evening` für Schulter links/rechts, Rücken, Ellenbogen | 0–10 |
| | `food_amount`, `protein_ok`, `caffeine_drinks` (alle Koffein-Getränke) → `last_caffeine_time`, `alcohol_drinks` | Auswahl, ja/nein, Anzahl, Uhrzeit, Anzahl |
| Pro Einheit | Einheit laut Plan (A, A-moderat, A_kurz, B, C, C-Light, C-kurz, D, Plyo2, Handball, Spiel, Sonstiges; daraus Art und Spiel/Training), Session-RPE, Dauer, Knie während der Einheit links/rechts; bei Handball Spielminuten (nur Spiel), Wurfvolumen | Auswahl; Borg CR10 0–10; 0–10; Minuten; kaum/wenig/mittel/viel |

Versionen: Katalog 1 → 2 ersetzt die abendliche Knie-Frage (`pain_knee_*_evening`) durch „Knie im Alltag“ und ergänzt Symptome und die Mittagsfrage. Katalog 2 → 3: Koffein als Anzahl (`caffeine_drinks` statt `caffeine_today`), Symptom-Zeitpunkt, Knie-Warnzeichen, langes Stehen/Sitzen. Einheiten-Skalen 1 → 2 ergänzen Knie und Spielminuten, 2 → 3 die Einheit laut Plan (Schema V3: `CompletedSession.planUnit`).

- **Timing:** Die Tageskarte zeigt Morgen-Check, Mittagsfrage und Abend-Check mit Status. Eine Einheit aus Apple Health, die vor mindestens 30 Minuten geendet hat und noch kein RPE hat, erscheint oben als Hinweis. Vor 4 Uhr gilt noch der Vortag („logischer Tag“).
- **Vergangene Tage:** Über den Tagesumschalter lassen sich frühere Tage ansehen und Check-ins und Einheiten nachtragen.
- **Einheiten:** Selbst erfasste Einheiten lassen sich löschen; falsch erkannte Workouts aus Apple Health lassen sich ausblenden (zählen dann nirgends mit, wieder einblendbar).
- **Push-Erinnerungen** (lokal, `ReminderPlanner`): Wiegen Mo/Mi/Fr 8:30, Morgen-Check 9:00, Mittag 13:30 (mit Antwortknöpfen 1–5), Abend-Check 22:30. Sie werden 14 Tage im Voraus geplant, bei jedem App-Start und nach jedem gespeicherten Bogen neu berechnet und entfallen, wenn der Check schon erledigt ist. Antippen öffnet den passenden Bogen. Alle Erinnerungen haben Ton; ob das iPhone dabei vibriert, hängt von den Haptik-Einstellungen ab. „Zeitkritische“ Benachrichtigungen (durchbrechen Fokus-Modi) gibt es mit dem kostenlosen Entwickler-Account nicht.
- **RPE bei Eingang der Einheit:** HealthKit-Hintergrundzustellung (`HKObserverQuery`, Entitlement `healthkit.background-delivery`, funktioniert mit dem kostenlosen Account). Kommt ein neues Workout in Apple Health an, importiert die App im Hintergrund und plant eine Erinnerung 30 Minuten nach Ende der Einheit (bei später Synchronisierung sofort, aber nur einmal). Bei Handball fragt sie Session-RPE und Wurfvolumen ab. Wann iOS die App weckt, entscheidet das System; bei gesperrtem iPhone kann es sich verzögern.
- **Speicherung:** `QuestionnaireEntry` (Tag, Phase, Katalog-Version, Antworten als JSON) und `CompletedSession` (bestätigte Art, Dauer, RPE, Last = RPE × Dauer, verknüpfte Workout-IDs). Ab hier gibt es ein versioniertes SwiftData-Schema mit Migrationsplan; der alte, unversionierte Speicher (nur Health-Daten) wird einmalig neu angelegt und neu importiert.
- **Zepp-RMSSD** bekommt ab 14 Werten eine eigene Norm und erscheint als eigene Zeile in der HRV-Kachel, nie vermischt mit SDNN.

---

## 6. Datenmodell (Skizze)

Umgesetzt (Phase 1): `DailyMetrics` und `HealthWorkout`. Der Rest ist noch Skizze.

```swift
@Model final class DailyMetrics {              // re-importable from Apple Health
    @Attribute(.unique) var day: Date          // local wake day (start of day)
    var inBedStart: Date?, inBedEnd: Date?
    var asleepMin: Int?, awakeMin: Int?
    var coreMin: Int?, deepMin: Int?, remMin: Int?, unspecifiedMin: Int?
    var sleepSource: String?
    var hrvMetric: String?                     // "healthkit_sdnn"
    var hrvSamplesJSON: Data?                  // raw night samples [{time, ms}]
    var hrvNightMeanMs: Double?
    var hrvSource: String?
    var restingHR: Double?
    var restingHRSource: String?
    var fetchedAt: Date
}

@Model final class HealthWorkout {
    @Attribute(.unique) var healthID: UUID     // HealthKit UUID
    var day: Date
    var start: Date, end: Date
    var activityTypeRaw: Int                   // kind is only suggested from this
    var activityTypeName: String?
    var sourceBundleID: String
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
    var kind: String                           // "gym" | "handball" | "other"
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

**Import:** Beim ersten Start die letzten 90 Tage, danach ab dem letzten gespeicherten Tag minus 3 Tage (spät synchronisierte Werte werden nachgezogen). Upsert nach Tag bzw. HealthKit-UUID. Pro Metrik wird nur die Quelle mit den meisten Werten verwendet.

**Hinweis:** Sobald nicht wiederherstellbare Daten (Fragebogen, Session-RPE) gespeichert werden, kommt ein versioniertes SwiftData-Schema (`VersionedSchema`) mit Migrationsplan dazu.

---

## 7. Import und Export

**Import (v1):** CSV-Export eines Wochenblatts der Plan-Tabelle per Dateiauswahl. Gelesen werden die Plan-Spalten (Tag, Datum, Einheit, Übung, Sätze×Wdh, RIR/Tempo, Pause, %1RM, Ziel kg). Der Parser toleriert Leerzeilen, Notizzeilen und deutsche Dezimalkommas. Ist-Werte und berechnete Spalten werden nicht importiert.

**Export (Tages-CSV, umgesetzt):** `cockpit_export.csv` (`CSVExport`, `ExportService`). Die Trainingsplanung liest diese eine Datei direkt.
- UTF-8, Komma als Trenner, Dezimalpunkt, Datum `JJJJ-MM-TT`, eine Zeile pro Tag, immer alle Tage vom ersten Tag mit Daten bis heute.
- Leer = nicht erfasst, nie 0. Einheit steht im Spaltennamen. Spalten werden nur hinten ergänzt; `schema_version` steigt, wenn sich eine Bedeutung ändert.
- Spalten: `datum, knie_morgen_links, knie_morgen_rechts, knie_belastung_links, knie_belastung_rechts, knie_alltag_links, knie_alltag_rechts, schulter_links, schulter_rechts, ruecken, ellenbogen, schlaf_h, hrv_rmssd_ms, gewicht_kg, notiz, ruhepuls_bpm, alkohol_drinks, krank, symptome, handball_belastung, spielminuten, wurfvolumen, kaffee, letzter_kaffee_uhrzeit, energie_mittag, trainingslast_au, schema_version, fieber, symptome_zeit, knie_rote_flagge, knie_rote_flagge_art, einheit_1, minuten_1, rpe_1, einheit_2, minuten_2, rpe_2, einheit_3, minuten_3, rpe_3, kaffee_tassen, stehen_sitzen_lang, muskelkater` – bei mehr als 3 Einheiten an einem Tag ganz hinten zusätzlich `einheit_4, minuten_4, rpe_4` usw.
- Herkunft: Schmerzen morgens aus dem Morgen-Check; `knie_alltag` aus dem Abend-Check; `knie_belastung` = höchster Wert der Einheiten des Tages; `schlaf_h` = Nacht, die am Morgen des Tages endet; `hrv_rmssd_ms` nur aus dem Zepp-Feld (RMSSD), nie SDNN; `krank` = 1 schon bei leichten Anzeichen, Details in `symptome` (mit `;` getrennt); `handball_belastung` aus dem höchsten Handball-RPE (bis 4 leicht, 5–6 mittel, ab 7 hart); `wurfvolumen` = höchste Stufe des Tages; `kaffee` 0/1, die Uhrzeit nur bei 1; `trainingslast_au` = Summe RPE × Minuten der Einheiten mit RPE; `notiz` = Notizen von morgens, abends und aus den Einheiten, mit „ | “ getrennt; `fieber` = 1, wenn bei den Symptomen „Fieber“ angekreuzt ist (0 bei keinen Krankheitszeichen); `knie_rote_flagge_art` mit `;` getrennt; `einheit_n/minuten_n/rpe_n` = Einheiten des Tages nach Startzeit, auch Workouts aus Apple Health ohne Eintrag (dann nur Minuten); ältere Einträge ohne Plan-Einheit: Handball/Spiel/Sonstiges abgeleitet, Gym leer; `kaffee_tassen` = Anzahl Koffein-Getränke, `kaffee` daraus 0/1 (vorher ja/nein); `muskelkater` = 0–6, höher = stärker (in der App 1–7 mit 7 = keiner).
- **Ablage:** Die Datei wird einmal über die Dateien-App verknüpft (z. B. in einem Cloud-Ordner der Trainingsplanung) und danach nach jedem gespeicherten Check-in, jeder Einheit und beim Öffnen überschrieben. Auf dem Gerät mit Google Drive geprüft: Die verknüpfte Datei wird zuverlässig überschrieben. Als Rückfall gibt es „Datei teilen“.

**Export (Wochenbericht, geplant):** `weekly_report_<YYYY>-W<ww>.json` (versioniert) und `.md` (kompakte Zusammenfassung ohne Interpretation).

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

**Bereits zusätzlich umgesetzt:** Belastungs-Monitoring (Wochenlast nach Art, Tageslast, akut 7 Tage vs. Ø 28 Tage mit Hinweis auf die umstrittene ACWR, Monotonie und Strain nach Foster, Wurfvolumen pro Woche, Knie neben der Last) und Gewichtsverlauf (Trend = Mittel der letzten 3 Wiegungen).

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
- Exportdateien sind sensibel. Ausnahme (Entscheidung des Nutzers): Die Tages-CSV wird automatisch in die einmal bewusst verknüpfte Datei geschrieben, auch wenn diese in einem Cloud-Ordner liegt. Andere Exporte werden nur bewusst geteilt.
- Die App trifft **keine medizinischen Aussagen**; Hinweise sind Orientierung.
