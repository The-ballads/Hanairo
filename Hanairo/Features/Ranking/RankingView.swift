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
                    .padding(.top, 112)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await refresh()
                }
                .onChange(of: requestKey) { _, _ in
                    proxy.scrollTo(scrollTopID, anchor: .top)
                }
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        floatingModeSelector
                        floatingLatestButton
                    }

                    floatingDatePicker
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
            .glassEffect(.regular.interactive(), in: .capsule)
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

    private var floatingDatePicker: some View {
        HStack(spacing: 6) {
            yearMenu
            monthMenu
            dayMenu
        }
    }

    private var yearMenu: some View {
        Menu {
            ForEach(availableYears, id: \.self) { year in
                Button {
                    updateSelectedDate(year: year)
                } label: {
                    Label("\(year)年", systemImage: year == selectedYear ? "checkmark" : "calendar")
                }
            }
        } label: {
            dateMenuLabel("\(selectedYear)年")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择年份")
    }

    private var monthMenu: some View {
        Menu {
            ForEach(availableMonths, id: \.self) { month in
                Button {
                    updateSelectedDate(month: month)
                } label: {
                    Label("\(month)月", systemImage: month == selectedMonth ? "checkmark" : "calendar")
                }
            }
        } label: {
            dateMenuLabel("\(selectedMonth)月")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择月份")
    }

    private var dayMenu: some View {
        Menu {
            ForEach(availableDays, id: \.self) { day in
                Button {
                    updateSelectedDate(day: day)
                } label: {
                    Label("\(day)日", systemImage: day == selectedDay ? "checkmark" : "calendar")
                }
            }
        } label: {
            dateMenuLabel("\(selectedDay)日")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择日期")
    }

    private func dateMenuLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var selectedYear: Int {
        Calendar.current.component(.year, from: selectedDate)
    }

    private var selectedMonth: Int {
        Calendar.current.component(.month, from: selectedDate)
    }

    private var selectedDay: Int {
        Calendar.current.component(.day, from: selectedDate)
    }

    private var availableYears: [Int] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        return Array((currentYear - 19)...currentYear).reversed()
    }

    private var availableMonths: [Int] {
        let calendar = Calendar.current
        if selectedYear == calendar.component(.year, from: Date()) {
            return Array(1...calendar.component(.month, from: Date()))
        }
        return Array(1...12)
    }

    private var availableDays: [Int] {
        let calendar = Calendar.current
        let maxDay = daysInMonth(year: selectedYear, month: selectedMonth)
        if
            selectedYear == calendar.component(.year, from: Date()),
            selectedMonth == calendar.component(.month, from: Date())
        {
            return Array(1...min(maxDay, calendar.component(.day, from: Date())))
        }
        return Array(1...maxDay)
    }

    private func daysInMonth(year: Int, month: Int) -> Int {
        let calendar = Calendar.current
        let components = DateComponents(year: year, month: month, day: 1)
        guard let date = calendar.date(from: components) else { return 30 }
        return calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    private func updateSelectedDate(
        year: Int? = nil,
        month: Int? = nil,
        day: Int? = nil
    ) {
        let calendar = Calendar.current
        let newYear = year ?? selectedYear
        let newMonth = month ?? selectedMonth
        let maxDay = daysInMonth(year: newYear, month: newMonth)
        let newDay = min(day ?? selectedDay, maxDay)
        let components = DateComponents(year: newYear, month: newMonth, day: newDay)
        guard let date = calendar.date(from: components) else { return }
        withAnimation(.snappy) {
            selectedDate = min(date, Date())
        }
    }

    private var floatingLatestButton: some View {
        Button {
            withAnimation(.snappy) {
                selectedDate = Date()
            }
            Task {
                await feed.reload(requestKey: requestKey, showsInitialLoading: true) {
                    try await repository.ranking(mode: mode.rawValue, date: effectiveDate)
                }
            }
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("使用最新排行")
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

    private var effectiveDate: Date? {
        Calendar.current.isDateInToday(selectedDate) ? nil : selectedDate
    }

    private var requestKey: String {
        "\(mode.rawValue)-\(selectedDate.timeIntervalSinceReferenceDate)-\(authentication.userID ?? 0)"
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
        let activeDate = effectiveDate
        await feed.loadIfNeeded(requestKey: activeRequestKey) {
            try await repository.ranking(mode: activeMode, date: activeDate)
        }
    }

    private func refresh() async {
        let activeRequestKey = requestKey
        let activeMode = mode.rawValue
        let activeDate = effectiveDate
        await feed.reload(requestKey: activeRequestKey, showsInitialLoading: false) {
            try await repository.ranking(mode: activeMode, date: activeDate)
        }
    }

    private func retry() async {
        let activeRequestKey = requestKey
        let activeMode = mode.rawValue
        let activeDate = effectiveDate
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
