import Foundation
import Security

/// Anonymous sessions, so onboarding can run real AI before the user has an account.
///
/// The first screen of onboarding asks for a recipe, not an email. But every AI call goes
/// through the metered proxy, and the proxy has no notion of an anonymous caller — it reads
/// the user id off the token and refuses without one. A guest account is what closes that
/// gap: a real (machine-generated) account the server opens for this device, used for the
/// length of onboarding and retired once the user creates a real one.
///
/// The device id lives in the **Keychain**, not UserDefaults, for one specific reason: the
/// Keychain survives deleting the app. If it didn't, reinstalling would hand out a fresh
/// guest with a fresh free quota every time.
enum GuestSession {

    private static let endpoint = URL(string: "https://j7pth4qn.function2.insforge.app/guest")!
    private static let keychainAccount = "gs_guest_device_id"

    enum GuestError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .failed(let m): return m
            }
        }
    }

    /// Opens (or reopens) this device's guest session.
    static func start() async throws -> SocialAPI.Session {
        let device = deviceID()
        let json = try await call(["action": "start", "device_id": device], token: nil)
        guard let token = json["accessToken"] as? String,
              let user = json["user"] as? [String: Any],
              let id = user["id"] as? String else {
            throw GuestError.failed(json["error"] as? String ?? "Couldn't start a guest session")
        }
        return SocialAPI.Session(
            accessToken: token,
            refreshToken: json["refreshToken"] as? String,
            userID: id,
            displayName: (user["name"] as? String) ?? "Guest"
        )
    }

    /// Deletes the guest account once a real one has taken over. Best-effort: a failure here
    /// leaves a stray row, which is untidy but harmless, and must never surface to the user
    /// in the middle of a successful sign-up.
    static func retire(session: SocialAPI.Session) async {
        _ = try? await call(["action": "retire"], token: session.accessToken)
    }

    private static func call(_ body: [String: String], token: String?) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token ?? SocialAPI.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 300 else {
            throw GuestError.failed(json["error"] as? String ?? "Guest session failed")
        }
        return json
    }

    // MARK: - Device id (Keychain)

    /// This device's stable id, minted once and kept in the Keychain thereafter.
    static func deviceID() -> String {
        if let existing = readKeychain() { return existing }
        let fresh = UUID().uuidString.lowercased()
        writeKeychain(fresh)
        return fresh
    }

    private static func query(_ extra: [String: Any] = [:]) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.goodies.goodiesSnap",
            kSecAttrAccount as String: keychainAccount,
        ]
        for (k, v) in extra { q[k] = v }
        return q
    }

    private static func readKeychain() -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            query([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) as CFDictionary,
            &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ value: String) {
        let data = Data(value.utf8)
        SecItemDelete(query() as CFDictionary)
        // ThisDeviceOnly: the id identifies a handset, so it must not ride an iCloud Keychain
        // restore onto a second device and make two phones share one guest quota.
        SecItemAdd(query([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) as CFDictionary, nil)
    }
}
