import XCTest
import Foundation
@testable import OneClient
import SwiftUI
import Combine

@MainActor
final class OneAppTests: XCTestCase {
    func testAddContextUsesPrimaryActionsOutsideFinance() {
        let appTabs: [OneAppShell.Tab] = [.today, .review, .settings]

        for tab in appTabs {
            XCTAssertEqual(OneAddContext(tab: tab).actions, [.task, .habit, .note])
        }
    }

    func testAddContextUsesFinanceActionsInsideFinance() {
        XCTAssertEqual(OneAddContext(tab: .finance).actions, [.income, .expense, .transfer])
        XCTAssertEqual(OneAddAction.task.iconKey, .task)
        XCTAssertEqual(OneAddAction.habit.iconKey, .habit)
        XCTAssertEqual(OneAddAction.note.iconKey, .note)
        XCTAssertEqual(OneAddAction.income.iconKey, .income)
        XCTAssertEqual(OneAddAction.expense.iconKey, .expense)
        XCTAssertEqual(OneAddAction.transfer.iconKey, .transfer)
        XCTAssertEqual(OneAddAction.income.financeTransactionType, .income)
        XCTAssertEqual(OneAddAction.expense.financeTransactionType, .expense)
        XCTAssertEqual(OneAddAction.transfer.financeTransactionType, .transfer)
        XCTAssertNil(OneAddAction.task.financeTransactionType)
    }

    func testOneIconKeyNormalizesLegacyTaskCategoryIcons() {
        XCTAssertEqual(OneIconKey.taskCategory(name: "Gym", storedIcon: "🏋️"), .categoryGym)
        XCTAssertEqual(OneIconKey.taskCategory(name: "School", storedIcon: "🎓"), .categorySchool)
        XCTAssertEqual(OneIconKey.taskCategory(name: "Personal Projects", storedIcon: "💡"), .categoryProjects)
        XCTAssertEqual(OneIconKey.taskCategory(name: "Wellbeing", storedIcon: "🌿"), .categoryWellbeing)
        XCTAssertEqual(OneIconKey.taskCategory(name: "Life Admin", storedIcon: "🧾"), .categoryLifeAdmin)
        XCTAssertEqual(OneIconKey.taskCategory(name: "Unknown", storedIcon: nil), .categoryGeneric)
    }

    func testThemePreferenceMapping() throws {
        XCTAssertEqual(OneTheme.preferredColorScheme(from: .light), .light)
        XCTAssertEqual(OneTheme.preferredColorScheme(from: .dark), .dark)
        XCTAssertNil(OneTheme.preferredColorScheme(from: .system))
        XCTAssertNil(OneTheme.preferredColorScheme(from: nil))
    }

