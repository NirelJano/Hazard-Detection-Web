import SwiftUI
import MapKit

struct DashboardView: View {
    @EnvironmentObject private var app: AppController
    @State private var searchText   = ""
    @State private var filters      = ReportFilters()
    @State private var sortOption   = ReportSortOption.idDescending
    @State private var showFilters  = false
    @State private var isMapOpen    = false

    // MARK: - Cached derived data
    // Recomputed only when inputs change, never inside body.

    @State private var displayed: [HazardReport] = []
    @State private var stats = ReportStats()
    @State private var uniqueTypes: [String] = ["All"]

    private func recomputeDerived() {
        var result = filters.apply(to: app.reports)
        if !searchText.isEmpty {
            // Build the search key once per report rather than in a computed prop
            result = result.filter { report in
                let key = [
                    report.numericId.map(String.init) ?? report.id,
                    report.hazardType,
                    report.address ?? "",
                    report.reportedBy
                ].joined(separator: " ")
                return key.localizedCaseInsensitiveContains(searchText)
            }
        }
        displayed   = sortOption.apply(to: result)
        stats       = ReportStats(from: app.reports)
        uniqueTypes = ["All"] + Set(app.reports.map(\.hazardType)).sorted()
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.appDark950.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    statsGrid
                    mapSection
                    reportsSection
                }
                .padding(20)
            }
            .refreshable { app.refreshReports() }
            .searchable(text: $searchText, prompt: "Search ID, type, address…")
            .sheet(isPresented: $showFilters) {
                FilterSheetView(filters: $filters, types: uniqueTypes)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { recomputeDerived() }
        .onChange(of: app.reports)  { recomputeDerived() }
        .onChange(of: searchText)   { recomputeDerived() }
        .onChange(of: filters)      { recomputeDerived() }
        .onChange(of: sortOption)   { recomputeDerived() }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderBadge()
            Text("Dashboard")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
            Text("Signed in as \(app.currentUser?.displayName ?? "User").")
                .foregroundColor(.appDark400)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(value: "\(stats.total)",           label: "Total")
            StatTile(value: "\(stats.newCount)",        label: "New",         accent: .appPrimary)
            StatTile(value: "\(stats.inProgressCount)", label: "In Progress", accent: .appWarning)
            StatTile(value: "\(stats.fixedCount)",      label: "Fixed",       accent: .appSuccess)
        }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3)) { isMapOpen.toggle() }
            } label: {
                HStack {
                    Label("Map View", systemImage: "map")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: isMapOpen ? "chevron.up" : "chevron.down")
                        .foregroundColor(.appDark400)
                        .font(.system(size: 13))
                }
                .padding(14)
                .background(Color.appDark900)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if isMapOpen {
                Map {
                    ForEach(displayed, id: \.id) { report in
                        Annotation(
                            report.hazardType,
                            coordinate: CLLocationCoordinate2D(
                                latitude:  report.coordinate.latitude,
                                longitude: report.coordinate.longitude
                            )
                        ) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Color.forStatus(report.status))
                                .padding(6)
                                .background(Color.appDark900)
                                .clipShape(Circle())
                        }
                    }
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
    }

    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            reportsHeader

            if app.isLoadingReports {
                StatusText(message: "Loading reports…", color: .appDark400)
            } else if let msg = app.dashboardMessage {
                StatusText(message: msg, color: .appWarning)
            }

            if displayed.isEmpty {
                StatusText(
                    message: (filters.activeCount > 0 || !searchText.isEmpty)
                        ? "No reports match the current filters."
                        : "No reports yet.",
                    color: .appDark400
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(displayed) { report in
                        NavigationLink(destination: ReportDetailView(report: report)) {
                            ReportRow(report: report)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if app.isAdmin, let docId = report.docId {
                                Button(role: .destructive) {
                                    Task { try? await app.reportRepository.deleteReport(reportId: docId, isAdmin: true) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Text("\(displayed.count) report\(displayed.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundColor(.appDark400)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
    }

    private var reportsHeader: some View {
        HStack(spacing: 10) {
            Text("Reports")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Spacer()

            // Sort menu
            Menu {
                ForEach(ReportSortOption.allCases) { option in
                    Button {
                        sortOption = option
                    } label: {
                        sortOption == option
                            ? Label(option.rawValue, systemImage: "checkmark")
                            : Label(option.rawValue, systemImage: "")
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundColor(.appDark400)
                    .frame(width: 36, height: 36)
                    .background(Color.appDark900)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Filter button with badge
            Button { showFilters = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(filters.activeCount > 0 ? .appPrimary : .appDark400)
                        .frame(width: 36, height: 36)
                        .background(Color.appDark900)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if filters.activeCount > 0 {
                        Text("\(filters.activeCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(Color.appPrimary)
                            .clipShape(Circle())
                            .offset(x: 6, y: -6)
                    }
                }
            }
        }
    }
}

// MARK: - Report Row

struct ReportRow: View {
    let report: HazardReport

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("#\(report.numericId.map(String.init) ?? "–")")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.appPrimary)
                    Text(report.hazardType)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(report.address ?? "Unknown location")
                    .font(.system(size: 13))
                    .foregroundColor(.appDark400)
                    .lineLimit(1)
                Text(report.date)
                    .font(.system(size: 11))
                    .foregroundColor(.appDark400)
            }

            Spacer(minLength: 0)
            StatusBadge(status: report.status)
        }
        .padding(12)
        .background(Color.appDark900)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var thumbnail: some View {
        Group {
            if let urlStr = report.imageUrl, !urlStr.isEmpty, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        thumbPlaceholder
                    }
                }
            } else {
                thumbPlaceholder
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var thumbPlaceholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 18))
            .foregroundColor(.appDark400)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appDark800)
    }
}

// MARK: - Filter Sheet

struct FilterSheetView: View {
    @Binding var filters: ReportFilters
    let types: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appDark950.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        filterBlock(title: "Status") {
                            ChipRow(
                                options: ["All"] + ReportStatus.allCases.map(\.rawValue),
                                label: { opt in
                                    opt == "All" ? "All" : (ReportStatus(rawValue: opt)?.displayName ?? opt)
                                },
                                selected: $filters.status
                            )
                        }

                        filterBlock(title: "Hazard Type") {
                            ChipRow(options: types, label: { $0 }, selected: $filters.type)
                        }

                        filterBlock(title: "Reporter") {
                            AppTextField(title: "Filter by reporter name…", text: $filters.reporter)
                        }

                        filterBlock(title: "Date Range") {
                            VStack(spacing: 10) {
                                DateFilterRow(label: "From", date: $filters.dateFrom)
                                DateFilterRow(label: "To",   date: $filters.dateTo)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear All") { filters.reset() }
                        .foregroundColor(filters.activeCount > 0 ? .appDanger : .appDark400)
                        .disabled(filters.activeCount == 0)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(.appPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func filterBlock<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.appDark400)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
    }
}

struct ChipRow: View {
    let options: [String]
    let label: (String) -> String
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { opt in
                    Button { selected = opt } label: {
                        Text(label(opt))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selected == opt ? .white : .appDark400)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selected == opt ? Color.appPrimary : Color.appDark900)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(
                                    selected == opt ? Color.clear : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                            )
                    }
                }
            }
        }
    }
}

struct DateFilterRow: View {
    let label: String
    @Binding var date: Date?

    @State private var isOpen   = false
    @State private var tempDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label)
                    .foregroundColor(.white)
                    .font(.system(size: 14))
                Spacer()
                if let d = date {
                    Text(d.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appPrimary)
                    Button {
                        date   = nil
                        isOpen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.appDark400)
                    }
                    .padding(.leading, 8)
                } else {
                    Button {
                        withAnimation { isOpen.toggle() }
                        if isOpen { date = tempDate }
                    } label: {
                        Text("Set date")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.appPrimary)
                    }
                }
            }
            .padding(12)
            .background(Color.appDark900)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if isOpen {
                DatePicker(
                    "",
                    selection: Binding(get: { date ?? tempDate }, set: { date = $0; tempDate = $0 }),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(.appPrimary)
                .colorScheme(.dark)
                .background(Color.appDark900)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
    }
}
