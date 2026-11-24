import Foundation

/// One training session for load monitoring. `load` is session RPE × minutes (Foster), `nil` without RPE.
nonisolated struct LoadEntry: Sendable, Equatable {
    let day: Date
    let kind: SessionKind
    let load: Int?
    var throwVolume: Int?
}

nonisolated struct WeekLoad: Sendable, Equatable, Identifiable {
    let weekStart: Date
    var byKind: [SessionKind: Int] = [:]
    /// Sessions without RPE: their load is unknown, so the week total is a lower bound.
    var unrated = 0
    /// Handball sessions per throwing-volume index.
    var throwVolumes: [Int: Int] = [:]

    var id: Date { weekStart }
    var total: Int { byKind.values.reduce(0, +) }
}

nonisolated struct LoadSummary: Sendable, Equatable {
    /// Sum of the last 7 days including today.
    let acute: Int
    /// Mean weekly load over the last 28 days; `nil` with less than 28 days of history.
    let chronicWeekly: Double?
    /// Acute : chronic workload ratio. Shown with a caveat, it is debated in sports science.
    let ratio: Double?
    /// Foster: mean / standard deviation of the last 7 daily loads; `nil` if they do not vary.
    let monotony: Double?
    /// Foster: weekly load × monotony.
    let strain: Double?
    /// Sessions in the last 7 days without RPE.
    let unrated: Int
}

nonisolated enum LoadMetrics {
    static let acuteDays = 7
    static let chronicDays = 28

    /// Load per day; days without sessions have load 0 (no training is a real zero).
    static func dailyLoads(_ entries: [LoadEntry], days: [Date]) -> [Date: Int] {
        let byDay = Dictionary(grouping: entries, by: \.day).mapValues { $0.compactMap(\.load).reduce(0, +) }
        return Dictionary(uniqueKeysWithValues: days.map { ($0, byDay[$0] ?? 0) })
    }

    /// The last `count` weeks (Monday to Sunday) up to the week containing `today`, oldest first.
    static func weeks(_ entries: [LoadEntry], endingAt today: Date, count: Int, calendar: Calendar = .current) -> [WeekLoad] {
        var cal = calendar
        cal.firstWeekday = 2
        guard let currentWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        let starts = (0..<count).reversed().compactMap { cal.date(byAdding: .weekOfYear, value: -$0, to: currentWeek) }
        var weeks = Dictionary(uniqueKeysWithValues: starts.map { ($0, WeekLoad(weekStart: $0)) })

        for entry in entries {
            guard let start = cal.dateInterval(of: .weekOfYear, for: entry.day)?.start, var week = weeks[start] else { continue }
            if let load = entry.load {
                week.byKind[entry.kind, default: 0] += load
            } else {
                week.unrated += 1
            }
            if entry.kind == .handball, let volume = entry.throwVolume {
                week.throwVolumes[volume, default: 0] += 1
            }
            weeks[start] = week
        }
        return starts.compactMap { weeks[$0] }
    }

    /// - Parameter firstDay: first day the app has training data for (history length for the chronic load).
    static func summary(_ entries: [LoadEntry], today: Date, firstDay: Date, calendar: Calendar = .current) -> LoadSummary {
        let acuteDays = LocalDay.window(endingAt: today, count: Self.acuteDays, calendar: calendar)
        let chronicDays = LocalDay.window(endingAt: today, count: Self.chronicDays, calendar: calendar)
        let daily = dailyLoads(entries, days: chronicDays)

        let acuteLoads = acuteDays.map { Double(daily[$0] ?? 0) }
        let acute = Int(acuteLoads.reduce(0, +))

        let hasChronicHistory = chronicDays.first.map { firstDay <= $0 } ?? false
        let chronicWeekly = hasChronicHistory ? Double(chronicDays.map { daily[$0] ?? 0 }.reduce(0, +)) / 4 : nil
        let ratio = chronicWeekly.flatMap { $0 > 0 ? Double(acute) / $0 : nil }

        let mean = acuteLoads.reduce(0, +) / Double(acuteLoads.count)
        let variance = acuteLoads.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(acuteLoads.count)
        let sd = variance.squareRoot()
        let monotony = sd > 0 ? mean / sd : nil

        let acuteSet = Set(acuteDays)
        let unrated = entries.filter { $0.load == nil && acuteSet.contains($0.day) }.count

        return LoadSummary(
            acute: acute,
            chronicWeekly: chronicWeekly,
            ratio: ratio,
            monotony: monotony,
            strain: monotony.map { Double(acute) * $0 },
            unrated: unrated
        )
    }
}
