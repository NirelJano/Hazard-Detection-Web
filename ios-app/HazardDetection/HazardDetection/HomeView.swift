import PhotosUI
import SwiftUI

private enum AppRoute: Hashable {
    case upload
    case settings
}

private enum AuthMode {
    case login
    case register
}

struct HomeView: View {
    @StateObject private var app = AppController()
    @StateObject private var cameraManager = CameraManager()
    @State private var showingLiveDetection = false

    var body: some View {
        NavigationStack {
            Group {
                if app.currentUser == nil {
                    AuthenticationView()
                } else {
                    DashboardView(showingLiveDetection: $showingLiveDetection)
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .upload:
                    UploadReportView()
                case .settings:
                    SettingsView()
                }
            }
        }
        .environmentObject(app)
        .fullScreenCover(isPresented: $showingLiveDetection) {
            LiveDetectionView(cameraManager: cameraManager)
                .environmentObject(app)
        }
    }
}

private struct AuthenticationView: View {
    @EnvironmentObject private var app: AppController
    @State private var mode: AuthMode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    private var isAuthInputValid: Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .login {
            return !cleanEmail.isEmpty && !cleanPassword.isEmpty
        } else {
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !cleanName.isEmpty && !cleanEmail.isEmpty && !cleanPassword.isEmpty
        }
    }

    var body: some View {
        ZStack {
            Color.appDark950.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                HeaderBadge()

                VStack(alignment: .leading, spacing: 10) {
                    Text(mode == .login ? "Welcome back" : "Create account")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                    Text("Sign in to manage live road hazard reports.")
                        .font(.system(size: 16))
                        .foregroundColor(.appDark400)
                }

                VStack(spacing: 14) {
                    if mode == .register {
                        AppTextField(title: "Full name", text: $name)
                    }
                    AppTextField(title: "Email", text: $email, keyboardType: .emailAddress)
                    SecureField("Password", text: $password)
                        .textContentType(mode == .login ? .password : .newPassword)
                        .textFieldStyle(AppTextFieldStyle())

                    if mode == .register {
                        Text("Password must be at least 8 characters with upper and lower case.")
                            .font(.system(size: 12))
                            .foregroundColor(.appDark400)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        if mode == .login {
                            app.signIn(email: email, password: password)
                        } else {
                            app.register(
                                username: name,
                                email: email,
                                password: password
                            )
                        }
                    } label: {
                        Text(app.isAuthenticating ? "Please wait..." : mode == .login ? "Sign In" : "Register")
                            .primaryButtonStyle()
                    }
                    .disabled(app.isAuthenticating || !isAuthInputValid)

                    Button {
                        app.authMessage = nil
                        mode = mode == .login ? .register : .login
                    } label: {
                        Text(mode == .login ? "Need an account? Register" : "Already registered? Sign in")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.appPrimary)
                    }

                    if let message = app.authMessage {
                        StatusText(message: message, color: .appWarning)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var app: AppController
    @Binding var showingLiveDetection: Bool

    private var openReports: Int {
        app.reports.filter { $0.status == "new" }.count
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
                        Button("Sign Out") { app.signOut() }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.appPrimary)
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

                    VStack(spacing: 14) {
                        NavigationLink(value: AppRoute.upload) {
                            ActionRow(icon: "square.and.arrow.up", title: "Manual Report", subtitle: "Upload a hazard with GPS and image storage.")
                        }

                        Button {
                            app.locationService.requestPermission()
                            showingLiveDetection = true
                        } label: {
                            ActionRow(icon: "video.fill", title: "Live Detection", subtitle: "Open dashcam-style auto reporting.")
                        }

                        NavigationLink(value: AppRoute.settings) {
                            ActionRow(icon: "gearshape.fill", title: "Settings", subtitle: "Review account and backend configuration.")
                        }
                    }

                    if app.isLoadingReports {
                        StatusText(message: "Loading reports...", color: .appDark400)
                    } else if let message = app.dashboardMessage {
                        StatusText(message: message, color: .appWarning)
                    }

                    RecentReportsSection(reports: Array(app.reports.prefix(8)))
                }
                .padding(24)
            }
            .refreshable {
                app.refreshReports()
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

private struct UploadReportView: View {
    @EnvironmentObject private var app: AppController
    @State private var hazardType = "Pothole"
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    private let hazardTypes = ["Pothole", "Crack"]

    var body: some View {
        FormScreen(title: "Manual Report", subtitle: "Create a real Firestore report with Cloudinary image storage.") {
            Picker("Hazard Type", selection: $hazardType) {
                ForEach(hazardTypes, id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)

            PhotosPicker(selection: $selectedItem, matching: .images) {
                HStack {
                    Image(systemName: "photo")
                    Text(selectedImage == nil ? "Choose Image" : "Change Image")
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(14)
                .background(Color.appDark900)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .onChange(of: selectedItem) { _, item in
                Task { await loadImage(from: item) }
            }

            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            LocationStatus()

            Button {
                app.locationService.requestPermission()
                app.createManualReport(image: selectedImage, hazardType: hazardType)
            } label: {
                Text(app.isUploadingReport ? "Saving..." : "Submit Report")
                    .primaryButtonStyle()
            }
            .disabled(app.isUploadingReport)

            if let message = app.uploadMessage {
                StatusText(message: message, color: message == "Report saved." ? .appSuccess : .appWarning)
            }
        }
        .onAppear { app.locationService.requestPermission() }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        await MainActor.run { selectedImage = UIImage(data: data) }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var app: AppController

    var body: some View {
        FormScreen(title: "Settings", subtitle: "Backend and permission status.") {
            SettingRow(title: "Firebase", value: AppConfig.current.isBackendConfigured ? "Configured" : "Missing")
            SettingRow(title: "Cloudinary", value: AppConfig.current.isMediaConfigured ? "Configured" : "Missing")
            SettingRow(title: "Mapbox", value: AppConfig.current.mapboxAccessToken.isEmpty ? "Missing" : "Configured")
            SettingRow(title: "Location", value: locationText)
            Button("Refresh Reports") { app.refreshReports() }
                .foregroundColor(.appPrimary)
        }
    }

    private var locationText: String {
        switch app.locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Allowed"
        case .denied, .restricted:
            return "Denied"
        case .notDetermined:
            return "Not Requested"
        @unknown default:
            return "Unknown"
        }
    }
}

private struct FormScreen<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.appDark950.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                        Text(subtitle)
                            .foregroundColor(.appDark400)
                    }

                    VStack(spacing: 16) {
                        content
                    }
                    .tint(.appPrimary)
                    .padding(18)
                    .background(Color.appDark900.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(24)
            }
        }
    }
}

private struct RecentReportsSection: View {
    let reports: [HazardReport]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Reports")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            if reports.isEmpty {
                StatusText(message: "No reports yet.", color: .appDark400)
            } else {
                ForEach(reports) { report in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("#\(report.numericID) \(report.hazardType)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            Text(report.address.isEmpty ? report.date : report.address)
                                .font(.system(size: 13))
                                .foregroundColor(.appDark400)
                                .lineLimit(2)
                        }

                        Spacer()

                        Text(report.status.uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(report.status == "new" ? .appWarning : .appSuccess)
                    }
                    .padding(16)
                    .background(Color.appDark900)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct LocationStatus: View {
    @EnvironmentObject private var app: AppController

    var body: some View {
        let coordinate = app.locationService.currentCoordinate
        let text = coordinate.map { String(format: "GPS %.5f, %.5f", $0.latitude, $0.longitude) } ?? "Waiting for GPS location"
        StatusText(message: text, color: coordinate == nil ? .appWarning : .appSuccess)
    }
}

private struct SettingRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(value == "Configured" || value == "Allowed" ? .appSuccess : .appWarning)
        }
        .padding(14)
        .background(Color.appDark900)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusText: View {
    let message: String
    let color: Color

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.appDark900)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct HeaderBadge: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(Color.appPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Hazard Detection")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Text("Road safety operations")
                    .font(.system(size: 13))
                    .foregroundColor(.appDark400)
            }
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.appDark400)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.appDark900)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ActionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.appPrimary)
                .frame(width: 42, height: 42)
                .background(Color.appPrimary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.appDark400)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.appDark400)
        }
        .padding(16)
        .background(Color.appDark900)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AppTextField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(AppTextFieldStyle())
    }
}

private struct AppTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundColor(.white)
            .padding(14)
            .background(Color.appDark900)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private extension Text {
    func primaryButtonStyle() -> some View {
        self
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.appPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
