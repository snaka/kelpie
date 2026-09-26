import Foundation

/// Whether a failure means herdr and Kelpie no longer agree on the JSON API.
///
/// herdr offers no JSON API version to check up front: the `protocol` number in
/// `ping` and `session.snapshot` versions the binary protocol between herdr's
/// own client and server, and its documentation tells JSON clients to ignore
/// unknown fields and treat unsupported methods as ordinary errors instead.
/// So compatibility is judged from what actually happens on the wire — herdr
/// rejecting a request it cannot parse, or answering with something Kelpie
/// cannot decode — rather than predicted from a number.
public enum HerdrCompatibility {
    /// herdr's code for a request line it could not deserialise: an unknown
    /// method, or params missing a field it requires.
    static let unparseableRequest = "invalid_request"

    public static func isIncompatibility(_ error: any Error) -> Bool {
        switch error {
        case RequestError.malformedResponse:
            return true
        case RequestError.herdr(let code, _):
            return code == unparseableRequest
        case EventConnectionError.subscriptionRejected(let code, _):
            // `pane_not_found` is the ordinary race of a planned pane closing
            // before the subscribe lands, and must stay retryable.
            return code == unparseableRequest
        default:
            return false
        }
    }
}
