import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppController

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
                Text("System Info")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.appDark400)
                    .padding(.top, 8)
                
                SettingRow(title: "Firebase", value: "Configured")
                SettingRow(title: "Cloudinary", value: "Configured")
                SettingRow(title: "Mapbox", value: "Configured")
                SettingRow(title: "Location", value: locationText)
            }
            
            Button("Force Refresh Reports") { app.refreshReports() }
                .foregroundColor(.appPrimary)
                .padding(.top, 16)
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
