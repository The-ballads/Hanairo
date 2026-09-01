import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RankingView: View {
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(PixivRepository.self) private var repository
    @Environment(AppSettings.self) private var settings

    @State private var mode: RankingMode = .daily
    @State private var selectedDate = Date()
    @State private var usesCustomDate = false
    @State private var isDateCardExpanded = false
    @State private var feed = PaginatedStore<PixivIllustration>(id: { $0.id })
    @State private var actionError: String?

    private let scrollTopID = "ranking-scroll-top"

    var body: some View {
        GeometryReader { geometry in
            let usesFourColumns = usesFourColumnLayout(for: geometry.size.width)

            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear
                        .frame(height: 1)
                        .id(scrollTopID)

                    LazyVStack(alignment: .leading, spacing: 18) {
                        modeDescription

                        content(columnCount: usesFourColumns ? 4 : nil)
                    }
                    .padding(.horizontal)
                    .padding(.top, floatingTopPadding)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await refresh()
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newOffset in
                    if isDateCardExpanded, newOffset > 8 {
                        withAnimation(.snappy) {
                            isDateCardExpanded = false
                        }
                    }
                }
                .onChange(of: requestKey) { _, _ in
                    proxy.scrollTo(scrollTopID, anchor: .top)
                }
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        floatingModeSelector
                        floatingDateToggle
                    }

                    if isDateCardExpanded {
                        floatingDatePickerCard
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 8)
            }
        }
        .navigationTitle("排行榜")
        .task(id: requestKey) {
            await loadIfNeeded()
        }
        .onChange(of: settings.showsMatureArtwork) { _, showsMatureArtwork in
            if !showsMatureArtwork, mode.isMature {
                mode = .daily
            }
        }
        .alert("操作失败", isPresented: actionErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(displayedError ?? "未知错误")
        }
    }

    private var modeDescription: some View {
        Text(mode.description)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var floatingModeSelector: some View {
        Menu {
            rankingModePicker
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode.systemImage)
                    .frame(width: 20)

                Text(mode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if mode.isMature {
                    matureBadge
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var rankingModePicker: some View {
        Picker("排行榜", selection: $mode) {
            ForEach(availableModes) { mode in
                Label(mode.title, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
    }

    private var floatingDateToggle: some View {
        Button {
            withAnimation(.snappy) {
                if isDateCardExpanded {
                    isDateCardExpanded = false
                } else {
                    isDateCardExpanded = true
                    if !usesCustomDate {
                        usesCustomDate = true
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .frame(width: 20)

                Text(usesCustomDate ? selectedDate.formatted(.dateTime.month().day()) : "指定日期")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .glassEffect(
                usesCustomDate
                    ? Glass.regular.tint(.accentColor).interactive()
                    : Glass.regular.interactive(),
                in: .rect(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }

    private var floatingDatePickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker(
                "排行日期",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .labelsHidden()

            Button {
                withAnimation(.snappy) {
                    usesCustomDate = false
                    isDateCardExpanded = false
                }
            } label: {
                Label("使用最新排行", systemImage: "arrow.counterclockwise")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.glass)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private var matureBadge: some View {
        Text("R-18")
            .font(.caption.bold())
            .foregroundStyle(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.red.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func content(columnCount: Int?) -> some View {
        switch feed.phase {
        case .idle, .loading:
            LoadingArtworkGrid()
        case let .failed(message):
            ErrorStateView(message: message) {
                Task { await retry() }
            }
            .frame(minHeight: 360)
        case .loaded:
            if feed.items.isEmpty {
                ContentUnavailableView("暂无排行数据", systemImage: "trophy")
                    .frame(minHeight: 360)
            } else {
                ArtworkMasonryGrid(
                    illustrations: feed.items,
                    showsRanking: true,
                    columnCount: columnCount,
                    onLoadMore: loadMore
                ) { id in
                    await toggleBookmark(id: id)
                }
                PaginationStatusView(
                    isLoading: feed.isLoadingMore,
                    errorMessage: feed.loadMoreError,
                    onRetry: loadMore
                )
            }
        }
    }

    private var requestKey: String {
        "\(mode.rawValue)-\(usesCustomDate)-\(selectedDate.timeIntervalSinceReferenceDate)-\(authentication.userID ?? 0)"
    }

    private var availableModes: [RankingMode] {
        RankingMode.allCases.filter { settings.showsMatureArtwork || !$0.isMature }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { displayedError != nil },
            set: {
                if !$0 {
                    actionError = nil
                    feed.clearRefreshError()
                }
            }
        )
    }

    private var displayedError: String? {
        actionError ?? feed.refreshError
    }

    private func loadIfNeeded() async {
        let activeRequestKey = requestKey
        let activeMode = mode.rawValue
        let activeDate = usesCustomDate ? selectedDate : nil
        await feed.loadIfNeeded(requestKey: activeRequestKey) {
            try await repository.ranking(mode: activeMode, date: activeDate)
        }
    }

    private func refresh() async {
        let activeRequestKey = requestKey
        let activeMode = mode.rawValue
        let activeDate = usesCustomDate ? selectedDate : nil
        await feed.reload(requestKey: activeRequestKey, showsInitialLoading: false) {
            try await repository.ranking(mode: activeMode, date: activeDate)
        }
    }

    private func retry() async {
        let activeRequestKey = requestKey
        let activeMode = mode.rawValue
        let activeDate = usesCustomDate ? selectedDate : nil
        await feed.reload(requestKey: activeRequestKey, showsInitialLoading: true) {
            try await repository.ranking(mode: activeMode, date: activeDate)
        }
    }

    private func loadMore() async {
        let activeRequestKey = requestKey
        await feed.loadMore(requestKey: activeRequestKey) { nextURL in
            try await repository.illustrations(nextURL: nextURL)
        }
    }

    private func toggleBookmark(id: Int) async {
        guard let illustration = feed.item(id: id) else { return }
        do {
            let isBookmarked = try await repository.toggleBookmark(illustration)
            feed.updateItem(id: id) { $0.isBookmarked = isBookmarked }
        } catch is CancellationError {
            return
        } catch {
            actionError = error.localizedDescription
        }
    }

    private var floatingTopPadding: CGFloat {
        isDateCardExpanded ? 168 : 64
    }

    private func usesFourColumnLayout(for width: CGFloat) -> Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom != .phone && width >= 700
#else
        width >= 900
#endif
    }
}

private enum RankingMode: String, CaseIterable, Identifiable {
    case daily = "day"
    case male = "day_male"
    case female = "day_female"
    case original = "week_original"
    case rookie = "week_rookie"
    case weekly = "week"
    case monthly = "month"
    case ai = "day_ai"
    case matureAI = "day_r18_ai"
    case matureDaily = "day_r18"
    case matureWeekly = "week_r18"
    case matureG = "week_r18g"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "日榜"
        case .male: "男性热门"
        case .female: "女性热门"
        case .original: "原创榜"
        case .rookie: "新人榜"
        case .weekly: "周榜"
        case .monthly: "月榜"
        case .ai: "AI 日榜"
        case .matureAI: "AI R-18 日榜"
        case .matureDaily: "R-18 日榜"
        case .matureWeekly: "R-18 周榜"
        case .matureG: "R-18G 周榜"
        }
    }

    var description: String {
        switch self {
        case .daily: "Pixiv 全站每日综合排名"
        case .male: "男性用户关注度较高的每日作品"
        case .female: "女性用户关注度较高的每日作品"
        case .original: "最近一周的原创作品排名"
        case .rookie: "最近一周的新锐作者作品排名"
        case .weekly: "最近一周的综合排名"
        case .monthly: "最近一个月的综合排名"
        case .ai: "AI 生成作品每日排名"
        case .matureAI: "成人向 AI 生成作品每日排名"
        case .matureDaily: "成人向作品每日排名"
        case .matureWeekly: "成人向作品每周排名"
        case .matureG: "高限制级作品每周排名"
        }
    }

    var systemImage: String {
        switch self {
        case .original: "paintbrush"
        case .rookie: "leaf"
        case .ai, .matureAI: "wand.and.stars"
        case .male, .female: "person.2"
        default: "trophy"
        }
    }

    var isMature: Bool {
        switch self {
        case .matureAI, .matureDaily, .matureWeekly, .matureG: true
        default: false
        }
    }
}

#Preview("排行榜预览") {
    NavigationStack {
        RankingView()
    }
    .withPreviewDependencies()
}
