import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var userProfile: AppUserProfile?
    @Published private(set) var isAuthenticated = false
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var profileListener: ListenerRegistration?
    private let db = Firestore.firestore()

    init() {
        installAuthStateListener()
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
        profileListener?.remove()
    }

    func register(email: String, password: String, displayName: String) async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Enter a valid email and password."
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let result = try await Auth.auth().createUser(withEmail: cleanEmail, password: password)

            let profile = AppUserProfile(
                type: "user",
                email: cleanEmail,
                displayName: cleanDisplayName.isEmpty ? nil : cleanDisplayName
            )

            do {
                try db.collection("users").document(result.user.uid).setData(from: profile)
            } catch {
                let nsError = error as NSError
                errorMessage = "Account created, but profile setup failed. \(error.localizedDescription)"
                print("Firestore profile creation failed: domain=\(nsError.domain) code=\(nsError.code) info=\(nsError.userInfo)")
            }

            user = result.user
            userProfile = profile
            isAuthenticated = true
            print("Firebase Auth registered user: \(result.user.uid)")
        } catch {
            let nsError = error as NSError
            errorMessage = Self.friendlyMessage(for: error)
            print("Firebase Auth registration failed: domain=\(nsError.domain) code=\(nsError.code) info=\(nsError.userInfo)")
        }
        isLoading = false
    }

    func login(email: String, password: String) async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Enter a valid email and password."
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let result = try await Auth.auth().signIn(withEmail: cleanEmail, password: password)
            user = result.user
            isAuthenticated = true
            installProfileListener(uid: result.user.uid)
            print("Firebase Auth signed in user: \(result.user.uid)")
        } catch {
            let nsError = error as NSError
            errorMessage = Self.friendlyMessage(for: error)
            print("Firebase Auth sign in failed: domain=\(nsError.domain) code=\(nsError.code) info=\(nsError.userInfo)")
        }
        isLoading = false
    }

    func logout() {
        do {
            try Auth.auth().signOut()
            profileListener?.remove()
            profileListener = nil
            user = nil
            userProfile = nil
            isAuthenticated = false
            errorMessage = nil
            print("Firebase Auth signed out.")
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
            print("Firebase Auth sign out failed: \(error.localizedDescription)")
        }
    }

    // Snapshot listener: auto-recovers when connectivity is restored, handles
    // the cold-start token timing window that caused one-shot getDocument() to
    // return "Missing or insufficient permissions".
    private func installProfileListener(uid: String) {
        profileListener?.remove()
        profileListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        print("Failed to fetch user profile: \(error)")
                        if self.userProfile == nil {
                            self.userProfile = AppUserProfile(type: "user", email: self.user?.email, displayName: nil)
                        }
                        return
                    }
                    guard let snapshot else { return }
                    if snapshot.exists {
                        self.userProfile = try? snapshot.data(as: AppUserProfile.self)
                    } else {
                        self.userProfile = AppUserProfile(type: "user", email: self.user?.email, displayName: nil)
                    }
                }
            }
    }

    private func installAuthStateListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.user = user

                if let user {
                    self.installProfileListener(uid: user.uid)
                    self.isAuthenticated = true
                } else {
                    self.profileListener?.remove()
                    self.profileListener = nil
                    self.userProfile = nil
                    self.isAuthenticated = false
                }
                print("Firebase Auth state changed. Authenticated: \(user != nil)")
            }
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return error.localizedDescription
        }

        switch code {
        case .emailAlreadyInUse:
            return "This email is already registered."
        case .invalidEmail:
            return "Enter a valid email address."
        case .weakPassword:
            return "Password is too weak. Use at least 6 characters."
        case .wrongPassword, .userNotFound, .invalidCredential:
            return "Invalid email or password."
        case .networkError:
            return "Network error. Check your connection and try again."
        case .operationNotAllowed:
            return "Email/password sign-in is disabled in Firebase Authentication."
        case .tooManyRequests:
            return "Too many attempts. Try again later."
        default:
            return error.localizedDescription
        }
    }
}
