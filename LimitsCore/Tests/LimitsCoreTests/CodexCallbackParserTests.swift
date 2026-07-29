import XCTest
@testable import LimitsCore

final class CodexCallbackParserTests: XCTestCase {
    func testParsesCodeAndStateFromNominalRequestLine() {
        let request = "GET /auth/callback?code=abc123&state=xyz789 HTTP/1.1\r\nHost: localhost:1455\r\n\r\n"
        let callback = CodexCallbackParser.parse(requestLine: request)
        XCTAssertEqual(callback, OAuthCallback(code: "abc123", state: "xyz789"))
    }

    func testParsesEvenWhenQueryParametersAreReordered() {
        let request = "GET /auth/callback?state=xyz789&code=abc123 HTTP/1.1\r\n\r\n"
        XCTAssertEqual(CodexCallbackParser.parse(requestLine: request), OAuthCallback(code: "abc123", state: "xyz789"))
    }

    func testReturnsNilWhenCodeIsMissing() {
        let request = "GET /auth/callback?state=xyz789 HTTP/1.1\r\n\r\n"
        XCTAssertNil(CodexCallbackParser.parse(requestLine: request))
    }

    func testReturnsNilWhenStateIsMissing() {
        let request = "GET /auth/callback?code=abc123 HTTP/1.1\r\n\r\n"
        XCTAssertNil(CodexCallbackParser.parse(requestLine: request))
    }

    func testReturnsNilWhenCodeIsEmpty() {
        let request = "GET /auth/callback?code=&state=xyz789 HTTP/1.1\r\n\r\n"
        XCTAssertNil(CodexCallbackParser.parse(requestLine: request))
    }

    func testReturnsNilForNonGETMethod() {
        let request = "POST /auth/callback?code=abc123&state=xyz789 HTTP/1.1\r\n\r\n"
        XCTAssertNil(CodexCallbackParser.parse(requestLine: request))
    }

    func testReturnsNilForNoQueryStringAtAll() {
        let request = "GET /auth/callback HTTP/1.1\r\n\r\n"
        XCTAssertNil(CodexCallbackParser.parse(requestLine: request))
    }

    func testReturnsNilForGarbageInput() {
        XCTAssertNil(CodexCallbackParser.parse(requestLine: "not an http request at all"))
        XCTAssertNil(CodexCallbackParser.parse(requestLine: ""))
    }

    func testHandlesUnrelatedRequestLikeFavicon() {
        let request = "GET /favicon.ico HTTP/1.1\r\n\r\n"
        XCTAssertNil(CodexCallbackParser.parse(requestLine: request))
    }
}
