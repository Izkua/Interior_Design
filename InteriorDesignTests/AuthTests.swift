import XCTest
@testable import InteriorDesign

/// Sign-in logic that doesn't need the network.
final class AuthTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testErrorsBecomePlainMessages() {
        XCTAssertEqual(AuthClient.mapError(status: 400, data: data(#"{"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#)), .wrongPassword)
        XCTAssertEqual(AuthClient.mapError(status: 422, data: data(#"{"error_code":"user_already_exists"}"#)), .emailInUse)
        XCTAssertEqual(AuthClient.mapError(status: 400, data: data(#"{"error_code":"email_not_confirmed"}"#)), .emailNotConfirmed)
        XCTAssertEqual(AuthClient.mapError(status: 429, data: data("{}")), .rateLimited)
        if case .weakPassword(let message) = AuthClient.mapError(status: 422, data: data(#"{"error_code":"weak_password","msg":"Password should be at least 8 characters."}"#)) {
            XCTAssertEqual(message, "Password should be at least 8 characters.")
        } else {
            XCTFail("expected weakPassword")
        }
        // Unknown errors still say something useful.
        XCTAssertNotNil(AuthClient.mapError(status: 500, data: data("oops")).errorDescription)
    }

    func testDecodesSession() throws {
        let json = #"""
        {"access_token":"a","refresh_token":"r","expires_in":3600,"token_type":"bearer",
         "user":{"id":"u1","email":"pat@example.com","user_metadata":{"full_name":"Pat Lee","avatar":{"x":1}},"app_metadata":{"provider":"google"}}}
        """#
        let session = try AuthClient.decodeSession(data(json))
        XCTAssertEqual(session.accessToken, "a")
        XCTAssertEqual(session.user.name, "Pat Lee")
        XCTAssertEqual(session.user.provider, "google")
        XCTAssertFalse(session.needsRefresh)
        XCTAssertEqual(session.expiresAt.timeIntervalSinceNow, 3600, accuracy: 5)
    }

    func testExpiringSessionNeedsRefresh() {
        let user = AuthUser(id: "u", email: nil, name: nil, provider: "email")
        let session = AuthSession(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(30), user: user)
        XCTAssertTrue(session.needsRefresh)
    }

    func testCallbackWithErrorIsReported() async {
        let url = URL(string: "interiordesign://auth-callback#error=access_denied&error_description=Email+link+is+invalid")!
        do {
            _ = try await AuthClient().session(fromCallback: url)
            XCTFail("should throw")
        } catch let error as AuthError {
            XCTAssertEqual(error, .server("Email link is invalid"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testAuthorizeURLAsksForCallbackWithPKCE() {
        let pkce = AuthClient.PKCE(verifier: "v", challenge: "abc_-123")
        let url = AuthClient().authorizeURL(provider: "google", pkce: pkce).absoluteString
        XCTAssertTrue(url.hasPrefix("https://tpansxzplscfoffsscqn.supabase.co/auth/v1/authorize?"))
        XCTAssertTrue(url.contains("provider=google"))
        XCTAssertTrue(url.contains("redirect_to=interiordesign://auth-callback"))
        XCTAssertTrue(url.contains("code_challenge=abc_-123"))
        XCTAssertTrue(url.contains("code_challenge_method=s256"))
    }

    func testPKCEChallengeMatchesTheStandardExample() {
        // The worked example from the PKCE standard (RFC 7636, appendix B).
        XCTAssertEqual(
            AuthClient.PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testPKCEVerifierIsRandomAndURLSafe() {
        let a = AuthClient.PKCE.make(), b = AuthClient.PKCE.make()
        XCTAssertNotEqual(a.verifier, b.verifier)
        XCTAssertEqual(a.verifier.count, 43)
        XCTAssertNil(a.verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        XCTAssertEqual(a.challenge, AuthClient.PKCE.challenge(for: a.verifier))
    }

    func testReadsCodeFromCallback() throws {
        let url = URL(string: "interiordesign://auth-callback?code=abc123")!
        XCTAssertEqual(try AuthClient.code(fromCallback: url), "abc123")
    }

    func testCallbackErrorBecomesMessage() {
        let url = URL(string: "interiordesign://auth-callback?error=access_denied&error_description=Unsupported+provider")!
        XCTAssertThrowsError(try AuthClient.code(fromCallback: url)) { error in
            XCTAssertEqual(error as? AuthError, .server("Unsupported provider"))
        }
        XCTAssertThrowsError(try AuthClient.code(fromCallback: URL(string: "interiordesign://auth-callback")!))
    }

    func testNoSecretKeysInTheApp() {
        // Only the publishable key may ship in the app.
        XCTAssertTrue(BackendConfig.publishableKey.hasPrefix("sb_publishable_"))
    }
}

final class AppleSignInTests: XCTestCase {
    func testNonceIsRandomAndLongEnough() {
        let a = AppleSignIn.makeNonce(), b = AppleSignIn.makeNonce()
        XCTAssertEqual(a.count, 32)
        XCTAssertNotEqual(a, b)
    }

    func testSHA256MatchesKnownValue() {
        // Known SHA-256 of "abc".
        XCTAssertEqual(AppleSignIn.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testIdTokenRequestBody() {
        let body = AuthClient.idTokenBody(provider: "apple", idToken: "token123", nonce: "raw-nonce")
        XCTAssertEqual(body, ["provider": "apple", "id_token": "token123", "nonce": "raw-nonce"])
    }

    func testDisplayName() {
        var name = PersonNameComponents()
        name.givenName = "Ada"
        name.familyName = "Lovelace"
        XCTAssertEqual(AppleSignIn.displayName(name), "Ada Lovelace")
        XCTAssertNil(AppleSignIn.displayName(PersonNameComponents()))
        XCTAssertNil(AppleSignIn.displayName(nil))
    }
}
