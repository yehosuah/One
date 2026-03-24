#if canImport(SwiftUI)
import SwiftUI
import Combine
#if canImport(SwiftData)
import SwiftData
#endif
#if os(iOS)
import UIKit
#endif

@MainActor
public final class OneAppContainer: ObservableObject {
    public let authViewModel: AuthViewModel
    public let tasksViewModel: TasksViewModel
    public let todayViewModel: TodayViewModel
    public let financeViewModel: FinanceViewModel
    public let analyticsViewModel: AnalyticsViewModel
    public let profileViewModel: ProfileViewModel
    public let coachViewModel: CoachViewModel
    public let reflectionsViewModel: ReflectionsViewModel
    public let notesViewModel: NotesViewModel
    let syncFeedbackCenter: OneSyncFeedbackCenter
    let quickActionCenter: OneQuickActionCenter
    public let fatalStartupMessage: String?
    private var cancellables: Set<AnyCancellable> = []

    public init(
        authRepository: AuthRepository,
        tasksRepository: TasksRepository,
        todayRepository: TodayRepository,
        financeRepository: FinanceRepository = NoopFinanceRepository(),
        analyticsRepository: AnalyticsRepository,
        reflectionsRepository: ReflectionsRepository,
        profileRepository: ProfileRepository,
        coachRepository: CoachRepository,
        notificationApplier: NotificationPreferenceApplier = NoopNotificationPreferenceApplier(),
        fatalStartupMessage: String? = nil
    ) {
        let profileViewModel = ProfileViewModel(repository: profileRepository, applier: notificationApplier)
        let reflectionsViewModel = ReflectionsViewModel(repository: reflectionsRepository)
        let notesViewModel = NotesViewModel(repository: reflectionsRepository)
        self.syncFeedbackCenter = OneSyncFeedbackCenter.shared
        self.quickActionCenter = OneQuickActionCenter()
        self.authViewModel = AuthViewModel(repository: authRepository)
        self.tasksViewModel = TasksViewModel(repository: tasksRepository, scheduleRefresher: profileViewModel)
        self.todayViewModel = TodayViewModel(repository: todayRepository)
        self.financeViewModel = FinanceViewModel(repository: financeRepository)
        self.analyticsViewModel = AnalyticsViewModel(
            repository: analyticsRepository,
            reflectionsRepository: reflectionsRepository
        )
        self.profileViewModel = profileViewModel
        self.coachViewModel = CoachViewModel(repository: coachRepository)
        self.reflectionsViewModel = reflectionsViewModel
        self.notesViewModel = notesViewModel
        self.fatalStartupMessage = fatalStartupMessage
        bindChildViewModels()
    }

    public static func live(environment: AppEnvironment = .current()) -> OneAppContainer {
        _ = environment
        let sessionStore: AuthSessionStore
        #if canImport(Security)
        sessionStore = KeychainAuthSessionStore()
        #else
        sessionStore = InMemoryAuthSessionStore()
        #endif

        let apiClient: APIClient
        let syncQueue: SyncQueue
        let financeRepository: FinanceRepository
        var fatalStartupMessage: String?

        #if canImport(SwiftData)
        do {
            let stack = try LocalPersistenceFactory.makeStored(sessionStore: sessionStore)
            apiClient = stack.apiClient
            syncQueue = stack.syncQueue
            financeRepository = LocalFinanceRepository(
                container: stack.container,
                sessionStore: sessionStore
            )
        } catch {
            fatalStartupMessage = "Local data store is unavailable. Restart the app and try again."
            apiClient = LocalModeUnavailableAPIClient(
                sessionStore: sessionStore,
                message: fatalStartupMessage ?? "Local data store is unavailable."
            )
            syncQueue = InMemorySyncQueue()
            financeRepository = NoopFinanceRepository()
        }
        #else
        fatalStartupMessage = "Local data store is unavailable. Restart the app and try again."
        apiClient = LocalModeUnavailableAPIClient(
            sessionStore: sessionStore,
            message: fatalStartupMessage ?? "Local data store is unavailable."
        )
        syncQueue = InMemorySyncQueue()
        financeRepository = NoopFinanceRepository()
        #endif

        let notificationService: LocalNotificationService
        #if canImport(UserNotifications) && os(iOS)
        notificationService = UserNotificationCenterService()
        #else
        notificationService = NoopLocalNotificationService()
        #endif

        let notificationApplier = LiveNotificationPreferenceApplier(
            apiClient: apiClient,
            notificationService: notificationService
        )

        return OneAppContainer(
            authRepository: DefaultAuthRepository(apiClient: apiClient),
            tasksRepository: DefaultTasksRepository(apiClient: apiClient, syncQueue: syncQueue),
            todayRepository: DefaultTodayRepository(apiClient: apiClient, syncQueue: syncQueue),
            financeRepository: financeRepository,
            analyticsRepository: DefaultAnalyticsRepository(apiClient: apiClient),
            reflectionsRepository: DefaultReflectionsRepository(apiClient: apiClient),
            profileRepository: DefaultProfileRepository(apiClient: apiClient),
            coachRepository: DefaultCoachRepository(apiClient: apiClient),
            notificationApplier: notificationApplier,
            fatalStartupMessage: fatalStartupMessage
        )
    }

    public func bootstrap(anchorDate: String) async {
        await authViewModel.bootstrap()
        guard authViewModel.user != nil else {
            return
        }
        await refreshAll(anchorDate: anchorDate)
    }

    public func refreshAll(anchorDate: String) async {
        await profileViewModel.load()
        await refreshFinanceContext()
        await tasksViewModel.loadCategories()
        await tasksViewModel.loadTasks()
        await todayViewModel.load(date: anchorDate)
        await reflectionsViewModel.load(periodType: .daily)
        await coachViewModel.load()
        await refreshAnalytics(anchorDate: anchorDate)
        await profileViewModel.refreshSchedules()
    }

    public func refreshTasksContext(anchorDate: String) async {
        await tasksViewModel.loadTasks()
        await todayViewModel.load(date: anchorDate)
        await refreshAnalytics(anchorDate: anchorDate)
        await profileViewModel.refreshSchedules()
    }

    public func refreshAnalytics(anchorDate: String) async {
        let weekStart = profileViewModel.preferences?.weekStart ?? 0
        await analyticsViewModel.loadWeekly(anchorDate: anchorDate, weekStart: weekStart)
        if analyticsViewModel.selectedPeriod != .weekly {
            await analyticsViewModel.loadPeriod(
                anchorDate: anchorDate,
                periodType: analyticsViewModel.selectedPeriod,
                weekStart: weekStart
            )
        }
    }

    public func refreshFinanceContext() async {
        let weekStart = profileViewModel.preferences?.weekStart ?? 0
        await financeViewModel.refreshAll(weekStart: weekStart)
    }

    public func refreshDailyReflections() async {
        await reflectionsViewModel.load(periodType: .daily)
    }

    private func bindChildViewModels() {
        observe(authViewModel)
        observe(tasksViewModel)
        observe(todayViewModel)
        observe(financeViewModel)
        observe(analyticsViewModel)
        observe(profileViewModel)
        observe(coachViewModel)
        observe(reflectionsViewModel)
        observe(notesViewModel)
        observe(syncFeedbackCenter)
        observe(quickActionCenter)
    }

    private func observe<Object: ObservableObject>(_ object: Object)
    where Object.ObjectWillChangePublisher == ObservableObjectPublisher {
        object.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}

private actor LocalModeUnavailableAPIClient: APIClient {
    private let sessionStore: AuthSessionStore
    private let message: String

    init(
        sessionStore: AuthSessionStore,
        message: String = "Local data store is unavailable."
    ) {
        self.sessionStore = sessionStore
        self.message = message
    }

    func currentSession() async -> AuthSessionTokens? {
        await sessionStore.setRecoverySuppressed(true)
        await sessionStore.clear()
        return nil
    }

    func clearSession() async {
        await sessionStore.setRecoverySuppressed(true)
        await sessionStore.clear()
    }

    func login(email: String, password: String) async throws -> AuthSession {
        try await fail()
    }

    func signup(email: String, password: String, displayName: String, timezone: String) async throws -> AuthSession {
        try await fail()
    }

    func fetchMe() async throws -> User {
        try await fail()
    }

    func fetchCategories() async throws -> [Category] {
        try await fail()
    }

    func fetchHabits() async throws -> [Habit] {
        try await fail()
    }

    func fetchTodos() async throws -> [Todo] {
        try await fail()
    }

    func fetchCoachCards() async throws -> [CoachCard] {
        try await fail()
    }

    func createHabit(input: HabitCreateInput) async throws -> Habit {
        try await fail()
    }

    func createTodo(input: TodoCreateInput) async throws -> Todo {
        try await fail()
    }

    func fetchToday(date: String?) async throws -> TodayResponse {
        try await fail()
    }

    func putTodayOrder(dateLocal: String, items: [TodayOrderItem]) async throws -> TodayResponse {
        try await fail()
    }

    func updateCompletion(itemType: ItemType, itemId: String, dateLocal: String, state: CompletionState) async throws {
        let _: Void = try await fail()
    }

    func fetchDaily(startDate: String, endDate: String) async throws -> [DailySummary] {
        try await fail()
    }

    func fetchPeriod(anchorDate: String, periodType: PeriodType) async throws -> PeriodSummary {
        try await fail()
    }

    func fetchHabitStats(habitId: String, anchorDate: String?, windowDays: Int?) async throws -> HabitStats {
        try await fail()
    }

    func fetchReflections(periodType: PeriodType?) async throws -> [ReflectionNote] {
        try await fail()
    }

    func upsertReflection(input: ReflectionWriteInput) async throws -> ReflectionNote {
        try await fail()
    }

    func deleteReflection(id: String) async throws {
        let _: Void = try await fail()
    }

    func fetchPreferences() async throws -> UserPreferences {
        try await fail()
    }

    func patchPreferences(input: UserPreferencesUpdateInput) async throws -> UserPreferences {
        try await fail()
    }

    func patchUser(input: UserProfileUpdateInput) async throws -> User {
        try await fail()
    }

    func patchHabit(id: String, input: HabitUpdateInput, clientUpdatedAt: Date?) async throws -> Habit {
        try await fail()
    }

    func patchTodo(id: String, fields: [String : String], clientUpdatedAt: Date?) async throws -> Todo {
        try await fail()
    }

    func patchTodo(id: String, input: TodoUpdateInput, clientUpdatedAt: Date?) async throws -> Todo {
        try await fail()
    }

    func deleteHabit(id: String) async throws {
        let _: Void = try await fail()
    }

    func deleteTodo(id: String) async throws {
        let _: Void = try await fail()
    }

    private func fail<T>() async throws -> T {
        throw APIError.transport(message)
    }
}

public struct OneAppShell: View {
    @StateObject private var container: OneAppContainer
    @State private var selectedTab: Tab = .today
    @State private var activeSheet: SheetRoute?
    @State private var didBootstrap = false
    @State private var isBootstrapping = true
    @State private var lastResolvedAnchorDate: String?
    @Environment(\.scenePhase) private var scenePhase

    public init(container: OneAppContainer = OneAppContainer.live()) {
        _container = StateObject(wrappedValue: container)
    }

    private var currentAnchorDate: String {
        OneDate.isoDate()
    }

