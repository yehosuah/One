import Foundation

public enum ItemType: String, Codable, Sendable {
    case habit
    case todo
    case reflection
}

public enum CompletionState: String, Codable, Sendable {
    case completed
    case notCompleted = "not_completed"
}

public enum PeriodType: String, Codable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly
}

public enum ReflectionSentiment: String, Codable, Sendable, CaseIterable {
    case great
    case focused
    case okay
    case tired
    case stressed
}

public enum TodoStatus: String, Codable, Sendable {
    case open
    case completed
    case canceled
}

public enum Theme: String, Codable, Sendable {
    case light
    case dark
    case system
}

public enum PriorityTier: String, Codable, Sendable, CaseIterable, Hashable {
    case low
    case standard
    case high
    case urgent

    public var title: String {
        switch self {
        case .low:
            return "Low"
        case .standard:
            return "Standard"
        case .high:
            return "High"
        case .urgent:
            return "Urgent"
        }
    }

    public var helperText: String {
        switch self {
        case .low:
            return "Can wait without losing momentum."
        case .standard:
            return "Normal attention for planned work."
        case .high:
            return "Should stand out in Today."
        case .urgent:
            return "Needs attention before the rest."
        }
    }

    public var representativeValue: Int {
        switch self {
        case .low:
            return 20
        case .standard:
            return 50
        case .high:
            return 75
        case .urgent:
            return 95
        }
    }

    public static func resolve(priority: Int?, isPinned: Bool = false) -> PriorityTier {
        if isPinned {
            return .urgent
        }

        switch priority ?? 50 {
        case ..<35:
            return .low
        case 35..<65:
            return .standard
        case 65..<85:
            return .high
        default:
            return .urgent
        }
    }
}

public struct User: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let email: String
    public let appleSub: String?
    public let displayName: String
    public let timezone: String
    public let createdAt: Date?

    public init(id: String, email: String, appleSub: String? = nil, displayName: String, timezone: String, createdAt: Date? = nil) {
        self.id = id
        self.email = email
        self.appleSub = appleSub
        self.displayName = displayName
        self.timezone = timezone
        self.createdAt = createdAt
    }
}

public struct AuthSessionTokens: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date?

    public init(accessToken: String, refreshToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public struct AuthSession: Codable, Sendable, Equatable {
    public let tokens: AuthSessionTokens
    public let user: User

    public init(tokens: AuthSessionTokens, user: User) {
        self.tokens = tokens
        self.user = user
    }
}

public struct Category: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let userId: String
    public var name: String
    public let icon: String
    public let color: String
    public let sortOrder: Int
    public let isDefault: Bool
    public let archivedAt: Date?

    public init(
        id: String,
        userId: String,
        name: String,
        icon: String = OneIconKey.categoryGeneric.rawValue,
        color: String = "#5B8DEF",
        sortOrder: Int = 0,
        isDefault: Bool = false,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.icon = icon
        self.color = color
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.archivedAt = archivedAt
    }
}

public struct Habit: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let userId: String
    public let categoryId: String
    public var title: String
    public var notes: String
    public var recurrenceRule: String
    public let startDate: String
    public var endDate: String?
    public var priorityWeight: Int
    public var preferredTime: String?
    public var isActive: Bool

    public init(
        id: String,
        userId: String,
        categoryId: String,
        title: String,
        notes: String = "",
        recurrenceRule: String,
        startDate: String,
        endDate: String? = nil,
        priorityWeight: Int = 50,
        preferredTime: String? = nil,
        isActive: Bool = true
    ) {
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
    }

    public var priorityTier: PriorityTier {
        PriorityTier.resolve(priority: priorityWeight)
    }
}

public struct TodayItem: Codable, Sendable, Equatable, Identifiable {
    public let itemType: ItemType
    public let itemId: String
    public let title: String
    public let categoryId: String
    public var completed: Bool
    public let sortBucket: Int
    public let sortScore: Double
    public let subtitle: String?
    public let isPinned: Bool?
    public let priority: Int?
    public let dueAt: Date?
    public let preferredTime: String?

