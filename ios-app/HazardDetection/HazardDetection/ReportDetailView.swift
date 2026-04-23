import SwiftUI
import MapKit

struct ReportDetailView: View {
    @EnvironmentObject private var app: AppController
    @Environment(\.dismiss) private var dismiss
    let report: HazardReport
    
    private var isAdmin: Bool {
        app.userProfile?.type == "admin"
    }

    private var reportTitle: String {
        report.hazardType
    }

    private var reportNumberText: String {
        if let numericId = report.numericId {
            return "#\(numericId)"
        }
        return report.id
    }
    
    var body: some View {
        ZStack {
            Color.appDark950.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let imageUrlStr = report.imageUrl, let url = URL(string: imageUrlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 250)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 250)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            case .failure:
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: 40))
                                    .foregroundColor(.appDark400)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 250)
                                    .background(Color.appDark900)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(.appDark400)
                            .frame(maxWidth: .infinity)
                            .frame(height: 250)
                            .background(Color.appDark900)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(reportTitle)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Text(report.status.uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(report.status == "pending" ? .appWarning : .appSuccess)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(report.status == "pending" ? Color.appWarning.opacity(0.2) : Color.appSuccess.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        
                        Text("Report ID: \(reportNumberText)")
                            .foregroundColor(.appDark400)
                            .font(.system(size: 14))
                        
                        Text(report.date)
                            .foregroundColor(.appDark400)
                            .font(.system(size: 14))
                        
                        if let address = report.address {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(.appPrimary)
                                    .padding(.top, 2)
                                Text(address)
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))
                            }
                            .padding(.top, 8)
                        }
                        
                        Text("Reported by: \(report.reportedBy)")
                            .foregroundColor(.appDark400)
                            .font(.system(size: 14))
                            .padding(.top, 4)
                    }
                    
                    Map(initialPosition: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: report.coordinate.latitude, longitude: report.coordinate.longitude), span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))) {
                        Annotation(reportTitle, coordinate: CLLocationCoordinate2D(latitude: report.coordinate.latitude, longitude: report.coordinate.longitude)) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(report.status == "pending" ? .appWarning : .appSuccess)
                                .padding(8)
                                .background(Color.appDark900)
                                .clipShape(Circle())
                        }
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    if isAdmin {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Admin Controls")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.appWarning)
                                .padding(.top, 16)
                            
                            HStack(spacing: 16) {
                                Button {
                                    updateStatus(to: "resolved")
                                } label: {
                                    Text("Mark Resolved")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.appSuccess)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .disabled(report.status == "resolved")
                                
                                Button {
                                    updateStatus(to: "rejected")
                                } label: {
                                    Text("Reject")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.appDanger)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .disabled(report.status == "rejected")
                            }
                            
                            Button {
                                deleteReport()
                            } label: {
                                Text("Delete Report")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.appDanger.opacity(0.2))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appDanger, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("Report \(reportNumberText)")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func updateStatus(to status: String) {
        guard let docId = report.docId else { return }
        Task {
            do {
                try await app.reportRepository.updateReportStatus(reportId: docId, newStatus: status, isAdmin: isAdmin)
                // app.refreshReports() is triggered via listener or manually if needed
            } catch {
                print("Failed to update status: \(error)")
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
                print("Failed to delete report: \(error)")
            }
        }
    }
}
