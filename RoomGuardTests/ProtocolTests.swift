import XCTest
@testable import RoomGuard

final class ProtocolTests: XCTestCase {
    let text = #"{"v":1,"url":"https://test.trycloudflare.com","key":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="}"#
    func testPythonAuthenticationCompatibility() throws {
        let pairing = try Pairing.parse(text)
        XCTAssertEqual(pairing.token, "44dd5d5f63ab6d5e1140b036b8d0a8f2d222d0715ce525dfef8e25196e3ec2d4")
        XCTAssertEqual(pairing.socketURL.absoluteString, "wss://test.trycloudflare.com/v1/live?fps=30")
    }
    func testPythonEncryptedFrameCompatibility() throws {
        let packet = Data(base64Encoded: "AAECAwQFBgcICQoLRwLXiQns1mBymePuwp1VB/Oz4MspYUl+1jh1YpVHoVFvlDI79A==")!
        let result = try FrameDecoder.decode(packet, key: Pairing.parse(text).keyData)
        XCTAssertEqual(result.timestamp, 1730000000123)
        XCTAssertEqual(result.jpeg, Data([0xff, 0xd8]) + Data("test-jpeg".utf8) + Data([0xff, 0xd9]))
        var changed = packet
        changed[changed.count - 1] ^= 1
        XCTAssertThrowsError(try FrameDecoder.decode(changed, key: Pairing.parse(text).keyData))
    }
    func testRejectsUnsafePairingAddressesAndKeys() {
        for url in ["http://example.com", "https://user:pass@example.com", "https://example.com/?key=leak", "https://example.com/#key", "https://example.com/a", "https://example.com:8443"] {
            XCTAssertThrowsError(try Pairing.parse(text.replacingOccurrences(of: "https://test.trycloudflare.com", with: url)))
        }
        XCTAssertThrowsError(try Pairing.parse(text.replacingOccurrences(of: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=", with: "bad")))
        XCTAssertThrowsError(try Pairing.parse("not a pairing code"))
        XCTAssertThrowsError(try FrameDecoder.decode(Data([1, 2]), key: Data(repeating: 0, count: 32)))
    }
}
