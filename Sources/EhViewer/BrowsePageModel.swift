import Foundation
import Observation
import EHDomain
import EHNetworking
import EHPersistence

@MainActor
@Observable
final class BrowsePageModel {
    private unowned let model: AppModel
    private let loadTagSuggestions: @Sendable (String) async throws -> [SearchTagSuggestion]
    let api: any EHAPI
    let persistence: PersistenceStore
    let kind: GalleryListQuery.ListKind

    var galleries: [GallerySummary] = []
    var isLoading = false
    var nextPageURL: URL?
    var searchText = ""
    var submittedSearchText = ""
    var tagSearchSuggestions: [SearchTagSuggestion] = []
    var searchHistorySuggestions: [String] = []
    var suggestionQuery = ""
    var isUpdatingSearchSuggestions = false
    var advancedSearch: GalleryAdvancedSearch?
    var errorMessage: String?
    var scrollPosition: GalleryKey?

    private var activeQuery: GalleryListQuery
    private var activeRequestID = UUID()
    private var suggestionRequestID = UUID()
    private var cachedQuickSearches: [String]?
    private var hasLoadedList = false
    private var loadedConfigurationID: String?
    private var consecutiveFilteredPages = 0

    var shouldAutomaticallyLoadMore: Bool {
        consecutiveFilteredPages < 5
    }

    init(
        model: AppModel,
        kind: GalleryListQuery.ListKind,
        initialSearchText: String? = nil,
        tagSuggestionLoader: (@Sendable (String) async throws -> [SearchTagSuggestion])? = nil
    ) {
        self.model = model
        let normalizedSearchText = SearchQueryComposer.normalized(initialSearchText ?? "")
        api = model.api
        persistence = model.persistence
        if let tagSuggestionLoader {
            loadTagSuggestions = tagSuggestionLoader
        } else {
            let provider = model.tagSuggestionProvider
            loadTagSuggestions = { keyword in
                try await provider.suggestions(for: keyword)
            }
        }
        self.kind = kind
        searchText = normalizedSearchText
        submittedSearchText = normalizedSearchText
        activeQuery = GalleryListQuery(
            site: model.site,
            kind: kind,
            searchText: normalizedSearchText.isEmpty ? nil : normalizedSearchText
        )
    }

    var listQuery: GalleryListQuery {
        GalleryListQuery(
            site: model.site,
            kind: kind,
            searchText: submittedSearchText.isEmpty ? nil : submittedSearchText,
            advancedSearch: advancedSearch
        )
    }

    var configurationID: String {
        let rules = model.filterRules.map { "\($0.pattern)=\($0.isEnabled)" }.joined(separator: "|")
        return "\(model.site.rawValue)|\(rules)"
    }

