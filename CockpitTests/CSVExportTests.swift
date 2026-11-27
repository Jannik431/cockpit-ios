import Foundation
import Testing
@testable import Cockpit

/// All data here is synthetic.
struct CSVExportTests {
    private let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private var day: Date { berlin.date(from: DateComponents(year: 2026, month: 11, day: 24))! }

    private func lines(_ days: [ExportDay]) -> [String] {
        CSVExport.csv(days: days, calendar: berlin).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func value(_ column: String, in day: ExportDay) -> String? {
        CSVExport.row(for: day, calendar: berlin)[column]
    }

    @Test func headerStartsWithRequiredColumnsInOrder() {
        let header = lines([])[0]
        #expect(header.hasPrefix("datum,knie_morgen_links,knie_morgen_rechts,knie_belastung_links,knie_belastung_rechts,knie_alltag_links,knie_alltag_rechts,schulter_links,schulter_rechts,ruecken,ellenbogen,schlaf_h,hrv_rmssd_ms,gewicht_kg,notiz"))
        #expect(header.contains(",schema_version,"))
    }

    @Test func emptyDayHasOnlyDateAndVersion() {
        let row = lines([ExportDay(day: day)])[1]
        #expect(row.hasPrefix("2026-11-24,"))
        #expect(row.split(separator: ",", omittingEmptySubsequences: false).count == CSVExport.columns.count)
        #expect(CSVExport.row(for: ExportDay(day: day), calendar: berlin) == ["datum": "2026-11-24", "schema_version": "1"])
        #expect(!row.contains(",0,"))
    }

    @Test func zeroIsKeptAndMissingStaysEmpty() {
        var export = ExportDay(day: day)
        export.morning = ["pain_knee_left_morning": .int(0)]
        #expect(value("knie_morgen_links", in: export) == "0")
        #expect(value("knie_morgen_rechts", in: export) == nil)
    }

    @Test func numbersUseDecimalPointAndNoTrailingZeros() {
        var export = ExportDay(day: day)
        export.asleepMin = 444
        export.restingHR = 58
        export.morning = ["hrv_rmssd_zepp": .double(41), "body_weight": .double(86.25)]
        #expect(value("schlaf_h", in: export) == "7.4")
        #expect(value("hrv_rmssd_ms", in: export) == "41")
        #expect(value("gewicht_kg", in: export) == "86.3")
        #expect(value("ruhepuls_bpm", in: export) == "58")
    }

    @Test func notesAreJoinedAndEscaped() {
        var export = ExportDay(day: day)
        export.notes = ["Knie ok, \"gut\"", "  ", "zweite"]
        #expect(value("notiz", in: export) == "Knie ok, \"gut\" | zweite")
        #expect(lines([export])[1].contains("\"Knie ok, \"\"gut\"\" | zweite\""))
    }

    @Test func sessionsGiveKneeLoadHandballBandAndTrainingLoad() {
        var export = ExportDay(day: day)
        export.sessions = [
            ExportSession(kind: .gym, rpe: 6, durationMin: 60, kneePainLeft: 1),
            ExportSession(kind: .handball, rpe: 7, durationMin: 90, isMatch: true, throwVolume: 2,
                          kneePainLeft: 3, kneePainRight: 0, minutesPlayed: 40),
            ExportSession(kind: .handball, rpe: nil, durationMin: 30, throwVolume: 1),
        ]
        #expect(value("knie_belastung_links", in: export) == "3")
        #expect(value("knie_belastung_rechts", in: export) == "0")
        #expect(value("handball_belastung", in: export) == "hart")
        #expect(value("spielminuten", in: export) == "40")
        #expect(value("wurfvolumen", in: export) == "mittel")
        #expect(value("trainingslast_au", in: export) == "990")
    }

    @Test func illnessCaffeineAndMidday() {
        var export = ExportDay(day: day)
        export.morning = ["illness": .int(1), "symptoms": .list([0, 1])]
        export.evening = ["caffeine_today": .bool(true), "last_caffeine_time": .time(13 * 60 + 30), "alcohol_drinks": .int(0)]
        export.midday = ["energy_midday": .int(3)]
        #expect(value("krank", in: export) == "1")
        #expect(value("symptome", in: export) == "Hals;Schnupfen")
        #expect(value("kaffee", in: export) == "1")
        #expect(value("letzter_kaffee_uhrzeit", in: export) == "13:30")
        #expect(value("alkohol_drinks", in: export) == "0")
        #expect(value("energie_mittag", in: export) == "3")

        export.evening = ["caffeine_today": .bool(false)]
        #expect(value("kaffee", in: export) == "0")
        #expect(value("letzter_kaffee_uhrzeit", in: export) == nil)
    }

    @Test func newColumnsAreAppendedAfterSchemaVersion() {
        let header = lines([])[0].split(separator: ",").map(String.init)
        let version = header.firstIndex(of: "schema_version")!
        #expect(Array(header[(version + 1)...]) == [
            "fieber", "symptome_zeit", "knie_rote_flagge", "knie_rote_flagge_art",
            "einheit_1", "minuten_1", "rpe_1", "einheit_2", "minuten_2", "rpe_2", "einheit_3", "minuten_3", "rpe_3",
            "kaffee_tassen", "stehen_sitzen_lang", "muskelkater",
        ])
    }

    @Test func feverSymptomTimingRedFlagsPostureAndSoreness() {
        var export = ExportDay(day: day)
        export.morning = ["illness": .int(2), "symptoms": .list([0, 3]), "muscle_soreness": .int(5)]
        export.evening = ["symptoms_time": .int(2), "knee_red_flag": .bool(true), "knee_red_flag_types": .list([0, 6]),
                          "long_static_posture": .bool(true), "caffeine_drinks": .int(3), "last_caffeine_time": .time(14 * 60)]
        #expect(value("fieber", in: export) == "1")
        #expect(value("symptome_zeit", in: export) == "ganztags")
        #expect(value("knie_rote_flagge", in: export) == "1")
        #expect(value("knie_rote_flagge_art", in: export) == "wegknicken;nachtschmerz")
        #expect(value("stehen_sitzen_lang", in: export) == "1")
        #expect(value("muskelkater", in: export) == "2")
        #expect(value("kaffee_tassen", in: export) == "3")
        #expect(value("kaffee", in: export) == "1")
        #expect(value("letzter_kaffee_uhrzeit", in: export) == "14:00")

        export.morning = ["illness": .int(0), "muscle_soreness": .int(7)]
        export.evening = ["knee_red_flag": .bool(false), "caffeine_drinks": .int(0), "last_caffeine_time": .time(9 * 60)]
        #expect(value("fieber", in: export) == "0")
        #expect(value("muskelkater", in: export) == "0")
        #expect(value("knie_rote_flagge", in: export) == "0")
        #expect(value("knie_rote_flagge_art", in: export) == nil)
        #expect(value("kaffee", in: export) == "0")
        #expect(value("letzter_kaffee_uhrzeit", in: export) == nil)
    }

    @Test func sessionsFillUnitColumnsInOrderAndAddGroupsBeyondThree() {
        var export = ExportDay(day: day)
        export.sessions = [
            ExportSession(kind: .gym, rpe: 6, durationMin: 60, planUnit: "A-moderat"),
            ExportSession(kind: .handball, rpe: nil, durationMin: 85),
            ExportSession(kind: .handball, rpe: 8, durationMin: 70, planUnit: "Spiel"),
            ExportSession(kind: .other, rpe: 3, durationMin: 20, planUnit: "Sonstiges"),
        ]
        #expect(value("einheit_1", in: export) == "A-moderat")
        #expect(value("minuten_1", in: export) == "60")
        #expect(value("rpe_1", in: export) == "6")
        #expect(value("einheit_2", in: export) == nil)
        #expect(value("minuten_2", in: export) == "85")
        #expect(value("rpe_2", in: export) == nil)
        #expect(value("einheit_3", in: export) == "Spiel")

        let csv = lines([export, ExportDay(day: berlin.date(byAdding: .day, value: -1, to: day)!)])
        #expect(csv[0].hasSuffix(",einheit_4,minuten_4,rpe_4"))
        #expect(csv[2].hasSuffix(",Sonstiges,20,3"))
        #expect(csv[1].split(separator: ",", omittingEmptySubsequences: false).count == csv[0].split(separator: ",").count)
    }

    @Test func olderCaffeineAnswerStillExported() {
        var export = ExportDay(day: day)
        export.evening = ["caffeine_today": .bool(true), "last_caffeine_time": .time(13 * 60)]
        #expect(value("kaffee", in: export) == "1")
        #expect(value("kaffee_tassen", in: export) == nil)
        #expect(value("letzter_kaffee_uhrzeit", in: export) == "13:00")
    }

    @Test func handballBandThresholds() {
        #expect(SessionScales.handballLoadBand(rpe: 4) == "leicht")
        #expect(SessionScales.handballLoadBand(rpe: 5) == "mittel")
        #expect(SessionScales.handballLoadBand(rpe: 6) == "mittel")
        #expect(SessionScales.handballLoadBand(rpe: 7) == "hart")
    }

    @Test func logicalTodayRollsOverAtFour() {
        let late = berlin.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 0, minute: 40))!
        let morning = berlin.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 4, minute: 0))!
        #expect(LocalDay.logicalToday(late, calendar: berlin) == day)
        #expect(LocalDay.logicalToday(morning, calendar: berlin) == berlin.date(byAdding: .day, value: 1, to: day))
    }
}
