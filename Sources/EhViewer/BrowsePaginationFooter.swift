import SwiftUI

struct BrowsePaginationFooter: View {
    var body: some View {
        ProgressView("正在加载更多…")
            .frame(maxWidth: .infinity, minHeight: 64)
            .accessibilityIdentifier("browse-pagination-footer")
    }
}