    func load(query: GalleryListQuery) async {
        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true
        errorMessage = nil
        nextPageURL = nil
        var loadedNextPageURL: URL?
        var didLoadPage = false
        defer {
            if activeRequestID == requestID {
                isLoading = false
                if didLoadPage { nextPageURL = loadedNextPageURL }
            }
        }

        activeQuery = query
        do {
            let result = if query.kind == .favorites {
                try await api.favorites(query: query)
            } else {
                try await api.list(query: query)
            }
            try Task.checkCancellation()
            guard activeRequestID == requestID else { return }
            galleries = result.items.filter(matchesFilter)
            consecutiveFilteredPages = galleries.isEmpty ? 1 : 0
            errorMessage = nil
            loadedNextPageURL = result.cursor?.nextPageURL
            didLoadPage = true
            hasLoadedList = true
            loadedConfigurationID = configurationID
            try await persistence.upsert(result.items)
            if let searchText = query.searchText {
                try? await persistence.recordQuickSearch(searchText)
                cachedQuickSearches = nil
            }
        } catch is CancellationError {
            return
        } catch {
            if activeRequestID == requestID {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadIfNeeded(query: GalleryListQuery) async {
        guard hasLoadedList == false
                || isSameList(query, activeQuery) == false
                || loadedConfigurationID != configurationID else { return }
        await load(query: query)
    }

    func loadMoreIfNeeded(after galleryKey: GalleryKey) async {
        guard galleries.last?.key == galleryKey else { return }
        await loadMore()
    }

    func loadMore() async {
        guard let pageURL = nextPageURL,
              isLoading == false else { return }

        let requestID = activeRequestID
        var query = activeQuery
        query.page += 1
        isLoading = true
        var loadedNextPageURL: URL?
        var didLoadPage = false
        defer {
            if activeRequestID == requestID {
                isLoading = false
                if didLoadPage { nextPageURL = loadedNextPageURL }
            }
        }

        do {
            let result = try await api.list(query: query, pageURL: pageURL)
            try Task.checkCancellation()
            guard activeRequestID == requestID else { return }
            let visibleItems = result.items.filter(matchesFilter)
            appendUniqueGalleries(visibleItems)
            if visibleItems.isEmpty {
                consecutiveFilteredPages += 1
            } else {
                consecutiveFilteredPages = 0
            }
            loadedNextPageURL = result.cursor?.nextPageURL
            didLoadPage = true
            activeQuery = query
            try await persistence.upsert(result.items)
        } catch is CancellationError {
            return
        } catch {
            if activeRequestID == requestID {
                errorMessage = error.localizedDescription
            }
        }
    }

    func continueAfterFilteredPages() async {
        consecutiveFilteredPages = 0
        await loadMore()
    }

    private func isSameList(_ lhs: GalleryListQuery, _ rhs: GalleryListQuery) -> Bool {
        var lhs = lhs
        var rhs = rhs
        lhs.page = 0
        rhs.page = 0
        return lhs == rhs
    }

    func submitSearch() {
        let normalized = SearchQueryComposer.normalized(searchText)
        searchText = normalized
        submittedSearchText = normalized
    }

    func clearSearch() {
        searchText = ""
        submittedSearchText = ""
    }

    func refreshSearchSuggestions(for query: String) async {
        let requestID = UUID()
        suggestionRequestID = requestID
        let normalizedQuery = SearchQueryComposer.normalized(query)
        let fragment = SearchQueryComposer.suggestionFragment(in: normalizedQuery)

        suggestionQuery = normalizedQuery
        isUpdatingSearchSuggestions = true
        searchHistorySuggestions = cachedQuickSearches.map {
            filteredSearchHistory($0, prefix: normalizedQuery)
        } ?? []
        tagSearchSuggestions = fragment.isEmpty ? [] : tagSearchSuggestions.filter {
            matchesTagSuggestion($0, keyword: fragment)
        }

        // Coalesce changes made in the same run-loop turn without adding a
        // fixed delay that makes the visible suggestions lag behind typing.
        await Task.yield()

        do {
            try Task.checkCancellation()
            let history = try await searchHistorySuggestions(for: normalizedQuery)
            try Task.checkCancellation()
            let tags: [SearchTagSuggestion]
            if fragment.isEmpty {
                tags = []
            } else {
                tags = try await loadTagSuggestions(fragment)
            }
            try Task.checkCancellation()
            guard isLatestSuggestionRequest(requestID, query: normalizedQuery) else { return }
            if searchHistorySuggestions != history {
                searchHistorySuggestions = history
            }
            if tagSearchSuggestions != tags {
                tagSearchSuggestions = tags
            }
            isUpdatingSearchSuggestions = false
        } catch is CancellationError {
            return
        } catch {
            guard Task.isCancelled == false,
                  isLatestSuggestionRequest(requestID, query: normalizedQuery) else { return }
            searchHistorySuggestions = cachedQuickSearches.map {
                filteredSearchHistory($0, prefix: normalizedQuery)
            } ?? []
            isUpdatingSearchSuggestions = false
        }
    }

    private func isLatestSuggestionRequest(_ requestID: UUID, query: String) -> Bool {
        suggestionRequestID == requestID
            && suggestionQuery == query
            && SearchQueryComposer.normalized(searchText) == query
    }

    private func searchHistorySuggestions(for prefix: String) async throws -> [String] {
        if cachedQuickSearches == nil {
            cachedQuickSearches = try await persistence.quickSearches(limit: 100)
        }
        return filteredSearchHistory(cachedQuickSearches ?? [], prefix: prefix)
    }

    private func filteredSearchHistory(_ searches: [String], prefix: String) -> [String] {
        guard prefix.isEmpty == false else { return searches }
        return searches.filter {
            $0 != prefix && $0.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
        }
    }

    private func matchesTagSuggestion(_ suggestion: SearchTagSuggestion, keyword: String) -> Bool {
        suggestion.english.localizedCaseInsensitiveContains(keyword)
            || suggestion.localizedText?.localizedCaseInsensitiveContains(keyword) == true
    }

    func deleteSearchHistory(_ query: String) async {
        do {
            try await persistence.deleteQuickSearch(query)
            cachedQuickSearches = nil
            await refreshSearchSuggestions(for: searchText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeTagSuggestion(_ tag: String) {
        searchText = SearchQueryComposer.completing(tag: tag, in: searchText)
    }

    func selectSearchHistory(_ query: String) {
        searchText = SearchQueryComposer.normalized(query)
    }

    private func matchesFilter(_ gallery: GallerySummary) -> Bool {
        let haystack = ([gallery.title, gallery.secondaryTitle ?? ""] + gallery.tags)
            .joined(separator: " ")
            .lowercased()
        return model.filterRules.contains { rule in
            rule.isEnabled && haystack.localizedCaseInsensitiveContains(rule.pattern)
        } == false
    }

    private func appendUniqueGalleries(_ newGalleries: [GallerySummary]) {
        var existingKeys = Set(galleries.map(\.key))
        galleries.append(contentsOf: newGalleries.filter {
            existingKeys.insert($0.key).inserted
        })
    }
}
