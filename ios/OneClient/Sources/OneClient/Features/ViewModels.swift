import Foundation
import Combine
import SwiftUI

private func userFacingError(_ error: Error) -> String {
    if let apiError = error as? APIError {
        switch apiError {
        case .unauthorized:
            return "Session ended on this device. Continue to resume your saved profile."
        case .transport:
            let environment = AppEnvironment.current()
            switch environment.runtimeMode {
            case .local:
                return "Local data store is unavailable. Restart the app and try again."
            case .remote:
                return "Backend unreachable at \(environment.apiBaseURL.absoluteString). Check API URL and network connection."
            }
        case .server(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .decoding:
            return "Received an unexpected response. Please update the app or try again."
        case .conflict:
            return "Data conflict detected. Reloading your latest data."
        }
    }
    return String(describing: error)
}

@MainActor
public final class AuthViewModel: ObservableObject {
    @Published public private(set) var user: User?
    @Published public private(set) var localProfileCandidate: User?
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private let repository: AuthRepository

    public init(repository: AuthRepository) {
        self.repository = repository
    }

    public func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        user = await repository.restoreSession()
        localProfileCandidate = user == nil ? await repository.localProfileCandidate() : nil
        errorMessage = nil
    }

    public func login(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            user = try await repository.login(email: email, password: password)
            localProfileCandidate = nil
            errorMessage = nil
        } catch {
            errorMessage = userFacingError(error)
        }
    }

    public func signup(email: String, password: String, displayName: String, timezone: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            user = try await repository.signup(
                email: email,
                password: password,
                displayName: displayName,
                timezone: timezone
            )
            localProfileCandidate = nil
            errorMessage = nil
        } catch {
            errorMessage = userFacingError(error)
        }
    }

    public func createLocalProfile(displayName: String) async {
        let slug = displayName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "-")
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let localPart = slug.isEmpty ? "local-user" : slug
        await signup(
            email: "\(localPart)@one.local",
            password: "offline-local-profile",
            displayName: displayName,
            timezone: TimeZone.autoupdatingCurrent.identifier
        )
    }

    public func logout() async {
        await repository.logout()
        user = nil
        localProfileCandidate = await repository.localProfileCandidate()
        errorMessage = nil
    }

    public func resumeLocalProfile() async {
        isLoading = true
        defer { isLoading = false }
        if let candidate = await repository.localProfileCandidate() {
            do {
                user = try await repository.login(email: candidate.email, password: "")
                localProfileCandidate = nil
                errorMessage = nil
            } catch {
                user = nil
                localProfileCandidate = await repository.localProfileCandidate()
                errorMessage = userFacingError(error)
            }
            return
        }

        user = await repository.restoreSession()
        localProfileCandidate = user == nil ? await repository.localProfileCandidate() : nil
        errorMessage = user == nil ? "Unable to resume your saved profile." : nil
    }
}

@MainActor
public protocol NotificationScheduleRefresher {
    func refreshSchedules() async
}

@MainActor
public struct NoopNotificationScheduleRefresher: NotificationScheduleRefresher {
    public init() {}

    public func refreshSchedules() async {}
}

@MainActor
public final class TasksViewModel: ObservableObject {
    @Published public private(set) var categories: [Category] = []
    @Published public private(set) var habits: [Habit] = []
    @Published public private(set) var todos: [Todo] = []
    @Published public private(set) var errorMessage: String?

    private let repository: TasksRepository
    private let scheduleRefresher: NotificationScheduleRefresher

    public init(
        repository: TasksRepository,
        scheduleRefresher: NotificationScheduleRefresher = NoopNotificationScheduleRefresher()
    ) {
        self.repository = repository
        self.scheduleRefresher = scheduleRefresher
    }

    public func loadCategories() async {
        do {
            let loadedCategories = try await repository.loadCategories()
            withAnimation(OneMotion.animation(.calmRefresh)) {
                categories = loadedCategories
            }
            errorMessage = nil
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
        }
    }

    public func loadTasks() async {
        do {
            async let loadedHabits = repository.loadHabits()
            async let loadedTodos = repository.loadTodos()
            let nextHabits = try await loadedHabits
            let nextTodos = try await loadedTodos
            withAnimation(OneMotion.animation(.calmRefresh)) {
                habits = nextHabits
                todos = nextTodos
            }
            errorMessage = nil
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
        }
    }

    public func createHabit(input: HabitCreateInput) async -> Habit? {
        do {
            let created = try await repository.createHabit(input)
            withAnimation(OneMotion.animation(.stateChange)) {
                habits.append(created)
            }
            await scheduleRefresher.refreshSchedules()
            OneHaptics.shared.trigger(.saveSucceeded)
            OneSyncFeedbackCenter.shared.showSynced(
                title: "Habit added",
                message: "\(created.title) is ready for Today."
            )
            errorMessage = nil
            return created
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
            return nil
        }
    }

    public func createTodo(input: TodoCreateInput) async -> Todo? {
        do {
            let created = try await repository.createTodo(input)
            withAnimation(OneMotion.animation(.stateChange)) {
                todos.append(created)
            }
            await scheduleRefresher.refreshSchedules()
            OneHaptics.shared.trigger(.saveSucceeded)
            OneSyncFeedbackCenter.shared.showSynced(
                title: "Task added",
                message: "\(created.title) was added to your queue."
            )
            errorMessage = nil
            return created
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
            return nil
        }
    }

    public func updateHabit(id: String, input: HabitUpdateInput) async -> Habit? {
        do {
            let updated = try await repository.updateHabit(id: id, input: input, clientUpdatedAt: Date())
            if let index = habits.firstIndex(where: { $0.id == id }) {
                withAnimation(OneMotion.animation(.stateChange)) {
                    habits[index] = updated
                }
            }
            await scheduleRefresher.refreshSchedules()
            OneHaptics.shared.trigger(.saveSucceeded)
            OneSyncFeedbackCenter.shared.showSynced(
                title: "Habit saved",
                message: "\(updated.title) stays aligned with Today."
            )
            errorMessage = nil
            return updated
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
            return nil
        }
    }

    public func updateTodo(id: String, input: TodoUpdateInput) async -> Todo? {
        do {
            let updated = try await repository.updateTodo(id: id, input: input, clientUpdatedAt: Date())
            if let index = todos.firstIndex(where: { $0.id == id }) {
                withAnimation(OneMotion.animation(.stateChange)) {
                    todos[index] = updated
                }
            }
            await scheduleRefresher.refreshSchedules()
            OneHaptics.shared.trigger(.saveSucceeded)
            OneSyncFeedbackCenter.shared.showSynced(
                title: "Task saved",
                message: "\(updated.title) was updated."
            )
            errorMessage = nil
            return updated
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
            return nil
        }
    }

    public func deleteHabit(id: String) async -> Bool {
        do {
            try await repository.deleteHabit(id: id)
            withAnimation(OneMotion.animation(.dismiss)) {
                habits.removeAll { $0.id == id }
            }
            await scheduleRefresher.refreshSchedules()
            OneHaptics.shared.trigger(.destructiveConfirmed)
            errorMessage = nil
            return true
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
            return false
        }
    }

    public func deleteTodo(id: String) async -> Bool {
        do {
            try await repository.deleteTodo(id: id)
            withAnimation(OneMotion.animation(.dismiss)) {
                todos.removeAll { $0.id == id }
            }
            await scheduleRefresher.refreshSchedules()
            OneHaptics.shared.trigger(.destructiveConfirmed)
            errorMessage = nil
            return true
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
            return false
        }
    }

