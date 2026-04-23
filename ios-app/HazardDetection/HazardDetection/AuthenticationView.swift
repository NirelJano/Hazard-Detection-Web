import SwiftUI

enum AuthMode {
    case login
    case register
}

struct AuthenticationView: View {
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


