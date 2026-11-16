import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NullmereTestSupport
import XCTest
@testable import NullmereRealm

/// What a keeper is told when the realm can't be reached: plain words for
/// every kind of trouble, never an error's domain, code and user info.
final class RealmTroubleTests: XCTestCase {
    func testEachTroubleIsSaidPlainly() {
        let said: [(any Error, String)] = [
            (SpacetimeError("The realm isn't open yet."), "The realm isn't open yet."),
            (URLError(.notConnectedToInternet), "This Mac isn't connected to the internet."),
            (URLError(.timedOut), "The realm didn't answer in time."),
            (URLError(.cannotFindHost), "The realm can't be found."),
            (URLError(.dnsLookupFailed), "The realm can't be found."),
            (URLError(.serverCertificateUntrusted), "The realm couldn't be reached safely."),
            (URLError(.secureConnectionFailed), "The realm couldn't be reached safely."),
            (URLError(.cannotConnectToHost), "The realm can't be reached."),
            (URLError(.networkConnectionLost), "The realm can't be reached."),
            (NSError(domain: "NSOSStatusErrorDomain", code: -25308),
             "This Mac's keychain wouldn't keep your key. Unlock the keychain, then try again."),
            (NSError(domain: "Elsewhere", code: 7), "The realm can't be reached."),
            // What the server says is for whoever runs it; the keeper hears
            // plain words, but for the realm's own refusals, written for them.
            (SpacetimeError("The realm isn't open yet.", status: 404), "The realm isn't open yet."),
            (SpacetimeError.unauthorized, SpacetimeError.unauthorized.description),
            (SpacetimeError("The reducer panicked: index out of bounds", status: 530), "The realm couldn't answer just now."),
            (SpacetimeError("The realm answered 503.", status: 503), "The realm couldn't answer just now."),
            (SpacetimeError("expected value at line 1 column 1", status: 400), "The realm couldn't take that request."),
            (SpacetimeError("Too many of your requests are waiting; give the realm a moment.", status: 530),
             "Too many of your requests are waiting; give the realm a moment."),
            (SpacetimeError("The realm didn't answer in time."), "The realm didn't answer in time."),
        ]
        for (error, words) in said {
            XCTAssertEqual(RealmTrouble.words(for: error), words, "\(error)")
        }
        // On the phone that speaks for the keeper, the words name the phone.
        let onThePhone: [(any Error, String)] = [
            (URLError(.notConnectedToInternet), "This phone isn't connected to the internet."),
            (URLError(.dataNotAllowed), "This phone isn't connected to the internet."),
            (NSError(domain: "NSOSStatusErrorDomain", code: -25308),
             "This phone's keychain wouldn't keep your key. Unlock the phone, then try again."),
            (SpacetimeError.unauthorized, "The realm doesn't accept this phone's key just now. The key is kept, and offered again in a while."),
            (URLError(.timedOut), "The realm didn't answer in time."),
            (URLError(.cannotConnectToHost), "The realm can't be reached."),
            (SpacetimeError("The realm answered 503.", status: 503), "The realm couldn't answer just now."),
        ]
        for (error, words) in onThePhone {
            XCTAssertEqual(RealmTrouble.words(for: error, on: .phone), words, "\(error)")
        }
        let garbled = Result { try JSONDecoder().decode(SpacetimeCredentials.self, from: Data("{}".utf8)) }
        if case .failure(let error) = garbled {
            XCTAssertTrue(RealmTrouble.words(for: error).hasPrefix("The realm answered in words"))
        } else {
            XCTFail("Garbled credentials don't decode")
        }
    }
}

