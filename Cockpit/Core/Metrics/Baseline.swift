import Foundation

/// Metrics that are compared against the personal norm.
nonisolated enum BaselineMetric: String, CaseIterable, Sendable {
    case sleep
    case hrv
    case restingHR

    var title: String {
        switch self {
        case .sleep: "Schlaf"
        case .hrv: HRVMetric.title
        case .restingHR: "Ruhepuls"
        }
    }

    /// HRV is roughly log-normal, so its spread and z-score are computed on ln(value).
    var usesLogScale: Bool { self == .hrv }

    /// Direction that counts as favourable for the colour coding: more sleep, higher HRV, lower resting HR.
    var higherIsFavorable: Bool { self != .restingHR }
}

/// Colour coding of a deviation by its likely effect (user decision, see spec section 4).
/// Orientation only, not a medical assessment.
nonisolated enum Impact: String, Sendable {
    /// Within the norm or deviating in the favourable direction.
    case good
    /// Slightly in the unfavourable direction.
    case caution
    /// Clearly in the unfavourable direction.
    case warning
    /// Cannot be judged (no spread in the norm).
    case unknown

    init(_ deviation: Deviation, metric: BaselineMetric) {
        let favorableUp = metric.higherIsFavorable
        switch deviation.band {
        case .withinNorm: self = .good
        case .undetermined: self = .unknown
        case .slightlyAbove: self = favorableUp ? .good : .caution
        case .clearlyAbove: self = favorableUp ? .good : .warning
        case .slightlyBelow: self = favorableUp ? .caution : .good
        case .clearlyBelow: self = favorableUp ? .warning : .good
        }
    }
}

extension MetricAssessment {
    var impact: Impact? {
        guard case .available(let deviation) = status else { return nil }
        return Impact(deviation, metric: metric)
    }
}

/// Median and spread of one metric over a window of local days.
nonisolated struct Baseline: Sendable, Equatable {
    let windowDays: Int
    /// Days in the window with a value.
    let count: Int
    /// Median in the metric's own unit (for log-scale metrics: exp of the median of the logs).
    let median: Double
    /// Median absolute deviation, on the log scale for log-scale metrics.
    let mad: Double

    var missing: Int { windowDays - count }
}

nonisolated enum DeviationBand: String, Sendable {
    case withinNorm
    case slightlyBelow
    case slightlyAbove
    case clearlyBelow
    case clearlyAbove
    /// The norm has no spread (MAD = 0), so the size of a deviation cannot be judged.
    case undetermined

    var title: String {
        switch self {
        case .withinNorm: "im Normbereich"
        case .slightlyBelow: "leicht unter der Norm"
        case .slightlyAbove: "leicht über der Norm"
        case .clearlyBelow: "deutlich unter der Norm"
        case .clearlyAbove: "deutlich über der Norm"
        case .undetermined: "keine Streuung in der Norm"
        }
    }
}

nonisolated struct Deviation: Sendable, Equatable {
    let value: Double
    /// `value - norm median`, in the metric's own unit.
    let difference: Double
    /// Robust z-score: (x − median) / (1.4826 × MAD), on the log scale for log-scale metrics.
    let z: Double?
    let band: DeviationBand
}

nonisolated enum BaselineStatus: Sendable, Equatable {
    /// Fewer than `required` values in the norm window.
    case insufficientData(count: Int, required: Int)
    /// The norm exists, but the day itself has no value.
    case missingValue
    case available(Deviation)
}

nonisolated struct MetricAssessment: Sendable, Equatable {
    let metric: BaselineMetric
    let day: Date
    let value: Double?
    /// The `normWindowDays` days *before* `day`.
    let norm: Baseline?
    /// The `shortWindowDays` days up to and including `day`.
    let shortTerm: Baseline?
    let status: BaselineStatus
    /// Short-term median compared with the norm (trend of the last week).
    let shortTermDeviation: Deviation?
}

