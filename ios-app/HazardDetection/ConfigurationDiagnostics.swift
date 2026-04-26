import Foundation
import UIKit

/// Diagnostic utility for checking backend service configurations
/// Use this in your SettingsView or during app startup to verify all services are properly configured
struct ConfigurationDiagnostics {
    
    // MARK: - Configuration Status
    
    struct ServiceStatus {
        let name: String
        let isConfigured: Bool
        let details: String
        let emoji: String
        
        var displayText: String {
            "\(emoji) \(name): \(isConfigured ? "✅ Ready" : "❌ Not Configured")"
        }
    }
    
    // MARK: - Check All Services
    
    static func checkAllServices() -> [ServiceStatus] {
        return [
            checkFirebase(),
            checkCloudinary(),
            checkMapbox()
        ]
    }
    
    // MARK: - Individual Service Checks
    
    static func checkFirebase() -> ServiceStatus {
        // Check for GoogleService-Info.plist first
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            return ServiceStatus(
                name: "Firebase",
                isConfigured: true,
                details: "Using GoogleService-Info.plist",
                emoji: "🔥"
            )
        }
        
        // Fall back to checking Info.plist configuration
        let apiKey = Bundle.main.object(forInfoDictionaryKey: "FirebaseAPIKey") as? String
        let isValid = isValidConfigValue(apiKey)
        
        return ServiceStatus(
            name: "Firebase",
            isConfigured: isValid,
            details: isValid ? "Using Info.plist configuration" : "Missing GoogleService-Info.plist or FirebaseAPIKey",
            emoji: "🔥"
        )
    }
    
    static func checkCloudinary() -> ServiceStatus {
        let cloudName = Bundle.main.object(forInfoDictionaryKey: "CloudinaryCloudName") as? String
        let uploadPreset = Bundle.main.object(forInfoDictionaryKey: "CloudinaryUploadPreset") as? String
        
        let cloudNameValid = isValidConfigValue(cloudName)
        let presetValid = isValidConfigValue(uploadPreset)
        let isConfigured = cloudNameValid && presetValid
        
        var details = "Cloud Name: \(cloudNameValid ? "✓" : "✗"), Upload Preset: \(presetValid ? "✓" : "✗")"
        
        return ServiceStatus(
            name: "Cloudinary",
            isConfigured: isConfigured,
            details: details,
            emoji: "☁️"
        )
    }
    
    static func checkMapbox() -> ServiceStatus {
        let token = Bundle.main.object(forInfoDictionaryKey: "MapboxAccessToken") as? String
        let isValid = isValidConfigValue(token)
        
        // Additional validation: Mapbox tokens should start with 'pk.' or 'sk.'
        let hasValidPrefix = token?.hasPrefix("pk.") ?? false || token?.hasPrefix("sk.") ?? false
        let fullyValid = isValid && hasValidPrefix
        
        var details = isValid ? (hasValidPrefix ? "Valid token format" : "Token doesn't start with pk./sk.") : "Token missing or invalid"
        
        return ServiceStatus(
            name: "Mapbox",
            isConfigured: fullyValid,
            details: details,
            emoji: "🗺️"
        )
    }
    
    // MARK: - Helper Methods
    
    /// Checks if a configuration value is valid (not nil, not empty, not a placeholder)
    private static func isValidConfigValue(_ value: String?) -> Bool {
        guard let value = value, !value.isEmpty else {
            return false
        }
        
        // Check for common placeholder patterns
        let placeholders = ["$(", "YOUR_", "REPLACE_", "PLACEHOLDER"]
        for placeholder in placeholders {
            if value.contains(placeholder) {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Detailed Report
    
    static func printDetailedReport() {
        print("\n" + String(repeating: "=", count: 50))
        print("📊 BACKEND CONFIGURATION DIAGNOSTIC REPORT")
        print(String(repeating: "=", count: 50) + "\n")
        
        let services = checkAllServices()
        
        for service in services {
            print(service.displayText)
            print("   Details: \(service.details)")
            print("")
        }
        
        let allConfigured = services.allSatisfy { $0.isConfigured }
        
        print(String(repeating: "-", count: 50))
        if allConfigured {
            print("✅ ALL SERVICES CONFIGURED - App is ready to use!")
        } else {
            print("⚠️  INCOMPLETE CONFIGURATION - Some services need setup")
            print("\nNext Steps:")
            for service in services where !service.isConfigured {
                print("  • Configure \(service.name)")
            }
            print("\nSee CONFIGURATION_DEBUG.md for detailed setup instructions")
        }
        print(String(repeating: "=", count: 50) + "\n")
    }
    
    // MARK: - Quick Status
    
    static var allServicesConfigured: Bool {
        return checkAllServices().allSatisfy { $0.isConfigured }
    }
    
    static var configurationSummary: String {
        let services = checkAllServices()
        let configured = services.filter { $0.isConfigured }.count
        let total = services.count
        return "\(configured)/\(total) services configured"
    }
}

// MARK: - Testing Helper

#if DEBUG
extension ConfigurationDiagnostics {
    /// Call this during app launch in DEBUG builds to see configuration status
    static func debugPrintStatus() {
        printDetailedReport()
    }
}
#endif