    public func loadHabitStats(habitId: String, anchorDate: String? = nil, windowDays: Int? = nil) async -> HabitStats? {
        do {
            let stats = try await repository.loadHabitStats(habitId: habitId, anchorDate: anchorDate, windowDays: windowDays)
            errorMessage = nil
            return stats
        } catch {
            errorMessage = userFacingError(error)
            return nil
        }
    }
}

@MainActor
public final class TodayViewModel: ObservableObject {
    @Published public private(set) var dateLocal: String = ""
    @Published public private(set) var items: [TodayItem] = []
    @Published public private(set) var completedCount: Int = 0
    @Published public private(set) var totalCount: Int = 0
    @Published public private(set) var completionRatio: Double = 0
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var highlightedItemID: String?
    @Published public private(set) var milestoneCount = 0

    private let repository: TodayRepository

    public init(repository: TodayRepository) {
        self.repository = repository
    }

    public func load(date: String? = nil) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await repository.loadToday(date: date)
            withAnimation(OneMotion.animation(.calmRefresh)) {
                dateLocal = response.dateLocal
                items = response.items
                completedCount = response.completedCount
                totalCount = response.totalCount
                completionRatio = response.completionRatio
            }
            errorMessage = nil
        } catch {
            errorMessage = userFacingError(error)
        }
    }

    public func toggle(item: TodayItem, dateLocal: String) async {
        let next: CompletionState = item.completed ? .notCompleted : .completed
        do {
            let response = try await repository.setCompletion(
                itemType: item.itemType,
                itemId: item.itemId,
                dateLocal: dateLocal,
                state: next
            )
            withAnimation(OneMotion.animation(next == .completed ? .stateChange : .dismiss)) {
                self.items = response.items
                self.completedCount = response.completedCount
                self.totalCount = response.totalCount
                self.completionRatio = response.completionRatio
                self.highlightedItemID = item.id
            }

            let completedDay = next == .completed && response.totalCount > 0 && response.completedCount == response.totalCount
            OneHaptics.shared.trigger(completedDay ? .milestoneReached : .completionCommitted)
            if completedDay {
                milestoneCount += 1
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.85))
                guard highlightedItemID == item.id else {
                    return
                }
                withAnimation(OneMotion.animation(.dismiss)) {
                    highlightedItemID = nil
                }
            }
            errorMessage = nil
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
        }
    }

    public func reorder(items reordered: [TodayItem], dateLocal: String) async {
        let order = reordered.enumerated().map {
            TodayOrderItem(itemType: $0.element.itemType, itemId: $0.element.itemId, orderIndex: $0.offset)
        }
        do {
            let response = try await repository.reorder(dateLocal: dateLocal, items: order)
            withAnimation(OneMotion.animation(.reorder)) {
                self.items = response.items
                self.completedCount = response.completedCount
                self.totalCount = response.totalCount
                self.completionRatio = response.completionRatio
            }
            OneHaptics.shared.trigger(.reorderDrop)
            errorMessage = nil
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
        }
    }

    public func highlight(itemType: ItemType, itemId: String) {
        let highlightID = "\(itemType.rawValue):\(itemId)"
        withAnimation(OneMotion.animation(.stateChange)) {
            highlightedItemID = highlightID
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard highlightedItemID == highlightID else {
                return
            }
            withAnimation(OneMotion.animation(.dismiss)) {
                highlightedItemID = nil
            }
        }
    }
}

public enum AnalyticsActivityFilter: String, CaseIterable, Sendable {
    case all
    case habits
    case todos

    public var title: String {
        switch self {
        case .all:
            return "All"
        case .habits:
            return "Habits"
        case .todos:
            return "Tasks"
        }
    }
}

public struct AnalyticsChartSeries: Sendable, Equatable {
    public let values: [Double]
    public let labels: [String]

    public init(values: [Double] = [], labels: [String] = []) {
        self.values = values
        self.labels = labels
    }
}

public struct AnalyticsContributionDayCell: Sendable, Equatable, Identifiable {
    public let dateLocal: String
    public let dayNumber: Int
    public let completionRate: Double
    public let hasSummary: Bool

    public var id: String { dateLocal }
}

public struct AnalyticsContributionMonthSection: Sendable, Equatable, Identifiable {
    public let month: Int
    public let label: String
    public let completedItems: Int
    public let expectedItems: Int
    public let leadingPlaceholders: Int
    public let days: [AnalyticsContributionDayCell]

    public var id: Int { month }
}

public struct AnalyticsSentimentDistributionItem: Sendable, Equatable, Identifiable {
    public let sentiment: ReflectionSentiment
    public let count: Int

    public var id: ReflectionSentiment { sentiment }
}

public struct AnalyticsSentimentTrendPoint: Sendable, Equatable, Identifiable {
    public let label: String
    public let sentiment: ReflectionSentiment?
    public let dateLocal: String?

    public var id: String { dateLocal ?? label }
}

public struct AnalyticsSentimentOverview: Sendable, Equatable {
    public let dominant: ReflectionSentiment?
    public let distribution: [AnalyticsSentimentDistributionItem]
    public let trend: [AnalyticsSentimentTrendPoint]
}

public struct AnalyticsMonthWeekBucket: Sendable, Equatable, Identifiable {
    public let week: Int
    public let title: String
    public let shortLabel: String
    public let completionRate: Double
    public let startDate: String
    public let endDate: String

    public var id: Int { week }
}

public struct AnalyticsExecutionSplitRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let completedItems: Int
    public let expectedItems: Int
    public let completionRate: Double

    public init(id: String, title: String, completedItems: Int, expectedItems: Int, completionRate: Double) {
        self.id = id
        self.title = title
        self.completedItems = completedItems
        self.expectedItems = expectedItems
        self.completionRate = completionRate
    }
}

public struct AnalyticsRecoveryRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let completedItems: Int
    public let expectedItems: Int
    public let gap: Int
    public let completionRate: Double

    public init(
        id: String,
        label: String,
        completedItems: Int,
        expectedItems: Int,
        gap: Int,
        completionRate: Double
    ) {
        self.id = id
        self.label = label
        self.completedItems = completedItems
        self.expectedItems = expectedItems
        self.gap = gap
        self.completionRate = completionRate
    }
}

public struct NotesDayOption: Sendable, Equatable, Identifiable {
    public let dateLocal: String
    public let weekdayLabel: String
    public let dayNumber: Int
    public let sentiment: ReflectionSentiment?
    public let hasNotes: Bool

    public var id: String { dateLocal }
}

public struct NotesMonthOption: Sendable, Equatable, Identifiable {
    public let month: Int
    public let label: String
    public let noteCount: Int
    public let dominant: ReflectionSentiment?

    public var id: Int { month }
}

public struct NotesSentimentSummary: Sendable, Equatable {
    public let noteCount: Int
    public let activeDays: Int
    public let dominant: ReflectionSentiment?
    public let distribution: [AnalyticsSentimentDistributionItem]
}

struct ReflectionSentimentVoteSummary: Sendable, Equatable {
    let dominant: ReflectionSentiment?
    let distribution: [AnalyticsSentimentDistributionItem]
}

func reflectionNoteSort(lhs: ReflectionNote, rhs: ReflectionNote) -> Bool {
    let lhsDate = lhs.updatedAt ?? lhs.createdAt ?? .distantPast
    let rhsDate = rhs.updatedAt ?? rhs.createdAt ?? .distantPast
    if lhsDate != rhsDate {
        return lhsDate > rhsDate
    }
    return lhs.id > rhs.id
}