    func testAppEnvironmentAlwaysUsesLocalRuntimeMode() {
        let suiteName = "OneAppTests.AppEnvironment.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected dedicated defaults suite")
            return
        }
        defaults.set(AppEnvironment.RuntimeMode.remote.rawValue, forKey: AppEnvironment.debugRuntimeModeKey)

        let environment = AppEnvironment.current(bundle: .main, defaults: defaults)

        XCTAssertEqual(environment.runtimeMode, .local)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testAnalyticsWeeklyBoundsUsesCalendarWeek() throws {
        let bounds = AnalyticsDateRange.bounds(anchorDate: "2026-03-12", periodType: .weekly, weekStart: 0)
        XCTAssertEqual(bounds.startDate, "2026-03-09")
        XCTAssertEqual(bounds.endDate, "2026-03-15")
        try assertRecurrenceRuleRoundTrip()
    }

    func testReminderSchedulerRespectsQuietHoursAndFlags() throws {
        let scheduler = ReminderScheduler()
        let dueAt = ISO8601DateFormatter().date(from: "2026-03-12T06:30:00Z")
        let habits = [
            Habit(
                id: "h1",
                userId: "u1",
                categoryId: "c1",
                title: "Workout",
                recurrenceRule: "DAILY",
                startDate: "2026-03-01",
                preferredTime: "06:30:00"
            )
        ]
        let todos = [
            Todo(
                id: "t1",
                userId: "u1",
                categoryId: "c1",
                title: "Submit",
                dueAt: dueAt,
                status: .open
            )
        ]
        var preferences = UserPreferences(
            id: "p1",
            userId: "u1",
            notificationFlags: [
                "habit_reminders": true,
                "todo_reminders": true,
                "reflection_prompts": true,
                "weekly_summary": true,
            ],
            quietHoursStart: "22:00:00",
            quietHoursEnd: "07:00:00"
        )

        let all = scheduler.buildSchedules(habits: habits, todos: todos, preferences: preferences)
        XCTAssertEqual(all.count, 2)

        preferences.notificationFlags["todo_reminders"] = false
        let habitOnly = scheduler.buildSchedules(habits: habits, todos: todos, preferences: preferences)
        XCTAssertEqual(habitOnly.count, 1)

        let blocked = scheduler.dueReminders(
            schedules: all,
            nowHour: 6,
            nowMinute: 30,
            quietStart: "22:00:00",
            quietEnd: "07:00:00"
        )
        XCTAssertTrue(blocked.isEmpty)
    }

    func testSessionRestoreReturnsUserAfterLogin() async throws {
        let api = MockAPIClient()
        let authRepo = DefaultAuthRepository(apiClient: api)

        _ = try await authRepo.login(email: "one@example.com", password: "password123")
        let restored = await authRepo.restoreSession()

        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.email, "one@example.com")
    }

    func testContainerForwardsAuthViewModelChanges() async throws {
        let api = MockAPIClient()
        let syncQueue = InMemorySyncQueue()
        let container = OneAppContainer(
            authRepository: DefaultAuthRepository(apiClient: api),
            tasksRepository: DefaultTasksRepository(apiClient: api, syncQueue: syncQueue),
            todayRepository: DefaultTodayRepository(apiClient: api, syncQueue: syncQueue),
            analyticsRepository: DefaultAnalyticsRepository(apiClient: api),
            reflectionsRepository: DefaultReflectionsRepository(apiClient: api),
            profileRepository: DefaultProfileRepository(apiClient: api),
            coachRepository: DefaultCoachRepository(apiClient: api)
        )

        let changeExpectation = expectation(description: "Container forwards auth updates")
        changeExpectation.assertForOverFulfill = false
        var forwardedChanges = 0
        var cancellable: AnyCancellable?
        cancellable = container.objectWillChange.sink {
            forwardedChanges += 1
            changeExpectation.fulfill()
        }

        await container.authViewModel.createLocalProfile(
            displayName: "Local User"
        )

        await fulfillment(of: [changeExpectation], timeout: 1.0)
        XCTAssertGreaterThanOrEqual(forwardedChanges, 1)
        XCTAssertEqual(container.authViewModel.user?.displayName, "Local User")
        cancellable?.cancel()
    }

    func testSyncQueueRetryBehavior() async throws {
        let api = FlakyCompletionAPIClient()
        let queue = InMemorySyncQueue()
        let repo = DefaultTodayRepository(apiClient: api, syncQueue: queue)

        _ = try await repo.loadToday(date: "2026-03-12")
        _ = try await repo.setCompletion(itemType: .habit, itemId: "h1", dateLocal: "2026-03-12", state: .completed)

        let firstPending = await queue.all()
        XCTAssertEqual(firstPending.count, 1)

        await queue.drain(using: api)
        let pending = await queue.all()
        XCTAssertTrue(pending.isEmpty)
    }

    func testOfflineLocalStoreFlow() async throws {
        let sessionStore = InMemoryAuthSessionStore()
        let stack = try LocalPersistenceFactory.makeInMemory(sessionStore: sessionStore)

        let authRepository = DefaultAuthRepository(apiClient: stack.apiClient)
        let tasksRepository = DefaultTasksRepository(apiClient: stack.apiClient, syncQueue: stack.syncQueue)
        let todayRepository = DefaultTodayRepository(apiClient: stack.apiClient, syncQueue: stack.syncQueue)
        let analyticsRepository = DefaultAnalyticsRepository(apiClient: stack.apiClient)
        let reflectionsRepository = DefaultReflectionsRepository(apiClient: stack.apiClient)

        let user = try await authRepository.signup(
            email: "offline@one.local",
            password: "offline-local-profile",
            displayName: "Offline User",
            timezone: "America/Guatemala"
        )
        XCTAssertEqual(user.displayName, "Offline User")

        let categories = try await tasksRepository.loadCategories()
        XCTAssertEqual(categories.count, 5)
        XCTAssertEqual(
            categories.map(\.icon),
            [
                OneIconKey.categoryGym.rawValue,
                OneIconKey.categorySchool.rawValue,
                OneIconKey.categoryProjects.rawValue,
                OneIconKey.categoryWellbeing.rawValue,
                OneIconKey.categoryLifeAdmin.rawValue,
            ]
        )

        let habit = try await tasksRepository.createHabit(
            HabitCreateInput(
                categoryId: categories[0].id,
                title: "Workout",
                recurrenceRule: "DAILY",
                startDate: "2026-03-12"
            )
        )
        _ = try await tasksRepository.createTodo(
            TodoCreateInput(
                categoryId: categories[1].id,
                title: "Study quiz",
                dueAt: ISO8601DateFormatter().date(from: "2026-03-12T15:00:00Z"),
                priority: 70,
                isPinned: true
            )
        )

        let today = try await todayRepository.loadToday(date: "2026-03-12")
        XCTAssertEqual(today.totalCount, 2)

        let updated = try await todayRepository.setCompletion(
            itemType: .habit,
            itemId: habit.id,
            dateLocal: "2026-03-12",
            state: .completed
        )
        XCTAssertEqual(updated.completedCount, 1)

        let weekly = try await analyticsRepository.loadPeriod(anchorDate: "2026-03-12", periodType: .weekly)
        XCTAssertGreaterThanOrEqual(weekly.completedItems, 1)

        _ = try await reflectionsRepository.upsert(
            input: ReflectionWriteInput(
                periodType: .daily,
                periodStart: "2026-03-12",
                periodEnd: "2026-03-12",
                content: "Stayed on plan",
                sentiment: .focused
            )
        )
        _ = try await reflectionsRepository.upsert(
            input: ReflectionWriteInput(
                periodType: .daily,
                periodStart: "2026-03-12",
                periodEnd: "2026-03-12",
                content: "Captured another note",
                sentiment: .great
            )
        )
        let reflections = try await reflectionsRepository.list(periodType: .daily)
        XCTAssertEqual(reflections.count, 2)
        XCTAssertEqual(reflections.first?.content, "Captured another note")
        try await assertAnalyticsActivityFilter()
        try await assertWeeklyHabitStaysOnConfiguredWeekdayAcrossDeviceTimezones()
    }

    func testOfflineUpdatesCanClearOptionalTaskFields() async throws {
        let sessionStore = InMemoryAuthSessionStore()
        let stack = try LocalPersistenceFactory.makeInMemory(sessionStore: sessionStore)
        let authRepository = DefaultAuthRepository(apiClient: stack.apiClient)
        let tasksRepository = DefaultTasksRepository(apiClient: stack.apiClient, syncQueue: stack.syncQueue)

        _ = try await authRepository.signup(
            email: "clear-fields@one.local",
            password: "offline-local-profile",
            displayName: "Clear Fields",
            timezone: "America/Guatemala"
        )

        let categories = try await tasksRepository.loadCategories()
        let dueAt = ISO8601DateFormatter().date(from: "2026-03-18T14:30:00Z")

        let habit = try await tasksRepository.createHabit(
            HabitCreateInput(
                categoryId: categories[0].id,
                title: "Deep work",
                recurrenceRule: "DAILY",
                startDate: "2026-03-12",
                endDate: "2026-03-31",
                preferredTime: "08:30:00"
            )
        )
        let todo = try await tasksRepository.createTodo(
            TodoCreateInput(
                categoryId: categories[1].id,
                title: "Submit report",
                dueAt: dueAt
            )
        )

        let clearedHabit = try await tasksRepository.updateHabit(
            id: habit.id,
            input: HabitUpdateInput(
                clearEndDate: true,
                clearPreferredTime: true
            ),
            clientUpdatedAt: Date()
        )
        let clearedTodo = try await tasksRepository.updateTodo(
            id: todo.id,
            input: TodoUpdateInput(
                clearDueAt: true
            ),
            clientUpdatedAt: Date()
        )

        XCTAssertNil(clearedHabit.endDate)
        XCTAssertNil(clearedHabit.preferredTime)
        XCTAssertNil(clearedTodo.dueAt)

        let persistedHabits = try await tasksRepository.loadHabits()
        let persistedTodos = try await tasksRepository.loadTodos()
        let persistedHabit = persistedHabits.first(where: { $0.id == habit.id })
        let persistedTodo = persistedTodos.first(where: { $0.id == todo.id })
        XCTAssertNil(persistedHabit?.endDate)
        XCTAssertNil(persistedHabit?.preferredTime)
        XCTAssertNil(persistedTodo?.dueAt)
    }

    func testOfflineTodayOrdersNewestSamePriorityTodoFirst() async throws {
        let sessionStore = InMemoryAuthSessionStore()
        let stack = try LocalPersistenceFactory.makeInMemory(sessionStore: sessionStore)

        let authRepository = DefaultAuthRepository(apiClient: stack.apiClient)
        let tasksRepository = DefaultTasksRepository(apiClient: stack.apiClient, syncQueue: stack.syncQueue)
        let todayRepository = DefaultTodayRepository(apiClient: stack.apiClient, syncQueue: stack.syncQueue)

        _ = try await authRepository.signup(
            email: "ordering@one.local",
            password: "offline-local-profile",
            displayName: "Ordering User",
            timezone: "America/Guatemala"
        )

        let categories = try await tasksRepository.loadCategories()
        let older = try await tasksRepository.createTodo(
            TodoCreateInput(
                categoryId: categories[0].id,
                title: "Alpha task",
                priority: 50
            )
        )
        try? await Task.sleep(for: .milliseconds(20))
        let newer = try await tasksRepository.createTodo(
            TodoCreateInput(
                categoryId: categories[0].id,
                title: "Zulu task",
                priority: 50
            )
        )

        let today = try await todayRepository.loadToday(date: "2026-03-12")

        XCTAssertEqual(today.items.map(\.itemId), [newer.id, older.id])
    }

    func testStoredLocalStoreBootstrapFlow() async throws {
        let sessionStore = InMemoryAuthSessionStore()
        let stack = try LocalPersistenceFactory.makeStored(sessionStore: sessionStore)
        let authRepository = DefaultAuthRepository(apiClient: stack.apiClient)
        let profileRepository = DefaultProfileRepository(apiClient: stack.apiClient)
        let suffix = String(UUID().uuidString.prefix(8))

        let user = try await authRepository.signup(
            email: "stored-\(suffix)@one.local",
            password: "offline-local-profile",
            displayName: "Stored \(suffix)",
            timezone: "America/Guatemala"
        )
        let restored = await authRepository.restoreSession()

        XCTAssertEqual(restored?.id, user.id)

        let preferences = try await profileRepository.loadPreferences()
        XCTAssertEqual(preferences.userId, user.id)
    }

    func testStoredLocalStoreRestoresWithoutPersistedSessionAndKeepsTasks() async throws {
        let suffix = String(UUID().uuidString.prefix(8))
        let initialSessionStore = InMemoryAuthSessionStore()
        let initialStack = try LocalPersistenceFactory.makeStored(sessionStore: initialSessionStore)
        let initialAuthRepository = DefaultAuthRepository(apiClient: initialStack.apiClient)
        let initialTasksRepository = DefaultTasksRepository(apiClient: initialStack.apiClient, syncQueue: initialStack.syncQueue)

        let user = try await initialAuthRepository.signup(
            email: "relaunch-\(suffix)@one.local",
            password: "offline-local-profile",
            displayName: "Relaunch \(suffix)",
            timezone: "America/Guatemala"
        )
        let categories = try await initialTasksRepository.loadCategories()
        let habitTitle = "Persisted Habit \(suffix)"
        let todoTitle = "Persisted Todo \(suffix)"

        _ = try await initialTasksRepository.createHabit(
            HabitCreateInput(
                categoryId: categories[0].id,
                title: habitTitle,
                recurrenceRule: "DAILY",
                startDate: "2026-03-12"
            )
        )
        _ = try await initialTasksRepository.createTodo(
            TodoCreateInput(
                categoryId: categories[1].id,
                title: todoTitle,
                dueAt: ISO8601DateFormatter().date(from: "2026-03-12T15:00:00Z"),
                priority: 60
            )
        )

        let relaunchedSessionStore = InMemoryAuthSessionStore()
        let relaunchedStack = try LocalPersistenceFactory.makeStored(sessionStore: relaunchedSessionStore)
        let relaunchedAuthRepository = DefaultAuthRepository(apiClient: relaunchedStack.apiClient)
        let relaunchedTasksRepository = DefaultTasksRepository(apiClient: relaunchedStack.apiClient, syncQueue: relaunchedStack.syncQueue)

        let restored = await relaunchedAuthRepository.restoreSession()

        XCTAssertEqual(restored?.id, user.id)
        let habits = try await relaunchedTasksRepository.loadHabits()
        XCTAssertTrue(habits.contains(where: { $0.title == habitTitle }))
        let todos = try await relaunchedTasksRepository.loadTodos()
        XCTAssertTrue(todos.contains(where: { $0.title == todoTitle }))
    }

    func testLocalSignOutRequiresExplicitResumeAndKeepsLocalData() async throws {
        let sessionStore = InMemoryAuthSessionStore()
        let stack = try LocalPersistenceFactory.makeInMemory(sessionStore: sessionStore)
        let authRepository = DefaultAuthRepository(apiClient: stack.apiClient)
        let tasksRepository = DefaultTasksRepository(apiClient: stack.apiClient, syncQueue: stack.syncQueue)

        let created = try await authRepository.signup(
            email: "resume@one.local",
            password: "offline-local-profile",
            displayName: "Local Resume",
            timezone: "America/Guatemala"
        )
        XCTAssertEqual(created.displayName, "Local Resume")

        let categories = try await tasksRepository.loadCategories()
        let habitTitle = "Resume Habit"
        _ = try await tasksRepository.createHabit(
            HabitCreateInput(
                categoryId: categories[0].id,
                title: habitTitle,
                recurrenceRule: "DAILY",
                startDate: "2026-03-12"
            )
        )

        await authRepository.logout()
        let restoredAfterLogout = await authRepository.restoreSession()
        XCTAssertNil(restoredAfterLogout)

        let resumed = try await authRepository.login(email: created.email, password: "")
        XCTAssertEqual(resumed.id, created.id)

        let restored = await authRepository.restoreSession()
        XCTAssertEqual(restored?.displayName, "Local Resume")
        let habits = try await tasksRepository.loadHabits()
        XCTAssertTrue(habits.contains(where: { $0.title == habitTitle }))
    }

    func testNotesViewModelSupportsPeriodBrowsingAndDeletion() async throws {
        let repository = ReflectionsStubRepository(notes: [
            try makeReflectionNote(
                id: "note-1",
                periodStart: "2026-03-12",
                content: "First note of the day",
                sentiment: .focused,
                createdAt: "2026-03-12T12:00:00Z"
            ),
            try makeReflectionNote(
                id: "note-2",
                periodStart: "2026-03-12",
                content: "Second note of the day",
                sentiment: .great,
                createdAt: "2026-03-12T14:00:00Z"
            ),
            try makeReflectionNote(
                id: "note-3",
                periodStart: "2026-03-10",
                content: "Tuesday reset",
                sentiment: .okay,
                createdAt: "2026-03-10T09:00:00Z"
            ),
            try makeReflectionNote(
                id: "note-5",
                periodStart: "2026-03-12",
                content: "Closed strong",
                sentiment: .focused,
                createdAt: "2026-03-12T16:00:00Z"
            ),
            try makeReflectionNote(
                id: "note-6",
                periodStart: "2026-03-10",
                content: "Tough finish",
                sentiment: .stressed,
                createdAt: "2026-03-10T10:00:00Z"
            ),
            try makeReflectionNote(
                id: "note-4",
                periodStart: "2026-04-02",
                content: "April note",
                sentiment: .tired,
                createdAt: "2026-04-02T18:30:00Z"
            ),
        ])

        let viewModel = NotesViewModel(repository: repository)
        await viewModel.load(anchorDate: "2026-03-12", periodType: .daily, weekStart: 0, forceReload: true)

        XCTAssertEqual(viewModel.selectedDayNotes.map(\.id), ["note-5", "note-2", "note-1"])
        XCTAssertEqual(viewModel.sentimentSummary?.noteCount, 3)
        XCTAssertEqual(viewModel.sentimentSummary?.dominant, .focused)

        viewModel.selectPeriod(.weekly)
        XCTAssertEqual(viewModel.dayOptions.count, 7)
        XCTAssertEqual(viewModel.dayOptions.first(where: { $0.dateLocal == "2026-03-12" })?.sentiment, .focused)
        XCTAssertEqual(viewModel.dayOptions.first(where: { $0.dateLocal == "2026-03-10" })?.sentiment, .stressed)

        viewModel.selectPeriod(.monthly)
        XCTAssertEqual(viewModel.dayOptions.count, 31)
        XCTAssertEqual(viewModel.monthOptions.first(where: { $0.month == 3 })?.noteCount, 5)
        XCTAssertEqual(viewModel.monthOptions.first(where: { $0.month == 3 })?.dominant, .focused)

        viewModel.selectPeriod(.yearly)
        viewModel.selectMonth(4)
        viewModel.selectDay("2026-04-02")

        XCTAssertEqual(viewModel.selectedDayNotes.map(\.id), ["note-4"])
        XCTAssertEqual(viewModel.sentimentSummary?.noteCount, 1)

        let didDelete = await viewModel.delete(id: "note-4")
        XCTAssertTrue(didDelete)
        XCTAssertTrue(viewModel.selectedDayNotes.isEmpty)
        XCTAssertEqual(viewModel.monthOptions.first(where: { $0.month == 4 })?.noteCount, 0)
    }

    func testAnalyticsMonthlyWeekSelectionAndSentimentTimeline() async throws {
        let repository = AnalyticsStubRepository(
            period: PeriodSummary(
                periodType: .monthly,
                periodStart: "2026-03-01",
                periodEnd: "2026-03-31",
                completedItems: 7,
                expectedItems: 10,
                completionRate: 0.7,
                activeDays: 4,
                consistencyScore: 0.57
            ),
            daily: [
                DailySummary(
                    dateLocal: "2026-03-03",
                    completedItems: 1,
                    expectedItems: 2,
                    completionRate: 0.5,
                    habitCompleted: 1,
                    habitExpected: 1,
                    todoCompleted: 0,
                    todoExpected: 1
                ),
                DailySummary(
                    dateLocal: "2026-03-10",
                    completedItems: 2,
                    expectedItems: 2,
                    completionRate: 1,
                    habitCompleted: 1,
                    habitExpected: 1,
                    todoCompleted: 1,
                    todoExpected: 1
                ),
                DailySummary(
                    dateLocal: "2026-03-12",
                    completedItems: 1,
                    expectedItems: 2,
                    completionRate: 0.5,
                    habitCompleted: 1,
                    habitExpected: 1,
                    todoCompleted: 0,
                    todoExpected: 1
                ),
                DailySummary(
                    dateLocal: "2026-03-23",
                    completedItems: 3,
                    expectedItems: 4,
                    completionRate: 0.75,
                    habitCompleted: 2,
                    habitExpected: 2,
                    todoCompleted: 1,
                    todoExpected: 2
                ),
            ]
        )
        let reflectionsRepository = ReflectionsStubRepository(notes: [
            try makeReflectionNote(
                id: "s-1",
                periodStart: "2026-03-01",
                content: "Good start",
                sentiment: .great,
                createdAt: "2026-03-01T09:00:00Z"
            ),
            try makeReflectionNote(
                id: "s-2",
                periodStart: "2026-03-12",
                content: "Locked in",
                sentiment: .focused,
                createdAt: "2026-03-12T09:00:00Z"
            ),
            try makeReflectionNote(
                id: "s-3",
                periodStart: "2026-03-12",
                content: "Locked in again",
                sentiment: .focused,
                createdAt: "2026-03-12T13:00:00Z"
            ),
            try makeReflectionNote(
                id: "s-4",
                periodStart: "2026-03-12",
                content: "Hit resistance",
                sentiment: .stressed,
                createdAt: "2026-03-12T15:00:00Z"
            ),
            try makeReflectionNote(
                id: "s-5",
                periodStart: "2026-03-23",
                content: "Needed recovery",
                sentiment: .tired,
                createdAt: "2026-03-23T09:00:00Z"
            ),
        ])

        let viewModel = AnalyticsViewModel(
            repository: repository,
            reflectionsRepository: reflectionsRepository
        )
        await viewModel.loadPeriod(anchorDate: "2026-03-12", periodType: .monthly, weekStart: 0)

        XCTAssertEqual(viewModel.chartSeries.labels, ["W1", "W2", "W3", "W4", "W5"])
        XCTAssertEqual(viewModel.monthWeekBuckets.count, 5)
        XCTAssertEqual(viewModel.selectedMonthWeek, 2)
        XCTAssertEqual(Set(viewModel.dailySummaries.map(\.dateLocal)), Set(["2026-03-10", "2026-03-12"]))
        XCTAssertEqual(viewModel.selectedMonthWeekDetailLabel, "Week 2 · Days 8-14")
        XCTAssertEqual(viewModel.sentimentOverview?.dominant, .focused)
        XCTAssertEqual(viewModel.sentimentOverview?.distribution.first(where: { $0.sentiment == .focused })?.count, 2)
        XCTAssertEqual(viewModel.sentimentOverview?.distribution.first(where: { $0.sentiment == .stressed })?.count, 1)
        XCTAssertEqual(viewModel.sentimentOverview?.trend.count, 31)
        XCTAssertEqual(viewModel.sentimentOverview?.trend.first?.dateLocal, "2026-03-01")
        XCTAssertEqual(viewModel.sentimentOverview?.trend[11].dateLocal, "2026-03-12")
        XCTAssertEqual(viewModel.sentimentOverview?.trend[11].sentiment, .focused)

        viewModel.selectMonthWeek(4)

        XCTAssertEqual(viewModel.selectedMonthWeek, 4)
        XCTAssertEqual(viewModel.selectedMonthWeekDetailLabel, "Week 4 · Days 22-28")
        XCTAssertEqual(Set(viewModel.dailySummaries.map(\.dateLocal)), Set(["2026-03-23"]))
        XCTAssertEqual(viewModel.sentimentOverview?.trend.count, 31)
    }

    func testAnalyticsYearSelectionCommitsAfterDataLoads() async throws {
        let repository = AnalyticsStubRepository(
            period: PeriodSummary(
                periodType: .yearly,
                periodStart: "2026-01-01",
                periodEnd: "2026-12-31",
                completedItems: 9,
                expectedItems: 12,
                completionRate: 0.75,
                activeDays: 4,
                consistencyScore: 0.66
            ),
            daily: [
                DailySummary(
                    dateLocal: "2026-01-04",
                    completedItems: 2,
                    expectedItems: 3,
                    completionRate: 2.0 / 3.0,
                    habitCompleted: 1,
                    habitExpected: 2,
                    todoCompleted: 1,
                    todoExpected: 1
                ),
                DailySummary(
                    dateLocal: "2026-05-12",
                    completedItems: 4,
                    expectedItems: 5,
                    completionRate: 0.8,
                    habitCompleted: 2,
                    habitExpected: 3,
                    todoCompleted: 2,
                    todoExpected: 2
                ),
            ],
            delayNanos: 150_000_000
        )
        let viewModel = AnalyticsViewModel(repository: repository)

        let loadTask = Task {
            await viewModel.loadPeriod(anchorDate: "2026-03-12", periodType: .yearly, weekStart: 0)
        }

        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(viewModel.selectedPeriod, .weekly)
        XCTAssertEqual(viewModel.pendingPeriod, .yearly)
        XCTAssertTrue(viewModel.isSwitchingPeriod)

        await loadTask.value

        XCTAssertEqual(viewModel.selectedPeriod, .yearly)
        XCTAssertNil(viewModel.pendingPeriod)
        XCTAssertFalse(viewModel.isSwitchingPeriod)
        XCTAssertEqual(viewModel.chartSeries.labels.count, 12)
        XCTAssertEqual(viewModel.contributionSections.count, 12)
    }

    func testAnalyticsYearlyChartPadsMissingMonths() async throws {
        let repository = AnalyticsStubRepository(
            period: PeriodSummary(
                periodType: .yearly,
                periodStart: "2026-01-01",
                periodEnd: "2026-12-31",
                completedItems: 6,
                expectedItems: 8,
                completionRate: 0.75,
                activeDays: 2,
                consistencyScore: 0.7
            ),
            daily: [
                DailySummary(
                    dateLocal: "2026-01-04",
                    completedItems: 2,
                    expectedItems: 3,
                    completionRate: 2.0 / 3.0,
                    habitCompleted: 1,
                    habitExpected: 2,
                    todoCompleted: 1,
                    todoExpected: 1
                ),
                DailySummary(
                    dateLocal: "2026-05-12",
                    completedItems: 4,
                    expectedItems: 5,
                    completionRate: 0.8,
                    habitCompleted: 2,
                    habitExpected: 3,
                    todoCompleted: 2,
                    todoExpected: 2
                ),
            ]
        )
        let viewModel = AnalyticsViewModel(repository: repository)

        await viewModel.loadPeriod(anchorDate: "2026-03-12", periodType: .yearly, weekStart: 0)

        XCTAssertEqual(viewModel.chartSeries.labels, (1...12).map(OneDate.shortMonth(for:)))
        XCTAssertEqual(viewModel.chartSeries.values.count, 12)
        XCTAssertEqual(viewModel.chartSeries.values[0], 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.chartSeries.values[1], 0, accuracy: 0.001)
        XCTAssertEqual(viewModel.chartSeries.values[4], 0.8, accuracy: 0.001)
    }

    func testRefreshTasksContextRefreshesSchedulesForTodayMutations() async throws {
        let api = MockAPIClient()
        let syncQueue = InMemorySyncQueue()
        let applier = TrackingNotificationPreferenceApplier()
        let container = OneAppContainer(
            authRepository: DefaultAuthRepository(apiClient: api),
            tasksRepository: DefaultTasksRepository(apiClient: api, syncQueue: syncQueue),
            todayRepository: DefaultTodayRepository(apiClient: api, syncQueue: syncQueue),
            analyticsRepository: DefaultAnalyticsRepository(apiClient: api),
            reflectionsRepository: DefaultReflectionsRepository(apiClient: api),
            profileRepository: DefaultProfileRepository(apiClient: api),
            coachRepository: DefaultCoachRepository(apiClient: api),
            notificationApplier: applier
        )

        await container.authViewModel.createLocalProfile(displayName: "Local User")
        await container.profileViewModel.load()
        let initialApplyCount = await applier.recordedApplyCount()
        XCTAssertEqual(initialApplyCount, 0)

        await container.refreshTasksContext(anchorDate: "2026-03-12")

        let refreshedApplyCount = await applier.recordedApplyCount()
        XCTAssertEqual(refreshedApplyCount, 1)
    }

    func testNotesViewModelCreateNoteAddsEntryToSelectedDay() async throws {
        let repository = ReflectionsStubRepository(notes: [])
        let viewModel = NotesViewModel(repository: repository)

        await viewModel.load(anchorDate: "2026-03-12", periodType: .daily, weekStart: 0, forceReload: true)
        let created = await viewModel.createNote(
            content: "Captured while the day was moving",
            sentiment: .focused
        )

        XCTAssertNotNil(created)
        XCTAssertEqual(viewModel.selectedDayNotes.count, 1)
        XCTAssertEqual(viewModel.selectedDayNotes.first?.content, "Captured while the day was moving")
        XCTAssertEqual(viewModel.sentimentSummary?.noteCount, 1)
        XCTAssertEqual(viewModel.sentimentSummary?.dominant, .focused)
    }

    private func assertWeeklyHabitStaysOnConfiguredWeekdayAcrossDeviceTimezones() async throws {
        let originalTimeZone = NSTimeZone.default
        defer { NSTimeZone.default = originalTimeZone }

        for identifier in ["America/Los_Angeles", "Asia/Tokyo"] {
            guard let timeZone = TimeZone(identifier: identifier) else {
                XCTFail("Missing timezone \(identifier)")
                continue
            }
            NSTimeZone.default = timeZone

            let sessionStore = InMemoryAuthSessionStore()
            let stack = try LocalPersistenceFactory.makeInMemory(sessionStore: sessionStore)
            let authRepository = DefaultAuthRepository(apiClient: stack.apiClient)
            let tasksRepository = DefaultTasksRepository(apiClient: stack.apiClient, syncQueue: stack.syncQueue)
            let todayRepository = DefaultTodayRepository(apiClient: stack.apiClient, syncQueue: stack.syncQueue)

            _ = try await authRepository.signup(
                email: "weekly-\(identifier.replacingOccurrences(of: "/", with: "-"))@one.local",
                password: "offline-local-profile",
                displayName: "Weekly \(identifier)",
                timezone: "America/Guatemala"
            )

            let categories = try await tasksRepository.loadCategories()
            _ = try await tasksRepository.createHabit(
                HabitCreateInput(
                    categoryId: categories[0].id,
                    title: "Midweek reset",
                    recurrenceRule: "WEEKLY:WED",
                    startDate: "2026-03-11"
                )
            )

            let wednesday = try await todayRepository.loadToday(date: "2026-03-11")
            let thursday = try await todayRepository.loadToday(date: "2026-03-12")

            XCTAssertEqual(
                wednesday.items.filter { $0.itemType == .habit }.count,
                1,
                "Expected Wednesday habit on Wednesday for device timezone \(identifier)"
            )
            XCTAssertTrue(
                thursday.items.filter { $0.itemType == .habit }.isEmpty,
                "Did not expect Wednesday habit on Thursday for device timezone \(identifier)"
            )
        }
    }

    private func assertRecurrenceRuleRoundTrip() throws {
        let weekly = HabitRecurrenceRule(
            frequency: .weekly,
            weekdays: [.monday, .wednesday]
        )
        XCTAssertEqual(weekly.rawValue, "WEEKLY:MON,WED")
        XCTAssertEqual(HabitRecurrenceRule(rawValue: weekly.rawValue), weekly)

        let monthly = HabitRecurrenceRule(
            frequency: .monthly,
            monthDays: [15, 1]
        )
        XCTAssertEqual(monthly.rawValue, "MONTHLY:1,15")

        let yearly = HabitRecurrenceRule(
            frequency: .yearly,
            yearlyDates: [
                HabitRecurrenceYearlyDate(month: 12, day: 25),
                HabitRecurrenceYearlyDate(month: 3, day: 1),
            ]
        )
        XCTAssertEqual(yearly.rawValue, "YEARLY:03-01,12-25")
        XCTAssertEqual(yearly.summary, "Yearly on Mar 1, Dec 25")

        XCTAssertEqual(HabitRecurrenceRule(rawValue: "DAILY").summary, "Every day")
    }

    private func assertAnalyticsActivityFilter() async throws {
        let repository = AnalyticsStubRepository(
            period: PeriodSummary(
                periodType: .yearly,
                periodStart: "2026-01-01",
                periodEnd: "2026-12-31",
                completedItems: 8,
                expectedItems: 12,
                completionRate: 8.0 / 12.0,
                activeDays: 3,
                consistencyScore: 0.75
            ),
            daily: [
                DailySummary(
                    dateLocal: "2026-01-01",
                    completedItems: 3,
                    expectedItems: 4,
                    completionRate: 0.75,
                    habitCompleted: 2,
                    habitExpected: 3,
                    todoCompleted: 1,
                    todoExpected: 1
                ),
                DailySummary(
                    dateLocal: "2026-02-01",
                    completedItems: 5,
                    expectedItems: 8,
                    completionRate: 0.625,
                    habitCompleted: 1,
                    habitExpected: 4,
                    todoCompleted: 4,
                    todoExpected: 4
                ),
            ]
        )

        let viewModel = AnalyticsViewModel(repository: repository)
        await viewModel.loadPeriod(anchorDate: "2026-03-12", periodType: .yearly, weekStart: 0)

        XCTAssertEqual(viewModel.dailySummaries.count, 2)
        XCTAssertEqual(viewModel.summary?.expectedItems, 12)

        viewModel.selectActivityFilter(.habits)

        XCTAssertEqual(viewModel.summary?.completedItems, 3)
        XCTAssertEqual(viewModel.summary?.expectedItems, 7)
        XCTAssertEqual(viewModel.dailySummaries.map(\.expectedItems), [3, 4])

        viewModel.selectActivityFilter(.todos)

        XCTAssertEqual(viewModel.summary?.completedItems, 5)
        XCTAssertEqual(viewModel.summary?.expectedItems, 5)
        XCTAssertEqual(viewModel.dailySummaries.map(\.completedItems), [1, 4])
    }
}

