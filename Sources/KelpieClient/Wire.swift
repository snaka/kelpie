import Foundation
import KelpieCore

public struct EmptyParams: Encodable, Sendable {
    public init() {}
}

public struct AgentTargetParams: Encodable, Sendable {
    /// herdr accepts a pane id such as `w0:p1` or a live agent name.
    public let target: String
    public init(target: String) { self.target = target }
}

public struct SubscriptionType: Encodable, Sendable {
    public let type: String
    /// Present only for the per-pane kinds; `nil` omits the key entirely,
    /// which is what herdr requires for the global kinds.
    public let paneID: String?

    enum CodingKeys: String, CodingKey {
        case type
        case paneID = "pane_id"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(paneID, forKey: .paneID)
    }
}

public struct SubscribeParams: Encodable, Sendable {
    public let subscriptions: [SubscriptionType]

    public init(types: [String]) {
        self.subscriptions = types.map { SubscriptionType(type: $0, paneID: nil) }
    }

    public init(requests: [KelpieCore.SubscriptionRequest]) {
        self.subscriptions = requests.map { SubscriptionType(type: $0.type, paneID: $0.paneID) }
    }
}

public struct PongPayload: Decodable, Sendable {
    public let version: String
    public let protocolVersion: Int

    enum CodingKeys: String, CodingKey {
        case version
        case protocolVersion = "protocol"
    }
}

/// One line read from the socket, classified.
public enum WireMessage: Equatable, Sendable {
    case result(id: String, payload: Data)
    case failure(id: String, code: String, message: String)
    case event(kind: String, line: Data)
}

public enum WireError: Error, Equatable {
    case unrecognisedLine
}

public enum Wire {
    private struct RequestEnvelope<P: Encodable>: Encodable {
        let id: String
        let method: String
        let params: P
    }

    private struct ResponseEnvelope: Decodable {
        struct Failure: Decodable {
            let code: String
            let message: String
        }
        let id: String?
        let event: String?
        let error: Failure?
        let result: JSONPassthrough?
        /// `decodeIfPresent` cannot tell `"result": null` from a missing
        /// `result`, and the two mean different things here: the first is an
        /// answer, the second is a line Kelpie does not recognise.
        let hasResult: Bool

        enum CodingKeys: String, CodingKey {
            case id, event, error, result
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            event = try container.decodeIfPresent(String.self, forKey: .event)
            error = try container.decodeIfPresent(Failure.self, forKey: .error)
            result = try container.decodeIfPresent(JSONPassthrough.self, forKey: .result)
            hasResult = container.contains(.result)
        }
    }

    /// Captures `result` without knowing its shape, so each caller decodes
    /// only the payload it understands.
    private struct JSONPassthrough: Decodable {
        let data: Data
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(AnyCodableValue.self)
            // `.fragmentsAllowed` because a `result` need not be an object:
            // `JSONSerialization` rejects a scalar top level outright, and
            // without this a perfectly valid `"result": true` would throw here,
            // be dropped as an unreadable line, and leave the request to fail
            // only when the socket eventually closes.
            self.data = try JSONSerialization.data(
                withJSONObject: value.object, options: [.fragmentsAllowed]
            )
        }
    }

    private struct AnyCodableValue: Decodable {
        let object: Any
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let dictionary = try? container.decode([String: AnyCodableValue].self) {
                self.object = dictionary.mapValues(\.object)
            } else if let array = try? container.decode([AnyCodableValue].self) {
                self.object = array.map(\.object)
            } else if let string = try? container.decode(String.self) {
                self.object = string
            } else if let bool = try? container.decode(Bool.self) {
                self.object = bool
            } else if let int = try? container.decode(Int.self) {
                self.object = int
            } else if let double = try? container.decode(Double.self) {
                self.object = double
            } else {
                self.object = NSNull()
            }
        }
    }

    /// Returns the request as a complete line, newline included, ready to send.
    public static func encodeRequest<P: Encodable>(id: String, method: String, params: P) throws -> Data {
        let encoder = JSONEncoder()
        // Sorted keys keep the wire bytes deterministic, which makes test
        // failures readable.
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(RequestEnvelope(id: id, method: method, params: params))
        data.append(UInt8(ascii: "\n"))
        return data
    }

    public static func decode(line: Data) throws -> WireMessage {
        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: line)

        // Events arrive on the same stream as responses and carry no id, so
        // they are classified first.
        if let kind = envelope.event {
            return .event(kind: kind, line: line)
        }
        if let error = envelope.error {
            return .failure(id: envelope.id ?? "", code: error.code, message: error.message)
        }
        if let result = envelope.result {
            return .result(id: envelope.id ?? "", payload: result.data)
        }
        if envelope.hasResult {
            // An explicit `"result": null` is still an answer, and the waiting
            // request must be resolved by it. The payload is the JSON null, so
            // a caller that needs a real object fails its own decode with
            // `malformedResponse` instead of hanging until the socket closes.
            return .result(id: envelope.id ?? "", payload: Data("null".utf8))
        }
        throw WireError.unrecognisedLine
    }
}