func reflectionSentimentSummary(for notes: [ReflectionNote]) -> ReflectionSentimentVoteSummary {
    guard !notes.isEmpty else {
        return ReflectionSentimentVoteSummary(dominant: nil, distribution: [])
    }

    let sortedNotes = notes.sorted(by: reflectionNoteSort(lhs:rhs:))
    let counts = sortedNotes.reduce(into: [ReflectionSentiment: Int]()) { partial, note in
        partial[note.sentiment, default: 0] += 1
    }
    let maxCount = counts.values.max() ?? 0
    let tiedSentiments = Set(
        counts.compactMap { sentiment, count in
            count == maxCount ? sentiment : nil
        }
    )
    let dominant = sortedNotes.first(where: { tiedSentiments.contains($0.sentiment) })?.sentiment
    let distribution: [AnalyticsSentimentDistributionItem] = ReflectionSentiment.allCases.compactMap { sentiment -> AnalyticsSentimentDistributionItem? in
        let count = counts[sentiment, default: 0]
        guard count > 0 else {
            return nil
        }
        return AnalyticsSentimentDistributionItem(sentiment: sentiment, count: count)
    }

    return ReflectionSentimentVoteSummary(
        dominant: dominant,
        distribution: distribution
    )
}

private struct AnalyticsRawPeriodData: Sendable {
    let summary: PeriodSummary
    let dailySummaries: [DailySummary]
}

private struct AnalyticsPresentation: Sendable {
    let summary: PeriodSummary
    let dailySummaries: [DailySummary]
    let chartSeries: AnalyticsChartSeries
    let contributionSections: [AnalyticsContributionMonthSection]
    let monthWeekBuckets: [AnalyticsMonthWeekBucket]
    let executionRows: [AnalyticsExecutionSplitRow]
    let recoveryRows: [AnalyticsRecoveryRow]
}

private struct AnalyticsPeriodCacheKey: Hashable {
    let anchorDate: String
    let periodType: PeriodType
    let weekStart: Int
}

private struct AnalyticsPresentationCacheKey: Hashable {
    let periodKey: AnalyticsPeriodCacheKey
    let filter: AnalyticsActivityFilter
}

@MainActor
public final class AnalyticsViewModel: ObservableObject {
    @Published public var selectedPeriod: PeriodType = .weekly
    @Published public var selectedActivityFilter: AnalyticsActivityFilter = .all
    @Published public private(set) var pendingPeriod: PeriodType?
    @Published public private(set) var summary: PeriodSummary?
    @Published public private(set) var weekly: PeriodSummary?
    @Published public private(set) var dailySummaries: [DailySummary] = []
    @Published public private(set) var weeklyDailySummaries: [DailySummary] = []
    @Published public private(set) var chartSeries = AnalyticsChartSeries()
    @Published public private(set) var contributionSections: [AnalyticsContributionMonthSection] = []
    @Published public private(set) var monthWeekBuckets: [AnalyticsMonthWeekBucket] = []
    @Published public private(set) var selectedMonthWeek: Int?
    @Published public private(set) var sentimentOverview: AnalyticsSentimentOverview?
    @Published public private(set) var executionRows: [AnalyticsExecutionSplitRow] = []
    @Published public private(set) var recoveryRows: [AnalyticsRecoveryRow] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isTransitioning = false
    @Published public private(set) var isSwitchingPeriod = false

    private let repository: AnalyticsRepository
    private let reflectionsRepository: ReflectionsRepository
    private var rawPeriodCache: [AnalyticsPeriodCacheKey: AnalyticsRawPeriodData] = [:]
    private var presentationCache: [AnalyticsPresentationCacheKey: AnalyticsPresentation] = [:]
    private var currentPeriodKey: AnalyticsPeriodCacheKey?
    private var weeklyPeriodKey: AnalyticsPeriodCacheKey?
    private var rawDailyNotes: [ReflectionNote] = []
    private var activePeriodLoadTask: Task<(AnalyticsRawPeriodData, [ReflectionNote]), Error>?
    private var activePeriodLoadID = UUID()

    public init(
        repository: AnalyticsRepository,
        reflectionsRepository: ReflectionsRepository = NoopReflectionsRepository()
    ) {
        self.repository = repository
        self.reflectionsRepository = reflectionsRepository
    }

    public var selectedMonthWeekDetailLabel: String? {
        guard selectedPeriod == .monthly,
              let selectedMonthWeek,
              let bucket = monthWeekBuckets.first(where: { $0.week == selectedMonthWeek }) else {
            return nil
        }
        return "\(bucket.title) · Days \(OneDate.dayNumber(from: bucket.startDate))-\(OneDate.dayNumber(from: bucket.endDate))"
    }

    public func selectActivityFilter(_ filter: AnalyticsActivityFilter) {
        withAnimation(OneMotion.animation(.stateChange)) {
            selectedActivityFilter = filter
            applyActivityFilter()
        }
        OneHaptics.shared.trigger(.selectionChanged)
    }

    public func selectMonthWeek(_ week: Int) {
        withAnimation(OneMotion.animation(.stateChange)) {
            selectedMonthWeek = week
            applyActivityFilter()
        }
        OneHaptics.shared.trigger(.selectionChanged)
    }

    public func loadWeekly(anchorDate: String, weekStart: Int = 0) async {
        let key = AnalyticsPeriodCacheKey(anchorDate: anchorDate, periodType: .weekly, weekStart: weekStart)
        isTransitioning = true
        defer { isTransitioning = false }
        do {
            let rawData: AnalyticsRawPeriodData
            if let cached = rawPeriodCache[key] {
                rawData = cached
            } else {
                let bounds = AnalyticsDateRange.bounds(anchorDate: anchorDate, periodType: .weekly, weekStart: weekStart)
                async let loadedSummary = repository.loadPeriod(anchorDate: anchorDate, periodType: .weekly)
                async let loadedDaily = repository.loadDaily(startDate: bounds.startDate, endDate: bounds.endDate)
                rawData = try await AnalyticsRawPeriodData(
                    summary: loadedSummary,
                    dailySummaries: loadedDaily
                )
                rawPeriodCache[key] = rawData
            }

            rawDailyNotes = try await reflectionsRepository.list(periodType: .daily)
            presentationCache = presentationCache.filter { $0.key.periodKey != key }
            weeklyPeriodKey = key
            let weeklyPresentation = presentation(for: rawData, key: key)
            withAnimation(OneMotion.animation(.calmRefresh)) {
                weeklyDailySummaries = weeklyPresentation.dailySummaries
                weekly = weeklyPresentation.summary
            }
            if selectedPeriod == .weekly {
                currentPeriodKey = key
                applyPresentation(weeklyPresentation, key: key)
            }
            errorMessage = nil
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
        }
    }

