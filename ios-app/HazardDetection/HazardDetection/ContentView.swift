import SwiftUI

struct ContentView: View {
    @StateObject private var app = AppController()
    
    var body: some View {
        Group {
            if app.currentUser == nil {
                AuthenticationView()
            } else {
                MainTabView()
            }
        }
        .environmentObject(app)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
