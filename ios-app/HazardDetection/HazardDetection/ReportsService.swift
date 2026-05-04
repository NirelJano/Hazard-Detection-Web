import Foundation
import SwiftUI

// MARK: - Status (matches web app & Firestore)
enum ReportStatus: String, CaseIterable {
    case new = "new"
    case inProgress = "in-progress"
    case fixed = "fixed"

    var displayName: String {
        switch self {
        case .new:        return "New"
        case .inProgress: return "In Progress"
        case .fixed:      return "Fixed"
        }
    }

    var color: Color {
        switch self {
        case .new:        return .appPrimary
        case .inProgress: return .appWarning
        case .fixed:      return .appSuccess
        }
    }

    var icon: String {
        switch self {
        case .new:        return "circle.fill"
        case .inProgress: return "clock.fill"
        case .fixed:      return "checkmark.circle.fill"
        }
    }
}

extension Color {
    static func forStatus(_ status: String) -> Color {
        ReportStatus(rawValue: status.lowercased())?.color ?? .appDark400
    }
}

// MARK: - Sort
enum ReportSortOption: String, CaseIterable, Identifiable {
    case idDescending  = "ID (Newest)"
    case idAscending   = "ID (Oldest)"
    case dateNewest    = "Date (Newest)"
    case dateOldest    = "Date (Oldest)"

    var id: String { rawValue }

    func apply(to reports: [HazardReport]) -> [HazardReport] {
        switch self {
        case .idDescending:  return reports.sorted { ($0.numericId ?? 0) > ($1.numericId ?? 0) }
        case .idAscending:   return reports.sorted { ($0.numericId ?? 0) < ($1.numericId ?? 0) }
        case .dateNewest:    return reports.sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
        case .dateOldest:    return reports.sorted { ($0.createdAt ?? 0) < ($1.createdAt ?? 0) }
        }
    }
}

// MARK: - Filters
struct ReportFilters: Equatable {
    var status: String   = "All"
    var type: String     = "All"
    var dateFrom: Date?  = nil
    var dateTo: Date?    = nil
    var reporter: String = ""

    var activeCount: Int {
        [status != "All", type != "All", dateFrom != nil, dateTo != nil, !reporter.isEmpty]
            .filter { $0 }.count
    }

    mutating func reset() {
        status   = "All"
        type     = "All"
        dateFrom = nil
        dateTo   = nil
        reporter = ""
    }

    func apply(to reports: [HazardReport]) -> [HazardReport] {
        reports.filter { report in
            if status != "All", report.status.lowercased() != status.lowercased() { return false }
            if type   != "All", report.hazardType.lowercased() != type.lowercased() { return false }
            if !reporter.isEmpty,
               !report.reportedBy.localizedCaseInsensitiveContains(reporter) { return false }
            if let from = dateFrom {
                guard let ts = report.createdAt,
                      Date(timeIntervalSince1970: TimeInterval(ts) / 1000) >= from else { return false }
            }
            if let to = dateTo {
                let end = Calendar.current.date(byAdding: .day, value: 1, to: to) ?? to
                guard let ts = report.createdAt,
                      Date(timeIntervalSince1970: TimeInterval(ts) / 1000) < end else { return false }
            }
            return true
        }
    }
}

// MARK: - Stats
struct ReportStats {
    let total: Int
    let newCount: Int
    let inProgressCount: Int
    let fixedCount: Int

    init() { total = 0; newCount = 0; inProgressCount = 0; fixedCount = 0 }

    init(from reports: [HazardReport]) {
        total            = reports.count
        newCount         = reports.filter { $0.status == ReportStatus.new.rawValue }.count
        inProgressCount  = reports.filter { $0.status == ReportStatus.inProgress.rawValue }.count
        fixedCount       = reports.filter { $0.status == ReportStatus.fixed.rawValue }.count
    }
}