    public func loadPeriod(anchorDate: String, periodType: PeriodType, weekStart: Int = 0) async {
        let key = AnalyticsPeriodCacheKey(anchorDate: anchorDate, periodType: periodType, weekStart: weekStart)
        let cachedRawData = rawPeriodCache[key]
        let loadID = UUID()

        activePeriodLoadID = loadID
        activePeriodLoadTask?.cancel()
        pendingPeriod = periodType
        isSwitchingPeriod = true
        isTransitioning = true

        let repository = self.repository
        let reflectionsRepository = self.reflectionsRepository
        let task = Task<(AnalyticsRawPeriodData, [ReflectionNote]), Error> {
            let rawData: AnalyticsRawPeriodData
            if let cachedRawData {
                rawData = cachedRawData
            } else {
                let bounds = AnalyticsDateRange.bounds(anchorDate: anchorDate, periodType: periodType, weekStart: weekStart)
                async let loadedSummary = repository.loadPeriod(anchorDate: anchorDate, periodType: periodType)
                async let loadedDaily = repository.loadDaily(startDate: bounds.startDate, endDate: bounds.endDate)
                rawData = try await AnalyticsRawPeriodData(
                    summary: loadedSummary,
                    dailySummaries: loadedDaily
                )
            }

            let notes = try await reflectionsRepository.list(periodType: .daily)
            try Task.checkCancellation()
            return (rawData, notes)
        }

        activePeriodLoadTask = task

        do {
            let (rawData, notes) = try await task.value
            guard activePeriodLoadID == loadID else {
                return
            }

            if cachedRawData == nil {
                rawPeriodCache[key] = rawData
            }
            rawDailyNotes = notes
            presentationCache = presentationCache.filter { $0.key.periodKey != key }
            currentPeriodKey = key
            let currentPresentation = presentation(for: rawData, key: key)
            applyPresentation(currentPresentation, key: key, committedPeriod: periodType)
            if periodType == .weekly {
                weeklyPeriodKey = key
                weeklyDailySummaries = currentPresentation.dailySummaries
                weekly = currentPresentation.summary
            }

            pendingPeriod = nil
            isSwitchingPeriod = false
            isTransitioning = false
            OneHaptics.shared.trigger(.periodSwitched)
            errorMessage = nil
        } catch is CancellationError {
            guard activePeriodLoadID == loadID else {
                return
            }
            pendingPeriod = nil
            isSwitchingPeriod = false
            isTransitioning = false
        } catch {
            guard activePeriodLoadID == loadID else {
                return
            }
            pendingPeriod = nil
            isSwitchingPeriod = false
            isTransitioning = false
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
        }
    }

    private func applyActivityFilter() {
        if let key = currentPeriodKey,
           let rawData = rawPeriodCache[key] {
            let currentPresentation = presentation(for: rawData, key: key)
            applyPresentation(currentPresentation, key: key)
        }

        if let weeklyPeriodKey,
           let rawData = rawPeriodCache[weeklyPeriodKey] {
            let weeklyPresentation = presentation(for: rawData, key: weeklyPeriodKey)
            weeklyDailySummaries = weeklyPresentation.dailySummaries
            weekly = weeklyPresentation.summary
        }
    }

    private func presentation(for rawData: AnalyticsRawPeriodData, key: AnalyticsPeriodCacheKey) -> AnalyticsPresentation {
        let cacheKey = AnalyticsPresentationCacheKey(periodKey: key, filter: selectedActivityFilter)
        if let cached = presentationCache[cacheKey] {
            return cached
        }

        let filtered = filteredSummaries(from: rawData.dailySummaries)
        let summary = makeSummary(template: rawData.summary, summaries: rawData.dailySummaries) ?? rawData.summary
        let presentation = AnalyticsPresentation(
            summary: summary,
            dailySummaries: filtered,
            chartSeries: buildChartSeries(from: filtered, periodType: rawData.summary.periodType),
            contributionSections: buildContributionSections(from: filtered),
            monthWeekBuckets: buildMonthWeekBuckets(from: filtered),
            executionRows: buildExecutionRows(from: rawData.dailySummaries),
            recoveryRows: buildRecoveryRows(from: filtered, periodType: rawData.summary.periodType)
        )
        presentationCache[cacheKey] = presentation
        return presentation
    }

    private func applyPresentation(
        _ presentation: AnalyticsPresentation,
        key: AnalyticsPeriodCacheKey,
        committedPeriod: PeriodType? = nil
    ) {
        withAnimation(OneMotion.animation(.stateChange)) {
            if let committedPeriod {
                selectedPeriod = committedPeriod
            }
            summary = presentation.summary
            chartSeries = presentation.chartSeries
            executionRows = presentation.executionRows
            recoveryRows = presentation.recoveryRows

            switch key.periodType {
            case .monthly:
                monthWeekBuckets = presentation.monthWeekBuckets
                let defaultWeek = monthSegment(for: key.anchorDate)
                if let selectedMonthWeek,
                   monthWeekBuckets.contains(where: { $0.week == selectedMonthWeek }) {
                    self.selectedMonthWeek = selectedMonthWeek
                } else {
                    self.selectedMonthWeek = monthWeekBuckets.first(where: { $0.week == defaultWeek })?.week ?? monthWeekBuckets.first?.week
                }
                dailySummaries = monthlyDetailSummaries(from: presentation.dailySummaries)
                contributionSections = []
                sentimentOverview = buildSentimentOverview(key: key)
            case .yearly:
                monthWeekBuckets = []
                selectedMonthWeek = nil
                dailySummaries = presentation.dailySummaries
                contributionSections = presentation.contributionSections
                sentimentOverview = buildSentimentOverview(key: key)
            case .weekly:
                monthWeekBuckets = []
                selectedMonthWeek = nil
                dailySummaries = presentation.dailySummaries
                contributionSections = []
                sentimentOverview = buildSentimentOverview(key: key)
            case .daily:
                monthWeekBuckets = []
                selectedMonthWeek = nil
                dailySummaries = presentation.dailySummaries
                contributionSections = []
                sentimentOverview = buildSentimentOverview(key: key)
            }
        }
    }

    private func filteredSummaries(from summaries: [DailySummary]) -> [DailySummary] {
        guard selectedActivityFilter != .all else {
            return summaries
        }

        return summaries.map { summary in
            let completedItems: Int
            let expectedItems: Int
            switch selectedActivityFilter {
            case .all:
                completedItems = summary.completedItems
                expectedItems = summary.expectedItems
            case .habits:
                completedItems = summary.habitCompleted
                expectedItems = summary.habitExpected
            case .todos:
                completedItems = summary.todoCompleted
                expectedItems = summary.todoExpected
            }

            let completionRate = expectedItems == 0 ? 0 : Double(completedItems) / Double(expectedItems)
            return DailySummary(
                dateLocal: summary.dateLocal,
                completedItems: completedItems,
                expectedItems: expectedItems,
                completionRate: completionRate,
                habitCompleted: selectedActivityFilter == .todos ? 0 : summary.habitCompleted,
                habitExpected: selectedActivityFilter == .todos ? 0 : summary.habitExpected,
                todoCompleted: selectedActivityFilter == .habits ? 0 : summary.todoCompleted,
                todoExpected: selectedActivityFilter == .habits ? 0 : summary.todoExpected
            )
        }
    }

    private func makeSummary(template: PeriodSummary?, summaries: [DailySummary]) -> PeriodSummary? {
        guard let template else {
            return nil
        }
        guard selectedActivityFilter != .all else {
            return template
        }

        let filtered = filteredSummaries(from: summaries)
        let completedItems = filtered.reduce(0) { $0 + $1.completedItems }
        let expectedItems = filtered.reduce(0) { $0 + $1.expectedItems }
        let activeDays = filtered.filter { $0.expectedItems > 0 || $0.completedItems > 0 }.count
        let completionRate = expectedItems == 0 ? 0 : Double(completedItems) / Double(expectedItems)
        let consistencyScore = filtered.isEmpty ? 0 : Double(activeDays) / Double(filtered.count)

        return PeriodSummary(
            periodType: template.periodType,
            periodStart: template.periodStart,
            periodEnd: template.periodEnd,
            completedItems: completedItems,
            expectedItems: expectedItems,
            completionRate: completionRate,
            activeDays: activeDays,
            consistencyScore: consistencyScore
        )
    }

