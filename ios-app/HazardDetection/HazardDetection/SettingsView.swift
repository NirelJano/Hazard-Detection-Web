import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppController
    @Query(filter: #Predicate<PendingReport> {
        $0.statusRaw != "committed" && $0.statusRaw != "cancelled"
    })
    private var pendingUploads: [PendingReport]

    var body: some View {
        FormScreen(title: "Settings", subtitle: "Account info and backend configuration.") {

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.appDark400)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.currentUser?.displayName ?? "User")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text(app.currentUser?.email ?? "")
                            .font(.system(size: 14))
                            .foregroundColor(.appDark400)
                    }
                    .padding(.leading, 8)

                    Spacer()

                    Text(app.userProfile?.type.uppercased() ?? "USER")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.appPrimary)
                        .clipShape(Capsule())
                }
                .padding()

                Divider()
                    .background(Color.appDark400.opacity(0.3))

                Button(action: {
                    app.signOut()
                }) {
                    Text("Sign Out")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.appDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .background(Color.appDark900)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 16) {
                Text("Upload Queue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.appDark400)
                    .padding(.top, 8)

                SettingRow(title: "📤 Pending", value: queueSummary)

                if !failedUploads.isEmpty {
                    SettingRow(title: "⚠️ Failed", value: "\(failedUploads.count)")
                    if let lastError = failedUploads.first?.lastError {
                        Text(lastError)
                            .font(.system(size: 12))
                            .foregroundColor(.appDanger)
                            .lineLimit(2)
                    }
                }

                Button("Retry Failed Uploads") {
                    Task { await BackgroundUploadCoordinator.shared.processQueue() }
                }
                .foregroundColor(.appPrimary)
                .disabled(failedUploads.isEmpty)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("System Info")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.appDark400)
                    .padding(.top, 8)

                SettingRow(title: "🔥 Firebase", value: firebaseStatus)
                SettingRow(title: "☁️ Cloudinary", value: cloudinaryStatus)
                SettingRow(title: "🗺️ Mapbox", value: mapboxStatus)
                SettingRow(title: "📍 Location", value: locationText)
                SettingRow(title: "🌐 Network", value: ReachabilityMonitor.shared.isOnline ? "Online" : "Offline")
            }

            Button("Force Refresh Reports") { app.refreshReports() }
                .foregroundColor(.appPrimary)
                .padding(.top, 16)
        }
    }

    private var failedUploads: [PendingReport] {
        pendingUploads.filter { $0.status == .failed }
    }

    private var queueSummary: String {
        let active = pendingUploads.filter { $0.status == .pending || $0.status == .uploading || $0.status == .uploaded }
        if active.isEmpty && failedUploads.isEmpty { return "Empty" }
        var parts: [String] = []
        if !active.isEmpty { parts.append("\(active.count) uploading") }
        if !failedUploads.isEmpty { parts.append("\(failedUploads.count) failed") }
        return parts.joined(separator: ", ")
    }

    private var firebaseStatus: String {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            return "✅ Ready"
        }
        let apiKey = Bundle.main.object(forInfoDictionaryKey: "FirebaseAPIKey") as? String
        return isValidConfig(apiKey) ? "✅ Ready" : "❌ Not Configured"
    }

    private var cloudinaryStatus: String {
        let cloudName = Bundle.main.object(forInfoDictionaryKey: "CloudinaryCloudName") as? String
        let preset = Bundle.main.object(forInfoDictionaryKey: "CloudinaryUploadPreset") as? String
        return (isValidConfig(cloudName) && isValidConfig(preset)) ? "✅ Ready" : "❌ Not Configured"
    }

    private var mapboxStatus: String {
        let token = Bundle.main.object(forInfoDictionaryKey: "MapboxAccessToken") as? String
        let hasValidPrefix = token?.hasPrefix("pk.") ?? false || token?.hasPrefix("sk.") ?? false
        return (isValidConfig(token) && hasValidPrefix) ? "✅ Ready" : "❌ Not Configured"
    }

    private func isValidConfig(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return !value.contains("$(") && !value.contains("YOUR_") && !value.contains("REPLACE_")
    }

    private var locationText: String {
        switch app.locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return "Allowed"
        case .denied, .restricted: return "Denied"
        case .notDetermined: return "Not Requested"
        @unknown default: return "Unknown"
        }
    }
}
