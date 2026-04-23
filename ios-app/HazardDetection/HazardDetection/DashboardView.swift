import SwiftUI
import MapKit

struct DashboardView: View {
    @EnvironmentObject private var app: AppController
    @State private var searchText = ""
    @State private var selectedStatusFilter = "All"
    @State private var selectedTypeFilter = "All"
    
    private let statusFilters = ["All", "pending", "resolved", "rejected"]
    private let typeFilters = ["All", "Pothole", "Crack"]
    
    private var filteredReports: [HazardReport] {
        var reports = app.reports
        
        if selectedStatusFilter != "All" {
            reports = reports.filter { $0.status.lowercased() == selectedStatusFilter.lowercased() }
        }
        
        if selectedTypeFilter != "All" {
            reports = reports.filter { $0.hazardType.lowercased() == selectedTypeFilter.lowercased() }
        }
        
        if !searchText.isEmpty {
            reports = reports.filter { report in
                let searchString = "\(report.numericId.map(String.init) ?? report.id) \(report.hazardType) \(report.address ?? "") \(report.reportedBy)"
                return searchString.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return reports
    }

    private var openReports: Int {
        app.reports.filter { $0.status == "pending" }.count
    }

    private var cracks: Int {
        app.reports.filter { $0.hazardType.localizedCaseInsensitiveContains("crack") }.count
    }

    private var potholes: Int {
        app.reports.filter { $0.hazardType.localizedCaseInsensitiveContains("pothole") }.count
    }

    var body: some View {
        ZStack {
            Color.appDark950.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        HeaderBadge()
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dashboard")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                        Text("Signed in as \(app.currentUser?.displayName ?? "User").")
                            .foregroundColor(.appDark400)
                    }

                    HStack(spacing: 14) {
                        StatTile(value: "\(openReports)", label: "Open")
                        StatTile(value: "\(potholes)", label: "Potholes")
                        StatTile(value: "\(cracks)", label: "Cracks")
                    }
                    
                    // Map View
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Map View")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        Map {
                            ForEach(filteredReports, id: \.id) { report in
                                Annotation(report.hazardType, coordinate: CLLocationCoordinate2D(latitude: report.coordinate.latitude, longitude: report.coordinate.longitude)) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(report.status == "pending" ? .appWarning : .appSuccess)
                                        .padding(6)
                                        .background(Color.appDark900)
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Filters
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Filters")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        HStack {
                            Picker("Status", selection: $selectedStatusFilter) {
                                ForEach(statusFilters, id: \.self) { Text($0.capitalized) }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.appDark900)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            Picker("Type", selection: $selectedTypeFilter) {
                                ForEach(typeFilters, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.appDark900)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    if app.isLoadingReports {
                        StatusText(message: "Loading reports...", color: .appDark400)
                    } else if let message = app.dashboardMessage {
                        StatusText(message: message, color: .appWarning)
                    }

                    // Report List
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reports")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        if filteredReports.isEmpty {
                            StatusText(message: "No reports found.", color: .appDark400)
                        } else {
                            ForEach(filteredReports) { report in
                                NavigationLink(destination: ReportDetailView(report: report)) {
                                    ReportRow(report: report)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .refreshable {
                app.refreshReports()
            }
            .searchable(text: $searchText, prompt: "Search ID, type, address...")
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ReportRow: View {
    let report: HazardReport
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(report.numericId.map(String.init) ?? report.id)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.appPrimary)
                    Text(report.hazardType)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(report.address ?? "Unknown address")
                    .font(.system(size: 13))
                    .foregroundColor(.appDark400)
                    .lineLimit(1)
                
                Text(report.date)
                    .font(.system(size: 12))
                    .foregroundColor(.appDark400)
            }

            Spacer()

            Text(report.status.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(report.status == "pending" ? .appWarning : .appSuccess)
        }
        .padding(16)
        .background(Color.appDark900)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