    private func buildChartSeries(from summaries: [DailySummary], periodType: PeriodType) -> AnalyticsChartSeries {
        switch periodType {
        case .weekly:
            return AnalyticsChartSeries(
                values: summaries.map(\.completionRate),
                labels: summaries.map { OneDate.shortWeekday(from: $0.dateLocal) }
            )
        case .monthly:
            let buckets = buildMonthWeekBuckets(from: summaries)
            return AnalyticsChartSeries(
                values: buckets.map(\.completionRate),
                labels: buckets.map(\.shortLabel)
            )
        case .yearly:
            let grouped = Dictionary(grouping: summaries) { OneDate.monthBucket(from: $0.dateLocal) }
            let keys = grouped.keys.sorted()
            return AnalyticsChartSeries(
                values: keys.map { key in
                    let entries = grouped[key] ?? []
                    let completed = Double(entries.reduce(0) { $0 + $1.completedItems })
                    let expected = Double(entries.reduce(0) { $0 + $1.expectedItems })
                    return expected == 0 ? 0 : completed / expected
                },
                labels: keys.map { OneDate.shortMonth(for: $0) }
            )
        case .daily:
            return AnalyticsChartSeries()
        }
    }

    private func buildExecutionRows(from summaries: [DailySummary]) -> [AnalyticsExecutionSplitRow] {
        let habitCompleted = summaries.reduce(0) { $0 + $1.habitCompleted }
        let habitExpected = summaries.reduce(0) { $0 + $1.habitExpected }
        let todoCompleted = summaries.reduce(0) { $0 + $1.todoCompleted }
        let todoExpected = summaries.reduce(0) { $0 + $1.todoExpected }

        return [
            AnalyticsExecutionSplitRow(
                id: "habits",
                title: "Habits",
                completedItems: habitCompleted,
                expectedItems: habitExpected,
                completionRate: habitExpected == 0 ? 0 : Double(habitCompleted) / Double(habitExpected)
            ),
            AnalyticsExecutionSplitRow(
                id: "tasks",
                title: "Tasks",
                completedItems: todoCompleted,
                expectedItems: todoExpected,
                completionRate: todoExpected == 0 ? 0 : Double(todoCompleted) / Double(todoExpected)
            ),
        ]
    }

    private func buildRecoveryRows(from summaries: [DailySummary], periodType: PeriodType) -> [AnalyticsRecoveryRow] {
        let rows: [AnalyticsRecoveryRow]

        switch periodType {
        case .daily:
            rows = summaries.prefix(1).map {
                makeRecoveryRow(
                    id: $0.dateLocal,
                    label: OneDate.shortMonthDay(from: $0.dateLocal),
                    completedItems: $0.completedItems,
                    expectedItems: $0.expectedItems
                )
            }
        case .weekly:
            rows = summaries.map {
                makeRecoveryRow(
                    id: $0.dateLocal,
                    label: OneDate.shortWeekday(from: $0.dateLocal),
                    completedItems: $0.completedItems,
                    expectedItems: $0.expectedItems
                )
            }
        case .monthly:
            let grouped = Dictionary(grouping: summaries) { monthSegment(for: $0.dateLocal) }
            rows = grouped.keys.sorted().map { week in
                let entries = grouped[week] ?? []
                return makeRecoveryRow(
                    id: "week-\(week)",
                    label: "Week \(week)",
                    completedItems: entries.reduce(0) { $0 + $1.completedItems },
                    expectedItems: entries.reduce(0) { $0 + $1.expectedItems }
                )
            }
        case .yearly:
            let grouped = Dictionary(grouping: summaries) { OneDate.monthBucket(from: $0.dateLocal) }
            rows = grouped.keys.sorted().map { month in
                let entries = grouped[month] ?? []
                return makeRecoveryRow(
                    id: "month-\(month)",
                    label: OneDate.shortMonth(for: month),
                    completedItems: entries.reduce(0) { $0 + $1.completedItems },
                    expectedItems: entries.reduce(0) { $0 + $1.expectedItems }
                )
            }
        }

        return rows
            .filter { $0.expectedItems > 0 || $0.completedItems > 0 }
            .sorted { lhs, rhs in
                if lhs.gap != rhs.gap {
                    return lhs.gap > rhs.gap
                }
                if lhs.completionRate != rhs.completionRate {
                    return lhs.completionRate < rhs.completionRate
                }
                return lhs.label < rhs.label
            }
            .prefix(4)
            .map { $0 }
    }

    private func makeRecoveryRow(
        id: String,
        label: String,
        completedItems: Int,
        expectedItems: Int
    ) -> AnalyticsRecoveryRow {
        let gap = max(expectedItems - completedItems, 0)
        let completionRate = expectedItems == 0 ? 0 : Double(completedItems) / Double(expectedItems)
        return AnalyticsRecoveryRow(
            id: id,
            label: label,
            completedItems: completedItems,
            expectedItems: expectedItems,
            gap: gap,
            completionRate: completionRate
        )
    }

    private func buildMonthWeekBuckets(from summaries: [DailySummary]) -> [AnalyticsMonthWeekBucket] {
        guard let firstDate = summaries.first?.dateLocal,
              let year = OneDate.year(from: firstDate),
              let month = Optional(OneDate.monthBucket(from: firstDate)) else {
            return []
        }

        let daysInMonth = OneDate.numberOfDays(inMonth: month, year: year)
        let totalWeeks = max(1, ((daysInMonth - 1) / 7) + 1)
        let grouped = Dictionary(grouping: summaries) { monthSegment(for: $0.dateLocal) }

        return (1...totalWeeks).map { week in
            let entries = grouped[week] ?? []
            let completed = Double(entries.reduce(0) { $0 + $1.completedItems })
            let expected = Double(entries.reduce(0) { $0 + $1.expectedItems })
            let startDay = ((week - 1) * 7) + 1
            let endDay = min(startDay + 6, daysInMonth)
            return AnalyticsMonthWeekBucket(
                week: week,
                title: "Week \(week)",
                shortLabel: "W\(week)",
                completionRate: expected == 0 ? 0 : completed / expected,
                startDate: String(format: "%04d-%02d-%02d", year, month, startDay),
                endDate: String(format: "%04d-%02d-%02d", year, month, endDay)
            )
        }
    }

    private func buildContributionSections(from summaries: [DailySummary]) -> [AnalyticsContributionMonthSection] {
        let year = summaries.compactMap { OneDate.year(from: $0.dateLocal) }.first ?? OneDate.year(from: OneDate.isoDate()) ?? 2026
        return (1...12).map { month in
            let monthSummaries = summaries.filter { OneDate.monthBucket(from: $0.dateLocal) == month }
            let byDate = Dictionary(uniqueKeysWithValues: monthSummaries.map { ($0.dateLocal, $0) })
            let firstDate = OneDate.calendarDate(for: String(format: "%04d-%02d-01", year, month))
            let leadingPlaceholders = firstDate.map { OneDate.canonicalWeekdayIndex(for: $0) } ?? 0
            let daysInMonth = OneDate.numberOfDays(inMonth: month, year: year)
            let cells = (1...daysInMonth).map { day -> AnalyticsContributionDayCell in
                let dateLocal = String(format: "%04d-%02d-%02d", year, month, day)
                let summary = byDate[dateLocal]
                return AnalyticsContributionDayCell(
                    dateLocal: dateLocal,
                    dayNumber: day,
                    completionRate: summary?.completionRate ?? 0,
                    hasSummary: summary != nil
                )
            }
            return AnalyticsContributionMonthSection(
                month: month,
                label: OneDate.shortMonth(for: month),
                completedItems: monthSummaries.reduce(0) { $0 + $1.completedItems },
                expectedItems: monthSummaries.reduce(0) { $0 + $1.expectedItems },
                leadingPlaceholders: leadingPlaceholders,
                days: cells
            )
        }
    }

