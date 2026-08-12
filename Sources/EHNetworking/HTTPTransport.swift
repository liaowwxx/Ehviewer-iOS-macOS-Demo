import Foundation
import EHDomain

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EHError.invalidResponse
        }
        return (data, httpResponse)
    }
}

public struct SiteRequestBuilder: Sendable {
    public let site: SiteMode

    public init(site: SiteMode) {
        self.site = site
    }

    public var baseURL: URL {
        URL(string: "https://\(site.host)")!
    }

    public func galleryListRequest(query: GalleryListQuery) throws -> URLRequest {
        let path: String = switch query.kind {
        case .home, .search: "/"
        case .subscriptions: "/watched"
        case .popular: "/popular"
        case .toplist: "/toplist.php"
        case .favorites: "/favorites.php"
        }
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw EHError.invalidURL
        }
        var items = [URLQueryItem]()
        if let searchText = query.searchText, searchText.isEmpty == false {
            items.append(URLQueryItem(name: "f_search", value: searchText))
        }
        if query.page > 0 {
            items.append(URLQueryItem(name: "page", value: String(query.page)))
        }
        if let category = query.category {
            items.append(URLQueryItem(name: "f_cats", value: category))
        }
        if query.kind == .favorites, let favoriteCategory = query.favoriteCategory, (0...9).contains(favoriteCategory) {
            items.append(URLQueryItem(name: "favcat", value: String(favoriteCategory)))
        }
        if query.kind == .popular {
            items.append(URLQueryItem(name: "fs_from", value: "popular"))
        }
        if query.sort == .popular {
            items.append(URLQueryItem(name: "f_sname", value: "popularity"))
        } else if query.sort == .rating {
            items.append(URLQueryItem(name: "f_sname", value: "rating"))
        }
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url else { throw EHError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        return request
    }

    public func galleryRequest(key: GalleryKey) throws -> URLRequest {
        guard let url = URL(string: "https://\(site.host)/g/\(key.gid)/\(key.token)/") else {
            throw EHError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        return request
    }

    public func pageRequest(_ descriptor: GalleryPageDescriptor) throws -> URLRequest {
        var request = URLRequest(url: descriptor.pageURL)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml,application/json", forHTTPHeaderField: "Accept")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        return request
    }
}
