import Foundation
import CryptoKit

struct Profile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var icon = "person.crop.circle"
    static let defaultID = UUID(uuidString: "8E7C21A0-3B2E-4C9D-9F10-000000000001")!
    /// Development data roots never resolve to production WebKit stores.
    static func storeID(_ id: UUID, namespace: String?) -> UUID {
        guard let namespace else { return id }
        let bytes = Array(SHA256.hash(data: Data((namespace + id.uuidString).utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