private actor FlakyCompletionAPIClient: APIClient {
    private var session: AuthSessionTokens? = AuthSessionTokens(
        accessToken: "token",
        refreshToken: "refresh",
        expiresAt: Date().addingTimeInterval(3600)
    )
    private var remainingFailures = 1
    private var today = TodayResponse(
        dateLocal: "2026-03-12",
        items: [
            TodayItem(
                itemType: .habit,
                itemId: "h1",
                title: "Workout",
                categoryId: "c1",
                completed: false,
                sortBucket: 2,
                sortScore: 50
            )
        ],
        completedCount: 0,
        totalCount: 1,
        completionRatio: 0
    )

    func currentSession() async -> AuthSessionTokens? { session }
    func clearSession() async { session = nil }
    func login(email: String, password: String) async throws -> AuthSession { throw APIError.transport("unused") }
    func signup(email: String, password: String, displayName: String, timezone: String) async throws -> AuthSession { throw APIError.transport("unused") }
    func fetchMe() async throws -> User { throw APIError.transport("unused") }
    func fetchCategories() async throws -> [OneClient.Category] { throw APIError.transport("unused") }
    func fetchHabits() async throws -> [Habit] { throw APIError.transport("unused") }
    func fetchTodos() async throws -> [Todo] { throw APIError.transport("unused") }
    func fetchCoachCards() async throws -> [CoachCard] { throw APIError.transport("unused") }
    func createHabit(input: HabitCreateInput) async throws -> Habit { throw APIError.transport("unused") }
    func createTodo(input: TodoCreateInput) async throws -> Todo { throw APIError.transport("unused") }
    func fetchToday(date: String?) async throws -> TodayResponse { today }
    func putTodayOrder(dateLocal: String, items: [TodayOrderItem]) async throws -> TodayResponse { today }
    func fetchDaily(startDate: String, endDate: String) async throws -> [DailySummary] { throw APIError.transport("unused") }
    func fetchPeriod(anchorDate: String, periodType: PeriodType) async throws -> PeriodSummary { throw APIError.transport("unused") }
    func fetchHabitStats(habitId: String, anchorDate: String?, windowDays: Int?) async throws -> HabitStats { throw APIError.transport("unused") }
    func fetchReflections(periodType: PeriodType?) async throws -> [ReflectionNote] { throw APIError.transport("unused") }
    func upsertReflection(input: ReflectionWriteInput) async throws -> ReflectionNote { throw APIError.transport("unused") }
    func deleteReflection(id: String) async throws { throw APIError.transport("unused") }
    func fetchPreferences() async throws -> UserPreferences { throw APIError.transport("unused") }
    func patchPreferences(input: UserPreferencesUpdateInput) async throws -> UserPreferences { throw APIError.transport("unused") }
    func patchUser(input: UserProfileUpdateInput) async throws -> User { throw APIError.transport("unused") }
    func patchHabit(id: String, input: HabitUpdateInput, clientUpdatedAt: Date?) async throws -> Habit { throw APIError.transport("unused") }
    func patchTodo(id: String, fields: [String : String], clientUpdatedAt: Date?) async throws -> Todo { throw APIError.transport("unused") }
    func patchTodo(id: String, input: TodoUpdateInput, clientUpdatedAt: Date?) async throws -> Todo { throw APIError.transport("unused") }
    func deleteHabit(id: String) async throws {}
    func deleteTodo(id: String) async throws {}

    func updateCompletion(itemType: ItemType, itemId: String, dateLocal: String, state: CompletionState) async throws {
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw APIError.transport("transient failure")
        }

        let completed = state == .completed
        today = TodayResponse(
            dateLocal: dateLocal,
            items: [
                TodayItem(
                    itemType: itemType,
                    itemId: itemId,
                    title: "Workout",
                    categoryId: "c1",
                    completed: completed,
                    sortBucket: 2,
                    sortScore: 50
                )
            ],
            completedCount: completed ? 1 : 0,
            totalCount: 1,
            completionRatio: completed ? 1 : 0
        )
    }
}

