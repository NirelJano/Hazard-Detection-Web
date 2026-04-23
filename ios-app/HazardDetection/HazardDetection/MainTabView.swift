import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var app: AppController
    @StateObject private var cameraManager = CameraManager()

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar.doc.horizontal")
            }

            NavigationStack {
                LiveDetectionTabWrapper(cameraManager: cameraManager)
            }
            .tabItem {
                Label("Live", systemImage: "video.fill")
            }

            NavigationStack {
                UploadReportView()
            }
            .tabItem {
                Label("Upload", systemImage: "square.and.arrow.up")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

// Wrapper to handle starting/stopping the camera when the tab appears/disappears
// Wait, the plan asks for "Explicit Start/Stop controls" on the Live Detection UI.
// So LiveDetectionView will handle its own session state based on buttons.
struct LiveDetectionTabWrapper: View {
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        LiveDetectionView(cameraManager: cameraManager)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppController())
        .preferredColorScheme(.dark)
}
