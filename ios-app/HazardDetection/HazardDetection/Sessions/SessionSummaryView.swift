import SwiftUI

struct SessionSummaryView: View {
    let result: SessionFinalizationResult
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Image(systemName: result.finalReportCount > 0 ? "checkmark.circle.fill" : "magnifyingglass.circle")
                    .font(.system(size: 52))
                    .foregroundColor(result.finalReportCount > 0 ? .appSuccess : .appDark400)
                Text("Session Complete")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Text(durationText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                SummaryStatCell(value: "\(result.rawCandidateCount)", label: "Detections", color: .appPrimary)
                SummaryStatCell(value: "\(result.finalReportCount)", label: "Reports Queued", color: .appSuccess)
                SummaryStatCell(value: "\(result.skippedCandidateCount)", label: "Filtered Out", color: .appWarning)
                SummaryStatCell(
                    value: "\(result.failedCount)",
                    label: "Failed",
                    color: result.failedCount > 0 ? .appDanger : .appDark400
                )
            }
            .padding(.horizontal, 20)

            if result.finalReportCount == 0 && result.rawCandidateCount > 0 {
                Text("No confirmed hazards after post-processing.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            } else if result.rawCandidateCount == 0 {
                Text("No detections recorded in this session.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer()

            Button(action: onDismiss) {
                Text("Done")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.appPrimary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appDark900.ignoresSafeArea())
    }

    private var durationText: String {
        let total = Int(result.sessionDuration)
        let minutes = total / 60
        let seconds = total % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s session" : "\(seconds)s session"
    }
}

private struct SummaryStatCell: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