    private func monthlyDetailSummaries(from summaries: [DailySummary]) -> [DailySummary] {
        guard let selectedMonthWeek else {
            return summaries
        }
        return summaries.filter { monthSegment(for: $0.dateLocal) == selectedMonthWeek }
    }

    private func buildSentimentOverview(key: AnalyticsPeriodCacheKey) -> AnalyticsSentimentOverview? {
        let dates = sentimentDates(for: key)
        let dateSet = Set(dates)
        let visibleNotes = rawDailyNotes.filter { $0.periodType == .daily && dateSet.contains($0.periodStart) }
        let groupedNotes = Dictionary(grouping: visibleNotes, by: \.periodStart)
        let overallSummary = reflectionSentimentSummary(for: visibleNotes)
        guard !visibleNotes.isEmpty else {
            return nil
        }

        let trend: [AnalyticsSentimentTrendPoint]
        switch key.periodType {
        case .weekly, .monthly:
            trend = dates.map { dateLocal in
                let daySummary = reflectionSentimentSummary(for: groupedNotes[dateLocal] ?? [])
                return AnalyticsSentimentTrendPoint(
                    label: key.periodType == .weekly ? OneDate.shortWeekday(from: dateLocal) : OneDate.dayNumber(from: dateLocal),
                    sentiment: daySummary.dominant,
                    dateLocal: dateLocal
                )
            }
        case .yearly:
            let notesByMonth = Dictionary(grouping: visibleNotes) { OneDate.monthBucket(from: $0.periodStart) }
            trend = (1...12).map { month in
                let monthLabel = OneDate.shortMonth(for: month)
                let dominantMonth = reflectionSentimentSummary(for: notesByMonth[month] ?? []).dominant
                return AnalyticsSentimentTrendPoint(label: monthLabel, sentiment: dominantMonth, dateLocal: nil)
            }
        case .daily:
            guard let dateLocal = dates.first else {
                return nil
            }
            let sentiment = reflectionSentimentSummary(for: groupedNotes[dateLocal] ?? []).dominant
            trend = [
                AnalyticsSentimentTrendPoint(
                    label: OneDate.dayNumber(from: dateLocal),
                    sentiment: sentiment,
                    dateLocal: dateLocal
                )
            ]
        }

        return AnalyticsSentimentOverview(
            dominant: overallSummary.dominant,
            distribution: overallSummary.distribution,
            trend: trend
        )
    }

    private func monthSegment(for isoDateString: String) -> Int {
        let day = Int(OneDate.dayNumber(from: isoDateString)) ?? 1
        return max(1, ((day - 1) / 7) + 1)
    }

    private func sentimentDates(for key: AnalyticsPeriodCacheKey) -> [String] {
        switch key.periodType {
        case .daily:
            return [key.anchorDate]
        case .weekly, .monthly, .yearly:
            let bounds = AnalyticsDateRange.bounds(
                anchorDate: key.anchorDate,
                periodType: key.periodType,
                weekStart: key.weekStart
            )
            return sequenceDates(startDate: bounds.startDate, endDate: bounds.endDate)
        }
    }

    private func sequenceDates(startDate: String, endDate: String) -> [String] {
        guard let start = OneDate.calendarDate(for: startDate),
              let end = OneDate.calendarDate(for: endDate) else {
            return []
        }

        return stride(from: start, through: end, by: 86_400).map { date in
            AnalyticsDateRange.isoDate(date)
        }
    }

}

public enum AnalyticsDateRange {
    public static func bounds(anchorDate: String, periodType: PeriodType, weekStart: Int) -> (startDate: String, endDate: String) {
        guard let anchor = isoDateFormatter.date(from: anchorDate) else {
            return (anchorDate, anchorDate)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        switch periodType {
        case .daily:
            return (anchorDate, anchorDate)
        case .weekly:
            let weekday = calendar.component(.weekday, from: anchor)
            let normalizedWeekday = (weekday + 5) % 7
            let offset = (normalizedWeekday - weekStart + 7) % 7
            let start = calendar.date(byAdding: .day, value: -offset, to: anchor) ?? anchor
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return (isoDateFormatter.string(from: start), isoDateFormatter.string(from: end))
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: anchor)
            let start = calendar.date(from: components) ?? anchor
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? anchor
            return (isoDateFormatter.string(from: start), isoDateFormatter.string(from: end))
        case .yearly:
            let year = calendar.component(.year, from: anchor)
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? anchor
            let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? anchor
            return (isoDateFormatter.string(from: start), isoDateFormatter.string(from: end))
        }
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func isoDate(_ date: Date) -> String {
        isoDateFormatter.string(from: date)
    }
}

@MainActor
public final class CoachViewModel: ObservableObject {
    @Published public private(set) var cards: [CoachCard] = []
    @Published public private(set) var errorMessage: String?

    private let repository: CoachRepository

    public init(repository: CoachRepository) {
        self.repository = repository
    }

    public func load() async {
        do {
            let loadedCards = try await repository.loadCards()
            withAnimation(OneMotion.animation(.calmRefresh)) {
                cards = loadedCards
            }
            errorMessage = nil
        } catch {
            errorMessage = userFacingError(error)
        }
    }
}

@MainActor
public final class ReflectionsViewModel: ObservableObject {
    @Published public private(set) var notes: [ReflectionNote] = []
    @Published public private(set) var errorMessage: String?

    private let repository: ReflectionsRepository

    public init(repository: ReflectionsRepository) {
        self.repository = repository
    }

    public func load(periodType: PeriodType? = nil) async {
        do {
            let loadedNotes = try await repository.list(periodType: periodType)
            withAnimation(OneMotion.animation(.calmRefresh)) {
                notes = loadedNotes
            }
            errorMessage = nil
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
        }
    }

    public func upsert(input: ReflectionWriteInput) async -> ReflectionNote? {
        do {
            let note = try await repository.upsert(input: input)
            withAnimation(OneMotion.animation(.stateChange)) {
                if let index = notes.firstIndex(where: { $0.id == note.id }) {
                    notes[index] = note
                } else {
                    notes.insert(note, at: 0)
                }
            }
            OneHaptics.shared.trigger(.saveSucceeded)
            errorMessage = nil
            return note
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
            return nil
        }
    }

    public func delete(id: String) async -> Bool {
        do {
            try await repository.delete(id: id)
            withAnimation(OneMotion.animation(.dismiss)) {
                notes.removeAll { $0.id == id }
            }
            OneHaptics.shared.trigger(.destructiveConfirmed)
            errorMessage = nil
            return true
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
            return false
        }
    }

}

@MainActor
public final class NotesViewModel: ObservableObject {
    @Published public var selectedPeriod: PeriodType = .daily
    @Published public private(set) var anchorDate: String = OneDate.isoDate()
    @Published public private(set) var selectedDateLocal: String = OneDate.isoDate()
    @Published public private(set) var selectedYearMonth: Int = OneDate.monthBucket(from: OneDate.isoDate())
    @Published public private(set) var dayOptions: [NotesDayOption] = []
    @Published public private(set) var monthOptions: [NotesMonthOption] = []
    @Published public private(set) var selectedDayNotes: [ReflectionNote] = []
    @Published public private(set) var sentimentSummary: NotesSentimentSummary?
    @Published public private(set) var leadingPlaceholders: Int = 0
    @Published public private(set) var allNotes: [ReflectionNote] = []
    @Published public private(set) var errorMessage: String?

