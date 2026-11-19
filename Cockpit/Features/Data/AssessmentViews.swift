import SwiftUI

/// Full transparency for one metric: windows, counts, median, MAD, z and short-term trend.
struct AssessmentDetailSection: View {
    let assessment: MetricAssessment

    var body: some View {
        Section {
            LabeledContent("Wert", value: MetricsFormat.value(assessment.value, for: assessment.metric))
            if let norm = assessment.norm {
                LabeledContent("Norm (Median, \(norm.windowDays) Tage davor)", value: MetricsFormat.value(norm.median, for: assessment.metric))
                LabeledContent("Werte in der Norm", value: "\(norm.count) von \(norm.windowDays)")
            } else if case .insufficientData(let count, let required) = assessment.status {
                LabeledContent("Norm", value: "ab \(required) Werten (bisher \(count))")
            }
            switch assessment.status {
            case .available(let deviation):
                LabeledContent("Abweichung", value: MetricsFormat.difference(deviation.difference, for: assessment.metric))
                LabeledContent("Robuster z-Wert", value: MetricsFormat.z(deviation.z))
                LabeledContent("Einordnung", value: deviation.band.title)
            case .missingValue:
                LabeledContent("Abweichung", value: "kein Wert an diesem Tag")
            case .insufficientData:
                EmptyView()
            }
            if let shortTerm = assessment.shortTerm {
                LabeledContent("Letzte \(shortTerm.windowDays) Tage (Median)", value: MetricsFormat.value(shortTerm.median, for: assessment.metric))
                if let trend = assessment.shortTermDeviation {
                    LabeledContent("Trend zur Norm", value: "\(MetricsFormat.difference(trend.difference, for: assessment.metric)) · \(trend.band.title)")
                }
            }
        } header: {
            Text(assessment.metric.title)
        }
    }
}

/// Explains how norms and bands are computed (spec: thresholds must be transparent).
struct BaselineMethodFooter: View {
    var body: some View {
        Text("""
        Norm = Median der \(BaselineCalculator.normWindowDays) Tage vor dem Tag, ab \(BaselineCalculator.minimumNormValues) Werten. \
        Abweichung als robuster z-Wert: (Wert − Median) / (1,4826 × MAD), HRV logarithmiert. \
        |z| < 1 im Normbereich, 1–2 leicht, ab 2 deutlich. Fehlende Tage werden nicht aufgefüllt. Keine medizinische Bewertung.
        """)
    }
}
