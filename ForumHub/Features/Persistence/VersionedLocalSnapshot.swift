import Foundation

struct VersionedLocalSnapshot<Value: Codable>: Codable {
    let version: Int
    let payload: Value
}

enum LocalSnapshotDecodeResult<Value> {
    case missing
    case current(Value)
    case legacy(Value)
    case unavailable
}

enum VersionedLocalSnapshotCodec {
    static func decode<Value: Codable>(
        _ type: Value.Type,
        data: Data?,
        currentVersion: Int
    ) -> LocalSnapshotDecodeResult<Value> {
        guard let data else { return .missing }

        let decoder = JSONDecoder()
        if let snapshot = try? decoder.decode(VersionedLocalSnapshot<Value>.self, from: data) {
            guard snapshot.version == currentVersion else { return .unavailable }
            return .current(snapshot.payload)
        }
        if let legacy = try? decoder.decode(Value.self, from: data) {
            return .legacy(legacy)
        }
        return .unavailable
    }

    static func encode<Value: Codable>(_ value: Value, version: Int) -> Data? {
        try? JSONEncoder().encode(VersionedLocalSnapshot(version: version, payload: value))
    }
}
