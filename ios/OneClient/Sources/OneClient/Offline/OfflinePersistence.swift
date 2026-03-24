import Foundation

#if canImport(SwiftData)
import SwiftData

public protocol LocalDataGateway: APIClient {}

@Model
final class LocalUserEntity {
    @Attribute(.unique) var id: String
    var email: String
    var appleSub: String?
    var displayName: String
    var timezone: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(id: String, email: String, appleSub: String?, displayName: String, timezone: String, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id
        self.email = email
        self.appleSub = appleSub
        self.displayName = displayName
        self.timezone = timezone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class LocalPreferencesEntity {
    @Attribute(.unique) var id: String
    var userId: String
    var theme: String
    var weekStart: Int
    var defaultTab: String
    var notificationFlagsData: Data
    var quietHoursStart: String?
    var quietHoursEnd: String?
    var coachEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: String, userId: String, theme: String, weekStart: Int, defaultTab: String, notificationFlagsData: Data, quietHoursStart: String?, quietHoursEnd: String?, coachEnabled: Bool, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.userId = userId
        self.theme = theme
        self.weekStart = weekStart
        self.defaultTab = defaultTab
        self.notificationFlagsData = notificationFlagsData
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.coachEnabled = coachEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class LocalCategoryEntity {
    @Attribute(.unique) var id: String
    var userId: String
    var name: String
    var icon: String
    var color: String
    var sortOrder: Int
    var isDefault: Bool
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(id: String, userId: String, name: String, icon: String, color: String, sortOrder: Int, isDefault: Bool, archivedAt: Date?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id
        self.userId = userId
        self.name = name
        self.icon = icon
        self.color = color
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class LocalHabitEntity {
    @Attribute(.unique) var id: String
    var userId: String
    var categoryId: String
    var title: String
    var notes: String
    var recurrenceRule: String
    var startDate: String
    var endDate: String?
    var priorityWeight: Int
    var preferredTime: String?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(id: String, userId: String, categoryId: String, title: String, notes: String, recurrenceRule: String, startDate: String, endDate: String?, priorityWeight: Int, preferredTime: String?, isActive: Bool, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id
        self.userId = userId
        self.categoryId = categoryId
        self.title = title
        self.notes = notes
        self.recurrenceRule = recurrenceRule
        self.startDate = startDate
        self.endDate = endDate
        self.priorityWeight = priorityWeight
        self.preferredTime = preferredTime
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class LocalTodoEntity {
    @Attribute(.unique) var id: String
    var userId: String
    var categoryId: String
    var title: String
    var notes: String
    var dueAt: Date?
    var priority: Int
    var isPinned: Bool
    var status: String
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(id: String, userId: String, categoryId: String, title: String, notes: String, dueAt: Date?, priority: Int, isPinned: Bool, status: String, completedAt: Date?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id
        self.userId = userId
        self.categoryId = categoryId
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.priority = priority
        self.isPinned = isPinned
        self.status = status
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class LocalCompletionLogEntity {
    @Attribute(.unique) var id: String
    var userId: String
    var itemType: String
    var itemId: String
    var dateLocal: String
    var state: String
    var completedAt: Date?
    var source: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(id: String, userId: String, itemType: String, itemId: String, dateLocal: String, state: String, completedAt: Date?, source: String, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id
        self.userId = userId
        self.itemType = itemType
        self.itemId = itemId
        self.dateLocal = dateLocal
        self.state = state
        self.completedAt = completedAt
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class LocalTodayOrderOverrideEntity {
    @Attribute(.unique) var id: String
    var userId: String
    var dateLocal: String
    var itemType: String
    var itemId: String
    var orderIndex: Int
    var createdAt: Date
    var updatedAt: Date

    init(id: String, userId: String, dateLocal: String, itemType: String, itemId: String, orderIndex: Int, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.userId = userId
        self.dateLocal = dateLocal
        self.itemType = itemType
        self.itemId = itemId
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class LocalReflectionEntity {
    @Attribute(.unique) var id: String
    var userId: String
    var periodType: String
    var periodStart: String
    var periodEnd: String
    var content: String
    var sentiment: String
    var tagsData: Data
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: String,
        userId: String,
        periodType: String,
        periodStart: String,
        periodEnd: String,
        content: String,
        sentiment: String,
        tagsData: Data,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?
    ) {
        self.id = id
        self.userId = userId
        self.periodType = periodType
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.content = content
        self.sentiment = sentiment
        self.tagsData = tagsData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class LocalCoachCardEntity {
    @Attribute(.unique) var id: String
    var title: String
    var body: String
    var verseRef: String?
    var verseText: String?
    var tagsData: Data
    var locale: String
    var activeFrom: String?
    var activeTo: String?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: String, title: String, body: String, verseRef: String?, verseText: String?, tagsData: Data, locale: String, activeFrom: String?, activeTo: String?, isActive: Bool, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.verseRef = verseRef
        self.verseText = verseText
        self.tagsData = tagsData
        self.locale = locale
        self.activeFrom = activeFrom
        self.activeTo = activeTo
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct LocalPersistenceStack {
    public let container: ModelContainer
    public let apiClient: LocalDataClient
    public let syncQueue: SyncQueue
}

public enum LocalPersistenceFactory {
    public static func makeStored(sessionStore: AuthSessionStore) throws -> LocalPersistenceStack {
        try make(sessionStore: sessionStore, inMemory: false)
    }

    public static func makeInMemory(sessionStore: AuthSessionStore) throws -> LocalPersistenceStack {
        try make(sessionStore: sessionStore, inMemory: true)
    }

    private static func make(sessionStore: AuthSessionStore, inMemory: Bool) throws -> LocalPersistenceStack {
        let schema = Schema([
            LocalUserEntity.self,
            LocalPreferencesEntity.self,
            LocalCategoryEntity.self,
            LocalHabitEntity.self,
            LocalTodoEntity.self,
            LocalCompletionLogEntity.self,
            LocalTodayOrderOverrideEntity.self,
            LocalReflectionEntity.self,
            LocalCoachCardEntity.self,
            LocalFinanceTransactionEntity.self,
            LocalFinanceCategoryEntity.self,
            LocalFinanceBalanceEntity.self,
            LocalRecurringFinanceTransactionEntity.self,
            PendingMutationEntity.self,
        ])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration("OneOfflineStore", isStoredInMemoryOnly: true)
        } else {
            let fileManager = FileManager.default
            let applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            try fileManager.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
            let storeURL = applicationSupportURL.appendingPathComponent("OneOfflineStore.store")
            configuration = ModelConfiguration("OneOfflineStore", url: storeURL)
        }
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let apiClient = LocalDataClient(container: container, sessionStore: sessionStore)
        let syncQueue = SwiftDataSyncQueue(container: container)
        return LocalPersistenceStack(container: container, apiClient: apiClient, syncQueue: syncQueue)
    }
}

public actor LocalDataClient: LocalDataGateway, LocalProfileInspectable, ModelActor {
    nonisolated public let modelContainer: ModelContainer
    nonisolated public let modelExecutor: any ModelExecutor
    private let sessionStore: AuthSessionStore
    private let onboardingService = LocalOnboardingService()
    private let todayService = LocalTodayService()
    private let analyticsService = LocalAnalyticsService()
    private let reflectionService = LocalReflectionService()
    private let coachingService = LocalCoachingService()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var context: ModelContext {
        modelContext
    }

    public init(container: ModelContainer, sessionStore: AuthSessionStore) {
        let context = ModelContext(container)
        self.modelContainer = container
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.sessionStore = sessionStore
    }

    public func currentSession() async -> AuthSessionTokens? {
        await ensuredSessionTokens()
    }

    public func clearSession() async {
        await sessionStore.setRecoverySuppressed(true)
        await sessionStore.clear()
    }

    public func persistedLocalUser() async -> User? {
        guard let resolvedEntity = try? activeUserEntity() else {
            return nil
        }
        return mapUser(resolvedEntity)
    }

    public func login(email: String, password: String) async throws -> AuthSession {
        let users = try activeUsers()
        guard let user = users.first(where: { $0.email == email }) ?? users.first else {
            throw APIError.unauthorized
        }
        let session = makeSession(for: user)
        try await sessionStore.write(session.tokens)
        return session
    }

    public func signup(email: String, password: String, displayName: String, timezone: String) async throws -> AuthSession {
        _ = timezone
        let deviceTimezoneID = OfflineDateCoding.deviceTimeZoneIdentifier
        let now = Date()
        if let entity = try activeUserEntity() {
            entity.displayName = displayName
            entity.timezone = deviceTimezoneID
            entity.email = email
            entity.updatedAt = now
            try seedCoachCardsIfNeeded()
            try save()
            let session = makeSession(for: mapUser(entity))
            try await sessionStore.write(session.tokens)
            return session
        }

        let userID = UUID().uuidString
        let bundle = onboardingService.bootstrap(
            userID: userID,
            email: email,
            displayName: displayName,
            timezone: deviceTimezoneID
        )
        context.insert(
            LocalUserEntity(
                id: bundle.user.id,
                email: bundle.user.email,
                appleSub: bundle.user.appleSub,
                displayName: bundle.user.displayName,
                timezone: bundle.user.timezone,
                createdAt: bundle.user.createdAt ?? now,
                updatedAt: now,
                deletedAt: nil
            )
        )
        for category in bundle.categories {
            context.insert(
                LocalCategoryEntity(
                    id: category.id,
                    userId: category.userId,
                    name: category.name,
                    icon: category.icon,
                    color: category.color,
                    sortOrder: category.sortOrder,
                    isDefault: category.isDefault,
                    archivedAt: category.archivedAt,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil
                )
            )
        }
        context.insert(
            LocalPreferencesEntity(
                id: bundle.preferences.id,
                userId: bundle.preferences.userId,
                theme: bundle.preferences.theme.rawValue,
                weekStart: bundle.preferences.weekStart,
                defaultTab: bundle.preferences.defaultTab,
                notificationFlagsData: try encode(bundle.preferences.notificationFlags),
                quietHoursStart: bundle.preferences.quietHoursStart,
                quietHoursEnd: bundle.preferences.quietHoursEnd,
                coachEnabled: bundle.preferences.coachEnabled,
                createdAt: now,
                updatedAt: now
            )
        )
        try seedCoachCardsIfNeeded()
        try save()
        let session = makeSession(for: bundle.user)
        try await sessionStore.write(session.tokens)
        return session
    }

    public func fetchMe() async throws -> User {
        let userID = try await currentUserID()
        guard let entity = try activeUserEntity(userID: userID) else {
            throw APIError.unauthorized
        }
        return mapUser(entity)
    }

    public func fetchCategories() async throws -> [Category] {
        let userID = try await currentUserID()
        return try activeCategoryEntities()
            .filter { $0.userId == userID }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(mapCategory)
    }

    public func fetchHabits() async throws -> [Habit] {
        let userID = try await currentUserID()
        return try activeHabitEntities()
            .filter { $0.userId == userID }
            .sorted { $0.createdAt < $1.createdAt }
            .map(mapHabit)
    }

    public func fetchTodos() async throws -> [Todo] {
        let userID = try await currentUserID()
        return try activeTodoEntities()
            .filter { $0.userId == userID }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(mapTodo)
    }

    public func fetchCoachCards() async throws -> [CoachCard] {
        try seedCoachCardsIfNeeded()
        let cards = try activeCoachCardEntities().map(mapCoachCard)
        return coachingService.activeCards(cards: cards)
    }

    public func createHabit(input: HabitCreateInput) async throws -> Habit {
        let user = try await fetchMe()
        let now = Date()
        let habit = Habit(
            id: UUID().uuidString,
            userId: user.id,
            categoryId: input.categoryId,
            title: input.title,
            notes: input.notes,
            recurrenceRule: input.recurrenceRule,
            startDate: input.startDate ?? OfflineDateCoding.localDateString(from: now, timezoneID: user.timezone),
            endDate: input.endDate,
            priorityWeight: input.priorityWeight,
            preferredTime: input.preferredTime,
            isActive: true
        )
        context.insert(
            LocalHabitEntity(
                id: habit.id,
                userId: habit.userId,
                categoryId: habit.categoryId,
                title: habit.title,
                notes: habit.notes,
                recurrenceRule: habit.recurrenceRule,
                startDate: habit.startDate,
                endDate: habit.endDate,
                priorityWeight: habit.priorityWeight,
                preferredTime: habit.preferredTime,
                isActive: habit.isActive,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
        )
        try save()
        return habit
    }

    public func createTodo(input: TodoCreateInput) async throws -> Todo {
        let user = try await fetchMe()
        let now = Date()
        let todo = Todo(
            id: UUID().uuidString,
            userId: user.id,
            categoryId: input.categoryId,
            title: input.title,
            notes: input.notes,
            dueAt: input.dueAt,
            priority: input.priority,
            isPinned: input.isPinned,
            status: .open,
            createdAt: now,
            updatedAt: now
        )
        context.insert(
            LocalTodoEntity(
                id: todo.id,
                userId: todo.userId,
                categoryId: todo.categoryId,
                title: todo.title,
                notes: todo.notes,
                dueAt: todo.dueAt,
                priority: todo.priority,
                isPinned: todo.isPinned,
                status: todo.status.rawValue,
                completedAt: todo.completedAt,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
        )
        try save()
        return todo
    }

    public func fetchToday(date: String?) async throws -> TodayResponse {
        let user = try await fetchMe()
        let targetDate = date ?? OfflineDateCoding.localDateString(from: Date(), timezoneID: user.timezone)
        let habits = try await fetchHabits()
        let todos = try await fetchTodos()
        let logs = try activeCompletionLogEntities()
            .filter { $0.userId == user.id }
            .map(mapCompletionLog)
        let overrides = try activeTodayOrderOverrideEntities()
            .filter { $0.userId == user.id && $0.dateLocal == targetDate }
            .map {
                TodayOrderOverrideRecord(
                    itemType: ItemType(rawValue: $0.itemType) ?? .habit,
                    itemId: $0.itemId,
                    orderIndex: $0.orderIndex
                )
            }

        let materialization = todayService.materialize(
            user: user,
            targetDate: targetDate,
            habits: habits,
            todos: todos,
            completionLogs: logs,
            overrides: overrides
        )
        for log in materialization.materializedLogs {
            context.insert(
                LocalCompletionLogEntity(
                    id: log.id,
                    userId: log.userId,
                    itemType: log.itemType.rawValue,
                    itemId: log.itemId,
                    dateLocal: log.dateLocal,
                    state: log.state.rawValue,
                    completedAt: log.completedAt,
                    source: log.source,
                    createdAt: log.createdAt,
                    updatedAt: log.updatedAt,
                    deletedAt: nil
                )
            )
        }
        if !materialization.materializedLogs.isEmpty {
            try save()
        }
        return materialization.response
    }

    public func putTodayOrder(dateLocal: String, items: [TodayOrderItem]) async throws -> TodayResponse {
        let user = try await fetchMe()
        let existing = try activeTodayOrderOverrideEntities().filter { $0.userId == user.id && $0.dateLocal == dateLocal }
        for row in existing {
            context.delete(row)
        }
        let now = Date()
        for item in items {
            context.insert(
                LocalTodayOrderOverrideEntity(
                    id: "\(user.id)|\(dateLocal)|\(item.itemType.rawValue)|\(item.itemId)",
                    userId: user.id,
                    dateLocal: dateLocal,
                    itemType: item.itemType.rawValue,
                    itemId: item.itemId,
                    orderIndex: item.orderIndex,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
        try save()
        return try await fetchToday(date: dateLocal)
    }

    public func updateCompletion(itemType: ItemType, itemId: String, dateLocal: String, state: CompletionState) async throws {
        let user = try await fetchMe()
        switch itemType {
        case .habit:
            if let entity = try activeCompletionLogEntities().first(where: {
                $0.userId == user.id &&
                    $0.itemType == itemType.rawValue &&
                    $0.itemId == itemId &&
                    $0.dateLocal == dateLocal
            }) {
                entity.state = state.rawValue
                entity.completedAt = state == .completed ? Date() : nil
                entity.updatedAt = Date()
                entity.source = "ios"
            } else {
                let log = CompletionLog(
                    id: UUID().uuidString,
                    userId: user.id,
                    itemType: itemType,
                    itemId: itemId,
                    dateLocal: dateLocal,
                    state: state,
                    completedAt: state == .completed ? Date() : nil,
                    source: "ios"
                )
                context.insert(
                    LocalCompletionLogEntity(
                        id: log.id,
                        userId: log.userId,
                        itemType: log.itemType.rawValue,
                        itemId: log.itemId,
                        dateLocal: log.dateLocal,
                        state: log.state.rawValue,
                        completedAt: log.completedAt,
                        source: log.source,
                        createdAt: log.createdAt,
                        updatedAt: log.updatedAt,
                        deletedAt: nil
                    )
                )
            }
        case .todo:
            guard let todo = try activeTodoEntities().first(where: { $0.userId == user.id && $0.id == itemId }) else {
                throw APIError.server(statusCode: 404, message: "Task not found")
            }
            todo.status = (state == .completed ? TodoStatus.completed : TodoStatus.open).rawValue
            todo.completedAt = state == .completed ? Date() : nil
            todo.updatedAt = Date()
        case .reflection:
            return
        }
        try save()
    }

    public func fetchDaily(startDate: String, endDate: String) async throws -> [DailySummary] {
        let user = try await fetchMe()
        return analyticsService.dailySummaries(
            user: user,
            startDate: startDate,
            endDate: endDate,
            habits: try await fetchHabits(),
            todos: try await fetchTodos(),
            completionLogs: try activeCompletionLogEntities().filter { $0.userId == user.id }.map(mapCompletionLog)
        )
    }

    public func fetchPeriod(anchorDate: String, periodType: PeriodType) async throws -> PeriodSummary {
        let user = try await fetchMe()
        let preferences = try await fetchPreferences()
        return analyticsService.periodSummary(
            user: user,
            anchorDate: anchorDate,
            periodType: periodType,
            weekStart: preferences.weekStart,
            habits: try await fetchHabits(),
            todos: try await fetchTodos(),
            completionLogs: try activeCompletionLogEntities().filter { $0.userId == user.id }.map(mapCompletionLog)
        )
    }

    public func fetchHabitStats(habitId: String, anchorDate: String?, windowDays: Int?) async throws -> HabitStats {
        let user = try await fetchMe()
        let habits = try await fetchHabits()
        guard let habit = habits.first(where: { $0.id == habitId }) else {
            throw APIError.server(statusCode: 404, message: "Habit not found")
        }
        return analyticsService.habitStats(
            user: user,
            habit: habit,
            anchorDate: anchorDate ?? OfflineDateCoding.localDateString(from: Date(), timezoneID: user.timezone),
            windowDays: windowDays ?? 30,
            completionLogs: try activeCompletionLogEntities().filter { $0.userId == user.id }.map(mapCompletionLog)
        )
    }

    public func fetchReflections(periodType: PeriodType?) async throws -> [ReflectionNote] {
        let user = try await fetchMe()
        let notes = try activeReflectionEntities()
            .filter { $0.userId == user.id }
            .map(mapReflection)
        return reflectionService.list(notes: notes, userID: user.id, periodType: periodType)
    }

    public func upsertReflection(input: ReflectionWriteInput) async throws -> ReflectionNote {
        let user = try await fetchMe()
        let now = Date()
        let incoming = ReflectionNote(
            id: UUID().uuidString,
            userId: user.id,
            periodType: input.periodType,
            periodStart: input.periodStart,
            periodEnd: input.periodEnd,
            content: input.content,
            sentiment: input.sentiment,
            tags: input.tags,
            createdAt: now,
            updatedAt: now
        )
        let existing = try activeReflectionEntities().filter { $0.userId == user.id }.map(mapReflection)
        let updatedNotes = reflectionService.create(existing: existing, incoming: incoming)
        let latest = updatedNotes.last ?? incoming
        context.insert(
            LocalReflectionEntity(
                id: latest.id,
                userId: latest.userId,
                periodType: latest.periodType.rawValue,
                periodStart: latest.periodStart,
                periodEnd: latest.periodEnd,
                content: latest.content,
                sentiment: latest.sentiment.rawValue,
                tagsData: try encode(latest.tags),
                createdAt: latest.createdAt ?? now,
                updatedAt: latest.updatedAt ?? now,
                deletedAt: nil
            )
        )
        try save()
        return latest
    }

    public func deleteReflection(id: String) async throws {
        let userID = try await currentUserID()
        guard let entity = try activeReflectionEntities().first(where: { $0.userId == userID && $0.id == id }) else {
            throw APIError.server(statusCode: 404, message: "Reflection not found")
        }
        entity.deletedAt = Date()
        entity.updatedAt = Date()
        try save()
    }

    public func fetchPreferences() async throws -> UserPreferences {
        let userID = try await currentUserID()
        if let entity = try activePreferencesEntity(userID: userID) {
            return try mapPreferences(entity)
        }
        let now = Date()
        let preferences = UserPreferences(
            id: UUID().uuidString,
            userId: userID,
            notificationFlags: [
                "habit_reminders": true,
                "todo_reminders": true,
                "reflection_prompts": true,
                "weekly_summary": true,
            ]
        )
        context.insert(
            LocalPreferencesEntity(
                id: preferences.id,
                userId: preferences.userId,
                theme: preferences.theme.rawValue,
                weekStart: preferences.weekStart,
                defaultTab: preferences.defaultTab,
                notificationFlagsData: try encode(preferences.notificationFlags),
                quietHoursStart: preferences.quietHoursStart,
                quietHoursEnd: preferences.quietHoursEnd,
                coachEnabled: preferences.coachEnabled,
                createdAt: now,
                updatedAt: now
            )
        )
        try save()
        return preferences
    }

    public func patchPreferences(input: UserPreferencesUpdateInput) async throws -> UserPreferences {
        let userID = try await currentUserID()
        let defaultNotificationFlagsData = try encode([
            "habit_reminders": true,
            "todo_reminders": true,
            "reflection_prompts": true,
            "weekly_summary": true,
        ])
        let entity = try activePreferencesEntity(userID: userID) ?? {
            let row = LocalPreferencesEntity(
                id: UUID().uuidString,
                userId: userID,
                theme: Theme.system.rawValue,
                weekStart: 0,
                defaultTab: "today",
                notificationFlagsData: defaultNotificationFlagsData,
                quietHoursStart: nil,
                quietHoursEnd: nil,
                coachEnabled: true,
                createdAt: Date(),
                updatedAt: Date()
            )
            context.insert(row)
            return row
        }()

        if let theme = input.theme { entity.theme = theme.rawValue }
        if let weekStart = input.weekStart { entity.weekStart = weekStart }
        if let defaultTab = input.defaultTab { entity.defaultTab = defaultTab }
        if let quietHoursStart = input.quietHoursStart { entity.quietHoursStart = quietHoursStart }
        if let quietHoursEnd = input.quietHoursEnd { entity.quietHoursEnd = quietHoursEnd }
        if let notificationFlags = input.notificationFlags { entity.notificationFlagsData = try encode(notificationFlags) }
        if let coachEnabled = input.coachEnabled { entity.coachEnabled = coachEnabled }
        entity.updatedAt = Date()
        try save()
        return try mapPreferences(entity)
    }

    public func patchUser(input: UserProfileUpdateInput) async throws -> User {
        let userID = try await currentUserID()
        guard let entity = try activeUserEntity(userID: userID) else {
            throw APIError.unauthorized
        }
        if let displayName = input.displayName { entity.displayName = displayName }
        entity.timezone = OfflineDateCoding.deviceTimeZoneIdentifier
        entity.updatedAt = Date()
        try save()
        return mapUser(entity)
    }

    public func patchHabit(id: String, input: HabitUpdateInput, clientUpdatedAt: Date?) async throws -> Habit {
        guard let entity = try activeHabitEntities().first(where: { $0.id == id }) else {
            throw APIError.server(statusCode: 404, message: "Habit not found")
        }
        if let clientUpdatedAt, clientUpdatedAt < entity.updatedAt {
            return mapHabit(entity)
        }
        if let categoryId = input.categoryId { entity.categoryId = categoryId }
        if let title = input.title { entity.title = title }
        if let notes = input.notes { entity.notes = notes }
        if let recurrenceRule = input.recurrenceRule { entity.recurrenceRule = recurrenceRule }
        if input.clearEndDate { entity.endDate = nil }
        if let endDate = input.endDate { entity.endDate = endDate }
        if let priorityWeight = input.priorityWeight { entity.priorityWeight = priorityWeight }
        if input.clearPreferredTime { entity.preferredTime = nil }
        if let preferredTime = input.preferredTime { entity.preferredTime = preferredTime }
        if let isActive = input.isActive { entity.isActive = isActive }
        entity.updatedAt = Date()
        try save()
        return mapHabit(entity)
    }

    public func patchTodo(id: String, fields: [String: String], clientUpdatedAt: Date?) async throws -> Todo {
        let input = TodoUpdateInput(
            categoryId: fields["category_id"],
            title: fields["title"],
            notes: fields["notes"],
            dueAt: fields["due_at"].flatMap(isoDateTime(from:)),
            priority: fields["priority"].flatMap(Int.init),
            isPinned: fields["is_pinned"].map { ($0 as NSString).boolValue },
            status: fields["status"].flatMap(TodoStatus.init(rawValue:))
        )
        return try await patchTodo(id: id, input: input, clientUpdatedAt: clientUpdatedAt)
    }

    public func patchTodo(id: String, input: TodoUpdateInput, clientUpdatedAt: Date?) async throws -> Todo {
        guard let entity = try activeTodoEntities().first(where: { $0.id == id }) else {
            throw APIError.server(statusCode: 404, message: "Task not found")
        }
        if let clientUpdatedAt, clientUpdatedAt < entity.updatedAt {
            return mapTodo(entity)
        }
        if let categoryId = input.categoryId { entity.categoryId = categoryId }
        if let title = input.title { entity.title = title }
        if let notes = input.notes { entity.notes = notes }
        if input.clearDueAt { entity.dueAt = nil }
        if let dueAt = input.dueAt { entity.dueAt = dueAt }
        if let priority = input.priority { entity.priority = priority }
        if let isPinned = input.isPinned { entity.isPinned = isPinned }
        if let status = input.status {
            entity.status = status.rawValue
            entity.completedAt = status == .completed ? Date() : nil
        }
        entity.updatedAt = Date()
        try save()
        return mapTodo(entity)
    }

    public func deleteHabit(id: String) async throws {
        guard let entity = try activeHabitEntities().first(where: { $0.id == id }) else {
            return
        }
        entity.deletedAt = Date()
        entity.updatedAt = Date()
        try save()
    }

    public func deleteTodo(id: String) async throws {
        guard let entity = try activeTodoEntities().first(where: { $0.id == id }) else {
            return
        }
        entity.deletedAt = Date()
        entity.updatedAt = Date()
        try save()
    }

    private func currentUserID() async throws -> String {
        guard let session = await ensuredSessionTokens() else {
            throw APIError.unauthorized
        }
        return session.accessToken
    }

    private func ensuredSessionTokens() async -> AuthSessionTokens? {
        if let session = await sessionStore.read() {
            return session
        }
        guard await sessionStore.isRecoverySuppressed() == false else {
            return nil
        }
        guard let resolvedEntity = try? activeUserEntity() else {
            return nil
        }
        let session = makeSession(for: mapUser(resolvedEntity))
        try? await sessionStore.write(session.tokens)
        return session.tokens
    }

    private func makeSession(for user: User) -> AuthSession {
        let tokens = AuthSessionTokens(
            accessToken: user.id,
            refreshToken: "offline-\(user.id)",
            expiresAt: nil
        )
        return AuthSession(tokens: tokens, user: user)
    }

    private func seedCoachCardsIfNeeded() throws {
        let existing = try activeCoachCardEntities().map(mapCoachCard)
        let seeded = coachingService.seedCardsIfNeeded(existing: existing)
        guard existing.isEmpty else {
            return
        }
        let now = Date()
        for card in seeded {
            context.insert(
                LocalCoachCardEntity(
                    id: card.id,
                    title: card.title,
                    body: card.body,
                    verseRef: card.verseRef,
                    verseText: card.verseText,
                    tagsData: try encode(card.tags),
                    locale: card.locale,
                    activeFrom: card.activeFrom,
                    activeTo: card.activeTo,
                    isActive: card.isActive,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
        try save()
    }

    private func activeUserEntity() throws -> LocalUserEntity? {
        try activeUserEntities().first
    }

    private func activeUserEntity(userID: String) throws -> LocalUserEntity? {
        try activeUserEntities().first(where: { $0.id == userID })
    }

    private func activePreferencesEntity(userID: String) throws -> LocalPreferencesEntity? {
        try activePreferenceEntities().first(where: { $0.userId == userID })
    }

    private func activeUsers() throws -> [User] {
        try activeUserEntities().map(mapUser)
    }

    private func activeUserEntities() throws -> [LocalUserEntity] {
        let entities = try context.fetch(FetchDescriptor<LocalUserEntity>())
            .filter { $0.deletedAt == nil }
            .sorted {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.createdAt > $1.createdAt
            }
        #if DEBUG
        if entities.count > 1 {
            print("One local persistence warning: multiple active users found. Resuming the most recently updated profile.")
        }
        #endif
        return entities
    }

    private func activePreferenceEntities() throws -> [LocalPreferencesEntity] {
        try context.fetch(FetchDescriptor<LocalPreferencesEntity>())
    }

    private func activeCategoryEntities() throws -> [LocalCategoryEntity] {
        try context.fetch(FetchDescriptor<LocalCategoryEntity>()).filter { $0.deletedAt == nil }
    }

    private func activeHabitEntities() throws -> [LocalHabitEntity] {
        try context.fetch(FetchDescriptor<LocalHabitEntity>()).filter { $0.deletedAt == nil }
    }

    private func activeTodoEntities() throws -> [LocalTodoEntity] {
        try context.fetch(FetchDescriptor<LocalTodoEntity>()).filter { $0.deletedAt == nil }
    }

    private func activeCompletionLogEntities() throws -> [LocalCompletionLogEntity] {
        try context.fetch(FetchDescriptor<LocalCompletionLogEntity>()).filter { $0.deletedAt == nil }
    }

    private func activeTodayOrderOverrideEntities() throws -> [LocalTodayOrderOverrideEntity] {
        try context.fetch(FetchDescriptor<LocalTodayOrderOverrideEntity>())
    }

    private func activeReflectionEntities() throws -> [LocalReflectionEntity] {
        try context.fetch(FetchDescriptor<LocalReflectionEntity>()).filter { $0.deletedAt == nil }
    }

    private func activeCoachCardEntities() throws -> [LocalCoachCardEntity] {
        try context.fetch(FetchDescriptor<LocalCoachCardEntity>())
    }

    private func save() throws {
        try context.save()
    }

    private func mapUser(_ entity: LocalUserEntity) -> User {
        User(
            id: entity.id,
            email: entity.email,
            appleSub: entity.appleSub,
            displayName: entity.displayName,
            timezone: OfflineDateCoding.deviceTimeZoneIdentifier,
            createdAt: entity.createdAt
        )
    }

    private func mapCategory(_ entity: LocalCategoryEntity) -> Category {
        Category(
            id: entity.id,
            userId: entity.userId,
            name: entity.name,
            icon: OneIconKey.normalizedTaskCategoryID(name: entity.name, storedIcon: entity.icon),
            color: entity.color,
            sortOrder: entity.sortOrder,
            isDefault: entity.isDefault,
            archivedAt: entity.archivedAt
        )
    }

    private func mapHabit(_ entity: LocalHabitEntity) -> Habit {
        Habit(
            id: entity.id,
            userId: entity.userId,
            categoryId: entity.categoryId,
            title: entity.title,
            notes: entity.notes,
            recurrenceRule: entity.recurrenceRule,
            startDate: entity.startDate,
            endDate: entity.endDate,
            priorityWeight: entity.priorityWeight,
            preferredTime: entity.preferredTime,
            isActive: entity.isActive
        )
    }

    private func mapTodo(_ entity: LocalTodoEntity) -> Todo {
        Todo(
            id: entity.id,
            userId: entity.userId,
            categoryId: entity.categoryId,
            title: entity.title,
            notes: entity.notes,
            dueAt: entity.dueAt,
            priority: entity.priority,
            isPinned: entity.isPinned,
            status: TodoStatus(rawValue: entity.status) ?? .open,
            completedAt: entity.completedAt,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    private func mapCompletionLog(_ entity: LocalCompletionLogEntity) -> CompletionLog {
        CompletionLog(
            id: entity.id,
            userId: entity.userId,
            itemType: ItemType(rawValue: entity.itemType) ?? .habit,
            itemId: entity.itemId,
            dateLocal: entity.dateLocal,
            state: CompletionState(rawValue: entity.state) ?? .notCompleted,
            completedAt: entity.completedAt,
            source: entity.source,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    private func mapReflection(_ entity: LocalReflectionEntity) -> ReflectionNote {
        ReflectionNote(
            id: entity.id,
            userId: entity.userId,
            periodType: PeriodType(rawValue: entity.periodType) ?? .daily,
            periodStart: entity.periodStart,
            periodEnd: entity.periodEnd,
            content: entity.content,
            sentiment: ReflectionSentiment(rawValue: entity.sentiment) ?? .okay,
            tags: (try? decode([String].self, from: entity.tagsData)) ?? [],
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    private func mapCoachCard(_ entity: LocalCoachCardEntity) -> CoachCard {
        CoachCard(
            id: entity.id,
            title: entity.title,
            body: entity.body,
            verseRef: entity.verseRef,
            verseText: entity.verseText,
            tags: (try? decode([String].self, from: entity.tagsData)) ?? [],
            locale: entity.locale,
            activeFrom: entity.activeFrom,
            activeTo: entity.activeTo,
            isActive: entity.isActive
        )
    }

    private func mapPreferences(_ entity: LocalPreferencesEntity) throws -> UserPreferences {
        UserPreferences(
            id: entity.id,
            userId: entity.userId,
            theme: Theme(rawValue: entity.theme) ?? .system,
            weekStart: entity.weekStart,
            defaultTab: entity.defaultTab,
            notificationFlags: try decode([String: Bool].self, from: entity.notificationFlagsData),
            quietHoursStart: entity.quietHoursStart,
            quietHoursEnd: entity.quietHoursEnd,
            coachEnabled: entity.coachEnabled
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    private func isoDateTime(from value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFraction.date(from: value) {
            return parsed
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
#endif
