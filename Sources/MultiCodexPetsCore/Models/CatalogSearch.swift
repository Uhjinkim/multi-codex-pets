import Foundation

public enum CatalogSearch {
  public static func soundURL(query: String) -> URL {
    var url = URLComponents(string: "https://www.myinstants.com/ko/search/")!
    url.queryItems = [URLQueryItem(name: "name", value: query.trimmingCharacters(in: .whitespacesAndNewlines))]
    url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return url.url!
  }

  public static func petURL(query: String) -> URL {
    var parameters = URLComponents()
    parameters.queryItems = [URLQueryItem(name: "q", value: query.trimmingCharacters(in: .whitespacesAndNewlines))]
    parameters.percentEncodedQuery = parameters.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    var url = URLComponents(string: "https://codex-pets.net/")!
    url.percentEncodedFragment = "/?" + parameters.percentEncodedQuery!
    return url.url!
  }
}
