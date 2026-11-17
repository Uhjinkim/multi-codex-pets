import XCTest
@testable import MultiCodexPetsCore

final class CatalogSearchTests: XCTestCase {
  func testSearchTermsStayOneParameterIncludingKoreanAndURLCharacters() throws {
    let query = "치이카와 & usagi/#?=+🎵"
    let sound = try XCTUnwrap(URLComponents(url: CatalogSearch.soundURL(query: "  \(query) \n"), resolvingAgainstBaseURL: false))
    XCTAssertEqual(sound.host, "www.myinstants.com")
    XCTAssertEqual(sound.path, "/ko/search/")
    XCTAssertEqual(sound.queryItems, [URLQueryItem(name: "name", value: query)])
    XCTAssertFalse(sound.percentEncodedQuery!.contains("+"))
    let pet = try XCTUnwrap(URLComponents(url: CatalogSearch.petURL(query: " \(query) "), resolvingAgainstBaseURL: false))
    XCTAssertEqual(pet.host, "codex-pets.net")
    XCTAssertNil(pet.query)
    let fragment = try XCTUnwrap(pet.percentEncodedFragment)
    XCTAssertFalse(fragment.contains("+"))
    let route = try XCTUnwrap(URLComponents(string: "https://codex-pets.net" + fragment))
    XCTAssertEqual(route.path, "/")
    XCTAssertEqual(route.queryItems, [URLQueryItem(name: "q", value: query)])
  }

  func testEmptySearchOpensTheCatalog() {
    XCTAssertEqual(CatalogSearch.soundURL(query: "").absoluteString, "https://www.myinstants.com/ko/search/?name=")
    XCTAssertEqual(CatalogSearch.petURL(query: "chiikawa").absoluteString, "https://codex-pets.net/#/?q=chiikawa")
  }
}
