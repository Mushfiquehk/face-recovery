import CryptoKit
import Foundation
import Security

/// The optional 4-digit app lock. Only a salted hash of the PIN is stored, in the Keychain,
/// never the digits. A PIN this short is a privacy screen for someone borrowing an unlocked
/// phone, not protection against an attacker with the device.
enum PinStore {
    static let length = 4

    /// Whether the lock is on. Views observe this with `@AppStorage` so they react to Settings
    /// changes. It is also what lets `reconcile()` spot a PIN left over from an earlier install:
    /// Keychain items outlive an uninstall, but UserDefaults does not.
    static let enabledKey = "appLockEnabled"

    private static let service = "com.mushfique.facerecovery"
    private static let account = "app-lock-pin"

    /// Call once at launch. Makes the flag and the Keychain agree, so a reinstall never locks
    /// the user out of an empty app with a PIN they cannot remember setting.
    static func reconcile() {
        let flagged = UserDefaults.standard.bool(forKey: enabledKey)
        let stored = loadRecord() != nil
        if flagged && !stored {
            UserDefaults.standard.set(false, forKey: enabledKey)
        } else if !flagged && stored {
            SecItemDelete(baseQuery() as CFDictionary)
        }
    }

    static func set(_ pin: String) {
        guard isValid(pin) else { return }
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let record = salt + hash(pin, salt: salt)

        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: record,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { current, _ in current } as CFDictionary, nil)
        }
        UserDefaults.standard.set(true, forKey: enabledKey)
    }

    static func verify(_ pin: String) -> Bool {
        guard isValid(pin), let record = loadRecord() else { return false }
        return hash(pin, salt: record.prefix(16)) == record.dropFirst(16)
    }

    static func remove() {
        SecItemDelete(baseQuery() as CFDictionary)
        UserDefaults.standard.set(false, forKey: enabledKey)
    }

    private static func isValid(_ pin: String) -> Bool {
        pin.count == length && pin.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func hash(_ pin: String, salt: some DataProtocol) -> Data {
        Data(SHA256.hash(data: Data(salt) + Data(pin.utf8)))
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func loadRecord() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, data.count == 16 + 32
        else { return nil }
        return data
    }
}
