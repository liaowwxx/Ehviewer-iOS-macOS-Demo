import Foundation
import Observation
import EHDomain
import EHNetworking
import EHPersistence

@MainActor
@Observable
final class BrowsePageModel {
    let api: any EHAPI
    let persistence: PersistenceStore
    let tagSuggestionProvider: TagSuggestionProvider
    let site: SiteMode
    let kind: GalleryListQuery.ListKind

    var galleries: [GallerySummary] = []
    var isLoading = false
    var nextPageURL: URL?
    var searchText = ""
    var submittedSearchText = ""
    var tagSearchSuggestions: [SearchTagSuggestion] = []
    var errorMessage: String?

    private var filterRules: [FilterRuleSnapshot] = []
    private var didLoadFilterRules = false
    private var activeQuery: GalleryListQuery
    private var activeRequestID = UUID()

    init(model: AppModel, kind: GalleryListQuery.ListKind, initialSearchText: String? = nil) {
        let normalizedSearchText = SearchQueryComposer.normalized(initialSearchText ?? "")
        api = model.api
        persistence = model.persistence
        tagSuggestionProvider = model.tagSuggestionProvider
        site = model.site
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
            site: site,
            kind: kind,
            searchText: submittedSearchText.isEmpty ? nil : submittedSearchText
        )
    }

    func load(query: GalleryListQuery) async {
        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true
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
            await loadFilterRulesIfNeeded()
            let result = if query.kind == .favorites {
                try await api.favorites(query: query)
            } else {
                try await api.list(query: query)
            }
            try Task.checkCancellation()
            guard activeRequestID == requestID else { return }
            galleries = result.items.filter(matchesFilter)
            loadedNextPageURL = result.cursor?.nextPageURL
            didLoadPage = true
            try await persistence.upsert(result.items)
            if let searchText = query.searchText {
                try? await persistence.recordQuickSearch(searchText)
            }
        } catch is CancellationError {
            return
        } catch {
            if activeRequestID == requestID {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMoreIfNeeded(after galleryKey: GalleryKey) async {
        guard galleries.last?.key == galleryKey,
              let pageURL = nextPageURL,
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
            appendUniqueGalleries(result.items)
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

    func submitSearch() {
        let normalized = SearchQueryComposer.normalized(searchText)
        searchText = normalized
        submittedSearchText = normalized
    }

    func clearSearch() {
        searchText = ""
        submittedSearchText = ""
    }

    func updateTagSuggestions() async {
        let fragment = SearchQueryComposer.suggestionFragment(in: searchText)
        tagSearchSuggestions = []
        guard fragment.isEmpty == false else { return }
        do {
            try await Task.sleep(for: .milliseconds(120))
            let loadedTags = try await tagSuggestionProvider.suggestions(for: fragment)
            try Task.checkCancellation()
            guard SearchQueryComposer.suggestionFragment(in: searchText) == fragment else { return }
            tagSearchSuggestions = loadedTags
        } catch is CancellationError {
            return
        } catch {
            tagSearchSuggestions = []
        }
    }

    func completeTagSuggestion(_ tag: String) {
        searchText = SearchQueryComposer.completing(tag: tag, in: searchText)
    }

    private func loadFilterRulesIfNeeded() async {
        guard didLoadFilterRules == false else { return }
        filterRules = (try? await persistence.filterRules()) ?? []
        didLoadFilterRules = true
    }

    private func matchesFilter(_ gallery: GallerySummary) -> Bool {
        let haystack = ([gallery.title, gallery.secondaryTitle ?? ""] + gallery.tags)
            .joined(separator: " ")
            .lowercased()
        return filterRules.contains { rule in
            rule.isEnabled && haystack.localizedCaseInsensitiveContains(rule.pattern)
        } == false
    }

    private func appendUniqueGalleries(_ newGalleries: [GallerySummary]) {
        var existingKeys = Set(galleries.map(\.key))
        galleries.append(contentsOf: newGalleries.filter {
            matchesFilter($0) && existingKeys.insert($0.key).inserted
        })
    }
}
