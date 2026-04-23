import SwiftUI

struct AppTextField: View {
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

struct AppTextFieldStyle: TextFieldStyle {
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

struct StatusText: View {
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

struct HeaderBadge: View {
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

struct StatTile: View {
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

struct ActionRow: View {
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

struct FormScreen<Content: View>: View {
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

struct SettingRow: View {
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

extension Text {
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