    private let repository: ReflectionsRepository
    private var weekStart: Int = 0

    public init(repository: ReflectionsRepository) {
        self.repository = repository
    }

    public var currentYear: Int {
        OneDate.year(from: anchorDate) ?? OneDate.year(from: OneDate.isoDate()) ?? 2026
    }

    public var selectedDayTitle: String {
        OneDate.longDate(from: selectedDateLocal)
    }

    public var currentRangeTitle: String {
        switch selectedPeriod {
        case .daily:
            return selectedDayTitle
        case .weekly:
            let bounds = AnalyticsDateRange.bounds(anchorDate: selectedDateLocal, periodType: .weekly, weekStart: weekStart)
            return "\(OneDate.shortMonthDay(from: bounds.startDate)) - \(OneDate.shortMonthDay(from: bounds.endDate))"
        case .monthly:
            return "\(OneDate.fullMonth(for: selectedYearMonth)) \(currentYear)"
        case .yearly:
            return "\(currentYear)"
        }
    }

    public var selectedMonthLabel: String {
        "\(OneDate.fullMonth(for: selectedYearMonth)) \(currentYear)"
    }

    public func load(
        anchorDate: String,
        periodType: PeriodType,
        weekStart: Int = 0,
        forceReload: Bool = false
    ) async {
        self.weekStart = weekStart
        if forceReload || allNotes.isEmpty {
            do {
                allNotes = try await repository.list(periodType: .daily)
                errorMessage = nil
            } catch {
                errorMessage = userFacingError(error)
                return
            }
        }

        selectedPeriod = periodType
        self.anchorDate = anchorDate
        selectedDateLocal = anchorDate
        selectedYearMonth = OneDate.monthBucket(from: anchorDate)
        withAnimation(OneMotion.animation(.calmRefresh)) {
            refreshDerivedState()
        }
    }

    public func refreshFromStore(anchorDate: String? = nil, weekStart: Int? = nil) async {
        await load(
            anchorDate: anchorDate ?? selectedDateLocal,
            periodType: selectedPeriod,
            weekStart: weekStart ?? self.weekStart,
            forceReload: true
        )
    }

    public func selectPeriod(_ period: PeriodType) {
        withAnimation(OneMotion.animation(.stateChange)) {
            selectedPeriod = period
            selectedYearMonth = OneDate.monthBucket(from: selectedDateLocal)
            refreshDerivedState()
        }
        OneHaptics.shared.trigger(.selectionChanged)
    }

    public func selectDay(_ dateLocal: String) {
        withAnimation(OneMotion.animation(.stateChange)) {
            anchorDate = dateLocal
            selectedDateLocal = dateLocal
            selectedYearMonth = OneDate.monthBucket(from: dateLocal)
            refreshDerivedState()
        }
        OneHaptics.shared.trigger(.selectionChanged)
    }

    public func selectMonth(_ month: Int) {
        let day = Int(OneDate.dayNumber(from: selectedDateLocal)) ?? 1
        let clampedDay = min(day, OneDate.numberOfDays(inMonth: month, year: currentYear))
        let nextDate = String(format: "%04d-%02d-%02d", currentYear, month, clampedDay)
        withAnimation(OneMotion.animation(.stateChange)) {
            anchorDate = nextDate
            selectedDateLocal = nextDate
            selectedYearMonth = month
            refreshDerivedState()
        }
        OneHaptics.shared.trigger(.selectionChanged)
    }

    public func moveSelection(by offset: Int) {
        let nextDate: String
        switch selectedPeriod {
        case .daily:
            nextDate = shiftedDate(from: selectedDateLocal, days: offset)
        case .weekly:
            nextDate = shiftedDate(from: selectedDateLocal, days: offset * 7)
        case .monthly:
            nextDate = shiftedDate(from: selectedDateLocal, months: offset)
        case .yearly:
            nextDate = shiftedDate(from: selectedDateLocal, years: offset)
        }
        withAnimation(OneMotion.animation(.stateChange)) {
            anchorDate = nextDate
            selectedDateLocal = nextDate
            selectedYearMonth = OneDate.monthBucket(from: nextDate)
            refreshDerivedState()
        }
        OneHaptics.shared.trigger(.selectionChanged)
    }

    @discardableResult
    public func createNote(
        content: String,
        sentiment: ReflectionSentiment,
        for dateLocal: String? = nil
    ) async -> ReflectionNote? {
        let targetDate = dateLocal ?? selectedDateLocal
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        do {
            let note = try await repository.upsert(
                input: ReflectionWriteInput(
                    periodType: .daily,
                    periodStart: targetDate,
                    periodEnd: targetDate,
                    content: trimmed,
                    sentiment: sentiment
                )
            )
            withAnimation(OneMotion.animation(.stateChange)) {
                anchorDate = targetDate
                selectedDateLocal = targetDate
                selectedYearMonth = OneDate.monthBucket(from: targetDate)
                allNotes.insert(note, at: 0)
                refreshDerivedState()
            }
            OneHaptics.shared.trigger(.saveSucceeded)
            OneSyncFeedbackCenter.shared.showSynced(
                title: "Note saved",
                message: "Reflection added for \(OneDate.shortMonthDay(from: targetDate))."
            )
            errorMessage = nil
            return note
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
            return nil
        }
    }

    public func delete(id: String) async -> Bool {
        do {
            try await repository.delete(id: id)
            withAnimation(OneMotion.animation(.dismiss)) {
                allNotes.removeAll { $0.id == id }
                refreshDerivedState()
            }
            OneHaptics.shared.trigger(.destructiveConfirmed)
            errorMessage = nil
            return true
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
            return false
        }
    }

    private func refreshDerivedState() {
        let visibleDates = visibleDateRange()
        let visibleDateSet = Set(visibleDates)
        let allDailyNotes = allNotes.filter { $0.periodType == .daily }
        let notesByDate = Dictionary(grouping: allDailyNotes, by: \.periodStart)

        dayOptions = visibleDates.map { dateLocal in
            let dayNotes = notesByDate[dateLocal] ?? []
            let daySummary = reflectionSentimentSummary(for: dayNotes)
            return NotesDayOption(
                dateLocal: dateLocal,
                weekdayLabel: OneDate.shortWeekday(from: dateLocal),
                dayNumber: Int(OneDate.dayNumber(from: dateLocal)) ?? 0,
                sentiment: daySummary.dominant,
                hasNotes: !dayNotes.isEmpty
            )
        }

        if !visibleDateSet.contains(selectedDateLocal), let fallback = visibleDates.first {
            selectedDateLocal = fallback
            anchorDate = fallback
            selectedYearMonth = OneDate.monthBucket(from: fallback)
        }

        selectedDayNotes = allNotes
            .filter { $0.periodType == .daily && $0.periodStart == selectedDateLocal }
            .sorted(by: reflectionNoteSort(lhs:rhs:))

        monthOptions = (1...12).map { month in
            let notes = notesForMonth(month, year: currentYear)
            let monthSummary = reflectionSentimentSummary(for: notes)
            return NotesMonthOption(
                month: month,
                label: OneDate.shortMonth(for: month),
                noteCount: notes.count,
                dominant: monthSummary.dominant
            )
        }

        if let firstVisible = visibleDates.first,
           let firstDate = OneDate.calendarDate(for: firstVisible) {
            leadingPlaceholders = OneDate.canonicalWeekdayIndex(for: firstDate)
        } else {
            leadingPlaceholders = 0
        }

        let visibleNotes = allNotes.filter { visibleDateSet.contains($0.periodStart) }
        let visibleSummary = reflectionSentimentSummary(for: visibleNotes)

        sentimentSummary = visibleNotes.isEmpty ? nil : NotesSentimentSummary(
            noteCount: visibleNotes.count,
            activeDays: Set(visibleNotes.map(\.periodStart)).count,
            dominant: visibleSummary.dominant,
            distribution: visibleSummary.distribution
        )
    }