    public var id: String { "\(itemType.rawValue):\(itemId)" }

    public init(
        itemType: ItemType,
        itemId: String,
        title: String,
        categoryId: String,
        completed: Bool,
        sortBucket: Int,
        sortScore: Double,
        subtitle: String? = nil,
        isPinned: Bool? = nil,
        priority: Int? = nil,
        dueAt: Date? = nil,
        preferredTime: String? = nil
    ) {
        self.itemType = itemType
        self.itemId = itemId
        self.title = title
        self.categoryId = categoryId
        self.completed = completed
        self.sortBucket = sortBucket
        self.sortScore = sortScore
        self.subtitle = subtitle
        self.isPinned = isPinned
        self.priority = priority
        self.dueAt = dueAt
        self.preferredTime = preferredTime
    }

    public var priorityTier: PriorityTier {
        PriorityTier.resolve(priority: priority, isPinned: isPinned ?? false)
    }
}

public struct TodayResponse: Codable, Sendable, Equatable {
    public let dateLocal: String
    public let items: [TodayItem]
    public let completedCount: Int
    public let totalCount: Int
    public let completionRatio: Double

    public init(dateLocal: String, items: [TodayItem], completedCount: Int, totalCount: Int, completionRatio: Double) {
        self.dateLocal = dateLocal
        self.items = items
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.completionRatio = completionRatio
    }
}

public struct Todo: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let userId: String
    public let categoryId: String
    public var title: String
    public var notes: String
    public var dueAt: Date?
    public var priority: Int
    public var isPinned: Bool
    public var status: TodoStatus
    public var completedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        userId: String = "",
        categoryId: String,
        title: String,
        notes: String = "",
        dueAt: Date? = nil,
        priority: Int = 50,
        isPinned: Bool = false,
        status: TodoStatus = .open,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
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
    }

    public var priorityTier: PriorityTier {
        PriorityTier.resolve(priority: priority, isPinned: isPinned)
    }
}

public struct CompletionLog: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let userId: String
    public let itemType: ItemType
    public let itemId: String
    public let dateLocal: String
    public var state: CompletionState
    public var completedAt: Date?
    public var source: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        userId: String,
        itemType: ItemType,
        itemId: String,
        dateLocal: String,
        state: CompletionState = .notCompleted,
        completedAt: Date? = nil,
        source: String = "app",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
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
    }
}

public struct DailySummary: Codable, Sendable, Equatable {
    public let dateLocal: String
    public let completedItems: Int
    public let expectedItems: Int
    public let completionRate: Double
    public let habitCompleted: Int
    public let habitExpected: Int
    public let todoCompleted: Int
    public let todoExpected: Int

    public init(
        dateLocal: String,
        completedItems: Int,
        expectedItems: Int,
        completionRate: Double,
        habitCompleted: Int = 0,
        habitExpected: Int = 0,
        todoCompleted: Int = 0,
        todoExpected: Int = 0
    ) {
        self.dateLocal = dateLocal
        self.completedItems = completedItems
        self.expectedItems = expectedItems
        self.completionRate = completionRate
        self.habitCompleted = habitCompleted
        self.habitExpected = habitExpected
        self.todoCompleted = todoCompleted
        self.todoExpected = todoExpected
    }
}

public struct PeriodSummary: Codable, Sendable, Equatable {
    public let periodType: PeriodType
    public let periodStart: String
    public let periodEnd: String
    public let completedItems: Int
    public let expectedItems: Int
    public let completionRate: Double
    public let activeDays: Int
    public let consistencyScore: Double