private actor AnalyticsStubRepository: AnalyticsRepository {
    let period: PeriodSummary
    let daily: [DailySummary]
    let delayNanos: UInt64

    init(period: PeriodSummary, daily: [DailySummary], delayNanos: UInt64 = 0) {
        self.period = period
        self.daily = daily
        self.delayNanos = delayNanos
    }

    func loadWeekly(anchorDate: String) async throws -> PeriodSummary {
        try await sleepIfNeeded()
        return period
    }

    func loadPeriod(anchorDate: String, periodType: PeriodType) async throws -> PeriodSummary {
        try await sleepIfNeeded()
        return period
    }

    func loadDaily(startDate: String, endDate: String) async throws -> [DailySummary] {
        try await sleepIfNeeded()
        return daily
    }

    private func sleepIfNeeded() async throws {
        guard delayNanos > 0 else {
            return
        }
        try await Task.sleep(nanoseconds: delayNanos)
    }
}

private actor ReflectionsStubRepository: ReflectionsRepository {
    private var notes: [ReflectionNote]

    init(notes: [ReflectionNote]) {
        self.notes = notes
    }

    func list(periodType: PeriodType?) async throws -> [ReflectionNote] {
        if let periodType {
            return notes.filter { $0.periodType == periodType }
        }
        return notes
    }

    func upsert(input: ReflectionWriteInput) async throws -> ReflectionNote {
        let now = ISO8601DateFormatter().string(from: Date())
        let note = try makeReflectionNote(
            id: UUID().uuidString,
            periodStart: input.periodStart,
            content: input.content,
            sentiment: input.sentiment,
            createdAt: now,
            updatedAt: now
        )
        notes.insert(note, at: 0)
        return note
    }

    func delete(id: String) async throws {
        notes.removeAll { $0.id == id }
    }
}

private actor TrackingNotificationPreferenceApplier: NotificationPreferenceApplier {
    private var applyCount = 0

    func apply(preferences: UserPreferences) async -> NotificationScheduleStatus {
        applyCount += 1
        return NotificationScheduleStatus(
            permissionGranted: true,
            scheduledCount: 2,
            lastRefreshedAt: Date(),
            lastError: nil
        )
    }

    func status() async -> NotificationScheduleStatus? {
        nil
    }

    func recordedApplyCount() async -> Int {
        applyCount
    }
}

private func makeReflectionNote(
    id: String,
    periodStart: String,
    content: String,
    sentiment: ReflectionSentiment,
    createdAt: String,
    updatedAt: String? = nil
) throws -> ReflectionNote {
    var payload: [String: Any] = [
        "id": id,
        "user_id": "user-1",
        "period_type": "daily",
        "period_start": periodStart,
        "period_end": periodStart,
        "content": content,
        "sentiment": sentiment.rawValue,
        "tags": [],
        "created_at": createdAt,
    ]
    if let updatedAt {
        payload["updated_at"] = updatedAt
    }

    let data = try JSONSerialization.data(withJSONObject: payload)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(ReflectionNote.self, from: data)
}
