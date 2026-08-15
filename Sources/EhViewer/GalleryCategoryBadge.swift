import SwiftUI
import EHDomain

/// Category colors ported from the reference client's
/// `EhUtils.getCategoryColor` (Material palette values).
enum GalleryCategoryPalette {
    static func color(for name: String?) -> Color {
        guard let name, let category = GalleryCategory(rawValue: name) else { return Color(white: 0.45) }
        switch category {
        case .doujinshi: return Color(red: 0.957, green: 0.263, blue: 0.212)
        case .manga: return Color(red: 1.0, green: 0.596, blue: 0.0)
        case .artistCG: return Color(red: 0.984, green: 0.753, blue: 0.176)
        case .gameCG: return Color(red: 0.298, green: 0.686, blue: 0.314)
        case .western: return Color(red: 0.545, green: 0.765, blue: 0.290)
        case .nonH: return Color(red: 0.129, green: 0.588, blue: 0.953)
        case .imageSet: return Color(red: 0.247, green: 0.318, blue: 0.710)
        case .cosplay: return Color(red: 0.612, green: 0.153, blue: 0.690)
        case .asianPorn: return Color(red: 0.584, green: 0.459, blue: 0.804)
        case .misc: return Color(red: 0.941, green: 0.384, blue: 0.573)
        }
    }
}

/// White text on the category color, matching the reference card's badge.
struct CategoryBadge: View {
    let name: String

    var body: some View {
        Text(name.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(GalleryCategoryPalette.color(for: name), in: Capsule())
            .accessibilityLabel("分类 \(name)")
    }
}