    public init(
        periodType: PeriodType,
        periodStart: String,
        periodEnd: String,
        completedItems: Int,
        expectedItems: Int,
        completionRate: Double,
        activeDays: Int,
        consistencyScore: Double
    ) {
        self.periodType = periodType
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.completedItems = completedItems
        self.expectedItems = expectedItems
        self.completionRate = completionRate
        self.activeDays = activeDays
        self.consistencyScore = consistencyScore
    }
}

public struct ReflectionNote: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let userId: String
    public let periodType: PeriodType
    public let periodStart: String
    public let periodEnd: String
    public let content: String
    public let sentiment: ReflectionSentiment
    public let tags: [String]
    public let createdAt: Date?
    public let updatedAt: Date?
}

public struct ReflectionWriteInput: Codable, Sendable, Equatable {
    public let periodType: PeriodType
    public let periodStart: String
    public let periodEnd: String
    public let content: String
    public let sentiment: ReflectionSentiment
    public let tags: [String]

    public init(
        periodType: PeriodType,
        periodStart: String,
        periodEnd: String,
        content: String,
        sentiment: ReflectionSentiment,
        tags: [String] = []
    ) {
        self.periodType = periodType
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.content = content
        self.sentiment = sentiment
        self.tags = tags
    }
}

public struct TodayOrderItem: Codable, Sendable, Equatable {
    public let itemType: ItemType
    public let itemId: String
    public let orderIndex: Int

    public init(itemType: ItemType, itemId: String, orderIndex: Int) {
        self.itemType = itemType
        self.itemId = itemId
        self.orderIndex = orderIndex
    }
}

public struct HabitStats: Codable, Sendable, Equatable {
    public let habitId: String
    public let anchorDate: String
    public let windowDays: Int
    public let streakCurrent: Int
    public let completedWindow: Int
    public let expectedWindow: Int
    public let completionRateWindow: Double
    public let lastCompletedDate: String?
}

public struct UserPreferences: Codable, Sendable, Equatable {
    public let id: String
    public let userId: String
    public var theme: Theme
    public var weekStart: Int
    public var defaultTab: String
    public var notificationFlags: [String: Bool]
    public var quietHoursStart: String?
    public var quietHoursEnd: String?
    public var coachEnabled: Bool

    public init(
        id: String,
        userId: String,
        theme: Theme = .system,
        weekStart: Int = 0,
        defaultTab: String = "today",
        notificationFlags: [String: Bool],
        quietHoursStart: String? = nil,
        quietHoursEnd: String? = nil,
        coachEnabled: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.theme = theme
        self.weekStart = weekStart
        self.defaultTab = defaultTab
        self.notificationFlags = notificationFlags
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.coachEnabled = coachEnabled
    }
}

public struct CoachCard: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let verseRef: String?
    public let verseText: String?
    public let tags: [String]
    public let locale: String
    public let activeFrom: String?
    public let activeTo: String?
    public let isActive: Bool

    public init(
        id: String,
        title: String,
        body: String,
        verseRef: String? = nil,
        verseText: String? = nil,
        tags: [String] = [],
        locale: String = "en",
        activeFrom: String? = nil,
        activeTo: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.verseRef = verseRef
        self.verseText = verseText
        self.tags = tags
        self.locale = locale
        self.activeFrom = activeFrom
        self.activeTo = activeTo
        self.isActive = isActive
    }
}

public struct NotificationScheduleStatus: Codable, Sendable, Equatable {
    public let permissionGranted: Bool
    public let scheduledCount: Int
    public let lastRefreshedAt: Date?
    public let lastError: String?

    public init(
        permissionGranted: Bool,
        scheduledCount: Int,
        lastRefreshedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.permissionGranted = permissionGranted
        self.scheduledCount = scheduledCount
        self.lastRefreshedAt = lastRefreshedAt
        self.lastError = lastError
    }
}

public struct HabitCreateInput: Sendable, Equatable {
    public let categoryId: String
    public let title: String
    public let notes: String
    public let recurrenceRule: String
    public let startDate: String?
    public let endDate: String?
    public let priorityWeight: Int
    public let preferredTime: String?

