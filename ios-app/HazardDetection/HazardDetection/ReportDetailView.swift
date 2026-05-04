import SwiftUI
import MapKit

struct ReportDetailView: View {
    @EnvironmentObject private var app: AppController
    @Environment(\.dismiss) private var dismiss
    let report: HazardReport

    @State private var showDeleteAlert = false
    @State private var showShareSheet  = false

    private var isAdmin: Bool { app.userProfile?.type == "admin" }

    private var reportNumber: String {
        report.numericId.map { "#\($0)" } ?? report.id
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.appDark950.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    imageSection
                    infoCard
                    locationMap
                    if hasDetectionInfo { detectionCard }
                    if isAdmin { adminCard }
                }
                .padding(20)
            }
        }
        .navigationTitle("Report \(reportNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showShareSheet = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .foregroundColor(.appPrimary)
            }
        }
        .alert("Delete Report", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteReport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This report will be permanently deleted and cannot be recovered.")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
    }

    // MARK: - Image

    private var imageSection: some View {
        Group {
            if let urlStr = report.imageUrl, !urlStr.isEmpty, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        imageFallback(icon: "photo.badge.exclamationmark")
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 240)
                            .background(Color.appDark900)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                imageFallback(icon: "photo")
            }
        }
    }

    private func imageFallback(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 40))
            .foregroundColor(.appDark400)
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .background(Color.appDark900)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.hazardType)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text("Report \(reportNumber)")
                        .font(.system(size: 13))
                        .foregroundColor(.appDark400)
                }
                Spacer()
                StatusBadge(status: report.status)
            }

            Divider().background(Color.white.opacity(0.07))

            infoRow(icon: "calendar",          text: report.date)
            infoRow(icon: "person.fill",        text: "Reported by \(report.reportedBy)")

            if let address = report.address, !address.isEmpty {
                infoRow(icon: "mappin.and.ellipse", text: address)
            }

            if let desc = report.description, !desc.isEmpty {
                infoRow(icon: "text.alignleft", text: desc)
            }
        }
        .padding(16)
        .background(Color.appDark900)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.appPrimary)
                .frame(width: 18)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Map

    private var locationMap: some View {
        let coord = CLLocationCoordinate2D(
            latitude:  report.coordinate.latitude,
            longitude: report.coordinate.longitude
        )
        return Map(initialPosition: .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
        ))) {
            Annotation(report.hazardType, coordinate: coord) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color.forStatus(report.status))
                    .padding(8)
                    .background(Color.appDark900)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Detection Card

    private var hasDetectionInfo: Bool {
        report.detectedLabel != nil || report.detectionConfidence != nil || report.detectionSource != nil
    }

    private var detectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Detection Info", systemImage: "eye")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            Divider().background(Color.white.opacity(0.07))

            if let label = report.detectedLabel {
                detectionRow(icon: "tag",          label: "Detected",   value: label)
            }
            if let conf = report.detectionConfidence {
                detectionRow(icon: "gauge.medium",  label: "Confidence", value: "\(Int(conf * 100))%")
            }
            if let src = report.detectionSource {
                detectionRow(
                    icon: src.contains("live") ? "camera.fill" : "photo",
                    label: "Source",
                    value: src.replacingOccurrences(of: "_", with: " ").capitalized
                )
            }
        }
        .padding(16)
        .background(Color.appDark900)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func detectionRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.appPrimary)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.appDark400)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Admin Card

    private var adminCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Admin Controls", systemImage: "shield.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.appWarning)

            // Status buttons — one per status
            HStack(spacing: 8) {
                ForEach(ReportStatus.allCases, id: \.self) { s in
                    let isCurrent = report.status == s.rawValue
                    Button { updateStatus(to: s.rawValue) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: s.icon)
                                .font(.system(size: 14))
                            Text(s.displayName)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(isCurrent ? .white : s.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isCurrent ? s.color : s.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isCurrent ? Color.clear : s.color.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .disabled(isCurrent)
                }
            }

            // Delete
            Button { showDeleteAlert = true } label: {
                Label("Delete Report", systemImage: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appDanger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appDanger.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.appDanger.opacity(0.35), lineWidth: 1)
                    )
            }
        }
        .padding(16)
        .background(Color.appDark900)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func updateStatus(to status: String) {
        guard let docId = report.docId else { return }
        Task {
            do {
                try await app.reportRepository.updateReportStatus(reportId: docId, newStatus: status, isAdmin: isAdmin)
            } catch {
                print("Status update failed: \(error)")
            }
        }
    }

    private func deleteReport() {
        guard let docId = report.docId else { return }
        Task {
            do {
                try await app.reportRepository.deleteReport(reportId: docId, isAdmin: isAdmin)
                dismiss()
            } catch {
                print("Delete failed: \(error)")
            }
        }
    }

    // MARK: - Share

    private var shareText: String {
        var lines = [
            "Hazard Report \(reportNumber)",
            "Type: \(report.hazardType)",
            "Status: \(ReportStatus(rawValue: report.status)?.displayName ?? report.status)",
            "Date: \(report.date)",
            "Reported by: \(report.reportedBy)"
        ]
        if let address = report.address, !address.isEmpty {
            lines.insert("Location: \(address)", at: 3)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