/// Personal baselines (spec, section 4). All thresholds are constants here so they can be shown in the UI.
nonisolated enum BaselineCalculator {
    static let normWindowDays = 30
    static let shortWindowDays = 7
    static let minimumNormValues = 14
    static let minimumShortValues = 4
    /// Makes the MAD comparable to a standard deviation for normally distributed data.
    static let madScale = 1.4826
    static let notableZ = 1.0
    static let strongZ = 2.0

    /// - Parameter values: metric values keyed by local day (start of day). Missing days are simply absent.
    static func assess(
        _ metric: BaselineMetric,
        on day: Date,
        values: [Date: Double],
        calendar: Calendar = .current
    ) -> MetricAssessment {
        let day = LocalDay.start(of: day, calendar: calendar)
        let value = values[day]

        let normDays = calendar.date(byAdding: .day, value: -1, to: day).map {
            LocalDay.window(endingAt: $0, count: normWindowDays, calendar: calendar)
        } ?? []
        let shortDays = LocalDay.window(endingAt: day, count: shortWindowDays, calendar: calendar)

        let normValues = normDays.compactMap { values[$0] }
        let shortValues = shortDays.compactMap { values[$0] }

        let norm = normValues.count >= minimumNormValues
            ? baseline(normValues, windowDays: normWindowDays, logScale: metric.usesLogScale)
            : nil
        let shortTerm = shortValues.count >= minimumShortValues
            ? baseline(shortValues, windowDays: shortWindowDays, logScale: metric.usesLogScale)
            : nil

        let status: BaselineStatus
        if let norm {
            status = value.map { .available(deviation(of: $0, from: norm, logScale: metric.usesLogScale)) } ?? .missingValue
        } else {
            status = .insufficientData(count: normValues.count, required: minimumNormValues)
        }

        let shortTermDeviation: Deviation? = if let norm, let shortTerm {
            deviation(of: shortTerm.median, from: norm, logScale: metric.usesLogScale)
        } else {
            nil
        }

        return MetricAssessment(
            metric: metric,
            day: day,
            value: value,
            norm: norm,
            shortTerm: shortTerm,
            status: status,
            shortTermDeviation: shortTermDeviation
        )
    }

    static func baseline(_ values: [Double], windowDays: Int, logScale: Bool) -> Baseline? {
        let transformed = logScale ? values.filter { $0 > 0 }.map { Foundation.log($0) } : values
        guard let center = median(transformed) else { return nil }
        let mad = median(transformed.map { abs($0 - center) }) ?? 0
        return Baseline(
            windowDays: windowDays,
            count: transformed.count,
            median: logScale ? exp(center) : center,
            mad: mad
        )
    }

    static func deviation(of value: Double, from norm: Baseline, logScale: Bool) -> Deviation {
        let difference = value - norm.median
        let distance = logScale && value > 0 ? Foundation.log(value) - Foundation.log(norm.median) : difference
        let spread = madScale * norm.mad

        guard spread > 0 else {
            return Deviation(value: value, difference: difference, z: nil,
                             band: distance == 0 ? .withinNorm : .undetermined)
        }
        let z = distance / spread
        return Deviation(value: value, difference: difference, z: z, band: band(for: z))
    }

    /// The value range that counts as "within norm" (|z| < `notableZ`), in the metric's own unit.
    static func normRange(_ norm: Baseline, logScale: Bool) -> ClosedRange<Double> {
        let spread = notableZ * madScale * norm.mad
        if logScale {
            let center = Foundation.log(norm.median)
            return exp(center - spread)...exp(center + spread)
        }
        return (norm.median - spread)...(norm.median + spread)
    }

    /// |z| < 1: within norm · 1 ≤ |z| < 2: slight · |z| ≥ 2: clear.
    static func band(for z: Double) -> DeviationBand {
        if z <= -strongZ { return .clearlyBelow }
        if z <= -notableZ { return .slightlyBelow }
        if z < notableZ { return .withinNorm }
        if z < strongZ { return .slightlyAbove }
        return .clearlyAbove
    }

    private static func median(_ values: [Double]) -> Double? {
        Statistics.median(values)
    }
}