    public var body: some View {
        Group {
            if let fatalStartupMessage = container.fatalStartupMessage {
                BlockingStartupView(message: fatalStartupMessage)
            } else if isBootstrapping {
                SplashView()
            } else if container.authViewModel.user == nil {
                LocalProfileSetupView(viewModel: container.authViewModel)
            } else {
                MainTabsView(
                    selectedTab: $selectedTab,
                    activeSheet: $activeSheet,
                    container: container,
                    onSelectTab: { selectedTab = $0 },
                    onRefreshTasksContext: {
                        await container.refreshTasksContext(anchorDate: currentAnchorDate)
                    },
                    onRefreshAnalytics: {
                        await container.refreshAnalytics(anchorDate: currentAnchorDate)
                    },
                    onRefreshReflections: {
                        await container.refreshDailyReflections()
                    }
                )
            }
        }
        .preferredColorScheme(OneTheme.preferredColorScheme(from: container.profileViewModel.preferences?.theme))
        .tint(OneTheme.palette(for: OneTheme.preferredColorScheme(from: container.profileViewModel.preferences?.theme) ?? .light).accent)
        .sheet(item: $activeSheet) { route in
            switch route {
            case .addHabit:
                HabitFormSheet(categories: container.tasksViewModel.categories) { input in
                    if let created = await container.tasksViewModel.createHabit(input: input) {
                        selectedTab = .today
                        await container.refreshTasksContext(anchorDate: currentAnchorDate)
                        container.todayViewModel.highlight(itemType: .habit, itemId: created.id)
                        activeSheet = nil
                    }
                } onCancel: {
                    activeSheet = nil
                }
            case .addTodo:
                TodoFormSheet(categories: container.tasksViewModel.categories) { input in
                    if let created = await container.tasksViewModel.createTodo(input: input) {
                        selectedTab = .today
                        await container.refreshTasksContext(anchorDate: currentAnchorDate)
                        container.todayViewModel.highlight(itemType: .todo, itemId: created.id)
                        activeSheet = nil
                    }
                } onCancel: {
                    activeSheet = nil
                }
            case .notifications:
                NotificationPreferencesView(profileViewModel: container.profileViewModel) {
                    activeSheet = nil
                }
            case .coach:
                CoachSheetView(
                    viewModel: container.coachViewModel,
                    todayViewModel: container.todayViewModel,
                    analyticsViewModel: container.analyticsViewModel,
                    reflectionsViewModel: container.reflectionsViewModel,
                    currentDateLocal: currentAnchorDate
                ) {
                    activeSheet = nil
                }
            case .habitCategory(let categoryId):
                HabitCategorySheetView(
                    categoryId: categoryId,
                    tasksViewModel: container.tasksViewModel,
                    anchorDate: currentAnchorDate,
                    onDismiss: {
                        activeSheet = nil
                    },
                    onSave: {
                        await container.refreshTasksContext(anchorDate: currentAnchorDate)
                    }
                )
            case .addNote(let anchorDate):
                NoteComposerSheetView(
                    viewModel: container.notesViewModel,
                    anchorDate: anchorDate,
                    onDismiss: {
                        activeSheet = nil
                    },
                    onRefreshAnalytics: {
                        await container.refreshAnalytics(anchorDate: currentAnchorDate)
                    },
                    onRefreshReflections: {
                        await container.refreshDailyReflections()
                    }
                )
            case .notes(let anchorDate, let periodType):
                NotesSheetView(
                    viewModel: container.notesViewModel,
                    initialAnchorDate: anchorDate,
                    initialPeriod: periodType,
                    weekStart: container.profileViewModel.preferences?.weekStart ?? 0,
                    onDismiss: {
                        activeSheet = nil
                    },
                    onRefreshAnalytics: {
                        await container.refreshAnalytics(anchorDate: currentAnchorDate)
                    },
                    onRefreshReflections: {
                        await container.refreshDailyReflections()
                    }
                )
            }
        }
        .task {
            guard !didBootstrap, container.fatalStartupMessage == nil else {
                return
            }
            didBootstrap = true
            await container.bootstrap(anchorDate: currentAnchorDate)
            lastResolvedAnchorDate = currentAnchorDate
            isBootstrapping = false
        }
        .onChange(of: container.authViewModel.user?.id) { _, newUserID in
            guard !isBootstrapping else {
                return
            }
            Task {
                if newUserID != nil {
                    selectedTab = .today
                    await container.refreshAll(anchorDate: currentAnchorDate)
                    lastResolvedAnchorDate = currentAnchorDate
                } else {
                    selectedTab = .today
                    activeSheet = nil
                    lastResolvedAnchorDate = nil
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active,
                  !isBootstrapping,
                  didBootstrap,
                  container.authViewModel.user != nil else {
                return
            }
            let anchorDate = currentAnchorDate
            guard anchorDate != lastResolvedAnchorDate else {
                return
            }
            Task {
                await container.refreshAll(anchorDate: anchorDate)
                lastResolvedAnchorDate = anchorDate
            }
        }
    }

    enum Tab: Hashable {
        case today
        case review
        case finance
        case settings
    }

    enum SheetRoute: Identifiable {
        case addHabit
        case addTodo
        case addNote(anchorDate: String)
        case notifications
        case coach
        case habitCategory(categoryId: String)
        case notes(anchorDate: String, periodType: PeriodType)

        var id: String {
            switch self {
            case .addHabit:
                return "addHabit"
            case .addTodo:
                return "addTodo"
            case .addNote(let anchorDate):
                return "addNote-\(anchorDate)"
            case .notifications:
                return "notifications"
            case .coach:
                return "coach"
            case .habitCategory(let categoryId):
                return "habit-category-\(categoryId)"
            case .notes(let anchorDate, let periodType):
                return "notes-\(periodType.rawValue)-\(anchorDate)"
            }
        }
    }
}

private struct MainTabsView: View {
    private enum MainTabSlot: Hashable {
        case review
        case today
        case quickAdd
        case finance
        case settings

        init(tab: OneAppShell.Tab) {
            switch tab {
            case .review:
                self = .review
            case .today:
                self = .today
            case .finance:
                self = .finance
            case .settings:
                self = .settings
            }
        }

        var appTab: OneAppShell.Tab? {
            switch self {
            case .review:
                return .review
            case .today:
                return .today
            case .finance:
                return .finance
            case .settings:
                return .settings
            case .quickAdd:
                return nil
            }
        }
    }

    @Binding var selectedTab: OneAppShell.Tab
    @Binding var activeSheet: OneAppShell.SheetRoute?
    @ObservedObject var container: OneAppContainer
    let onSelectTab: (OneAppShell.Tab) -> Void
    let onRefreshTasksContext: () async -> Void
    let onRefreshAnalytics: () async -> Void
    let onRefreshReflections: () async -> Void

    @State private var selectedSlot: MainTabSlot = .today
    @State private var previousRealSlot: MainTabSlot = .today
    @State private var isQuickAddExpanded = false
    @State private var isResettingSlotSelection = false
    @State private var financeQuickAddRequest: OneAddAction?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    private var currentDateLocal: String {
        OneDate.isoDate()
    }

    private var quickAddContext: OneAddContext {
        OneAddContext(tab: selectedTab)
    }

    var body: some View {
        TabView(selection: $selectedSlot) {
            ReviewTabView(
                analyticsViewModel: container.analyticsViewModel,
                notesViewModel: container.notesViewModel,
                coachViewModel: container.coachViewModel,
                currentDateLocal: currentDateLocal,
                weekStart: container.profileViewModel.preferences?.weekStart ?? 0,
                onSelectPeriod: { periodType in
                    await container.analyticsViewModel.loadPeriod(
                        anchorDate: currentDateLocal,
                        periodType: periodType,
                        weekStart: container.profileViewModel.preferences?.weekStart ?? 0
                    )
                },
                onOpenSheet: { activeSheet = $0 },
                onOpenCoach: {
                    activeSheet = .coach
                },
                onRefreshAnalytics: onRefreshAnalytics,
                onRefreshReflections: onRefreshReflections
            )
            .tabItem {
                Label {
                    Text("Review")
                } icon: {
                    OneIconImageFactory.tabBarImage(for: .review)
                }
            }
            .tag(MainTabSlot.review)

            TodayTabView(
                todayViewModel: container.todayViewModel,
                tasksViewModel: container.tasksViewModel,
                currentDateLocal: currentDateLocal,
                onOpenSheet: { activeSheet = $0 },
                onOpenReview: openReview(for:),
                onRefreshTasksContext: onRefreshTasksContext,
                onRefreshAnalytics: onRefreshAnalytics
            )
            .tabItem {
                Label {
                    Text("Today")
                } icon: {
                    OneIconImageFactory.tabBarImage(for: .today)
                }
            }
            .tag(MainTabSlot.today)

            QuickAddTabPlaceholderView()
                .tabItem {
                    Label(
                        isQuickAddExpanded ? "Close" : "Add",
                        systemImage: isQuickAddExpanded ? "xmark.circle.fill" : "plus.circle.fill"
                    )
                }
                .tag(MainTabSlot.quickAdd)

            FinanceTabView(
                viewModel: container.financeViewModel,
                weekStart: container.profileViewModel.preferences?.weekStart ?? 0,
                quickAddRequest: $financeQuickAddRequest
            )
            .tabItem {
                Label {
                    Text("Finance")
                } icon: {
                    OneIconImageFactory.tabBarImage(for: .finance)
                }
            }
            .tag(MainTabSlot.finance)

            ProfileTabView(
                authViewModel: container.authViewModel,
                profileViewModel: container.profileViewModel,
                coachViewModel: container.coachViewModel,
                onOpenSheet: { activeSheet = $0 }
            )
            .tabItem {
                Label {
                    Text("Settings")
                } icon: {
                    OneIconImageFactory.tabBarImage(for: .settings)
                }
            }
            .tag(MainTabSlot.settings)
        }
        .tint(palette.accent)
        .onAppear {
            let initialSlot = MainTabSlot(tab: selectedTab)
            selectedSlot = initialSlot
            previousRealSlot = initialSlot
        }
        .onChange(of: selectedTab) { _, newValue in
            let nextSlot = MainTabSlot(tab: newValue)
            previousRealSlot = nextSlot
            guard selectedSlot != nextSlot else {
                return
            }
            isResettingSlotSelection = true
            selectedSlot = nextSlot
        }
        .onChange(of: selectedSlot) { _, newValue in
            handleSlotChange(newValue)
        }
        .onChange(of: activeSheet?.id) { _, newValue in
            guard newValue != nil else {
                return
            }
            dismissQuickAdd()
        }
        .overlay {
            QuickAddTrayOverlay(
                palette: palette,
                context: quickAddContext,
                isPresented: isQuickAddExpanded,
                feedbackIsVisible: container.syncFeedbackCenter.feedback != nil,
                onDismiss: dismissQuickAdd,
                onSelect: handleQuickAddAction(_:)
            )
        }
        .safeAreaInset(edge: .bottom) {
            if let feedback = container.syncFeedbackCenter.feedback {
                OneSyncFeedbackPill(palette: palette, feedback: feedback)
                    .padding(.horizontal, OneSpacing.md)
                    .padding(.vertical, OneSpacing.xs)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func openReview(for dateLocal: String) {
        guard selectedTab != .review else {
            Task {
                await container.notesViewModel.load(
                    anchorDate: dateLocal,
                    periodType: .daily,
                    weekStart: container.profileViewModel.preferences?.weekStart ?? 0,
                    forceReload: false
                )
            }
            return
        }
        OneHaptics.shared.trigger(.selectionChanged)
        onSelectTab(.review)
        Task {
            await container.notesViewModel.load(
                anchorDate: dateLocal,
                periodType: .daily,
                weekStart: container.profileViewModel.preferences?.weekStart ?? 0,
                forceReload: false
            )
        }
    }

    private func handleSlotChange(_ slot: MainTabSlot) {
        if isResettingSlotSelection {
            isResettingSlotSelection = false
            return
        }

        switch slot {
        case .quickAdd:
            toggleQuickAdd()
            isResettingSlotSelection = true
            selectedSlot = previousRealSlot
        case .today, .review, .finance, .settings:
            dismissQuickAdd()
            previousRealSlot = slot
            if let appTab = slot.appTab, selectedTab != appTab {
                onSelectTab(appTab)
            }
        }
    }

    private func dismissQuickAdd() {
        guard isQuickAddExpanded else {
            return
        }
        withAnimation(OneMotion.animation(.dismiss)) {
            isQuickAddExpanded = false
        }
    }

    private func toggleQuickAdd() {
        OneHaptics.shared.trigger(isQuickAddExpanded ? .selectionChanged : .sheetPresented)
        withAnimation(OneMotion.animation(isQuickAddExpanded ? .dismiss : .expand)) {
            isQuickAddExpanded.toggle()
        }
    }

    private func handleQuickAddAction(_ action: OneAddAction) {
        dismissQuickAdd()
        OneHaptics.shared.trigger(.selectionChanged)

        switch action {
        case .habit:
            activeSheet = .addHabit
        case .task:
            activeSheet = .addTodo
        case .note:
            let anchorDate = selectedTab == .review ? container.notesViewModel.selectedDateLocal : currentDateLocal
            activeSheet = .addNote(anchorDate: anchorDate)
        case .income, .expense, .transfer:
            financeQuickAddRequest = action
        }
    }
}

private struct QuickAddTabPlaceholderView: View {
    var body: some View {
        Color.clear
            .accessibilityHidden(true)
    }
}

private struct QuickAddTrayOverlay: View {
    let palette: OneTheme.Palette
    let context: OneAddContext
    let isPresented: Bool
    let feedbackIsVisible: Bool
    let onDismiss: () -> Void
    let onSelect: (OneAddAction) -> Void

    var body: some View {
        GeometryReader { proxy in
            if isPresented {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(palette.isDark ? 0.22 : 0.08)
                        .ignoresSafeArea()
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 74)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onDismiss)

                    QuickAddTray(
                        palette: palette,
                        context: context,
                        onSelect: onSelect
                    )
                    .padding(.horizontal, OneSpacing.lg)
                    .padding(.bottom, proxy.safeAreaInsets.bottom + 62 + (feedbackIsVisible ? 42 : 0))
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(isPresented)
    }
}

private struct QuickAddTray: View {
    let palette: OneTheme.Palette
    let context: OneAddContext
    let onSelect: (OneAddAction) -> Void

    private var title: String {
        switch context {
        case .app:
            return "Add to your system"
        case .finance:
            return "Add to finance"
        }
    }

    private var subtitle: String {
        switch context {
        case .app:
            return "Capture the next task, habit, or note without leaving the tab."
        case .finance:
            return "Log income, expenses, or transfers from the current finance view."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneSpacing.sm) {
            Text(title)
                .font(OneType.sectionTitle)
                .foregroundStyle(palette.text)
            Text(subtitle)
                .font(OneType.secondary)
                .foregroundStyle(palette.subtext)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(context.actions) { action in
                    QuickAddActionRow(
                        palette: palette,
                        action: action
                    ) {
                        onSelect(action)
                    }
                }
            }
        }
        .padding(OneSpacing.md)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusLarge, style: .continuous)
                .fill(palette.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneTheme.radiusLarge, style: .continuous)
                .stroke(palette.glassStroke, lineWidth: 1)
        )
        .shadow(color: palette.shadowColor.opacity(0.18), radius: 16, x: 0, y: 10)
    }
}

private struct QuickAddActionRow: View {
    let palette: OneTheme.Palette
    let action: OneAddAction
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Circle()
                    .fill(palette.accentSoft)
                    .frame(width: 38, height: 38)
                    .overlay(
                        OneIcon(
                            key: action.iconKey,
                            palette: palette,
                            size: 18,
                            tint: palette.accent
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(action.subtitle)
                        .font(OneType.caption)
                        .foregroundStyle(palette.subtext)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.subtext)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                    .fill(palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onePressable(scale: 0.98, opacity: 0.94)
    }
}

private struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    var body: some View {
        ZStack {
            OneScreenBackground(palette: palette)
            VStack(spacing: 18) {
                OneMarkBadge(palette: palette)
                Text("One")
                    .font(OneType.largeTitle)
                    .foregroundStyle(palette.text)
                Text("Daily execution first")
                    .font(OneType.body)
                    .foregroundStyle(palette.subtext)
                ProgressView()
                    .tint(palette.accent)
            }
            .padding(24)
        }
    }
}

private struct BlockingStartupView: View {
    let message: String
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    var body: some View {
        ZStack {
            OneScreenBackground(palette: palette)
            VStack(spacing: 20) {
                OneMarkBadge(palette: palette)
                Text("Local data unavailable")
                    .font(OneType.largeTitle)
                    .foregroundStyle(palette.text)
                Text(message)
                    .font(OneType.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.subtext)
                    .frame(maxWidth: 340)
            }
            .padding(24)
        }
    }
}

private struct LocalProfileSetupView: View {
    private enum AccessMode {
        case local
        case signIn
        case createAccount
    }

    @ObservedObject var viewModel: AuthViewModel
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var accessMode: AccessMode?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    private var localProfileCandidate: User? {
        viewModel.localProfileCandidate
    }

    private var deviceTimezoneID: String {
        OneDate.deviceTimeZoneIdentifier
    }

    private var title: String {
        switch accessMode {
        case .local?:
            return localProfileCandidate == nil ? "Use This iPhone" : "Welcome Back"
        case .signIn?:
            return "Sign In"
        case .createAccount?:
            return "Create Account"
        case nil:
            return "Welcome to One"
        }
    }

    private var subtitle: String {
        switch accessMode {
        case .local?:
            return localProfileCandidate == nil
                ? "Start with a local profile and keep your data on this iPhone."
                : "Your profile and data are still on this iPhone."
        case .signIn?:
            return "Use your account to sync your data across future devices."
        case .createAccount?:
            return "Create an account when you want more than local device storage."
        case nil:
            return "One currently runs as a local-first iPhone app."
        }
    }

    var body: some View {
        NavigationStack {
            OneScrollScreen(palette: palette, bottomPadding: 36) {
                OneGlassCard(palette: palette, padding: OneSpacing.lg) {
                    HStack(alignment: .top, spacing: OneSpacing.md) {
                        OneMarkBadge(palette: palette)
                        VStack(alignment: .leading, spacing: OneSpacing.xs) {
                            Text(title)
                                .font(OneType.largeTitle)
                                .foregroundStyle(palette.text)
                            Text(subtitle)
                                .font(OneType.body)
                                .foregroundStyle(palette.subtext)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                switch accessMode {
                case .local?:
                    localAccessCard
                case .signIn?:
                    signInCard
                case .createAccount?:
                    createAccountCard
                case nil:
                    localFirstEntry
                }

                if let message = viewModel.errorMessage {
                    InlineStatusCard(message: message, kind: .danger, palette: palette)
                }
            }
            .navigationTitle(title)
            .oneNavigationBarDisplayMode(.large)
            .oneKeyboardDismissible()
            .toolbar {
                if accessMode != nil {
                    ToolbarItem(placement: .oneNavigationLeading) {
                        Button("Back") {
                            accessMode = nil
                            password = ""
                        }
                    }
                }
                if accessMode == .signIn {
                    ToolbarItem(placement: .oneNavigationTrailing) {
                        Button("Create account") {
                            accessMode = .createAccount
                        }
                    }
                }
                if accessMode == .createAccount {
                    ToolbarItem(placement: .oneNavigationTrailing) {
                        Button("Sign in") {
                            accessMode = .signIn
                        }
                    }
                }
            }
        }
        .onAppear {
            hydrateFromProfileCandidate()
        }
        .onChange(of: localProfileCandidate?.id) { _, _ in
            hydrateFromProfileCandidate()
        }
    }

    private func hydrateFromProfileCandidate() {
        if let localProfileCandidate {
            displayName = localProfileCandidate.displayName
        }
        if localProfileCandidate == nil && accessMode == .local {
            email = ""
            password = ""
        }
    }

    @ViewBuilder
    private var localFirstEntry: some View {
        if localProfileCandidate == nil {
            OneSurfaceCard(palette: palette) {
                OneSectionHeading(palette: palette, title: "Start on this iPhone", meta: "Recommended")
                VStack(alignment: .leading, spacing: OneSpacing.xs) {
                    Text("Your name")
                        .font(OneType.label)
                        .foregroundStyle(palette.subtext)
                    TextField("Your name", text: $displayName)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                                .fill(palette.surfaceMuted)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                                .stroke(palette.border, lineWidth: 1)
                        )
                        .foregroundStyle(palette.text)
                }
                LabeledContent("Time zone", value: deviceTimezoneID)
                    .font(OneType.secondary)
                    .foregroundStyle(palette.subtext)
                OneActionButton(
                    palette: palette,
                    title: viewModel.isLoading ? "Starting..." : "Continue on This iPhone",
                    style: .primary
                ) {
                    Task {
                        await viewModel.createLocalProfile(
                            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                }
                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
        } else {
            localAccessCard
        }

        OneSurfaceCard(palette: palette) {
            OneSectionHeading(palette: palette, title: "Local storage", meta: "This pass")
            Text("Your profile, reminders, and progress stay on this iPhone. Account sync is not available in the current local runtime.")
                .font(OneType.secondary)
                .foregroundStyle(palette.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var localAccessCard: some View {
        OneSurfaceCard(palette: palette) {
            OneSectionHeading(palette: palette, title: "This iPhone", meta: localProfileCandidate == nil ? "Local profile" : "Saved profile")
            if let localProfileCandidate {
                Text(localProfileCandidate.displayName)
                    .font(OneType.title)
                    .foregroundStyle(palette.text)
                Text("Your profile and data are still on this iPhone.")
                    .font(OneType.secondary)
                    .foregroundStyle(palette.subtext)
                LabeledContent("Time zone", value: deviceTimezoneID)
                    .font(OneType.secondary)
                    .foregroundStyle(palette.subtext)
                OneActionButton(
                    palette: palette,
                    title: viewModel.isLoading ? "Continuing..." : "Continue as \(localProfileCandidate.displayName)",
                    style: .primary
                ) {
                    Task {
                        await viewModel.resumeLocalProfile()
                    }
                }
                .disabled(viewModel.isLoading)
            } else {
                VStack(alignment: .leading, spacing: OneSpacing.xs) {
                    Text("Your name")
                        .font(OneType.label)
                        .foregroundStyle(palette.subtext)
                    TextField("Your name", text: $displayName)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                                .fill(palette.surfaceMuted)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                                .stroke(palette.border, lineWidth: 1)
                        )
                        .foregroundStyle(palette.text)
                }
                LabeledContent("Time zone", value: deviceTimezoneID)
                    .font(OneType.secondary)
                    .foregroundStyle(palette.subtext)
                OneActionButton(
                    palette: palette,
                    title: viewModel.isLoading ? "Starting..." : "Continue on This iPhone",
                    style: .primary
                ) {
                    Task {
                        await viewModel.createLocalProfile(
                            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                }
                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
        }
    }

    private var signInCard: some View {
        OneSurfaceCard(palette: palette) {
            OneSectionHeading(palette: palette, title: "Account", meta: "Sync later")
            OneField(title: "Email", text: $email, placeholder: "name@example.com")
            OneSecureField(title: "Password", text: $password, placeholder: "Password")
            OneActionButton(
                palette: palette,
                title: viewModel.isLoading ? "Signing In..." : "Sign In",
                style: .primary
            ) {
                Task {
                    await viewModel.login(
                        email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password
                    )
                }
            }
            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || viewModel.isLoading)
        }
    }

    private var createAccountCard: some View {
        OneSurfaceCard(palette: palette) {
            OneSectionHeading(palette: palette, title: "Create account", meta: "Optional")
            VStack(alignment: .leading, spacing: OneSpacing.xs) {
                Text("Your name")
                    .font(OneType.label)
                    .foregroundStyle(palette.subtext)
                TextField("Your name", text: $displayName)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                            .fill(palette.surfaceMuted)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                            .stroke(palette.border, lineWidth: 1)
                    )
                    .foregroundStyle(palette.text)
            }
            OneField(title: "Email", text: $email, placeholder: "name@example.com")
            OneSecureField(title: "Password", text: $password, placeholder: "Create a password")
            LabeledContent("Time zone", value: deviceTimezoneID)
                .font(OneType.secondary)
                .foregroundStyle(palette.subtext)
            OneActionButton(
                palette: palette,
                title: viewModel.isLoading ? "Creating..." : "Create Account",
                style: .primary
            ) {
                Task {
                    await viewModel.signup(
                        email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password,
                        displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                        timezone: deviceTimezoneID
                    )
                }
            }
            .disabled(
                displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                password.isEmpty ||
                viewModel.isLoading
            )
        }
    }
}

private struct ReviewTabView: View {
    @ObservedObject var analyticsViewModel: AnalyticsViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    @ObservedObject var coachViewModel: CoachViewModel
    let currentDateLocal: String
    let weekStart: Int
    let onSelectPeriod: (PeriodType) async -> Void
    let onOpenSheet: (OneAppShell.SheetRoute) -> Void
    let onOpenCoach: () -> Void
    let onRefreshAnalytics: () async -> Void
    let onRefreshReflections: () async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeRailSection: ReviewUtilityRailSection = .review
    private let periodOptions: [PeriodType] = [.daily, .weekly, .monthly, .yearly]

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    private var featuredCoachCard: CoachCard? {
        guard !coachViewModel.cards.isEmpty else {
            return nil
        }
        let seed = currentDateLocal.unicodeScalars.reduce(into: 0) { partial, scalar in
            partial += Int(scalar.value)
        }
        return coachViewModel.cards[seed % coachViewModel.cards.count]
    }

    private var prioritizedCoachCards: [CoachCard] {
        guard let featuredCoachCard,
              let featuredIndex = coachViewModel.cards.firstIndex(where: { $0.id == featuredCoachCard.id }) else {
            return coachViewModel.cards
        }
        return Array(coachViewModel.cards[featuredIndex...]) + Array(coachViewModel.cards[..<featuredIndex])
    }

    private var supportingCoachCards: [CoachCard] {
        Array(prioritizedCoachCards.dropFirst().prefix(3))
    }

    private var primarySummary: PeriodSummary? {
        analyticsViewModel.summary ?? analyticsViewModel.weekly
    }

    private var displayedPeriod: PeriodType {
        analyticsViewModel.pendingPeriod ?? analyticsViewModel.selectedPeriod
    }

    private var reviewHeadline: String {
        guard let summary = primarySummary else {
            return "Review turns daily execution into visible progress."
        }
        if summary.periodType == .daily {
            if summary.completedItems == 0 {
                return "Today still needs a first completion."
            }
            return "Today shows \(summary.completedItems) finished step\(summary.completedItems == 1 ? "" : "s")."
        }
        if summary.completionRate >= 0.8 {
            return "Momentum is holding through this \(periodTitle(summary.periodType).lowercased())."
        }
        if summary.activeDays == 0 {
            return "This \(periodTitle(summary.periodType).lowercased()) has not started moving yet."
        }
        return "Review what changed, then keep the next step small and clear."
    }

    private var summaryNoteCount: String {
        "\(notesViewModel.sentimentSummary?.noteCount ?? 0)"
    }

    private var summaryActiveDays: String {
        "\(notesViewModel.sentimentSummary?.activeDays ?? 0)"
    }

    private var moodNoteCount: String {
        "\(analyticsViewModel.sentimentOverview?.distribution.reduce(0) { $0 + $1.count } ?? 0)"
    }

    private var dominantSummaryTitle: String {
        notesViewModel.sentimentSummary?.dominant?.title ?? "None"
    }

    private var reviewEquation: String {
        guard let summary = primarySummary else {
            return "Completion Rate = Completed / Planned"
        }
        return "Completion Rate = \(summary.completedItems) / \(summary.expectedItems) = \(Int((summary.completionRate * 100).rounded()))%"
    }

    private var selectedDayEntryTitle: String {
        let count = notesViewModel.selectedDayNotes.count
        if count == 0 {
            return "No notes on \(notesViewModel.selectedDayTitle)"
        }
        if count == 1 {
            return "1 note on \(notesViewModel.selectedDayTitle)"
        }
        return "\(count) notes on \(notesViewModel.selectedDayTitle)"
    }

    private var contributionMeta: String {
        switch analyticsViewModel.selectedPeriod {
        case .weekly:
            return "Full selected week"
        case .monthly:
            return analyticsViewModel.selectedMonthWeekDetailLabel ?? "Selected week"
        case .yearly:
            return "Full year"
        case .daily:
            return "Selected day"
        }
    }

    private var reviewNavigationTitle: String {
        activeRailSection == .review ? "Review" : activeRailSection.railItem.title
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                currentReviewPage
                    .id(activeRailSection)
                    .safeAreaInset(edge: .top) {
                        Color.clear
                            .frame(height: OneUtilityRailMetrics.persistentTopInset)
                    }
                    .transition(.opacity)

                OneUtilityRail(
                    palette: palette,
                    items: ReviewUtilityRailSection.railItems,
                    activeID: activeRailSection,
                    isSticky: true
                ) { section in
                    OneHaptics.shared.trigger(.selectionChanged)
                    withAnimation(OneMotion.animation(.stateChange, reduceMotion: reduceMotion)) {
                        activeRailSection = section
                    }
                }
                .padding(.horizontal, OneUtilityRailMetrics.stickyHorizontalInset)
                .padding(.top, OneUtilityRailMetrics.stickyTopPadding)
                .zIndex(1)
            }
            .animation(OneMotion.animation(.stateChange, reduceMotion: reduceMotion), value: activeRailSection)
            .navigationTitle(reviewNavigationTitle)
            .oneNavigationBarDisplayMode(.large)
            .task(id: "\(currentDateLocal)-\(weekStart)") {
                await bootstrapReview()
            }
            .task(id: activeRailSection.rawValue) {
                guard activeRailSection == .coach, coachViewModel.cards.isEmpty else {
                    return
                }
                await coachViewModel.load()
            }
        }
    }

    private var chartHighlightIndex: Int? {
        switch analyticsViewModel.selectedPeriod {
        case .daily:
            return analyticsViewModel.dailySummaries.indices.first
        case .weekly:
            return analyticsViewModel.dailySummaries.lastIndex(where: { $0.dateLocal == currentDateLocal })
        case .monthly:
            guard let selectedMonthWeek = analyticsViewModel.selectedMonthWeek else {
                return nil
            }
            return max(0, selectedMonthWeek - 1)
        case .yearly:
            return analyticsViewModel.chartSeries.labels.indices.last
        }
    }

    private func bootstrapReview() async {
        if analyticsViewModel.weekly == nil {
            await analyticsViewModel.loadWeekly(anchorDate: currentDateLocal, weekStart: weekStart)
        }
        if analyticsViewModel.summary == nil {
            await onSelectPeriod(analyticsViewModel.selectedPeriod)
        }
        await notesViewModel.load(
            anchorDate: notesViewModel.selectedDateLocal,
            periodType: analyticsViewModel.selectedPeriod,
            weekStart: weekStart,
            forceReload: notesViewModel.allNotes.isEmpty
        )
    }

    private func selectReviewPeriod(_ selection: PeriodType) async {
        await onSelectPeriod(selection)
        await notesViewModel.load(
            anchorDate: notesViewModel.selectedDateLocal,
            periodType: analyticsViewModel.selectedPeriod,
            weekStart: weekStart,
            forceReload: notesViewModel.allNotes.isEmpty
        )
    }

    private func selectDate(_ dateLocal: String) {
        notesViewModel.selectDay(dateLocal)
        withAnimation(OneMotion.animation(.stateChange, reduceMotion: reduceMotion)) {
            activeRailSection = .notes
        }
    }

    @ViewBuilder
    private var currentReviewPage: some View {
        switch activeRailSection {
        case .review:
            reviewPage {
                OneGlassCard(palette: palette, padding: OneSpacing.lg) {
                    Text("Review")
                        .font(OneType.label)
                        .foregroundStyle(palette.subtext)
                    Text(reviewHeadline)
                        .font(OneType.title)
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: OneSpacing.sm) {
                        SummaryMetricTile(palette: palette, title: "Completed", value: "\(primarySummary?.completedItems ?? 0)")
                        SummaryMetricTile(palette: palette, title: "Planned", value: "\(primarySummary?.expectedItems ?? 0)")
                        SummaryMetricTile(palette: palette, title: "Rate", value: "\(Int(((primarySummary?.completionRate ?? 0) * 100).rounded()))%")
                        SummaryMetricTile(palette: palette, title: "Consistency", value: "\(Int(((primarySummary?.consistencyScore ?? 0) * 100).rounded()))%")
                    }
                }

                OneSurfaceCard(palette: palette) {
                    OneSegmentedControl(
                        palette: palette,
                        options: periodOptions,
                        selection: displayedPeriod,
                        title: { periodTitle($0) }
                    ) { selection in
                        Task {
                            await selectReviewPeriod(selection)
                        }
                    }
                    if analyticsViewModel.isSwitchingPeriod {
                        HStack(spacing: OneSpacing.sm) {
                            ProgressView()
                                .tint(palette.accent)
                            Text("Updating \(displayedPeriod.rawValue) view")
                                .font(OneType.secondary)
                                .foregroundStyle(palette.subtext)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                OneSurfaceCard(palette: palette) {
                    OneSectionHeading(
                        palette: palette,
                        title: "History",
                        meta: contributionMeta
                    )
                    Group {
                        if analyticsViewModel.dailySummaries.isEmpty {
                            Text("Your progress history will appear here after the first completions.")
                                .font(OneType.secondary)
                                .foregroundStyle(palette.subtext)
                        } else if analyticsViewModel.selectedPeriod == .yearly {
                            AnalyticsYearContributionView(
                                palette: palette,
                                sections: analyticsViewModel.contributionSections,
                                onSelectDate: { dateLocal in
                                    selectDate(dateLocal)
                                }
                            )
                        } else {
                            AnalyticsContributionGrid(
                                palette: palette,
                                summaries: analyticsViewModel.dailySummaries,
                                onSelectDate: { dateLocal in
                                    selectDate(dateLocal)
                                }
                            )
                        }
                    }
                }
            }
        case .notes:
            reviewPage {
                notesSection
            }
        case .coach:
            reviewPage {
                coachPageContent
            }
        case .trend:
            reviewPage {
                trendPageContent
            }
        case .split:
            reviewPage {
                splitPageContent
            }
        case .recovery:
            reviewPage {
                recoveryPageContent
            }
        }
    }

    private func reviewPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        OneScrollScreen(
            palette: palette,
            bottomPadding: OneDockLayout.tabScreenBottomPadding
        ) {
            content()

            if let message = analyticsViewModel.errorMessage ?? notesViewModel.errorMessage {
                InlineStatusCard(message: message, kind: .danger, palette: palette)
            }
        }
    }

    @ViewBuilder
    private var trendPageContent: some View {
        if let summary = primarySummary {
            OneSurfaceCard(palette: palette) {
                OneSectionHeading(palette: palette, title: "Trend", meta: periodTitle(summary.periodType))
                HStack(spacing: OneSpacing.sm) {
                    SummaryMetricTile(palette: palette, title: "Active Days", value: "\(summary.activeDays)")
                    SummaryMetricTile(palette: palette, title: "Rate", value: "\(Int(summary.completionRate * 100))%")
                    SummaryMetricTile(palette: palette, title: "Gap", value: "\(max(summary.expectedItems - summary.completedItems, 0))")
                }
                if analyticsViewModel.chartSeries.values.isEmpty {
                    Text("Complete a few habits or tasks to build this view.")
                        .font(OneType.secondary)
                        .foregroundStyle(palette.subtext)
                } else {
                    OneActivityLane(
                        palette: palette,
                        values: analyticsViewModel.chartSeries.values,
                        labels: analyticsViewModel.chartSeries.labels,
                        highlightIndex: chartHighlightIndex,
                        onSelectIndex: analyticsViewModel.selectedPeriod == .monthly ? { index in
                            analyticsViewModel.selectMonthWeek(index + 1)
                        } : nil
                    )
                }
                ReviewEquationStrip(
                    palette: palette,
                    title: "Execution Equation",
                    equation: reviewEquation
                )
            }
        }

        if let sentimentOverview = analyticsViewModel.sentimentOverview {
            OneSurfaceCard(palette: palette) {
                OneSectionHeading(
                    palette: palette,
                    title: "Mood signal",
                    meta: sentimentOverview.dominant?.title ?? "No dominant pattern"
                )
                HStack(spacing: OneSpacing.sm) {
                    SummaryMetricTile(palette: palette, title: "Notes", value: moodNoteCount)
                    SummaryMetricTile(
                        palette: palette,
                        title: "Active Days",
                        value: "\(sentimentOverview.trend.filter { $0.sentiment != nil }.count)"
                    )
                    SummaryMetricTile(
                        palette: palette,
                        title: "Dominant",
                        value: sentimentOverview.dominant?.title ?? "None"
                    )
                }
                AnalyticsSentimentOverviewView(
                    palette: palette,
                    periodType: analyticsViewModel.selectedPeriod,
                    overview: sentimentOverview,
                    highlightedDates: analyticsViewModel.selectedPeriod == .monthly ? Set(analyticsViewModel.dailySummaries.map(\.dateLocal)) : [],
                    onOpenDate: { dateLocal in
                        selectDate(dateLocal)
                    }
                )
            }
        }
    }

    private var splitPageContent: some View {
        OneSurfaceCard(palette: palette) {
            OneSectionHeading(palette: palette, title: "Execution Split", meta: "Habits versus tasks")
            if analyticsViewModel.executionRows.isEmpty {
                Text("Habit and task mix appears after the first planned items.")
                    .font(OneType.secondary)
                    .foregroundStyle(palette.subtext)
            } else {
                ReviewTableHeader(palette: palette, columns: ["Track", "Done", "Planned", "Rate"])
                ForEach(analyticsViewModel.executionRows) { row in
                    ReviewExecutionRow(palette: palette, row: row)
                }
            }
        }
    }

    private var recoveryPageContent: some View {
        OneSurfaceCard(palette: palette) {
            OneSectionHeading(palette: palette, title: "Recovery Opportunities", meta: "Largest execution gaps")
            if analyticsViewModel.recoveryRows.isEmpty {
                Text("Opportunity rows appear when the current period has planned work.")
                    .font(OneType.secondary)
                    .foregroundStyle(palette.subtext)
            } else {
                ReviewTableHeader(palette: palette, columns: ["Span", "Gap", "Done/Plan", "Rate"])
                ForEach(analyticsViewModel.recoveryRows) { row in
                    ReviewRecoveryRow(palette: palette, row: row)
                }
            }
        }
    }

    private func scrollToSection(_ section: ReviewUtilityRailSection, scrollProxy: ScrollViewProxy) {
        OneHaptics.shared.trigger(.selectionChanged)
        activeRailSection = section
        withAnimation(OneMotion.animation(.stateChange, reduceMotion: reduceMotion)) {
            scrollProxy.scrollTo(OneUtilityRailAnchor(sectionID: section), anchor: .top)
        }
    }

    private func periodTitle(_ period: PeriodType) -> String {
        switch period {
        case .daily:
            return "Day"
        case .weekly:
            return "Week"
        case .monthly:
            return "Month"
        case .yearly:
            return "Year"
        }
    }

    private func notesPeriodTitle(_ period: PeriodType) -> String {
        periodTitle(period)
    }

    @ViewBuilder
    private func reviewSection<Content: View>(
        id: ReviewUtilityRailSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: OneSpacing.md) {
            Color.clear
                .frame(height: OneUtilityRailMetrics.anchorOffset)
                .padding(.bottom, -OneUtilityRailMetrics.anchorOffset)
                .id(OneUtilityRailAnchor(sectionID: id))
            content()
        }
        .oneUtilityRailMeasuredSection(id)
    }

    private var notesSection: some View {
        OneSurfaceCard(palette: palette) {
            VStack(alignment: .leading, spacing: OneSpacing.md) {
                HStack(alignment: .top, spacing: OneSpacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        OneSectionHeading(
                            palette: palette,
                            title: "Notes",
                            meta: notesPeriodTitle(notesViewModel.selectedPeriod)
                        )
                        Text(selectedDayEntryTitle)
                            .font(OneType.secondary)
                            .foregroundStyle(palette.subtext)
                    }
                    Spacer()
                    Button("New Note") {
                        OneHaptics.shared.trigger(.sheetPresented)
                        onOpenSheet(.addNote(anchorDate: notesViewModel.selectedDateLocal))
                    }
                    .font(OneType.label)
                    .foregroundStyle(palette.accent)
                }

                HStack(spacing: OneSpacing.sm) {
                    SummaryMetricTile(palette: palette, title: "Notes", value: summaryNoteCount)
                    SummaryMetricTile(palette: palette, title: "Active Days", value: summaryActiveDays)
                    SummaryMetricTile(palette: palette, title: "Dominant", value: dominantSummaryTitle)
                }

                HStack(spacing: 14) {
                    Button {
                        OneHaptics.shared.trigger(.selectionChanged)
                        notesViewModel.moveSelection(by: -1)
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .onePressable(scale: 0.94)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(notesViewModel.currentRangeTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text(notesViewModel.selectedDayTitle)
                            .font(OneType.secondary)
                            .foregroundStyle(palette.subtext)
                    }

                    Spacer()

                    Button {
                        OneHaptics.shared.trigger(.selectionChanged)
                        notesViewModel.moveSelection(by: 1)
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .onePressable(scale: 0.94)
                }

                switch notesViewModel.selectedPeriod {
                case .daily:
                    NotesFocusedDayCard(
                        palette: palette,
                        option: notesViewModel.dayOptions.first,
                        selectedDateLocal: notesViewModel.selectedDateLocal
                    ) { dateLocal in
                        notesViewModel.selectDay(dateLocal)
                    }
                case .weekly:
                    NotesDayStrip(
                        palette: palette,
                        options: notesViewModel.dayOptions,
                        selectedDateLocal: notesViewModel.selectedDateLocal
                    ) { dateLocal in
                        notesViewModel.selectDay(dateLocal)
                    }
                case .monthly:
                    NotesCalendarGridView(
                        palette: palette,
                        options: notesViewModel.dayOptions,
                        leadingPlaceholders: notesViewModel.leadingPlaceholders,
                        selectedDateLocal: notesViewModel.selectedDateLocal
                    ) { dateLocal in
                        notesViewModel.selectDay(dateLocal)
                    }
                case .yearly:
                    VStack(alignment: .leading, spacing: OneSpacing.sm) {
                        NotesMonthPickerView(
                            palette: palette,
                            options: notesViewModel.monthOptions,
                            selectedMonth: notesViewModel.selectedYearMonth
                        ) { month in
                            notesViewModel.selectMonth(month)
                        }
                        NotesCalendarGridView(
                            palette: palette,
                            options: notesViewModel.dayOptions,
                            leadingPlaceholders: notesViewModel.leadingPlaceholders,
                            selectedDateLocal: notesViewModel.selectedDateLocal
                        ) { dateLocal in
                            notesViewModel.selectDay(dateLocal)
                        }
                    }
                }

                if let summary = notesViewModel.sentimentSummary, !summary.distribution.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(summary.distribution) { item in
                            OneChip(
                                palette: palette,
                                title: "\(item.sentiment.title) \(item.count)",
                                kind: item.sentiment.chipKind
                            )
                        }
                    }
                }

                if notesViewModel.selectedDayNotes.isEmpty {
                    EmptyStateCard(
                        palette: palette,
                        title: "No notes for this date",
                        message: "Capture a short note when the day changes direction so Review stays useful when you return."
                    )
                } else {
                    VStack(spacing: OneSpacing.sm) {
                        ForEach(notesViewModel.selectedDayNotes) { note in
                            QuickNoteRow(
                                palette: palette,
                                note: note
                            ) {
                                Task {
                                    if await notesViewModel.delete(id: note.id) {
                                        await onRefreshReflections()
                                        await onRefreshAnalytics()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var coachPageContent: some View {
        if let featuredCoachCard {
            OneGlassCard(palette: palette) {
                Text("Coach")
                    .font(OneType.label)
                    .foregroundStyle(palette.highlight)
                Text(featuredCoachCard.title)
                    .font(OneType.title)
                    .foregroundStyle(palette.text)
                Text(featuredCoachCard.body)
                    .font(OneType.body)
                    .foregroundStyle(palette.subtext)
                    .fixedSize(horizontal: false, vertical: true)
                CoachVerseBlock(palette: palette, card: featuredCoachCard)
                if !featuredCoachCard.tags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(featuredCoachCard.tags, id: \.self) { tag in
                            OneChip(
                                palette: palette,
                                title: tag.capitalized,
                                kind: .strong
                            )
                        }
                    }
                }
            }

            ForEach(Array(supportingCoachCards.enumerated()), id: \.element.id) { index, card in
                OneSurfaceCard(palette: palette) {
                    OneSectionHeading(
                        palette: palette,
                        title: index == 0 ? "Keep moving" : "Coach note",
                        meta: nil
                    )
                    Text(card.title)
                        .font(OneType.sectionTitle)
                        .foregroundStyle(palette.text)
                    Text(card.body)
                        .font(OneType.body)
                        .foregroundStyle(palette.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                    CoachVerseBlock(palette: palette, card: card)
                    if !card.tags.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(card.tags, id: \.self) { tag in
                                OneChip(
                                    palette: palette,
                                    title: tag.capitalized,
                                    kind: .neutral
                                )
                            }
                        }
                    }
                }
            }

            OneSurfaceCard(palette: palette) {
                OneSectionHeading(palette: palette, title: "Full Coach", meta: "Expanded guidance")
                Text("Open the deeper coach workspace when you want the full set of supporting cards.")
                    .font(OneType.secondary)
                    .foregroundStyle(palette.subtext)
                    .fixedSize(horizontal: false, vertical: true)
                OneActionButton(palette: palette, title: "Open Full Coach", style: .secondary) {
                    OneHaptics.shared.trigger(.sheetPresented)
                    onOpenCoach()
                }
            }
        } else {
            EmptyStateCard(
                palette: palette,
                title: "Coach is still warming up",
                message: "Guidance will appear here once the current review context has enough signal."
            )
        }

        if let message = coachViewModel.errorMessage {
            InlineStatusCard(message: message, kind: .danger, palette: palette)
        }
    }

    @ViewBuilder
    private func trendSection(scrollProxy: ScrollViewProxy) -> some View {
        if let summary = primarySummary {
            OneSurfaceCard(palette: palette) {
                OneSectionHeading(palette: palette, title: "Trend", meta: periodTitle(summary.periodType))
                HStack(spacing: OneSpacing.sm) {
                    SummaryMetricTile(palette: palette, title: "Active Days", value: "\(summary.activeDays)")
                    SummaryMetricTile(palette: palette, title: "Rate", value: "\(Int(summary.completionRate * 100))%")
                    SummaryMetricTile(palette: palette, title: "Gap", value: "\(max(summary.expectedItems - summary.completedItems, 0))")
                }
                if analyticsViewModel.chartSeries.values.isEmpty {
                    Text("Complete a few habits or tasks to build this view.")
                        .font(OneType.secondary)
                        .foregroundStyle(palette.subtext)
                } else {
                    OneActivityLane(
                        palette: palette,
                        values: analyticsViewModel.chartSeries.values,
                        labels: analyticsViewModel.chartSeries.labels,
                        highlightIndex: chartHighlightIndex,
                        onSelectIndex: analyticsViewModel.selectedPeriod == .monthly ? { index in
                            analyticsViewModel.selectMonthWeek(index + 1)
                        } : nil
                    )
                }
                ReviewEquationStrip(
                    palette: palette,
                    title: "Execution Equation",
                    equation: reviewEquation
                )
            }
        }

        if let sentimentOverview = analyticsViewModel.sentimentOverview {
            OneSurfaceCard(palette: palette) {
                OneSectionHeading(
                    palette: palette,
                    title: "Mood signal",
                    meta: sentimentOverview.dominant?.title ?? "No dominant pattern"
                )
                HStack(spacing: OneSpacing.sm) {
                    SummaryMetricTile(palette: palette, title: "Notes", value: moodNoteCount)
                    SummaryMetricTile(
                        palette: palette,
                        title: "Active Days",
                        value: "\(sentimentOverview.trend.filter { $0.sentiment != nil }.count)"
                    )
                    SummaryMetricTile(
                        palette: palette,
                        title: "Dominant",
                        value: sentimentOverview.dominant?.title ?? "None"
                    )
                }
                AnalyticsSentimentOverviewView(
                    palette: palette,
                    periodType: analyticsViewModel.selectedPeriod,
                    overview: sentimentOverview,
                    highlightedDates: analyticsViewModel.selectedPeriod == .monthly ? Set(analyticsViewModel.dailySummaries.map(\.dateLocal)) : [],
                    onOpenDate: { dateLocal in
                        selectDate(dateLocal)
                    }
                )
            }
        }

        if primarySummary == nil, analyticsViewModel.sentimentOverview == nil {
            OneSurfaceCard(palette: palette) {
                OneSectionHeading(palette: palette, title: "Trend", meta: nil)
                Text("Trend details appear after a little more activity and note history are available.")
                    .font(OneType.secondary)
                    .foregroundStyle(palette.subtext)
            }
        }
    }
}

private struct ReviewEquationStrip: View {
    let palette: OneTheme.Palette
    let title: String
    let equation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(OneType.caption.weight(.semibold))
                .foregroundStyle(palette.subtext)
            Text(equation)
                .font(OneType.secondary.weight(.semibold))
                .foregroundStyle(palette.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .fill(palette.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}

private struct ReviewTableHeader: View {
    let palette: OneTheme.Palette
    let columns: [String]

    var body: some View {
        HStack(spacing: OneSpacing.sm) {
            ForEach(columns, id: \.self) { column in
                Text(column)
                    .font(OneType.caption.weight(.semibold))
                    .foregroundStyle(palette.subtext)
                    .frame(maxWidth: .infinity, alignment: column == columns.first ? .leading : .trailing)
            }
        }
    }
}

private struct ReviewExecutionRow: View {
    let palette: OneTheme.Palette
    let row: AnalyticsExecutionSplitRow

    var body: some View {
        HStack(spacing: OneSpacing.sm) {
            Text(row.title)
                .font(OneType.body.weight(.semibold))
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.completedItems)")
                .font(OneType.secondary)
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("\(row.expectedItems)")
                .font(OneType.secondary)
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("\(Int((row.completionRate * 100).rounded()))%")
                .font(OneType.secondary.weight(.semibold))
                .foregroundStyle(palette.subtext)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

private struct ReviewRecoveryRow: View {
    let palette: OneTheme.Palette
    let row: AnalyticsRecoveryRow

    var body: some View {
        HStack(spacing: OneSpacing.sm) {
            Text(row.label)
                .font(OneType.body.weight(.semibold))
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.gap)")
                .font(OneType.secondary.weight(.semibold))
                .foregroundStyle(row.gap > 0 ? palette.warning : palette.subtext)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("\(row.completedItems)/\(row.expectedItems)")
                .font(OneType.secondary)
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("\(Int((row.completionRate * 100).rounded()))%")
                .font(OneType.secondary.weight(.semibold))
                .foregroundStyle(palette.subtext)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

private struct TodayTabView: View {
    @ObservedObject var todayViewModel: TodayViewModel
    @ObservedObject var tasksViewModel: TasksViewModel
    let currentDateLocal: String
    let onOpenSheet: (OneAppShell.SheetRoute) -> Void
    let onOpenReview: (String) -> Void
    let onRefreshTasksContext: () async -> Void
    let onRefreshAnalytics: () async -> Void

    @State private var isReordering = false
    @State private var isUpNextExpanded = false
    @State private var isUpNextShowingAll = false
    @State private var isCompletedSectionExpanded = false
    @State private var visibleMilestoneCount = 0
    @State private var showsCompletionPayoff = false
    @State private var busyItemIDs: Set<String> = []
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    private var dateLocal: String {
        todayViewModel.dateLocal.isEmpty ? currentDateLocal : todayViewModel.dateLocal
    }

    private var activeItems: [TodayItem] {
        todayViewModel.items.filter { !$0.completed }
    }

    private var needsAttentionItems: [TodayItem] {
        activeItems.filter(isNeedsAttention)
    }

    private var upNextItems: [TodayItem] {
        activeItems.filter { !isNeedsAttention($0) }
    }

    private var upNextPreviewLimit: Int {
        3
    }

    private var showsCompactNeedsAttention: Bool {
        needsAttentionItems.count > 2
    }

    private var visibleExpandedUpNextItems: [TodayItem] {
        guard isUpNextExpanded else {
            return []
        }
        guard !isUpNextShowingAll, upNextItems.count > upNextPreviewLimit else {
            return upNextItems
        }
        return Array(upNextItems.prefix(upNextPreviewLimit))
    }

    private var completedItems: [TodayItem] {
        todayViewModel.items.filter(\.completed)
    }

    private var focusTitle: String {
        if todayViewModel.totalCount == 0 {
            return "A clear day starts here"
        }
        if todayViewModel.completionRatio == 1 {
            return "Today is complete"
        }
        if let first = needsAttentionItems.first ?? activeItems.first {
            return "Start with \(first.title)"
        }
        return "Keep going"
    }

    private var focusMessage: String {
        if todayViewModel.totalCount == 0 {
            return "Add a habit, task, or note to shape today."
        }
        if todayViewModel.completionRatio == 1 {
            return "Everything planned for today is done. Let the rest stay quiet."
        }
        if !needsAttentionItems.isEmpty {
            return "Time-sensitive and high-focus work stays in view first."
        }
        return "Keep the next small step moving."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OneScreenBackground(palette: palette)
                List {
                    rowSurface {
                        OneGlassCard(palette: palette) {
                            HStack(alignment: .top, spacing: OneSpacing.md) {
                                VStack(alignment: .leading, spacing: OneSpacing.xs) {
                                    Text(OneDate.longDate(from: dateLocal))
                                        .font(OneType.label)
                                        .foregroundStyle(palette.subtext)
                                    Text(focusTitle)
                                        .font(OneType.title)
                                        .foregroundStyle(palette.text)
                                    Text("\(activeItems.count) remaining of \(todayViewModel.totalCount)")
                                        .font(OneType.secondary)
                                        .foregroundStyle(palette.subtext)
                                    Text(focusMessage)
                                        .font(OneType.body)
                                        .foregroundStyle(palette.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 10) {
                                    OneProgressCluster(
                                        palette: palette,
                                        progress: todayViewModel.completionRatio,
                                        label: "\(Int(todayViewModel.completionRatio * 100))%"
                                    )
                                    if todayViewModel.completionRatio == 1 {
                                        HStack(spacing: 6) {
                                            OneIcon(key: .success, palette: palette, size: 14, tint: palette.highlight)
                                            Text("Done")
                                        }
                                        .font(OneType.caption.weight(.semibold))
                                        .foregroundStyle(palette.highlight)
                                    } else if !needsAttentionItems.isEmpty {
                                        HStack(spacing: 6) {
                                            OneIcon(key: .warning, palette: palette, size: 14, tint: palette.highlight)
                                            Text("Needs attention")
                                        }
                                        .font(OneType.caption.weight(.semibold))
                                        .foregroundStyle(palette.highlight)
                                    }
                                }
                            }
                        }
                    }

                    if showsCompletionPayoff {
                        rowSurface {
                            OneSurfaceCard(palette: palette) {
                                HStack(spacing: 8) {
                                    OneIcon(key: .completedDay, palette: palette, size: 18, tint: palette.highlight)
                                    Text("Day complete")
                                }
                                .font(OneType.sectionTitle)
                                .foregroundStyle(palette.highlight)
                                Text("You finished what you planned today. That progress is ready for review when you return.")
                                    .font(OneType.secondary)
                                    .foregroundStyle(palette.subtext)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if isReordering {
                        rowSurface {
                            OneSectionHeading(palette: palette, title: "Reorder", meta: "Drag to save order")
                        }

                        ForEach(activeItems) { item in
                            rowSurface {
                                TodayItemCard(
                                    palette: palette,
                                    item: item,
                                    categoryName: categoryName(for: item.categoryId),
                                    categoryIcon: categoryIcon(for: item.categoryId),
                                    isReordering: true,
                                    isHighlighted: item.id == todayViewModel.highlightedItemID,
                                    isBusy: isBusy(item),
                                    allowsSwipeCompletion: false,
                                    allowsSwipeDelete: false,
                                    onToggle: {
                                        toggleItem(item)
                                    },
                                    onDelete: nil
                                ) {
                                    destination(for: item)
                                }
                            }
                        }
                        .onMove { source, destination in
                            var reordered = activeItems
                            reordered.move(fromOffsets: source, toOffset: destination)
                            Task {
                                await todayViewModel.reorder(items: reordered, dateLocal: dateLocal)
                            }
                        }
                    } else if todayViewModel.items.isEmpty {
                        rowSurface {
                            EmptyStateCard(
                                palette: palette,
                                title: "Nothing is planned for today",
                                message: "Add a habit, task, or note to start shaping the day."
                            )
                        }
                    } else {
                        if !needsAttentionItems.isEmpty {
                            if showsCompactNeedsAttention {
                                compactItemsSection(
                                    title: "Needs attention",
                                    meta: "\(needsAttentionItems.count)",
                                    items: needsAttentionItems
                                )
                            } else {
                                rowSurface {
                                    OneSectionHeading(palette: palette, title: "Needs attention", meta: "\(needsAttentionItems.count)")
                                }

                                ForEach(needsAttentionItems) { item in
                                    rowSurface {
                                        TodayItemCard(
                                            palette: palette,
                                            item: item,
                                            categoryName: categoryName(for: item.categoryId),
                                            categoryIcon: categoryIcon(for: item.categoryId),
                                            isReordering: false,
                                            isHighlighted: item.id == todayViewModel.highlightedItemID,
                                            isBusy: isBusy(item),
                                            allowsSwipeCompletion: allowsSwipeCompletion(for: item),
                                            allowsSwipeDelete: allowsSwipeDelete(for: item),
                                            onToggle: {
                                                toggleItem(item)
                                            },
                                            onDelete: {
                                                deleteItem(item)
                                            }
                                        ) {
                                            destination(for: item)
                                        }
                                    }
                                }
                            }
                        }

                        if !upNextItems.isEmpty {
                            rowSurface {
                                OneSurfaceCard(palette: palette) {
                                    Button {
                                        toggleUpNextDisclosure()
                                    } label: {
                                        HStack(spacing: OneSpacing.sm) {
                                            OneSectionHeading(
                                                palette: palette,
                                                title: "Up next",
                                                meta: "\(upNextItems.count)"
                                            )
                                            Spacer()
                                            Image(systemName: isUpNextExpanded ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(palette.subtext)
                                        }
                                    }
                                    .onePressable(scale: 0.994)
                                }
                            }

                            if isUpNextExpanded {
                                ForEach(visibleExpandedUpNextItems) { item in
                                    rowSurface {
                                        CompactTodayActionRow(
                                            palette: palette,
                                            item: item,
                                            categoryName: categoryName(for: item.categoryId),
                                            isHighlighted: item.id == todayViewModel.highlightedItemID,
                                            isBusy: isBusy(item),
                                            allowsSwipeCompletion: allowsSwipeCompletion(for: item),
                                            allowsSwipeDelete: allowsSwipeDelete(for: item),
                                            onToggle: {
                                                toggleItem(item)
                                            },
                                            onDelete: {
                                                deleteItem(item)
                                            }
                                        ) {
                                            destination(for: item)
                                        }
                                    }
                                }

                                if upNextItems.count > upNextPreviewLimit {
                                    rowSurface {
                                        OneSurfaceCard(palette: palette) {
                                            Button {
                                                toggleUpNextShowAll()
                                            } label: {
                                                HStack(spacing: OneSpacing.sm) {
                                                    Text(isUpNextShowingAll ? "Show less" : "Show all")
                                                        .font(OneType.label)
                                                        .foregroundStyle(palette.accent)
                                                    Spacer()
                                                    Text(
                                                        isUpNextShowingAll
                                                        ? "Show preview"
                                                        : "\(upNextItems.count - visibleExpandedUpNextItems.count) more"
                                                    )
                                                    .font(OneType.caption)
                                                    .foregroundStyle(palette.subtext)
                                                }
                                            }
                                            .onePressable(scale: 0.99)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !completedItems.isEmpty {
                        rowSurface {
                            OneSurfaceCard(palette: palette) {
                                Button {
                                    OneHaptics.shared.trigger(.selectionChanged)
                                    withAnimation(OneMotion.animation(.expand)) {
                                        isCompletedSectionExpanded.toggle()
                                    }
                                } label: {
                                    HStack(spacing: OneSpacing.sm) {
                                        OneSectionHeading(
                                            palette: palette,
                                            title: "Completed",
                                            meta: "\(completedItems.count)"
                                        )
                                        Spacer()
                                        Image(systemName: isCompletedSectionExpanded ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(palette.subtext)
                                    }
                                }
                                .onePressable(scale: 0.994)

                                if isCompletedSectionExpanded {
                                    VStack(spacing: OneSpacing.sm) {
                                        ForEach(completedItems) { item in
                                            TodayItemCard(
                                                palette: palette,
                                                item: item,
                                                categoryName: categoryName(for: item.categoryId),
                                                categoryIcon: categoryIcon(for: item.categoryId),
                                                isReordering: false,
                                                isHighlighted: item.id == todayViewModel.highlightedItemID,
                                                isBusy: isBusy(item),
                                                allowsSwipeCompletion: false,
                                                allowsSwipeDelete: false,
                                                onToggle: {
                                                    toggleItem(item)
                                                },
                                                onDelete: nil
                                            ) {
                                                destination(for: item)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if let message = tasksViewModel.errorMessage ?? todayViewModel.errorMessage {
                        rowSurface {
                            InlineStatusCard(message: message, kind: .danger, palette: palette)
                        }
                    }

                    rowSurface {
                        Color.clear
                            .frame(height: OneDockLayout.listBottomSpacerHeight)
                    }
                }
            }
        }
        .navigationTitle("Today")
        .oneNavigationBarDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .oneNavigationLeading) {
                Button("Review") {
                    onOpenReview(dateLocal)
                }
            }
            ToolbarItem(placement: .oneNavigationTrailing) {
                Button(isReordering ? "Done" : "Reorder") {
                    OneHaptics.shared.trigger(isReordering ? .reorderDrop : .reorderPickup)
                    withAnimation(OneMotion.animation(.expand)) {
                        isReordering.toggle()
                        #if os(iOS)
                        editMode = isReordering ? .active : .inactive
                        #endif
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 8)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .redacted(reason: todayViewModel.isLoading ? .placeholder : [])
        .oneListRowSpacing(10)
        .onChange(of: todayViewModel.milestoneCount) { _, newValue in
            guard newValue > visibleMilestoneCount else {
                return
            }
            visibleMilestoneCount = newValue
            showsCompletionPayoff = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.6))
                withAnimation(OneMotion.animation(.dismiss)) {
                    showsCompletionPayoff = false
                }
            }
        }
        .onChange(of: upNextItems.count) { _, newValue in
            if newValue == 0 {
                isUpNextExpanded = false
            }
            if newValue <= upNextPreviewLimit {
                isUpNextShowingAll = false
            }
        }
        #if os(iOS)
        .oneListEditing(editMode: $editMode)
        #endif
    }

    private func isNeedsAttention(_ item: TodayItem) -> Bool {
        item.priorityTier == .urgent || item.priorityTier == .high || isOverdue(item)
    }

    private func isOverdue(_ item: TodayItem) -> Bool {
        guard let dueAt = item.dueAt else {
            return false
        }
        return dueAt < Date()
    }

    @ViewBuilder
    private func destination(for item: TodayItem) -> some View {
        if item.itemType == .habit {
            HabitDetailView(
                habitId: item.itemId,
                tasksViewModel: tasksViewModel,
                anchorDate: dateLocal,
                onSave: {
                    await onRefreshTasksContext()
                }
            )
        } else {
            TodoDetailView(
                todoId: item.itemId,
                tasksViewModel: tasksViewModel,
                onSave: {
                    await onRefreshTasksContext()
                }
            )
        }
    }

    private func categoryName(for categoryId: String) -> String {
        tasksViewModel.categories.first(where: { $0.id == categoryId })?.name ?? "Category"
    }

    private func categoryIcon(for categoryId: String) -> OneIconKey {
        let category = tasksViewModel.categories.first(where: { $0.id == categoryId })
        return actionQueueCategoryIcon(name: category?.name ?? "Category", storedIcon: category?.icon)
    }

    private func isBusy(_ item: TodayItem) -> Bool {
        busyItemIDs.contains(item.id)
    }

    private func allowsSwipeCompletion(for item: TodayItem) -> Bool {
        !isReordering && !item.completed
    }

    private func allowsSwipeDelete(for item: TodayItem) -> Bool {
        !isReordering && !item.completed && item.itemType == .todo
    }

    private func toggleUpNextDisclosure() {
        OneHaptics.shared.trigger(.selectionChanged)
        withAnimation(OneMotion.animation(.expand)) {
            isUpNextExpanded.toggle()
            if !isUpNextExpanded {
                isUpNextShowingAll = false
            }
        }
    }

    private func toggleUpNextShowAll() {
        OneHaptics.shared.trigger(.selectionChanged)
        withAnimation(OneMotion.animation(.expand)) {
            isUpNextShowingAll.toggle()
        }
    }

    private func toggleItem(_ item: TodayItem) {
        performItemAction(for: item) {
            await todayViewModel.toggle(item: item, dateLocal: dateLocal)
            await onRefreshTasksContext()
        }
    }

    private func deleteItem(_ item: TodayItem) {
        guard item.itemType == .todo else {
            return
        }
        performItemAction(for: item) {
            guard await tasksViewModel.deleteTodo(id: item.itemId) else {
                return
            }
            OneSyncFeedbackCenter.shared.showSynced(
                title: "Task deleted",
                message: "\(item.title) was removed from Today."
            )
            await onRefreshTasksContext()
        }
    }

    private func performItemAction(for item: TodayItem, action: @escaping () async -> Void) {
        guard !busyItemIDs.contains(item.id) else {
            return
        }
        busyItemIDs.insert(item.id)
        Task { @MainActor in
            defer { busyItemIDs.remove(item.id) }
            await action()
        }
    }

    @ViewBuilder
    private func compactItemsSection(
        title: String,
        meta: String,
        items: [TodayItem]
    ) -> some View {
        rowSurface {
            OneSurfaceCard(palette: palette) {
                OneSectionHeading(
                    palette: palette,
                    title: title,
                    meta: meta
                )
            }
        }

        ForEach(items) { item in
            rowSurface {
                CompactTodayActionRow(
                    palette: palette,
                    item: item,
                    categoryName: categoryName(for: item.categoryId),
                    isHighlighted: item.id == todayViewModel.highlightedItemID,
                    isBusy: isBusy(item),
                    allowsSwipeCompletion: allowsSwipeCompletion(for: item),
                    allowsSwipeDelete: allowsSwipeDelete(for: item),
                    onToggle: {
                        toggleItem(item)
                    },
                    onDelete: {
                        deleteItem(item)
                    }
                ) {
                    destination(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func rowSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private struct NotesSheetView: View {
    private struct ComposerRoute: Identifiable {
        let dateLocal: String

        var id: String { dateLocal }
    }

    @ObservedObject var viewModel: NotesViewModel
    let initialAnchorDate: String
    let initialPeriod: PeriodType
    let weekStart: Int
    let onDismiss: () -> Void
    let onRefreshAnalytics: () async -> Void
    let onRefreshReflections: () async -> Void

    @State private var pendingDeleteNote: ReflectionNote?
    @State private var composerRoute: ComposerRoute?
    @Environment(\.colorScheme) private var colorScheme

    private let periodOptions: [PeriodType] = [.daily, .weekly, .monthly, .yearly]

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    private var summaryNoteCount: String {
        "\(viewModel.sentimentSummary?.noteCount ?? 0)"
    }

    private var summaryActiveDays: String {
        "\(viewModel.sentimentSummary?.activeDays ?? 0)"
    }

    private var dominantSummaryTitle: String {
        viewModel.sentimentSummary?.dominant?.title ?? "None"
    }

    private var selectedDayEntryTitle: String {
        let count = viewModel.selectedDayNotes.count
        if count == 0 {
            return "No notes on \(viewModel.selectedDayTitle)"
        }
        if count == 1 {
            return "1 note on \(viewModel.selectedDayTitle)"
        }
        return "\(count) notes on \(viewModel.selectedDayTitle)"
    }

    var body: some View {
        NavigationStack {
            OneScrollScreen(
                palette: palette,
                bottomPadding: 36
            ) {
                OneGlassCard(palette: palette) {
                    OneSectionHeading(
                        palette: palette,
                        title: "Notes overview",
                        meta: notesPeriodTitle(viewModel.selectedPeriod)
                    )
                    Text("Review note volume, mood, and history without opening the capture flow.")
                        .font(OneType.secondary)
                        .foregroundStyle(palette.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        SummaryMetricTile(palette: palette, title: "Notes", value: summaryNoteCount)
                        SummaryMetricTile(palette: palette, title: "Active Days", value: summaryActiveDays)
                        SummaryMetricTile(palette: palette, title: "Dominant", value: dominantSummaryTitle)
                    }
                    if let summary = viewModel.sentimentSummary, !summary.distribution.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(summary.distribution) { item in
                                OneChip(
                                    palette: palette,
                                    title: "\(item.sentiment.title) \(item.count)",
                                    kind: item.sentiment.chipKind
                                )
                            }
                        }
                    }
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedDayEntryTitle)
                                .font(OneType.label)
                                .foregroundStyle(palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Use quick add when you want a focused note capture instead of opening history.")
                                .font(OneType.caption)
                                .foregroundStyle(palette.subtext)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button("New Note") {
                            OneHaptics.shared.trigger(.sheetPresented)
                            composerRoute = ComposerRoute(dateLocal: viewModel.selectedDateLocal)
                        }
                        .font(OneType.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(palette.accentSoft)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(palette.border, lineWidth: 1)
                        )
                        .buttonStyle(.plain)
                        .onePressable(scale: 0.97)
                    }
                }
                .oneEntranceReveal(index: 0)

                OneGlassCard(palette: palette) {
                    OneSegmentedControl(
                        palette: palette,
                        options: periodOptions,
                        selection: viewModel.selectedPeriod,
                        title: { notesPeriodTitle($0) }
                    ) { period in
                        viewModel.selectPeriod(period)
                    }
                }
                .oneEntranceReveal(index: 1)

                OneSurfaceCard(palette: palette) {
                    OneSectionHeading(
                        palette: palette,
                        title: "Browse dates",
                        meta: notesPeriodTitle(viewModel.selectedPeriod)
                    )
                    HStack(spacing: 14) {
                        Button {
                            OneHaptics.shared.trigger(.selectionChanged)
                            viewModel.moveSelection(by: -1)
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(palette.accent)
                        }
                        .onePressable(scale: 0.94)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.currentRangeTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text(viewModel.selectedDayTitle)
                                .font(OneType.secondary)
                                .foregroundStyle(palette.subtext)
                        }

                        Spacer()

                        Button {
                            OneHaptics.shared.trigger(.selectionChanged)
                            viewModel.moveSelection(by: 1)
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(palette.accent)
                        }
                        .onePressable(scale: 0.94)
                    }
                }
                .oneEntranceReveal(index: 2)

                OneSurfaceCard(palette: palette) {
                    switch viewModel.selectedPeriod {
                    case .daily:
                        NotesFocusedDayCard(
                            palette: palette,
                            option: viewModel.dayOptions.first,
                            selectedDateLocal: viewModel.selectedDateLocal
                        ) { dateLocal in
                            viewModel.selectDay(dateLocal)
                        }
                    case .weekly:
                        NotesDayStrip(
                            palette: palette,
                            options: viewModel.dayOptions,
                            selectedDateLocal: viewModel.selectedDateLocal
                        ) { dateLocal in
                            viewModel.selectDay(dateLocal)
                        }
                    case .monthly:
                        NotesCalendarGridView(
                            palette: palette,
                            options: viewModel.dayOptions,
                            leadingPlaceholders: viewModel.leadingPlaceholders,
                            selectedDateLocal: viewModel.selectedDateLocal
                        ) { dateLocal in
                            viewModel.selectDay(dateLocal)
                        }
                    case .yearly:
                        VStack(alignment: .leading, spacing: 16) {
                            NotesMonthPickerView(
                                palette: palette,
                                options: viewModel.monthOptions,
                                selectedMonth: viewModel.selectedYearMonth
                            ) { month in
                                viewModel.selectMonth(month)
                            }
                            NotesCalendarGridView(
                                palette: palette,
                                options: viewModel.dayOptions,
                                leadingPlaceholders: viewModel.leadingPlaceholders,
                                selectedDateLocal: viewModel.selectedDateLocal
                            ) { dateLocal in
                                viewModel.selectDay(dateLocal)
                            }
                        }
                    }
                }
                .oneEntranceReveal(index: 3)

                OneSurfaceCard(palette: palette) {
                    OneSectionHeading(
                        palette: palette,
                        title: "History",
                        meta: viewModel.selectedDayTitle
                    )

                    if viewModel.selectedDayNotes.isEmpty {
                        EmptyStateCard(
                            palette: palette,
                            title: "No notes for this date",
                            message: "Pick another day to review history, or use New Note for a focused capture flow."
                        )
                    } else {
                        VStack(spacing: 10) {
                            ForEach(viewModel.selectedDayNotes) { note in
                                QuickNoteRow(
                                    palette: palette,
                                    note: note,
                                    onDelete: {
                                        pendingDeleteNote = note
                                    }
                                )
                            }
                        }
                    }
                }
                .oneEntranceReveal(index: 4)

                if let message = viewModel.errorMessage {
                    InlineStatusCard(message: message, kind: .danger, palette: palette)
                        .oneEntranceReveal(index: 5)
                }
            }
            .navigationTitle("Notes")
            .oneNavigationBarDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .oneNavigationTrailing) {
                    Button("Done") {
                        OneHaptics.shared.trigger(.sheetDismissed)
                        onDismiss()
                    }
                }
            }
            .task(id: "\(initialAnchorDate)-\(initialPeriod.rawValue)-\(weekStart)") {
                await viewModel.load(
                    anchorDate: initialAnchorDate,
                    periodType: initialPeriod,
                    weekStart: weekStart,
                    forceReload: true
                )
            }
            .confirmationDialog(
                "Delete this note?",
                isPresented: Binding(
                    get: { pendingDeleteNote != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingDeleteNote = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Note", role: .destructive) {
                    guard let note = pendingDeleteNote else {
                        return
                    }
                    OneHaptics.shared.trigger(.destructiveConfirmed)
                    Task {
                        if await viewModel.delete(id: note.id) {
                            pendingDeleteNote = nil
                            await onRefreshReflections()
                            await onRefreshAnalytics()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteNote = nil
                }
            } message: {
                Text("This removes the note and its sentiment from your history.")
            }
            .sheet(item: $composerRoute) { route in
                NoteComposerSheetView(
                    viewModel: viewModel,
                    anchorDate: route.dateLocal,
                    onDismiss: {
                        composerRoute = nil
                    },
                    onRefreshAnalytics: onRefreshAnalytics,
                    onRefreshReflections: onRefreshReflections
                )
            }
        }
    }

    private func notesPeriodTitle(_ period: PeriodType) -> String {
        switch period {
        case .daily:
            return "Day"
        case .weekly:
            return "Week"
        case .monthly:
            return "Month"
        case .yearly:
            return "Year"
        }
    }
}

private struct NotesFocusedDayCard: View {
    let palette: OneTheme.Palette
    let option: NotesDayOption?
    let selectedDateLocal: String
    let onSelect: (String) -> Void

    var body: some View {
        if let option {
            Button {
                OneHaptics.shared.trigger(.selectionChanged)
                onSelect(option.dateLocal)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.weekdayLabel.uppercased())
                            .font(OneType.caption)
                            .foregroundStyle(palette.subtext)
                        Text("\(option.dayNumber)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(palette.text)
                    }
                    Spacer()
                    Image(systemName: option.sentiment?.symbolName ?? (option.hasNotes ? "circle.fill" : "circle"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(option.sentiment?.tint(in: palette) ?? palette.subtext)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                        .fill(option.dateLocal == selectedDateLocal ? palette.accentSoft : palette.surfaceMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                        .stroke(option.dateLocal == selectedDateLocal ? palette.accent : palette.border, lineWidth: 1)
                )
            }
            .onePressable(scale: 0.985)
        }
    }
}

private struct NoteComposerSheetView: View {
    @ObservedObject var viewModel: NotesViewModel
    let anchorDate: String
    let onDismiss: () -> Void
    let onRefreshAnalytics: () async -> Void
    let onRefreshReflections: () async -> Void

    @State private var draftContent = ""
    @State private var draftSentiment: ReflectionSentiment? = .focused
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @FocusState private var isComposerFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            OneScrollScreen(palette: palette, bottomPadding: 36) {
                OneGlassCard(palette: palette) {
                    OneSectionHeading(
                        palette: palette,
                        title: "New note",
                        meta: OneDate.longDate(from: anchorDate)
                    )
                    Text("Capture what matters without opening your note history.")
                        .font(OneType.secondary)
                        .foregroundStyle(palette.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                    SentimentPickerRow(
                        palette: palette,
                        selectedSentiment: $draftSentiment
                    )
                    OneTextEditorField(
                        title: "Reflection",
                        text: $draftContent,
                        placeholder: "What happened, what mattered, or what should not be lost?",
                        isFocused: $isComposerFocused
                    )
                    Text("Saves to \(OneDate.longDate(from: anchorDate))")
                        .font(OneType.caption)
                        .foregroundStyle(palette.subtext)
                    OneActionButton(
                        palette: palette,
                        title: isSaving ? "Saving..." : "Save Note",
                        style: .primary
                    ) {
                        guard !isSaving else {
                            return
                        }
                        Task {
                            await save()
                        }
                    }
                    .disabled(
                        isSaving ||
                        draftSentiment == nil ||
                        draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                if let saveErrorMessage {
                    InlineStatusCard(message: saveErrorMessage, kind: .danger, palette: palette)
                }
            }
            .navigationTitle("Add Note")
            .oneNavigationBarDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .oneNavigationLeading) {
                    Button("Cancel") {
                        OneHaptics.shared.trigger(.sheetDismissed)
                        onDismiss()
                    }
                }
            }
            .task {
                guard !isComposerFocused else {
                    return
                }
                try? await Task.sleep(for: .milliseconds(180))
                isComposerFocused = true
            }
        }
    }

    private func save() async {
        guard let draftSentiment else {
            return
        }
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }

        guard await viewModel.createNote(
            content: draftContent,
            sentiment: draftSentiment,
            for: anchorDate
        ) != nil else {
            saveErrorMessage = viewModel.errorMessage ?? "Could not save note."
            return
        }

        await onRefreshReflections()
        await onRefreshAnalytics()
        try? await Task.sleep(for: .milliseconds(220))
        onDismiss()
    }
}

private struct NotesDayStrip: View {
    let palette: OneTheme.Palette
    let options: [NotesDayOption]
    let selectedDateLocal: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options) { option in
                Button {
                    OneHaptics.shared.trigger(.selectionChanged)
                    onSelect(option.dateLocal)
                } label: {
                    VStack(spacing: 6) {
                        Text(option.weekdayLabel.uppercased())
                            .font(OneType.caption)
                            .foregroundStyle(option.dateLocal == selectedDateLocal ? palette.text : palette.subtext)
                        Text("\(option.dayNumber)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Circle()
                            .fill(option.sentiment?.tint(in: palette) ?? (option.hasNotes ? palette.subtext : Color.clear))
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(option.hasNotes ? Color.clear : palette.border, lineWidth: 1)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                            .fill(option.dateLocal == selectedDateLocal ? palette.accentSoft : palette.surfaceMuted)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                            .stroke(option.dateLocal == selectedDateLocal ? palette.accent : palette.border, lineWidth: 1)
                    )
                }
                .onePressable(scale: 0.97)
            }
        }
    }
}

private struct NotesMonthPickerView: View {
    let palette: OneTheme.Palette
    let options: [NotesMonthOption]
    let selectedMonth: Int
    let onSelect: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(options) { option in
                Button {
                    OneHaptics.shared.trigger(.selectionChanged)
                    onSelect(option.month)
                } label: {
                    VStack(spacing: 4) {
                        Text(option.label)
                            .font(OneType.label)
                            .foregroundStyle(palette.text)
                        Text(option.dominant?.title ?? "No notes")
                            .font(OneType.caption)
                            .foregroundStyle(option.dominant?.tint(in: palette) ?? palette.subtext)
                        Text("\(option.noteCount)")
                            .font(OneType.caption)
                            .foregroundStyle(palette.subtext)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                            .fill(option.month == selectedMonth ? palette.accentSoft : palette.surfaceMuted)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                            .stroke(option.month == selectedMonth ? palette.accent : palette.border, lineWidth: 1)
                    )
                }
                .onePressable(scale: 0.97)
            }
        }
    }
}

private struct NotesCalendarGridView: View {
    let palette: OneTheme.Palette
    let options: [NotesDayOption]
    let leadingPlaceholders: Int
    let selectedDateLocal: String
    let onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.subtext)
                    .frame(maxWidth: .infinity)
            }

            ForEach(0..<leadingPlaceholders, id: \.self) { _ in
                Color.clear
                    .frame(height: 48)
            }

            ForEach(options) { option in
                Button {
                    OneHaptics.shared.trigger(.selectionChanged)
                    onSelect(option.dateLocal)
                } label: {
                    VStack(spacing: 4) {
                        Text("\(option.dayNumber)")
                            .font(OneType.label)
                            .foregroundStyle(palette.text)
                        Circle()
                            .fill(option.sentiment?.tint(in: palette) ?? (option.hasNotes ? palette.subtext : Color.clear))
                            .frame(width: 7, height: 7)
                            .overlay(
                                Circle()
                                    .stroke(option.hasNotes ? Color.clear : palette.border.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(option.dateLocal == selectedDateLocal ? palette.accentSoft : palette.surfaceMuted)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(option.dateLocal == selectedDateLocal ? palette.accent : palette.border, lineWidth: 1)
                    )
                }
                .onePressable(scale: 0.96)
            }
        }
    }
}

private struct ProfileTabView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var profileViewModel: ProfileViewModel
    @ObservedObject var coachViewModel: CoachViewModel
    let onOpenSheet: (OneAppShell.SheetRoute) -> Void

    @State private var displayName = ""
    @State private var selectedTheme: Theme = .system
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    private var deviceTimezoneID: String {
        OneDate.deviceTimeZoneIdentifier
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Profile") {
                    TextField("Your name", text: $displayName)
                    LabeledContent("Time zone", value: deviceTimezoneID)
                    Button("Save name") {
                        Task {
                            await profileViewModel.saveProfile(displayName: displayName)
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $selectedTheme) {
                        Text("System").tag(Theme.system)
                        Text("Light").tag(Theme.light)
                        Text("Dark").tag(Theme.dark)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedTheme) { _, theme in
                        OneHaptics.shared.trigger(.selectionChanged)
                        Task {
                            await profileViewModel.savePreferences(
                                input: UserPreferencesUpdateInput(theme: theme)
                            )
                        }
                    }
                }

                Section("Device Status") {
                    Button {
                        OneHaptics.shared.trigger(.sheetPresented)
                        onOpenSheet(.notifications)
                    } label: {
                        OneSettingsRow(
                            palette: palette,
                            iconKey: .notifications,
                            title: "Notifications",
                            meta: "Permission, schedules, quiet hours, and reminder types.",
                            tail: notificationMeta
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        OneHaptics.shared.trigger(.sheetPresented)
                        onOpenSheet(.coach)
                    } label: {
                        OneSettingsRow(
                            palette: palette,
                            iconKey: .coach,
                            title: "Coach",
                            meta: coachViewModel.cards.first?.title ?? "Daily guidance that stays secondary.",
                            tail: nil
                        )
                    }
                    .buttonStyle(.plain)
                }

                Section("About") {
                    Text("One is built for calm daily execution on iPhone. Data stays on this device unless you choose an account.")
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        OneHaptics.shared.trigger(.destructiveConfirmed)
                        Task {
                            await authViewModel.logout()
                        }
                    }
                } header: {
                    Text("Session")
                } footer: {
                    Text("Signing out ends the current session on this device.")
                }

                if let message = profileViewModel.errorMessage {
                    Section {
                        InlineStatusCard(message: message, kind: .danger, palette: palette)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(OneScreenBackground(palette: palette))
            .navigationTitle("Settings")
            .oneNavigationBarDisplayMode(.large)
            .oneKeyboardDismissible()
            .onAppear {
                hydrateFromLoadedData()
            }
            .onChange(of: profileViewModel.user?.id) { _, _ in
                hydrateFromLoadedData()
            }
            .onChange(of: profileViewModel.preferences?.theme) { _, _ in
                hydrateFromLoadedData()
            }
        }
    }

    private func hydrateFromLoadedData() {
        if let user = profileViewModel.user {
            displayName = user.displayName
        }
        if let preferences = profileViewModel.preferences {
            selectedTheme = preferences.theme
        }
    }

    private var notificationMeta: String {
        guard let status = profileViewModel.notificationStatus else {
            return "Set up"
        }
        guard status.permissionGranted else {
            return "Permission off"
        }
        return "\(status.scheduledCount) scheduled"
    }

}

private struct HabitFormSheet: View {
    let categories: [Category]
    let onSave: (HabitCreateInput) async -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedCategoryID = ""
    @State private var notes = ""
    @State private var recurrence = HabitRecurrenceRule()
    @State private var selectedPriorityTier: PriorityTier = .standard
    @State private var usesPreferredTime = false
    @State private var preferredTimeSelection = Date()
    @State private var showsAdvanced = false
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    TextField("Morning workout", text: $title)
                    Picker("Category", selection: $selectedCategoryID) {
                        ForEach(categories, id: \.id) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                }

                Section("Schedule") {
                    RecurrenceBuilderCard(palette: palette, recurrence: $recurrence)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                    Toggle("Preferred time", isOn: $usesPreferredTime)
                    if usesPreferredTime {
                        DatePicker("Time", selection: $preferredTimeSelection, displayedComponents: [.hourAndMinute])
                    }
                }

                Section {
                    PriorityTierSelector(
                        palette: palette,
                        title: "Focus level",
                        subtitle: "High and urgent habits stay more visible in Today.",
                        selection: selectedPriorityTier
                    ) { tier in
                        selectedPriorityTier = tier
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section {
                    Button(showsAdvanced ? "Hide more options" : "More options") {
                        withAnimation(OneMotion.animation(.expand)) {
                            showsAdvanced.toggle()
                        }
                    }
                }

                if showsAdvanced {
                    Section("Notes") {
                        OneTextEditorField(title: "Notes", text: $notes, placeholder: "Optional context")
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(OneScreenBackground(palette: palette))
            .navigationTitle("Add Habit")
            .oneNavigationBarDisplayMode(.inline)
            .oneKeyboardDismissible()
            .toolbar {
                ToolbarItem(placement: .oneNavigationLeading) {
                    Button("Cancel") {
                        OneHaptics.shared.trigger(.sheetDismissed)
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .oneNavigationTrailing) {
                    Button("Add") {
                        Task {
                            await onSave(
                                HabitCreateInput(
                                    categoryId: selectedCategoryID,
                                    title: title,
                                    notes: notes,
                                    recurrenceRule: recurrence.rawValue,
                                    priorityWeight: selectedPriorityTier.representativeValue,
                                    preferredTime: usesPreferredTime ? OneTimeValueFormatter.string(from: preferredTimeSelection) : nil
                                )
                            )
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCategoryID.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if selectedCategoryID.isEmpty {
                    selectedCategoryID = categories.first?.id ?? ""
                }
            }
        }
    }
}

private struct TodoFormSheet: View {
    let categories: [Category]
    let onSave: (TodoCreateInput) async -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var selectedCategoryID = ""
    @State private var selectedPriorityTier: PriorityTier = .standard
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var showsAdvanced = false
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Submit project draft", text: $title)
                    Picker("Category", selection: $selectedCategoryID) {
                        ForEach(categories, id: \.id) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                }

                Section("Timing") {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due date", selection: $dueDate)
                    }
                }

                Section {
                    PriorityTierSelector(
                        palette: palette,
                        title: "Focus level",
                        subtitle: "Urgent tasks stay at the top of Today.",
                        selection: selectedPriorityTier
                    ) { tier in
                        selectedPriorityTier = tier
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section {
                    Button(showsAdvanced ? "Hide more options" : "More options") {
                        withAnimation(OneMotion.animation(.expand)) {
                            showsAdvanced.toggle()
                        }
                    }
                }

                if showsAdvanced {
                    Section("Notes") {
                        OneTextEditorField(title: "Notes", text: $notes, placeholder: "Optional context")
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(OneScreenBackground(palette: palette))
            .navigationTitle("Add Task")
            .oneNavigationBarDisplayMode(.inline)
            .oneKeyboardDismissible()
            .toolbar {
                ToolbarItem(placement: .oneNavigationLeading) {
                    Button("Cancel") {
                        OneHaptics.shared.trigger(.sheetDismissed)
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .oneNavigationTrailing) {
                    Button("Add") {
                        Task {
                            await onSave(
                                TodoCreateInput(
                                    categoryId: selectedCategoryID,
                                    title: title,
                                    notes: notes,
                                    dueAt: hasDueDate ? dueDate : nil,
                                    priority: selectedPriorityTier.representativeValue,
                                    isPinned: selectedPriorityTier == .urgent
                                )
                            )
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCategoryID.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if selectedCategoryID.isEmpty {
                    selectedCategoryID = categories.first?.id ?? ""
                }
            }
        }
    }
}

private struct HabitDetailView: View {
    let habitId: String
    @ObservedObject var tasksViewModel: TasksViewModel
    let anchorDate: String
    let onSave: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedCategoryID = ""
    @State private var notes = ""
    @State private var recurrenceRule = HabitRecurrenceRule()
    @State private var selectedPriorityTier: PriorityTier = .standard
    @State private var isActive = true
    @State private var stats: HabitStats?
    @State private var pendingDelete = false
    @State private var usesPreferredTime = false
    @State private var preferredTimeSelection = Date()
    @State private var showsAdvanced = false
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    private var habit: Habit? {
        tasksViewModel.habits.first(where: { $0.id == habitId })
    }

    var body: some View {
        Form {
            Section("Overview") {
                LabeledContent("Schedule", value: recurrenceRule.summary)
                LabeledContent("Status", value: isActive ? "Active" : "Paused")
                LabeledContent("Focus level", value: selectedPriorityTier.title)
                if let stats {
                    LabeledContent("Current streak", value: "\(stats.streakCurrent)")
                    LabeledContent("Completed", value: "\(stats.completedWindow)")
                    LabeledContent("Completion", value: "\(Int(stats.completionRateWindow * 100))%")
                }
                if usesPreferredTime {
                    LabeledContent("Preferred time", value: OneDate.timeString(from: preferredTimeSelection))
                }
            }

            Section("Details") {
                TextField("Habit name", text: $title)
                Picker("Category", selection: $selectedCategoryID) {
                    ForEach(tasksViewModel.categories, id: \.id) { category in
                        Text(category.name).tag(category.id)
                    }
                }
                Toggle("Active", isOn: $isActive)
                Toggle("Preferred time", isOn: $usesPreferredTime)
                if usesPreferredTime {
                    DatePicker("Time", selection: $preferredTimeSelection, displayedComponents: [.hourAndMinute])
                }
            }

            Section("Schedule builder") {
                RecurrenceBuilderCard(palette: palette, recurrence: $recurrenceRule)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section {
                PriorityTierSelector(
                    palette: palette,
                    title: "Focus level",
                    subtitle: "Paused habits stay out of Today. Higher focus levels stay visible when active.",
                    selection: selectedPriorityTier
                ) { tier in
                    selectedPriorityTier = tier
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section {
                Button(showsAdvanced ? "Hide more options" : "More options") {
                    withAnimation(OneMotion.animation(.expand)) {
                        showsAdvanced.toggle()
                    }
                }
            }

            if showsAdvanced {
                Section("Notes") {
                    OneTextEditorField(title: "Notes", text: $notes, placeholder: "Optional context")
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }

            Section {
                Button("Delete habit", role: .destructive) {
                    pendingDelete = true
                }
            } footer: {
                Text("Deleting this habit removes it from future schedules.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(OneScreenBackground(palette: palette))
        .navigationTitle(habit?.title ?? "Habit")
        .oneNavigationBarDisplayMode(.inline)
        .oneKeyboardDismissible()
        .toolbar {
            ToolbarItem(placement: .oneNavigationTrailing) {
                Button("Save") {
                    Task {
                        guard await tasksViewModel.updateHabit(
                            id: habitId,
                            input: HabitUpdateInput(
                                categoryId: selectedCategoryID,
                                title: title,
                                notes: notes,
                                recurrenceRule: recurrenceRule.rawValue,
                                priorityWeight: selectedPriorityTier.representativeValue,
                                preferredTime: usesPreferredTime ? OneTimeValueFormatter.string(from: preferredTimeSelection) : nil,
                                clearPreferredTime: !usesPreferredTime,
                                isActive: isActive
                            )
                        ) != nil else {
                            return
                        }
                        await onSave()
                        dismiss()
                    }
                }
                .fontWeight(.semibold)
            }
        }
        .task {
            if tasksViewModel.habits.isEmpty {
                await tasksViewModel.loadTasks()
            }
            hydrateFromHabit()
            stats = await tasksViewModel.loadHabitStats(habitId: habitId, anchorDate: anchorDate, windowDays: 30)
        }
        .confirmationDialog("Delete this habit?", isPresented: $pendingDelete, titleVisibility: .visible) {
            Button("Delete habit", role: .destructive) {
                OneHaptics.shared.trigger(.destructiveConfirmed)
                Task {
                    if await tasksViewModel.deleteHabit(id: habitId) {
                        await onSave()
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the habit from future schedules.")
        }
    }

    private func hydrateFromHabit() {
        guard let habit else {
            return
        }
        title = habit.title
        selectedCategoryID = habit.categoryId
        notes = habit.notes
        recurrenceRule = HabitRecurrenceRule(rawValue: habit.recurrenceRule)
        selectedPriorityTier = habit.priorityTier
        isActive = habit.isActive
        usesPreferredTime = habit.preferredTime != nil
        if let preferredTime = OneTimeValueFormatter.date(from: habit.preferredTime) {
            preferredTimeSelection = preferredTime
        }
    }
}

private struct TodoDetailView: View {
    let todoId: String
    @ObservedObject var tasksViewModel: TasksViewModel
    let onSave: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedCategoryID = ""
    @State private var notes = ""
    @State private var selectedPriorityTier: PriorityTier = .standard
    @State private var status: TodoStatus = .open
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var pendingDelete = false
    @State private var showsAdvanced = false
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    private var todo: Todo? {
        tasksViewModel.todos.first(where: { $0.id == todoId })
    }

    var body: some View {
        Form {
            Section("Overview") {
                LabeledContent("Status", value: statusTitle)
                LabeledContent("Focus level", value: selectedPriorityTier.title)
                LabeledContent("Due", value: hasDueDate ? OneDate.dateTimeString(from: dueDate) : "No due date")
            }

            Section("Details") {
                TextField("Task title", text: $title)
                Picker("Category", selection: $selectedCategoryID) {
                    ForEach(tasksViewModel.categories, id: \.id) { category in
                        Text(category.name).tag(category.id)
                    }
                }
                Picker("Status", selection: $status) {
                    Text("Open").tag(TodoStatus.open)
                    Text("Completed").tag(TodoStatus.completed)
                    Text("Canceled").tag(TodoStatus.canceled)
                }
                Toggle("Due date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Due at", selection: $dueDate)
                }
            }

            Section {
                PriorityTierSelector(
                    palette: palette,
                    title: "Focus level",
                    subtitle: "Urgent tasks stay at the top of Today.",
                    selection: selectedPriorityTier
                ) { tier in
                    selectedPriorityTier = tier
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section {
                Button(showsAdvanced ? "Hide more options" : "More options") {
                    withAnimation(OneMotion.animation(.expand)) {
                        showsAdvanced.toggle()
                    }
                }
            }

            if showsAdvanced {
                Section("Notes") {
                    OneTextEditorField(title: "Notes", text: $notes, placeholder: "Optional context")
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }

            Section {
                Button("Delete task", role: .destructive) {
                    pendingDelete = true
                }
            } footer: {
                Text("Deleting this task removes it from Today and future follow-up.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(OneScreenBackground(palette: palette))
        .navigationTitle(todo?.title ?? "Task")
        .oneNavigationBarDisplayMode(.inline)
        .oneKeyboardDismissible()
        .toolbar {
            ToolbarItem(placement: .oneNavigationTrailing) {
                Button("Save") {
                    Task {
                        guard await tasksViewModel.updateTodo(
                            id: todoId,
                            input: TodoUpdateInput(
                                categoryId: selectedCategoryID,
                                title: title,
                                notes: notes,
                                dueAt: hasDueDate ? dueDate : nil,
                                clearDueAt: !hasDueDate,
                                priority: selectedPriorityTier.representativeValue,
                                isPinned: selectedPriorityTier == .urgent,
                                status: status
                            )
                        ) != nil else {
                            return
                        }
                        await onSave()
                        dismiss()
                    }
                }
                .fontWeight(.semibold)
            }
        }
        .task {
            if tasksViewModel.todos.isEmpty {
                await tasksViewModel.loadTasks()
            }
            hydrateFromTodo()
        }
        .confirmationDialog("Delete this task?", isPresented: $pendingDelete, titleVisibility: .visible) {
            Button("Delete task", role: .destructive) {
                OneHaptics.shared.trigger(.destructiveConfirmed)
                Task {
                    if await tasksViewModel.deleteTodo(id: todoId) {
                        await onSave()
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the task from Today and future follow-up.")
        }
    }

    private func hydrateFromTodo() {
        guard let todo else {
            return
        }
        title = todo.title
        selectedCategoryID = todo.categoryId
        notes = todo.notes
        selectedPriorityTier = todo.priorityTier
        status = todo.status
        hasDueDate = todo.dueAt != nil
        if let dueAt = todo.dueAt {
            dueDate = dueAt
        }
    }

    private var statusTitle: String {
        switch status {
        case .open:
            return "Open"
        case .completed:
            return "Completed"
        case .canceled:
            return "Canceled"
        }
    }
}

private struct NotificationPreferencesView: View {
    @ObservedObject var profileViewModel: ProfileViewModel
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var habitReminders = true
    @State private var todoReminders = true
    @State private var reflectionPrompts = true
    @State private var weeklySummary = true
    @State private var quietHoursStartSelection = OneTimeValueFormatter.date(from: "22:00:00") ?? Date()
    @State private var quietHoursEndSelection = OneTimeValueFormatter.date(from: "07:00:00") ?? Date()
    @State private var coachEnabled = true
    @State private var isSaving = false
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let status = profileViewModel.notificationStatus {
                    Section {
                        LabeledContent("Permission", value: status.permissionGranted ? "On" : "Off")
                        LabeledContent("Scheduled", value: "\(status.scheduledCount)")
                        if let lastRefreshedAt = status.lastRefreshedAt {
                            LabeledContent("Last refreshed", value: lastRefreshedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        Button("Refresh schedules") {
                            Task {
                                await profileViewModel.refreshSchedules()
                            }
                        }
                        if !status.permissionGranted {
                            Button("Open iPhone Settings") {
                                openSystemSettings()
                            }
                        }
                        if let error = status.lastError, !error.isEmpty {
                            InlineStatusCard(message: error, kind: .danger, palette: palette)
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        }
                    } header: {
                        Text("Schedule status")
                    } footer: {
                        Text(
                            status.permissionGranted
                            ? "Habit and task reminders are being scheduled on this device."
                            : "Reminder scheduling needs notification permission in iOS Settings."
                        )
                    }
                }

                Section {
                    Toggle("Habit reminders", isOn: $habitReminders)
                    Toggle("Task reminders", isOn: $todoReminders)
                    Toggle("Notes prompts", isOn: $reflectionPrompts)
                    Toggle("Weekly summary", isOn: $weeklySummary)
                    Toggle("Coach prompts", isOn: $coachEnabled)
                } header: {
                    Text("Reminder types")
                } footer: {
                    Text("Only habit and task reminders are scheduled on this iPhone right now. Notes prompts, weekly summary, and coach prompts are saved as preferences for later support.")
                }

                Section {
                    DatePicker("Starts", selection: $quietHoursStartSelection, displayedComponents: [.hourAndMinute])
                    DatePicker("Ends", selection: $quietHoursEndSelection, displayedComponents: [.hourAndMinute])
                } header: {
                    Text("Quiet hours")
                } footer: {
                    Text("Quiet hours silence reminders between the times you set here.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(OneScreenBackground(palette: palette))
            .navigationTitle("Notifications")
            .oneNavigationBarDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .oneNavigationLeading) {
                    Button("Done") {
                        OneHaptics.shared.trigger(.sheetDismissed)
                        onClose()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .oneNavigationTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task {
                            guard !isSaving else {
                                return
                            }
                            isSaving = true
                            defer { isSaving = false }

                            guard await profileViewModel.savePreferences(
                                input: UserPreferencesUpdateInput(
                                    quietHoursStart: OneTimeValueFormatter.string(from: quietHoursStartSelection),
                                    quietHoursEnd: OneTimeValueFormatter.string(from: quietHoursEndSelection),
                                    notificationFlags: [
                                        "habit_reminders": habitReminders,
                                        "todo_reminders": todoReminders,
                                        "reflection_prompts": reflectionPrompts,
                                        "weekly_summary": weeklySummary,
                                    ],
                                    coachEnabled: coachEnabled
                                )
                            ) else {
                                return
                            }

                            try? await Task.sleep(for: .milliseconds(260))
                            OneHaptics.shared.trigger(.sheetDismissed)
                            onClose()
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                    .fontWeight(.semibold)
                }
            }
            .task {
                if profileViewModel.preferences == nil {
                    await profileViewModel.load()
                }
                hydrateFromLoadedData()
                await profileViewModel.refreshSchedules()
            }
        }
    }

    private func hydrateFromLoadedData() {
        guard let preferences = profileViewModel.preferences else {
            return
        }
        habitReminders = preferences.notificationFlags["habit_reminders"] ?? true
        todoReminders = preferences.notificationFlags["todo_reminders"] ?? true
        reflectionPrompts = preferences.notificationFlags["reflection_prompts"] ?? true
        weeklySummary = preferences.notificationFlags["weekly_summary"] ?? true
        if let quietHoursStart = OneTimeValueFormatter.date(from: preferences.quietHoursStart) {
            quietHoursStartSelection = quietHoursStart
        }
        if let quietHoursEnd = OneTimeValueFormatter.date(from: preferences.quietHoursEnd) {
            quietHoursEndSelection = quietHoursEnd
        }
        coachEnabled = preferences.coachEnabled
    }

    private func openSystemSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
        #endif
    }
}

private struct CoachSheetView: View {
    @ObservedObject var viewModel: CoachViewModel
    @ObservedObject var todayViewModel: TodayViewModel
    @ObservedObject var analyticsViewModel: AnalyticsViewModel
    @ObservedObject var reflectionsViewModel: ReflectionsViewModel
    let currentDateLocal: String
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    private var remainingItems: [TodayItem] {
        todayViewModel.items.filter { !$0.completed }
    }

    private var focusItem: TodayItem? {
        remainingItems.first(where: { $0.priorityTier == .urgent || $0.priorityTier == .high }) ?? remainingItems.first
    }

    private var todayNotes: [ReflectionNote] {
        reflectionsViewModel.notes.filter { $0.periodStart == currentDateLocal }
    }

    private var recentNotes: [ReflectionNote] {
        Array(reflectionsViewModel.notes.prefix(6))
    }

    private var reflectionSignal: [ReflectionNote] {
        todayNotes.isEmpty ? recentNotes : todayNotes
    }

    private var reflectionSummary: ReflectionSentimentVoteSummary {
        reflectionSentimentSummary(for: reflectionSignal)
    }

    private var prioritizedCards: [CoachCard] {
        let dateSeed = currentDateLocal.unicodeScalars.reduce(into: 0) { partial, scalar in
            partial += Int(scalar.value)
        }
        return Array(
            viewModel.cards.enumerated().sorted { lhs, rhs in
                coachCardScore(lhs.element, offset: lhs.offset, seed: dateSeed) >
                coachCardScore(rhs.element, offset: rhs.offset, seed: dateSeed)
            }
        )
        .map(\.element)
    }

    private var featuredCard: CoachCard? {
        prioritizedCards.first
    }

    private var supportingCards: [CoachCard] {
        Array(prioritizedCards.dropFirst().prefix(2))
    }

    var body: some View {
        NavigationStack {
            OneScrollScreen(palette: palette, bottomPadding: 36) {
                OneGlassCard(palette: palette) {
                    Text("Today")
                        .font(OneType.label)
                        .foregroundStyle(palette.highlight)
                    Text(featuredCard?.title ?? "Clear guidance needs a real signal")
                        .font(OneType.title)
                        .foregroundStyle(palette.text)
                    Text(featuredCard?.body ?? "The coach will get sharper as you log tasks, habits, and notes. For now it stays focused on the next honest move.")
                        .font(OneType.body)
                        .foregroundStyle(palette.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                    if let featuredCard {
                        CoachVerseBlock(palette: palette, card: featuredCard)
                        if !featuredCard.tags.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(featuredCard.tags, id: \.self) { tag in
                                    OneChip(
                                        palette: palette,
                                        title: tag.capitalized,
                                        kind: .strong
                                    )
                                }
                            }
                        }
                    } else {
                        Text("Add a note or complete the first item in Today to give the coach a stronger read on the day.")
                            .font(OneType.caption)
                            .foregroundStyle(palette.subtext)
                    }
                }
                .oneEntranceReveal(index: 0)

                OneSurfaceCard(palette: palette) {
                    OneSectionHeading(
                        palette: palette,
                        title: "Right now",
                        meta: focusItem == nil ? "No current item" : "Today"
                    )
                    Text(currentGuidanceTitle)
                        .font(OneType.sectionTitle)
                        .foregroundStyle(palette.text)
                    Text(currentGuidanceBody)
                        .font(OneType.body)
                        .foregroundStyle(palette.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .oneEntranceReveal(index: 1)

                OneSurfaceCard(palette: palette) {
                    OneSectionHeading(
                        palette: palette,
                        title: "Momentum",
                        meta: weeklyMeta
                    )
                    Text(momentumTitle)
                        .font(OneType.sectionTitle)
                        .foregroundStyle(palette.text)
                    Text(momentumBody)
                        .font(OneType.body)
                        .foregroundStyle(palette.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .oneEntranceReveal(index: 2)

                OneSurfaceCard(palette: palette) {
                    OneSectionHeading(
                        palette: palette,
                        title: "Notes signal",
                        meta: todayNotes.isEmpty ? "No note today" : "\(todayNotes.count) today"
                    )
                    Text(reflectionTitle)
                        .font(OneType.sectionTitle)
                        .foregroundStyle(palette.text)
                    Text(reflectionBody)
                        .font(OneType.body)
                        .foregroundStyle(palette.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .oneEntranceReveal(index: 3)

                ForEach(Array(supportingCards.enumerated()), id: \.element.id) { index, card in
                    OneSurfaceCard(palette: palette) {
                        Text(card.title)
                            .font(OneType.sectionTitle)
                            .foregroundStyle(palette.text)
                        Text(card.body)
                            .font(OneType.body)
                            .foregroundStyle(palette.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                        CoachVerseBlock(palette: palette, card: card)
                        if !card.tags.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(card.tags, id: \.self) { tag in
                                    OneChip(
                                        palette: palette,
                                        title: tag.capitalized,
                                        kind: .neutral
                                    )
                                }
                            }
                        }
                    }
                    .oneEntranceReveal(index: index + 4)
                }

                if let message = viewModel.errorMessage {
                    InlineStatusCard(message: message, kind: .danger, palette: palette)
                        .oneEntranceReveal(index: 6)
                }
            }
            .navigationTitle("Coach")
            .oneNavigationBarDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .oneNavigationTrailing) {
                    Button("Done") {
                        OneHaptics.shared.trigger(.sheetDismissed)
                        onClose()
                    }
                }
            }
            .task {
                if viewModel.cards.isEmpty {
                    await viewModel.load()
                }
            }
        }
    }

    private var currentGuidanceTitle: String {
        guard let focusItem else {
            return "Set the day with one honest commitment"
        }
        if focusItem.priorityTier == .urgent {
            return "Protect \(focusItem.title)"
        }
        return "Keep \(focusItem.title) moving"
    }

    private var currentGuidanceBody: String {
        guard let focusItem else {
            return "Nothing active is carrying the day yet. Add one task, habit, or note before the plan starts diffusing."
        }
        if focusItem.priorityTier == .urgent {
            return "This is carrying the most weight in Today right now. Finish the first usable step before widening the queue."
        }
        if remainingItems.count <= 2 {
            return "The queue is still small. Protect the next decisive action instead of creating more motion than the day needs."
        }
        return "You have \(remainingItems.count) open items. The coach is narrowing your attention to the next clear step so the list stays usable."
    }

    private var weeklyMeta: String {
        guard let weekly = analyticsViewModel.weekly else {
            return "Waiting for signal"
        }
        return "\(weekly.completedItems)/\(weekly.expectedItems)"
    }

    private var momentumTitle: String {
        guard let weekly = analyticsViewModel.weekly else {
            return "Momentum appears after the first completions"
        }
        if weekly.completionRate >= 0.75 {
            return "This week already has real traction"
        }
        if weekly.activeDays == 0 {
            return "The week still needs a first rep"
        }
        return "The week needs a smaller, cleaner target"
    }

    private var momentumBody: String {
        guard let weekly = analyticsViewModel.weekly else {
            return "Once habits, tasks, and notes start moving, the coach will anchor its advice to what is actually happening."
        }
        if weekly.completionRate >= 0.75 {
            return "You have finished \(weekly.completedItems) of \(weekly.expectedItems) planned items across \(weekly.activeDays) active days. Keep protecting the rhythm instead of chasing more intensity."
        }
        if weekly.activeDays == 0 {
            return "No activity is recorded yet for this week. One completion is enough to turn the week from abstract to real."
        }
        return "You have finished \(weekly.completedItems) of \(weekly.expectedItems). Reduce the scope of the next move so you can recover momentum instead of bargaining with a heavy plan."
    }

    private var reflectionTitle: String {
        if todayNotes.isEmpty {
            if let dominant = reflectionSummary.dominant {
                return "Recent notes lean \(dominant.title.lowercased())"
            }
            return "No note is anchoring the day yet"
        }
        if let dominant = reflectionSummary.dominant {
            return "Today's notes lean \(dominant.title.lowercased())"
        }
        return "Today's notes are still mixed"
    }

    private var reflectionBody: String {
        if todayNotes.isEmpty {
            if recentNotes.isEmpty {
                return "Write one honest line while the day is still fresh. Notes make the coach and the review screens materially sharper."
            }
            return "You have \(recentNotes.count) recent notes, but nothing for today yet. Capture one line while the day is still in motion so the signal stays current."
        }
        return "You have \(todayNotes.count) note\(todayNotes.count == 1 ? "" : "s") for today. Keep using notes when the day changes direction so guidance is built from the real pattern, not from placeholders."
    }

    private func coachCardScore(_ card: CoachCard, offset: Int, seed: Int) -> Int {
        let tags = Set(card.tags.map { $0.lowercased() })
        var score = seed % max(viewModel.cards.count, 1) == offset ? 4 : 0

        if let focusItem, focusItem.priorityTier == .urgent || focusItem.priorityTier == .high {
            if !tags.isDisjoint(with: ["focus", "discipline", "clarity", "stress"]) {
                score += 8
            }
        }

        if let weekly = analyticsViewModel.weekly, weekly.completionRate < 0.45 {
            if !tags.isDisjoint(with: ["reset", "resilience", "recovery", "rest"]) {
                score += 7
            }
        }

        if let dominant = reflectionSummary.dominant {
            switch dominant {
            case .stressed:
                if !tags.isDisjoint(with: ["stress", "rest", "clarity"]) {
                    score += 6
                }
            case .tired:
                if !tags.isDisjoint(with: ["fatigue", "recovery", "rest"]) {
                    score += 6
                }
            case .focused:
                if !tags.isDisjoint(with: ["focus", "discipline", "consistency"]) {
                    score += 6
                }
            case .great:
                if !tags.isDisjoint(with: ["faithfulness", "streaks", "habits"]) {
                    score += 5
                }
            case .okay:
                if !tags.isDisjoint(with: ["clarity", "planning", "consistency"]) {
                    score += 4
                }
            }
        }

        return score
    }
}

private struct TodayItemCard<Destination: View>: View {
    let palette: OneTheme.Palette
    let item: TodayItem
    let categoryName: String
    let categoryIcon: OneIconKey
    let isReordering: Bool
    let isHighlighted: Bool
    let isBusy: Bool
    let allowsSwipeCompletion: Bool
    let allowsSwipeDelete: Bool
    let onToggle: () -> Void
    let onDelete: (() -> Void)?
    @ViewBuilder let destination: Destination
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var supportingLine: String? {
        if let dueAt = item.dueAt {
            return "Due \(OneDate.dateTimeString(from: dueAt))"
        }
        if let preferredTime = item.preferredTime, !preferredTime.isEmpty {
            if let parsedPreferredTime = OneTimeValueFormatter.date(from: preferredTime) {
                return "Around \(OneDate.timeString(from: parsedPreferredTime))"
            }
            return "Around \(preferredTime)"
        }
        return item.subtitle?.hasPrefix("Habit ·") == true ? nil : item.subtitle
    }

    private var itemTypeTitle: String {
        item.itemType == .habit ? "Habit" : "Task"
    }

    private var metadataLine: String {
        [itemTypeTitle, categoryName].joined(separator: " · ")
    }

    private var priorityTier: PriorityTier {
        item.priorityTier
    }

    private var isOverdue: Bool {
        guard let dueAt = item.dueAt, !item.completed else {
            return false
        }
        return dueAt < Date()
    }

    private var emphasisColor: Color {
        if isOverdue || priorityTier == .urgent {
            return palette.danger
        }
        if priorityTier == .high {
            return palette.highlight
        }
        return palette.accent
    }

    var body: some View {
        OneSurfaceCard(palette: palette) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(item.completed ? palette.success : palette.subtext)
                        .scaleEffect(isHighlighted && !reduceMotion ? 1.08 : 1)
                }
                .onePressable(scale: 0.92, opacity: 0.85)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(item.completed ? palette.subtext : palette.text)
                            .strikethrough(item.completed, color: palette.subtext)
                        if priorityTier == .high || priorityTier == .urgent {
                            Text(priorityTier.title)
                                .font(OneType.caption.weight(.semibold))
                                .foregroundStyle(emphasisColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(emphasisColor.opacity(0.12))
                                )
                        }
                    }
                    if let supportingLine, !supportingLine.isEmpty {
                        Text(supportingLine)
                            .font(OneType.secondary)
                            .foregroundStyle(isOverdue ? palette.danger : palette.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(metadataLine)
                        .font(OneType.caption)
                        .foregroundStyle(palette.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(spacing: 10) {
                    if isReordering {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.subtext)
                            .padding(.top, 4)
                    }
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else {
                        NavigationLink {
                            destination
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.accent)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                                        .fill(palette.surfaceMuted)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                                        .stroke(palette.border, lineWidth: 1)
                                )
                        }
                        .onePressable(scale: 0.96)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: OneTheme.radiusLarge, style: .continuous)
                .fill(
                    isHighlighted
                    ? (item.completed ? palette.success.opacity(palette.isDark ? 0.16 : 0.1) : palette.accentSoft)
                    : Color.clear
                )
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                .fill(item.completed ? palette.success : emphasisColor)
                .frame(width: 4)
                .padding(.vertical, 12)
                .opacity(item.completed || priorityTier == .high || priorityTier == .urgent || isOverdue ? 1 : 0.2)
        }
        .scaleEffect(isHighlighted && !reduceMotion ? 0.992 : 1)
        .opacity(isBusy ? 0.82 : 1)
        .disabled(isBusy)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if allowsSwipeDelete, let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: allowsSwipeCompletion) {
            if allowsSwipeCompletion {
                Button(action: onToggle) {
                    Label("Done", systemImage: "checkmark.circle.fill")
                }
                .tint(palette.success)
            }
        }
        .animation(
            OneMotion.animation(item.completed ? .stateChange : .dismiss, reduceMotion: reduceMotion),
            value: isHighlighted
        )
    }
}

private struct EmojiBadge: View {
    let symbol: OneIconKey
    let palette: OneTheme.Palette
    var accessibilityLabel: String? = nil

    var body: some View {
        OneIconBadge(
            key: symbol,
            palette: palette,
            size: 30,
            tint: palette.symbol,
            background: palette.surfaceMuted,
            border: palette.border,
            shape: .roundedSquare
        )
        .accessibilityLabel(accessibilityLabel ?? symbol.accessibilityLabel)
    }
}

private struct SymbolBadge: View {
    let systemName: String
    let tint: Color
    let palette: OneTheme.Palette

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                    .fill(palette.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
    }
}

private struct PriorityBadge: View {
    let tier: PriorityTier
    let palette: OneTheme.Palette

    var body: some View {
        Circle()
            .fill(priorityTierColor(for: tier, palette: palette))
            .frame(width: 24, height: 24)
            .overlay(
                Circle()
                    .stroke(palette.surface, lineWidth: 2)
            )
            .overlay(
                Circle()
                    .stroke(priorityTierColor(for: tier, palette: palette).opacity(0.35), lineWidth: 6)
            )
            .accessibilityLabel("\(tier.title) priority")
    }
}

private struct QuickNoteRow: View {
    let palette: OneTheme.Palette
    let note: ReflectionNote
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(note.createdAt.map { OneDate.timeString(from: $0) } ?? note.periodStart)
                    .font(OneType.caption)
                    .foregroundStyle(palette.subtext)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: note.sentiment.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(note.sentiment.tint(in: palette))
                    Text(note.sentiment.title)
                        .font(OneType.caption)
                        .foregroundStyle(palette.text)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(palette.surface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.danger)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                                .fill(palette.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                                .stroke(palette.border, lineWidth: 1)
                        )
                }
                .onePressable(scale: 0.92)
            }
            Text(note.content)
                .font(OneType.body)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .fill(palette.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}

private struct SentimentPickerRow: View {
    let palette: OneTheme.Palette
    @Binding var selectedSentiment: ReflectionSentiment?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mood")
                .font(OneType.label)
                .foregroundStyle(palette.subtext)
            FlowLayout(spacing: 8) {
                ForEach(ReflectionSentiment.allCases, id: \.self) { sentiment in
                    Button {
                        OneHaptics.shared.trigger(.selectionChanged)
                        selectedSentiment = sentiment
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: sentiment.symbolName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(selectedSentiment == sentiment ? sentiment.tint(in: palette) : palette.subtext)
                            Text(sentiment.title)
                                .font(OneType.caption)
                                .foregroundStyle(palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                            .frame(minWidth: 92, minHeight: 74)
                            .scaleEffect(selectedSentiment == sentiment && !reduceMotion ? 1.04 : 1)
                            .background(
                                RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                                    .fill(selectedSentiment == sentiment ? palette.accentSoft : palette.surfaceMuted)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                                    .stroke(selectedSentiment == sentiment ? palette.accent : palette.border, lineWidth: 1)
                            )
                    }
                    .onePressable(scale: 0.94, opacity: 0.9)
                    .animation(
                        OneMotion.animation(.stateChange, reduceMotion: reduceMotion),
                        value: selectedSentiment == sentiment
                    )
                    .accessibilityLabel(sentiment.title)
                }
            }
        }
    }
}

private struct CompactTodayPreviewRow: View {
    let palette: OneTheme.Palette
    let item: TodayItem

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(item.completed ? palette.success.opacity(0.2) : palette.surfaceStrong)
                .frame(width: 34, height: 34)
                .overlay(
                    OneIcon(
                        key: item.completed ? .success : (item.itemType == .habit ? .habit : .task),
                        palette: palette,
                        size: 16,
                        tint: item.completed ? palette.success : palette.symbol
                    )
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(item.subtitle ?? (item.itemType == .habit ? "Scheduled habit" : "Task"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.subtext)
            }
            Spacer()
            if item.isPinned == true {
                Image(systemName: "pin.fill")
                    .foregroundStyle(palette.danger)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .fill(palette.surfaceMuted)
        )
    }
}

private struct CompactTodayActionRow<Destination: View>: View {
    let palette: OneTheme.Palette
    let item: TodayItem
    let categoryName: String
    let isHighlighted: Bool
    let isBusy: Bool
    let allowsSwipeCompletion: Bool
    let allowsSwipeDelete: Bool
    let onToggle: () -> Void
    let onDelete: (() -> Void)?
    @ViewBuilder let destination: Destination
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var supportingLine: String? {
        if let dueAt = item.dueAt {
            return "Due \(OneDate.dateTimeString(from: dueAt))"
        }
        if let preferredTime = item.preferredTime, !preferredTime.isEmpty {
            return "Around \(preferredTime)"
        }
        return item.subtitle
    }

    private var emphasisColor: Color {
        if item.priorityTier == .urgent {
            return palette.danger
        }
        if item.priorityTier == .high {
            return palette.highlight
        }
        return palette.accent
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(item.completed ? palette.success : palette.subtext)
            }
            .onePressable(scale: 0.92, opacity: 0.84)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.completed ? palette.subtext : palette.text)
                        .lineLimit(1)
                    if item.priorityTier == .high || item.priorityTier == .urgent {
                        Text(item.priorityTier.title)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(emphasisColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(emphasisColor.opacity(0.12))
                            )
                    }
                }
                if let supportingLine, !supportingLine.isEmpty {
                    Text(supportingLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.subtext)
                        .lineLimit(1)
                }
                Text("\(item.itemType == .habit ? "Habit" : "Task") · \(categoryName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.subtext.opacity(0.9))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            } else {
                NavigationLink {
                    destination
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                                .fill(palette.surfaceMuted)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                                .stroke(palette.border, lineWidth: 1)
                        )
                }
                .onePressable(scale: 0.96)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .fill(isHighlighted ? palette.accentSoft.opacity(palette.isDark ? 0.72 : 0.9) : Color.clear)
        )
        .opacity(isBusy ? 0.82 : 1)
        .disabled(isBusy)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if allowsSwipeDelete, let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: allowsSwipeCompletion) {
            if allowsSwipeCompletion {
                Button(action: onToggle) {
                    Label("Done", systemImage: "checkmark.circle.fill")
                }
                .tint(palette.success)
            }
        }
        .animation(
            OneMotion.animation(.stateChange, reduceMotion: reduceMotion),
            value: isHighlighted
        )
    }
}

private struct HomeHabitCategoryGroup: Identifiable {
    let categoryId: String
    let categoryName: String
    let categoryIcon: OneIconKey
    let habits: [Habit]

    var id: String { categoryId }
}

private struct HomeHabitCategoryGroupRow: View {
    let palette: OneTheme.Palette
    let group: HomeHabitCategoryGroup

    var body: some View {
        HStack(spacing: 12) {
            OneIconBadge(
                key: group.categoryIcon,
                palette: palette,
                size: 36,
                tint: palette.symbol,
                background: palette.surfaceStrong,
                border: palette.border,
                shape: .circle
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(group.categoryName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text("\(group.habits.count) active habit\(group.habits.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.subtext)
            }

            Spacer()

            Image(systemName: "chevron.right.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.accent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .fill(palette.surfaceMuted)
        )
    }
}

private struct HabitCategorySheetView: View {
    let categoryId: String
    @ObservedObject var tasksViewModel: TasksViewModel
    let anchorDate: String
    let onDismiss: () -> Void
    let onSave: () async -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    private var category: Category? {
        tasksViewModel.categories.first(where: { $0.id == categoryId })
    }

    private var categoryName: String {
        category?.name ?? "Category"
    }

    private var categoryIcon: OneIconKey {
        actionQueueCategoryIcon(name: category?.name ?? "Category", storedIcon: category?.icon)
    }

    private var activeHabits: [Habit] {
        tasksViewModel.habits
            .filter { $0.isActive && $0.categoryId == categoryId }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            OneScrollScreen(palette: palette) {
                OneSurfaceCard(palette: palette) {
                    HStack(spacing: 12) {
                        OneIconBadge(
                            key: categoryIcon,
                            palette: palette,
                            size: 42,
                            tint: palette.symbol,
                            background: palette.surfaceStrong,
                            border: palette.border,
                            shape: .circle
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(categoryName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text("Browse and edit the habits in this category.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.subtext)
                        }
                    }
                }

                OneSurfaceCard(palette: palette) {
                    OneSectionHeading(
                        palette: palette,
                        title: "Habits",
                        meta: activeHabits.isEmpty ? "Nothing active" : "\(activeHabits.count)"
                    )

                    if activeHabits.isEmpty {
                        EmptyStateCard(
                            palette: palette,
                            title: "No active habits here",
                            message: "Activate or add a habit in this category to see it here."
                        )
                    } else {
                        VStack(spacing: 10) {
                            ForEach(activeHabits) { habit in
                                NavigationLink {
                                    HabitDetailView(
                                        habitId: habit.id,
                                        tasksViewModel: tasksViewModel,
                                        anchorDate: anchorDate,
                                        onSave: {
                                            await onSave()
                                        }
                                    )
                                } label: {
                                    ActiveHabitHomeRow(
                                        palette: palette,
                                        habit: habit,
                                        categoryName: categoryName,
                                        categoryIcon: categoryIcon
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle(categoryName)
            .oneNavigationBarDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .oneNavigationTrailing) {
                    Button("Done") {
                        OneHaptics.shared.trigger(.sheetDismissed)
                        onDismiss()
                    }
                }
            }
        }
    }
}

private struct ActiveHabitHomeRow: View {
    let palette: OneTheme.Palette
    let habit: Habit
    let categoryName: String
    let categoryIcon: OneIconKey

    private var recurrenceSummary: String {
        HabitRecurrenceRule(rawValue: habit.recurrenceRule).summary
    }

    private var supportingLine: String {
        if let preferredTime = habit.preferredTime, !preferredTime.isEmpty {
            return "\(categoryName) • Around \(preferredTime)"
        }
        return categoryName
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            OneIconBadge(
                key: .habit,
                palette: palette,
                size: 34,
                tint: palette.accent,
                background: palette.surfaceStrong,
                border: palette.border,
                shape: .circle
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(habit.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(recurrenceSummary)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(supportingLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                EmojiBadge(symbol: categoryIcon, palette: palette, accessibilityLabel: categoryName)
                PriorityBadge(tier: habit.priorityTier, palette: palette)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .fill(palette.surfaceMuted)
        )
    }
}

private extension ReflectionSentiment {
    var title: String {
        switch self {
        case .great:
            return "Great"
        case .focused:
            return "Focused"
        case .okay:
            return "Okay"
        case .tired:
            return "Tired"
        case .stressed:
            return "Stressed"
        }
    }

    var symbolName: String {
        switch self {
        case .great:
            return "sun.max.fill"
        case .focused:
            return "scope"
        case .okay:
            return "circle.fill"
        case .tired:
            return "moon.zzz.fill"
        case .stressed:
            return "exclamationmark.circle.fill"
        }
    }

    var chipKind: OneChip.Kind {
        switch self {
        case .great:
            return .success
        case .focused:
            return .strong
        case .okay:
            return .neutral
        case .tired:
            return .neutral
        case .stressed:
            return .danger
        }
    }

    func tint(in palette: OneTheme.Palette) -> Color {
        switch self {
        case .great:
            return palette.success
        case .focused:
            return palette.accent
        case .okay:
            return palette.subtext
        case .tired:
            return palette.warning
        case .stressed:
            return palette.danger
        }
    }
}

private struct SummaryMetricTile: View {
    let palette: OneTheme.Palette
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(OneType.caption)
                .foregroundStyle(palette.subtext)
            Text(value)
                .font(OneType.title)
                .foregroundStyle(palette.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .fill(palette.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}

private struct CoachVerseBlock: View {
    let palette: OneTheme.Palette
    let card: CoachCard

    private var resolvedVerse: String? {
        BibleVerseResolver.shared.resolveText(for: card.verseRef, fallback: card.verseText)
    }

    var body: some View {
        if let verse = resolvedVerse,
           let verseRef = card.verseRef,
           !verseRef.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(verseRef)
                    .font(OneType.caption)
                    .foregroundStyle(palette.subtext)
                Text(verse)
                    .font(OneType.body)
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                    .fill(palette.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
        } else if let verse = card.verseText,
                  !verse.isEmpty {
            Text(verse)
                .font(OneType.body)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EmptyStateCard: View {
    let palette: OneTheme.Palette
    let title: String
    let message: String

    var body: some View {
        OneSurfaceCard(palette: palette) {
            Text(title)
                .font(OneType.title)
                .foregroundStyle(palette.text)
            Text(message)
                .font(OneType.secondary)
                .foregroundStyle(palette.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InlineStatusCard: View {
    enum Kind {
        case neutral
        case danger
    }

    let message: String
    let kind: Kind
    let palette: OneTheme.Palette

    var body: some View {
        OneSurfaceCard(palette: palette) {
            HStack(spacing: 10) {
                OneIcon(
                    key: kind == .danger ? .warning : .coachInsight,
                    palette: palette,
                    size: 16,
                    tint: kind == .danger ? palette.danger : palette.accent
                )
                Text(message)
                    .font(OneType.secondary)
                    .foregroundStyle(kind == .danger ? palette.danger : palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private enum OneTimeValueFormatter {
    private static let storageFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let fallbackFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func string(from date: Date) -> String {
        storageFormatter.string(from: date)
    }

    static func date(from raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else {
            return nil
        }
        return storageFormatter.date(from: raw) ?? fallbackFormatter.date(from: raw)
    }
}

private struct OneField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.subtext)
            TextField(placeholder, text: $text)
                .onePlainTextInputBehavior()
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                        .fill(palette.surfaceMuted)
                )
                .foregroundStyle(palette.text)
        }
    }
}

private struct OneSecureField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.subtext)
            SecureField(placeholder, text: $text)
                .onePlainTextInputBehavior()
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                        .fill(palette.surfaceMuted)
                )
                .foregroundStyle(palette.text)
        }
    }
}

private struct OneTextEditorField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding? = nil
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OneTheme.Palette {
        OneTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.subtext)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                    .fill(palette.surfaceMuted)
                RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
                if let isFocused {
                    TextEditor(text: $text)
                        .focused(isFocused)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .foregroundStyle(palette.text)
                } else {
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .foregroundStyle(palette.text)
                }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.subtext.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct PickerCard: View {
    let palette: OneTheme.Palette
    let title: String
    @Binding var selection: String
    let options: [(id: String, name: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.subtext)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.id) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                    .fill(palette.surfaceMuted)
            )
        }
        .onChange(of: selection) { _, _ in
            OneHaptics.shared.trigger(.selectionChanged)
        }
    }
}

private struct SliderCard: View {
    let palette: OneTheme.Palette
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.subtext)
                Spacer()
                Text("\(Int(value))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.text)
            }
            Slider(value: $value, in: range, step: 1)
                .tint(palette.accent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .fill(palette.surfaceMuted)
        )
        .animation(OneMotion.animation(.stateChange), value: value)
    }
}

private struct ToggleCard: View {
    let palette: OneTheme.Palette
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(palette.accent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .fill(isOn ? palette.accentSoft : palette.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .stroke(isOn ? palette.accent.opacity(0.55) : palette.border, lineWidth: 1)
        )
        .animation(OneMotion.animation(.stateChange, reduceMotion: reduceMotion), value: isOn)
        .onChange(of: isOn) { _, _ in
            OneHaptics.shared.trigger(.selectionChanged)
        }
    }
}

private struct DatePickerCard: View {
    let palette: OneTheme.Palette
    let title: String
    @Binding var selection: Date
    var displayedComponents: DatePickerComponents = [.date]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.subtext)
            DatePicker("", selection: $selection, displayedComponents: displayedComponents)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .fill(palette.surfaceMuted)
        )
    }
}

private struct StatusPickerCard: View {
    let palette: OneTheme.Palette
    @Binding var selection: TodoStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.subtext)
            Picker("Status", selection: $selection) {
                Text("Open").tag(TodoStatus.open)
                Text("Completed").tag(TodoStatus.completed)
                Text("Canceled").tag(TodoStatus.canceled)
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .fill(palette.surfaceMuted)
        )
        .animation(OneMotion.animation(.stateChange, reduceMotion: reduceMotion), value: selection)
        .onChange(of: selection) { _, _ in
            OneHaptics.shared.trigger(.selectionChanged)
        }
    }
}

private struct RecurrenceBuilderCard: View {
    let palette: OneTheme.Palette
    @Binding var recurrence: HabitRecurrenceRule
    @State private var yearlyDraftDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.subtext)

            OneSegmentedControl(
                palette: palette,
                options: HabitRecurrenceFrequency.allCases,
                selection: recurrence.frequency,
                title: { $0.title }
            ) { selection in
                var updated = recurrence
                updated.frequency = selection
                switch selection {
                case .daily:
                    break
                case .weekly where updated.weekdays.isEmpty:
                    updated.weekdays = [.monday]
                case .monthly where updated.monthDays.isEmpty:
                    updated.monthDays = [1]
                case .yearly where updated.yearlyDates.isEmpty:
                    updated.yearlyDates = [HabitRecurrenceYearlyDate(month: 1, day: 1)]
                default:
                    break
                }
                OneHaptics.shared.trigger(.selectionChanged)
                withAnimation(OneMotion.animation(.stateChange, reduceMotion: reduceMotion)) {
                    recurrence = updated
                }
            }

            Group {
                switch recurrence.frequency {
            case .daily:
                Text("Daily habits materialize every day.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.subtext)
            case .weekly:
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(HabitRecurrenceWeekday.allCases, id: \.self) { weekday in
                        RecurrenceChoiceChip(
                            palette: palette,
                            title: weekday.shortTitle,
                            isSelected: recurrence.weekdays.contains(weekday)
                        ) {
                            var updated = recurrence
                            if updated.weekdays.contains(weekday) {
                                updated.weekdays.removeAll { $0 == weekday }
                            } else {
                                updated.weekdays.append(weekday)
                            }
                            OneHaptics.shared.trigger(.selectionChanged)
                            withAnimation(OneMotion.animation(.stateChange, reduceMotion: reduceMotion)) {
                                recurrence = HabitRecurrenceRule(
                                    frequency: updated.frequency,
                                    weekdays: updated.weekdays,
                                    monthDays: updated.monthDays,
                                    yearlyDates: updated.yearlyDates
                                )
                            }
                        }
                    }
                }
            case .monthly:
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(1...31, id: \.self) { day in
                        RecurrenceChoiceChip(
                            palette: palette,
                            title: "\(day)",
                            isSelected: recurrence.monthDays.contains(day)
                        ) {
                            var updated = recurrence
                            if updated.monthDays.contains(day) {
                                updated.monthDays.removeAll { $0 == day }
                            } else {
                                updated.monthDays.append(day)
                            }
                            OneHaptics.shared.trigger(.selectionChanged)
                            withAnimation(OneMotion.animation(.stateChange, reduceMotion: reduceMotion)) {
                                recurrence = HabitRecurrenceRule(
                                    frequency: updated.frequency,
                                    weekdays: updated.weekdays,
                                    monthDays: updated.monthDays,
                                    yearlyDates: updated.yearlyDates
                                )
                            }
                        }
                    }
                }
            case .yearly:
                VStack(alignment: .leading, spacing: 10) {
                    if recurrence.yearlyDates.isEmpty {
                        Text("Add one or more month-day dates.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.subtext)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recurrence.yearlyDates, id: \.self) { date in
                                    RemovableChoiceChip(palette: palette, title: date.title) {
                                        var updated = recurrence
                                        updated.yearlyDates.removeAll { $0 == date }
                                        OneHaptics.shared.trigger(.destructiveConfirmed)
                                        withAnimation(OneMotion.animation(.dismiss, reduceMotion: reduceMotion)) {
                                            recurrence = HabitRecurrenceRule(
                                                frequency: updated.frequency,
                                                weekdays: updated.weekdays,
                                                monthDays: updated.monthDays,
                                                yearlyDates: updated.yearlyDates
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        DatePicker("", selection: $yearlyDraftDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)

                        Button("Add date") {
                            let components = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: yearlyDraftDate)
                            guard let month = components.month, let day = components.day else {
                                return
                            }
                            var updated = recurrence
                            let nextDate = HabitRecurrenceYearlyDate(month: month, day: day)
                            guard !updated.yearlyDates.contains(nextDate) else {
                                return
                            }
                            updated.yearlyDates.append(nextDate)
                            OneHaptics.shared.trigger(.selectionChanged)
                            withAnimation(OneMotion.animation(.stateChange, reduceMotion: reduceMotion)) {
                                recurrence = HabitRecurrenceRule(
                                    frequency: updated.frequency,
                                    weekdays: updated.weekdays,
                                    monthDays: updated.monthDays,
                                    yearlyDates: updated.yearlyDates
                                )
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .onePressable(scale: 0.97)
                    }
                }
            }
            }
            .transition(.move(edge: .top).combined(with: .opacity))

            Text(recurrence.summary)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                        .fill(palette.surfaceMuted)
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .fill(palette.surfaceMuted)
        )
        .animation(OneMotion.animation(.stateChange, reduceMotion: reduceMotion), value: recurrence.frequency)
    }
}

private struct RecurrenceChoiceChip: View {
    let palette: OneTheme.Palette
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? palette.text : palette.subtext)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                        .fill(isSelected ? palette.surface : palette.glass)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                        .stroke(isSelected ? palette.accent : palette.border, lineWidth: 1)
                )
        }
        .onePressable(scale: 0.96)
    }
}

private struct RemovableChoiceChip: View {
    let palette: OneTheme.Palette
    let title: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                    .fill(palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OneTheme.radiusSmall, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
        }
        .onePressable(scale: 0.96)
    }
}

private struct AnalyticsYearContributionView: View {
    let palette: OneTheme.Palette
    let sections: [AnalyticsContributionMonthSection]
    let onSelectDate: (String) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(sections) { section in
                    AnalyticsMonthContributionSection(
                        palette: palette,
                        section: section,
                        onSelectDate: onSelectDate
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct AnalyticsMonthContributionSection: View {
    let palette: OneTheme.Palette
    let section: AnalyticsContributionMonthSection
    let onSelectDate: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(section.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.text)
                Spacer()
                Text("\(section.completedItems)/\(section.expectedItems)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.subtext)
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(palette.subtext)
                        .frame(maxWidth: .infinity)
                }

                ForEach(0..<section.leadingPlaceholders, id: \.self) { _ in
                    Color.clear
                        .frame(height: 16)
                }

                ForEach(section.days) { day in
                    Button {
                        onSelectDate(day.dateLocal)
                    } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(contributionFill(for: day.completionRate, palette: palette))
                            .frame(height: 16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(palette.border.opacity(0.55), lineWidth: 0.5)
                            )
                            .overlay {
                                Text("\(day.dayNumber)")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(palette.text.opacity(day.hasSummary ? 0.78 : 0.45))
                            }
                    }
                    .onePressable(scale: 0.96, opacity: 0.92)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .fill(palette.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneTheme.radiusMedium, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}

private struct AnalyticsContributionGrid: View {
    let palette: OneTheme.Palette
    let summaries: [DailySummary]
    let onSelectDate: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(summaries, id: \.dateLocal) { summary in
                Button {
                    onSelectDate(summary.dateLocal)
                } label: {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(contributionFill(for: summary.completionRate, palette: palette))
                        .frame(height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(palette.border.opacity(0.55), lineWidth: 0.5)
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Text(OneDate.dayNumber(from: summary.dateLocal))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(palette.text.opacity(0.75))
                                .padding(2)
                        }
                }
                .onePressable(scale: 0.96, opacity: 0.92)
            }
        }
    }
}

private struct AnalyticsSentimentOverviewView: View {
    let palette: OneTheme.Palette
    let periodType: PeriodType
    let overview: AnalyticsSentimentOverview
    let highlightedDates: Set<String>
    let onOpenDate: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !overview.distribution.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(overview.distribution) { item in
                        OneChip(
                            palette: palette,
                            title: "\(item.sentiment.title) \(item.count)",
                            kind: item.sentiment.chipKind
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Trend")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.subtext)
                switch periodType {
                case .monthly:
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(overview.trend) { point in
                            sentimentPoint(point)
                        }
                    }
                default:
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(overview.trend) { point in
                            sentimentPoint(point)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sentimentPoint(_ point: AnalyticsSentimentTrendPoint) -> some View {
        let content = VStack(spacing: 6) {
            Image(systemName: point.sentiment?.symbolName ?? "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(point.sentiment?.tint(in: palette) ?? palette.subtext)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(point.sentiment == nil ? palette.surfaceMuted : palette.surface)
                )
                .overlay(
                    Circle()
                        .stroke(
                            highlightedDates.contains(point.dateLocal ?? "") ? palette.accent : Color.clear,
                            lineWidth: 1.5
                        )
                )
            Text(point.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.subtext)
        }
        .frame(maxWidth: .infinity)

        if let dateLocal = point.dateLocal {
            Button {
                onOpenDate(dateLocal)
            } label: {
                content
            }
            .onePressable(scale: 0.96, opacity: 0.92)
        } else {
            content
        }
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        WrappingFlowLayout(spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WrappingFlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = max(proposal.width ?? 320, 1)
        let frames = wrappedFrames(for: subviews, maxWidth: width)
        let contentWidth = frames.reduce(0) { max($0, $1.maxX) }
        let contentHeight = frames.reduce(0) { max($0, $1.maxY) }
        return CGSize(width: proposal.width ?? contentWidth, height: contentHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let frames = wrappedFrames(for: subviews, maxWidth: max(bounds.width, 1))
        for (index, frame) in frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func wrappedFrames(for subviews: Subviews, maxWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        let availableWidth = max(maxWidth, 1)

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: availableWidth, height: nil))
            if currentX > 0, currentX + size.width > availableWidth {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            let frame = CGRect(origin: CGPoint(x: currentX, y: currentY), size: size)
            frames.append(frame)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return frames
    }
}

private func actionQueueCategoryIcon(name: String, storedIcon: String?) -> OneIconKey {
    OneIconKey.taskCategory(name: name, storedIcon: storedIcon)
}

private func priorityTierColor(for tier: PriorityTier, palette: OneTheme.Palette) -> Color {
    switch tier {
    case .low:
        return palette.subtext
    case .standard:
        return palette.accent
    case .high:
        return palette.highlight
    case .urgent:
        return palette.danger
    }
}

private func contributionFill(for rate: Double, palette: OneTheme.Palette) -> Color {
    if rate >= 0.8 {
        return palette.success.opacity(0.9)
    } else if rate >= 0.5 {
        return palette.accent.opacity(0.8)
    } else if rate > 0 {
        return palette.warning.opacity(0.8)
    } else {
        return palette.surfaceStrong
    }
}

enum OneDate {
    private static let canonicalTimeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    static var deviceTimeZone: TimeZone { .autoupdatingCurrent }
    static var deviceTimeZoneIdentifier: String { deviceTimeZone.identifier }
    private static let canonicalCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = canonicalTimeZone
        return calendar
    }()

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = canonicalCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = canonicalTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let longFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = canonicalCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = canonicalTimeZone
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()

    private static let shortWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = canonicalCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = canonicalTimeZone
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let shortMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = canonicalCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = canonicalTimeZone
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let fullMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = canonicalCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = canonicalTimeZone
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    private static let shortMonthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = canonicalCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = canonicalTimeZone
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static func isoDate(_ date: Date = Date()) -> String {
        isoDate(date, timezoneID: deviceTimeZoneIdentifier)
    }

    static func isoDate(_ date: Date = Date(), timezoneID: String?) -> String {
        _ = timezoneID
        let timeZone = deviceTimeZone
        var calendar = canonicalCalendar
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let localized = canonicalCalendar.date(from: components) else {
            return isoFormatter.string(from: date)
        }
        return isoFormatter.string(from: localized)
    }

    static func longDate(from isoDateString: String) -> String {
        guard let date = isoFormatter.date(from: isoDateString) else {
            return isoDateString
        }
        return longFormatter.string(from: date)
    }

    static func shortWeekday(from isoDateString: String) -> String {
        guard let date = isoFormatter.date(from: isoDateString) else {
            return ""
        }
        return shortWeekdayFormatter.string(from: date)
    }

    static func initials(from name: String) -> String {
        let words = name.split(separator: " ")
        let initials = words.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? "1" : initials.uppercased()
    }

    static func timeString(from date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func dateTimeString(from date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func dayNumber(from isoDateString: String) -> String {
        guard let date = isoFormatter.date(from: isoDateString) else {
            return ""
        }
        return String(canonicalCalendar.component(.day, from: date))
    }

    static func weekBucket(from isoDateString: String) -> Int {
        guard let date = isoFormatter.date(from: isoDateString) else {
            return 1
        }
        return canonicalCalendar.component(.weekOfMonth, from: date)
    }

    static func monthBucket(from isoDateString: String) -> Int {
        guard let date = isoFormatter.date(from: isoDateString) else {
            return 1
        }
        return canonicalCalendar.component(.month, from: date)
    }

    static func shortMonth(for month: Int) -> String {
        guard let date = canonicalCalendar.date(from: DateComponents(year: 2026, month: month, day: 1)) else {
            return ""
        }
        return shortMonthFormatter.string(from: date)
    }

    static func fullMonth(for month: Int) -> String {
        guard let date = canonicalCalendar.date(from: DateComponents(year: 2026, month: month, day: 1)) else {
            return ""
        }
        return fullMonthFormatter.string(from: date)
    }

    static func shortMonthDay(from isoDateString: String) -> String {
        guard let date = isoFormatter.date(from: isoDateString) else {
            return isoDateString
        }
        return shortMonthDayFormatter.string(from: date)
    }

    static func year(from isoDateString: String) -> Int? {
        guard let date = isoFormatter.date(from: isoDateString) else {
            return nil
        }
        return canonicalCalendar.component(.year, from: date)
    }

    static func calendarDate(for isoDateString: String) -> Date? {
        isoFormatter.date(from: isoDateString)
    }

    static func canonicalWeekdayIndex(for date: Date) -> Int {
        canonicalCalendar.component(.weekday, from: date) - 1
    }

    static func numberOfDays(inMonth month: Int, year: Int) -> Int {
        guard let date = canonicalCalendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return 30
        }
        return canonicalCalendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }
}

#if os(iOS)
private extension EditMode {
    var isEditing: Bool {
        self == .active
    }
}
#endif
#endif