    private func visibleDateRange() -> [String] {
        switch selectedPeriod {
        case .daily:
            return [selectedDateLocal]
        case .weekly:
            let bounds = AnalyticsDateRange.bounds(anchorDate: selectedDateLocal, periodType: .weekly, weekStart: weekStart)
            return sequenceDates(startDate: bounds.startDate, endDate: bounds.endDate)
        case .monthly:
            return monthDates(month: selectedYearMonth, year: currentYear)
        case .yearly:
            return monthDates(month: selectedYearMonth, year: currentYear)
        }
    }

    private func notesForMonth(_ month: Int, year: Int) -> [ReflectionNote] {
        allNotes.filter { note in
            note.periodType == .daily &&
            OneDate.year(from: note.periodStart) == year &&
            OneDate.monthBucket(from: note.periodStart) == month
        }
    }

    private func monthDates(month: Int, year: Int) -> [String] {
        let count = OneDate.numberOfDays(inMonth: month, year: year)
        return (1...count).map { day in
            String(format: "%04d-%02d-%02d", year, month, day)
        }
    }

    private func sequenceDates(startDate: String, endDate: String) -> [String] {
        guard let start = OneDate.calendarDate(for: startDate),
              let end = OneDate.calendarDate(for: endDate) else {
            return []
        }

        return stride(from: start, through: end, by: 86_400).map { date in
            NotesViewModel.isoDateFormatter.string(from: date)
        }
    }

    private func shiftedDate(from dateLocal: String, days: Int = 0, months: Int = 0, years: Int = 0) -> String {
        guard let date = OneDate.calendarDate(for: dateLocal) else {
            return dateLocal
        }
        let components = DateComponents(year: years, month: months, day: days)
        let shifted = NotesViewModel.calendar.date(byAdding: components, to: date) ?? date
        return NotesViewModel.isoDateFormatter.string(from: shifted)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

public protocol NotificationPreferenceApplier: Sendable {
    func apply(preferences: UserPreferences) async -> NotificationScheduleStatus
    func status() async -> NotificationScheduleStatus?
}

public struct NoopNotificationPreferenceApplier: NotificationPreferenceApplier {
    public init() {}

    public func apply(preferences: UserPreferences) async -> NotificationScheduleStatus {
        NotificationScheduleStatus(
            permissionGranted: false,
            scheduledCount: 0,
            lastRefreshedAt: Date(),
            lastError: "Notification scheduling is unavailable."
        )
    }

    public func status() async -> NotificationScheduleStatus? {
        nil
    }
}

public actor LiveNotificationPreferenceApplier: NotificationPreferenceApplier {
    public static let preferenceKey = "one.notification.preferences"
    public static let statusKey = "one.notification.schedule.status"

    private let defaults: UserDefaults
    private let apiClient: APIClient
    private let notificationService: LocalNotificationService

    public init(
        apiClient: APIClient,
        notificationService: LocalNotificationService,
        defaults: UserDefaults = .standard
    ) {
        self.apiClient = apiClient
        self.notificationService = notificationService
        self.defaults = defaults
    }

    public func apply(preferences: UserPreferences) async -> NotificationScheduleStatus {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: Self.preferenceKey)
        } else {
            defaults.removeObject(forKey: Self.preferenceKey)
        }

        do {
            let habits = try await apiClient.fetchHabits()
            let todos = try await apiClient.fetchTodos()
            let result = await notificationService.refresh(
                habits: habits,
                todos: todos,
                preferences: preferences
            )
            if let data = try? JSONEncoder().encode(result) {
                defaults.set(data, forKey: Self.statusKey)
            }
            return result
        } catch {
            let fallback = NotificationScheduleStatus(
                permissionGranted: false,
                scheduledCount: 0,
                lastRefreshedAt: Date(),
                lastError: userFacingError(error)
            )
            if let data = try? JSONEncoder().encode(fallback) {
                defaults.set(data, forKey: Self.statusKey)
            }
            return fallback
        }
    }

    public func status() async -> NotificationScheduleStatus? {
        guard let raw = defaults.data(forKey: Self.statusKey) else {
            return nil
        }
        return try? JSONDecoder().decode(NotificationScheduleStatus.self, from: raw)
    }
}

@MainActor
public final class ProfileViewModel: ObservableObject, NotificationScheduleRefresher {
    @Published public private(set) var user: User?
    @Published public private(set) var preferences: UserPreferences?
    @Published public private(set) var notificationStatus: NotificationScheduleStatus?
    @Published public private(set) var errorMessage: String?

    private let repository: ProfileRepository
    private let applier: NotificationPreferenceApplier

    public init(repository: ProfileRepository, applier: NotificationPreferenceApplier = NoopNotificationPreferenceApplier()) {
        self.repository = repository
        self.applier = applier
    }

    public func load() async {
        do {
            async let loadedUser = repository.loadProfile()
            async let loadedPreferences = repository.loadPreferences()
            let nextUser = try await loadedUser
            let nextPreferences = try await loadedPreferences
            withAnimation(OneMotion.animation(.calmRefresh)) {
                user = nextUser
                preferences = nextPreferences
            }
            notificationStatus = await applier.status()
            errorMessage = nil
        } catch {
            errorMessage = userFacingError(error)
        }
    }

    public func refreshSchedules() async {
        guard let preferences else {
            return
        }
        let refreshedStatus = await applier.apply(preferences: preferences)
        withAnimation(OneMotion.animation(.calmRefresh)) {
            notificationStatus = refreshedStatus
        }
    }

    @discardableResult
    public func saveProfile(displayName: String) async -> Bool {
        do {
            let updatedUser = try await repository.updateProfile(
                UserProfileUpdateInput(
                    displayName: displayName,
                    timezone: TimeZone.autoupdatingCurrent.identifier
                )
            )
            withAnimation(OneMotion.animation(.stateChange)) {
                user = updatedUser
            }
            OneHaptics.shared.trigger(.saveSucceeded)
            OneSyncFeedbackCenter.shared.showSynced(
                title: "Name saved",
                message: "Your profile is updated on this device."
            )
            errorMessage = nil
            return true
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
            return false
        }
    }

    @discardableResult
    public func savePreferences(input: UserPreferencesUpdateInput) async -> Bool {
        do {
            let updated = try await repository.updatePreferences(input)
            withAnimation(OneMotion.animation(.stateChange)) {
                preferences = updated
            }
            notificationStatus = await applier.apply(preferences: updated)
            OneHaptics.shared.trigger(.saveSucceeded)
            OneSyncFeedbackCenter.shared.showSynced(
                title: "Preferences saved",
                message: "Your latest settings are stored on this device."
            )
            errorMessage = nil
            return true
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = userFacingError(error)
            return false
        }
    }
}