    public init(
        categoryId: String,
        title: String,
        notes: String = "",
        recurrenceRule: String = "DAILY",
        startDate: String? = nil,
        endDate: String? = nil,
        priorityWeight: Int = 50,
        preferredTime: String? = nil
    ) {
        self.categoryId = categoryId
        self.title = title
        self.notes = notes
        self.recurrenceRule = recurrenceRule
        self.startDate = startDate
        self.endDate = endDate
        self.priorityWeight = priorityWeight
        self.preferredTime = preferredTime
    }
}

public struct TodoCreateInput: Sendable, Equatable {
    public let categoryId: String
    public let title: String
    public let notes: String
    public let dueAt: Date?
    public let priority: Int
    public let isPinned: Bool

    public init(
        categoryId: String,
        title: String,
        notes: String = "",
        dueAt: Date? = nil,
        priority: Int = 50,
        isPinned: Bool = false
    ) {
        self.categoryId = categoryId
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.priority = priority
        self.isPinned = isPinned
    }
}

public struct HabitUpdateInput: Codable, Sendable, Equatable {
    public var categoryId: String?
    public var title: String?
    public var notes: String?
    public var recurrenceRule: String?
    public var endDate: String?
    public var clearEndDate: Bool
    public var priorityWeight: Int?
    public var preferredTime: String?
    public var clearPreferredTime: Bool
    public var isActive: Bool?

    public init(
        categoryId: String? = nil,
        title: String? = nil,
        notes: String? = nil,
        recurrenceRule: String? = nil,
        endDate: String? = nil,
        clearEndDate: Bool = false,
        priorityWeight: Int? = nil,
        preferredTime: String? = nil,
        clearPreferredTime: Bool = false,
        isActive: Bool? = nil
    ) {
        self.categoryId = categoryId
        self.title = title
        self.notes = notes
        self.recurrenceRule = recurrenceRule
        self.endDate = endDate
        self.clearEndDate = clearEndDate
        self.priorityWeight = priorityWeight
        self.preferredTime = preferredTime
        self.clearPreferredTime = clearPreferredTime
        self.isActive = isActive
    }
}

public struct TodoUpdateInput: Codable, Sendable, Equatable {
    public var categoryId: String?
    public var title: String?
    public var notes: String?
    public var dueAt: Date?
    public var clearDueAt: Bool
    public var priority: Int?
    public var isPinned: Bool?
    public var status: TodoStatus?

    public init(
        categoryId: String? = nil,
        title: String? = nil,
        notes: String? = nil,
        dueAt: Date? = nil,
        clearDueAt: Bool = false,
        priority: Int? = nil,
        isPinned: Bool? = nil,
        status: TodoStatus? = nil
    ) {
        self.categoryId = categoryId
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.clearDueAt = clearDueAt
        self.priority = priority
        self.isPinned = isPinned
        self.status = status
    }
}

public struct UserPreferencesUpdateInput: Sendable, Equatable {
    public var theme: Theme?
    public var weekStart: Int?
    public var defaultTab: String?
    public var quietHoursStart: String?
    public var quietHoursEnd: String?
    public var notificationFlags: [String: Bool]?
    public var coachEnabled: Bool?

    public init(
        theme: Theme? = nil,
        weekStart: Int? = nil,
        defaultTab: String? = nil,
        quietHoursStart: String? = nil,
        quietHoursEnd: String? = nil,
        notificationFlags: [String: Bool]? = nil,
        coachEnabled: Bool? = nil
    ) {
        self.theme = theme
        self.weekStart = weekStart
        self.defaultTab = defaultTab
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.notificationFlags = notificationFlags
        self.coachEnabled = coachEnabled
    }
}

public struct UserProfileUpdateInput: Sendable, Equatable {
    public var displayName: String?
    public var timezone: String?

    public init(displayName: String? = nil, timezone: String? = nil) {
        self.displayName = displayName
        self.timezone = timezone
    }
}
