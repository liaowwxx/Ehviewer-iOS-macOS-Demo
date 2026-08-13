import SwiftUI
import EHDomain

struct MoreView: View {
    var body: some View {
        List {
            Section("浏览") {
                NavigationLink(value: AppRoute.subscriptions) {
                    Label("subscriptions_title", systemImage: "tag")
                }
                NavigationLink(value: AppRoute.popular) {
                    Label("popular_title", systemImage: "chart.line.uptrend.xyaxis")
                }
                NavigationLink(value: AppRoute.toplist) {
                    Label("toplist_title", systemImage: "list.number")
                }
            }
            Section("个人") {
                NavigationLink(value: AppRoute.history) {
                    Label("history_title", systemImage: "clock")
                }
                NavigationLink(value: AppRoute.favorites) {
                    Label("favorites_title", systemImage: "heart")
                }
            }
            Section {
                NavigationLink(value: AppRoute.settings) {
                    Label("settings_title", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("更多")
    }
}
