import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

public enum APIError: Error, Sendable {
    case unauthorized
    case transport(String)
    case decoding(String)
    case conflict
    case server(statusCode: Int, message: String)
}

public protocol APIClient: Sendable {
    func currentSession() async -> AuthSessionTokens?
    func clearSession() async

    func login(email: String, password: String) async throws -> AuthSession
    func signup(email: String, password: String, displayName: String, timezone: String) async throws -> AuthSession
    func fetchMe() async throws -> User

    func fetchCategories() async throws -> [Category]
    func fetchHabits() async throws -> [Habit]
    func fetchTodos() async throws -> [Todo]
    func fetchCoachCards() async throws -> [CoachCard]
    func createHabit(input: HabitCreateInput) async throws -> Habit
    func createTodo(input: TodoCreateInput) async throws -> Todo
    func fetchToday(date: String?) async throws -> TodayResponse
    func putTodayOrder(dateLocal: String, items: [TodayOrderItem]) async throws -> TodayResponse

    func updateCompletion(itemType: ItemType, itemId: String, dateLocal: String, state: CompletionState) async throws

    func fetchDaily(startDate: String, endDate: String) async throws -> [DailySummary]
    func fetchPeriod(anchorDate: String, periodType: PeriodType) async throws -> PeriodSummary
    func fetchHabitStats(habitId: String, anchorDate: String?, windowDays: Int?) async throws -> HabitStats
    func fetchReflections(periodType: PeriodType?) async throws -> [ReflectionNote]
    func upsertReflection(input: ReflectionWriteInput) async throws -> ReflectionNote
    func deleteReflection(id: String) async throws

    func fetchPreferences() async throws -> UserPreferences
    func patchPreferences(input: UserPreferencesUpdateInput) async throws -> UserPreferences
    func patchUser(input: UserProfileUpdateInput) async throws -> User
    func patchHabit(id: String, input: HabitUpdateInput, clientUpdatedAt: Date?) async throws -> Habit
    func patchTodo(id: String, fields: [String: String], clientUpdatedAt: Date?) async throws -> Todo
    func patchTodo(id: String, input: TodoUpdateInput, clientUpdatedAt: Date?) async throws -> Todo
    func deleteHabit(id: String) async throws
    func deleteTodo(id: String) async throws
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Non-HTTP response")
        }
        return (data, http)
    }
}

public protocol AuthSessionStore: Sendable {
    func read() async -> AuthSessionTokens?
    func write(_ session: AuthSessionTokens) async throws
    func clear() async
    func isRecoverySuppressed() async -> Bool
    func setRecoverySuppressed(_ suppressed: Bool) async
}

public actor InMemoryAuthSessionStore: AuthSessionStore {
    private var session: AuthSessionTokens?
    private var recoverySuppressed = false

    public init(session: AuthSessionTokens? = nil) {
        self.session = session
    }

    public func read() async -> AuthSessionTokens? {
        session
    }

    public func write(_ session: AuthSessionTokens) async throws {
        self.session = session
        recoverySuppressed = false
    }

    public func clear() async {
        session = nil
    }

    public func isRecoverySuppressed() async -> Bool {
        recoverySuppressed
    }

    public func setRecoverySuppressed(_ suppressed: Bool) async {
        recoverySuppressed = suppressed
    }
}

#if canImport(Security)
public actor KeychainAuthSessionStore: AuthSessionStore {
    private let service: String
    private let account: String
    private let defaults: UserDefaults

    public init(
        service: String = "one.app.auth",
        account: String = "default",
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.account = account
        self.defaults = defaults
    }

    public func read() async -> AuthSessionTokens? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var output: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &output)
        guard status == errSecSuccess else {
            return nil
        }
        guard let data = output as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(AuthSessionTokens.self, from: data)
    }

    public func write(_ session: AuthSessionTokens) async throws {
        let data = try JSONEncoder().encode(session)
        var query = baseQuery()
        query[kSecValueData as String] = data

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess {
            defaults.set(false, forKey: recoverySuppressedKey)
            return
        }
        if addStatus == errSecDuplicateItem {
            let attrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attrs as CFDictionary)
            if updateStatus == errSecSuccess {
                defaults.set(false, forKey: recoverySuppressedKey)
                return
            }
            throw APIError.transport("Keychain update failed: \(updateStatus)")
        }
        throw APIError.transport("Keychain write failed: \(addStatus)")
    }

    public func clear() async {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    public func isRecoverySuppressed() async -> Bool {
        defaults.bool(forKey: recoverySuppressedKey)
    }

    public func setRecoverySuppressed(_ suppressed: Bool) async {
        defaults.set(suppressed, forKey: recoverySuppressedKey)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private var recoverySuppressedKey: String {
        "one.auth.recovery_suppressed.\(service).\(account)"
    }
}
#endif

public actor HTTPAPIClient: APIClient {
    private let baseURLProvider: @Sendable () -> URL
    private let transport: HTTPTransport
    private let sessionStore: AuthSessionStore

    public init(baseURL: URL, transport: HTTPTransport = URLSessionHTTPTransport(), sessionStore: AuthSessionStore) {
        self.baseURLProvider = { baseURL }
        self.transport = transport
        self.sessionStore = sessionStore
    }

    public init(
        baseURLProvider: @escaping @Sendable () -> URL,
        transport: HTTPTransport = URLSessionHTTPTransport(),
        sessionStore: AuthSessionStore
    ) {
        self.baseURLProvider = baseURLProvider
        self.transport = transport
        self.sessionStore = sessionStore
    }

    public func currentSession() async -> AuthSessionTokens? {
        await sessionStore.read()
    }

    public func clearSession() async {
        await sessionStore.setRecoverySuppressed(true)
        await sessionStore.clear()
    }

    public func login(email: String, password: String) async throws -> AuthSession {
        let body = WireEmailLoginRequest(email: email, password: password)
        let data = try await send(path: "/auth/login", method: "POST", body: body, authorized: false)
        let wire: WireAuthSession = try decode(data)
        let session = map(wire)
        try await sessionStore.write(session.tokens)
        return session
    }

    public func signup(email: String, password: String, displayName: String, timezone: String) async throws -> AuthSession {
        let body = WireEmailSignupRequest(
            email: email,
            password: password,
            displayName: displayName,
            timezone: timezone
        )
        let data = try await send(path: "/auth/signup", method: "POST", body: body, authorized: false)
        let wire: WireAuthSession = try decode(data)
        let session = map(wire)
        try await sessionStore.write(session.tokens)
        return session
    }

    public func fetchMe() async throws -> User {
        let data = try await send(path: "/users/me", method: "GET")
        let wire: WireUser = try decode(data)
        return map(wire)
    }

    public func fetchCategories() async throws -> [Category] {
        let data = try await send(path: "/categories", method: "GET")
        let wire: [WireCategory] = try decode(data)
        return wire.map(map)
    }

    public func fetchHabits() async throws -> [Habit] {
        let data = try await send(path: "/habits", method: "GET")
        let wire: [WireHabit] = try decode(data)
        return wire.map(map)
    }

    public func fetchTodos() async throws -> [Todo] {
        let data = try await send(path: "/todos", method: "GET")
        let wire: [WireTodo] = try decode(data)
        return wire.map(map)
    }

    public func fetchCoachCards() async throws -> [CoachCard] {
        let data = try await send(path: "/coach-cards", method: "GET")
        let wire: [WireCoachCard] = try decode(data)
        return wire.map(map)
    }

    public func createHabit(input: HabitCreateInput) async throws -> Habit {
        let body = WireHabitCreateRequest(
            categoryId: input.categoryId,
            title: input.title,
            notes: input.notes,
            recurrenceRule: input.recurrenceRule,
            startDate: input.startDate,
            endDate: input.endDate,
            priorityWeight: input.priorityWeight,
            preferredTime: input.preferredTime
        )
        let data = try await send(path: "/habits", method: "POST", body: body)
        let wire: WireHabit = try decode(data)
        return map(wire)
    }

    public func createTodo(input: TodoCreateInput) async throws -> Todo {
        let body = WireTodoCreateRequest(
            categoryId: input.categoryId,
            title: input.title,
            notes: input.notes,
            dueAt: input.dueAt.map(Self.encodeDateTime),
            priority: input.priority,
            isPinned: input.isPinned
        )
        let data = try await send(path: "/todos", method: "POST", body: body)
        let wire: WireTodo = try decode(data)
        return map(wire)
    }

    public func fetchToday(date: String?) async throws -> TodayResponse {
        var query: [URLQueryItem] = []
        if let date, !date.isEmpty {
            query.append(URLQueryItem(name: "date", value: date))
        }
        let data = try await send(path: "/today", method: "GET", query: query)
        let wire: WireTodayResponse = try decode(data)
        return map(wire)
    }

    public func putTodayOrder(dateLocal: String, items: [TodayOrderItem]) async throws -> TodayResponse {
        let body = WireTodayOrderWriteRequest(
            dateLocal: dateLocal,
            items: items.map {
                WireTodayOrderItemRequest(
                    itemType: $0.itemType.rawValue,
                    itemId: $0.itemId,
                    orderIndex: $0.orderIndex
                )
            }
        )
        let data = try await send(path: "/today/order", method: "PUT", body: body)
        let wire: WireTodayResponse = try decode(data)
        return map(wire)
    }

    public func updateCompletion(itemType: ItemType, itemId: String, dateLocal: String, state: CompletionState) async throws {
        let body = WireCompletionWriteRequest(
            itemType: itemType.rawValue,
            itemId: itemId,
            dateLocal: dateLocal,
            state: state.rawValue,
            source: "ios"
        )
        _ = try await send(path: "/completions", method: "POST", body: body)
    }

    public func fetchDaily(startDate: String, endDate: String) async throws -> [DailySummary] {
        let query = [
            URLQueryItem(name: "start_date", value: startDate),
            URLQueryItem(name: "end_date", value: endDate),
        ]
        let data = try await send(path: "/analytics/daily", method: "GET", query: query)
        let wire: [WireDailySummary] = try decode(data)
        return wire.map(map)
    }

    public func fetchPeriod(anchorDate: String, periodType: PeriodType) async throws -> PeriodSummary {
        let query = [
            URLQueryItem(name: "anchor_date", value: anchorDate),
            URLQueryItem(name: "period_type", value: periodType.rawValue),
        ]
        let data = try await send(path: "/analytics/period", method: "GET", query: query)
        let wire: WirePeriodSummary = try decode(data)
        return map(wire)
    }

    public func fetchHabitStats(habitId: String, anchorDate: String?, windowDays: Int?) async throws -> HabitStats {
        var query: [URLQueryItem] = []
        if let anchorDate, !anchorDate.isEmpty {
            query.append(URLQueryItem(name: "anchor_date", value: anchorDate))
        }
        if let windowDays {
            query.append(URLQueryItem(name: "window_days", value: String(windowDays)))
        }
        let data = try await send(path: "/habits/\(habitId)/stats", method: "GET", query: query)
        let wire: WireHabitStats = try decode(data)
        return map(wire)
    }

    public func fetchReflections(periodType: PeriodType?) async throws -> [ReflectionNote] {
        var query: [URLQueryItem] = []
        if let periodType {
            query.append(URLQueryItem(name: "period_type", value: periodType.rawValue))
        }
        let data = try await send(path: "/reflections", method: "GET", query: query)
        let wire: [WireReflectionNote] = try decode(data)
        return wire.map(map)
    }

    public func upsertReflection(input: ReflectionWriteInput) async throws -> ReflectionNote {
        let body = WireReflectionWriteRequest(
            periodType: input.periodType.rawValue,
            periodStart: input.periodStart,
            periodEnd: input.periodEnd,
            content: input.content,
            sentiment: input.sentiment.rawValue,
            tags: input.tags
        )
        let data = try await send(path: "/reflections", method: "POST", body: body)
        let wire: WireReflectionNote = try decode(data)
        return map(wire)
    }

    public func deleteReflection(id: String) async throws {
        _ = try await send(path: "/reflections/\(id)", method: "DELETE")
    }

    public func fetchPreferences() async throws -> UserPreferences {
        let data = try await send(path: "/preferences", method: "GET")
        let wire: WireUserPreferences = try decode(data)
        return map(wire)
    }

    public func patchPreferences(input: UserPreferencesUpdateInput) async throws -> UserPreferences {
        let body = WireUserPreferencesPatchRequest(
            theme: input.theme?.rawValue,
            weekStart: input.weekStart,
            defaultTab: input.defaultTab,
            quietHoursStart: input.quietHoursStart,
            quietHoursEnd: input.quietHoursEnd,
            notificationFlags: input.notificationFlags,
            coachEnabled: input.coachEnabled
        )
        let data = try await send(path: "/preferences", method: "PATCH", body: body)
        let wire: WireUserPreferences = try decode(data)
        return map(wire)
    }

    public func patchUser(input: UserProfileUpdateInput) async throws -> User {
        let body = WireUserPatchRequest(displayName: input.displayName, timezone: input.timezone)
        let data = try await send(path: "/users/me", method: "PATCH", body: body)
        let wire: WireUser = try decode(data)
        return map(wire)
    }

    public func patchHabit(id: String, input: HabitUpdateInput, clientUpdatedAt: Date?) async throws -> Habit {
        let path = "/habits/\(id)"
        let headers = ["x-client-updated-at": clientUpdatedAt.map(Self.encodeDateTime) ?? ""]
        let body = WireHabitUpdateRequest(
            categoryId: input.categoryId,
            title: input.title,
            notes: input.notes,
            recurrenceRule: input.recurrenceRule,
            endDate: input.endDate,
            clearEndDate: input.clearEndDate,
            priorityWeight: input.priorityWeight,
            preferredTime: input.preferredTime,
            clearPreferredTime: input.clearPreferredTime,
            isActive: input.isActive
        )
        let data = try await send(path: path, method: "PATCH", body: body, extraHeaders: headers)
        let wire: WireHabit = try decode(data)
        return map(wire)
    }

    public func patchTodo(id: String, fields: [String: String], clientUpdatedAt: Date?) async throws -> Todo {
        let path = "/todos/\(id)"
        let headers = ["x-client-updated-at": clientUpdatedAt.map(Self.encodeDateTime) ?? ""]
        let data = try await send(path: path, method: "PATCH", body: fields, extraHeaders: headers)
        let wire: WireTodo = try decode(data)
        return map(wire)
    }

    public func patchTodo(id: String, input: TodoUpdateInput, clientUpdatedAt: Date?) async throws -> Todo {
        let path = "/todos/\(id)"
        let headers = ["x-client-updated-at": clientUpdatedAt.map(Self.encodeDateTime) ?? ""]
        let body = WireTodoUpdateRequest(
            categoryId: input.categoryId,
            title: input.title,
            notes: input.notes,
            dueAt: input.dueAt.map(Self.encodeDateTime),
            clearDueAt: input.clearDueAt,
            priority: input.priority,
            isPinned: input.isPinned,
            status: input.status?.rawValue
        )
        let data = try await send(path: path, method: "PATCH", body: body, extraHeaders: headers)
        let wire: WireTodo = try decode(data)
        return map(wire)
    }

    public func deleteHabit(id: String) async throws {
        _ = try await send(path: "/habits/\(id)", method: "DELETE")
    }

    public func deleteTodo(id: String) async throws {
        _ = try await send(path: "/todos/\(id)", method: "DELETE")
    }

    private func send<Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        query: [URLQueryItem] = [],
        authorized: Bool = true,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        let payload: Data
        do {
            payload = try JSONEncoder().encode(body)
        } catch {
            throw APIError.transport("Failed to encode request: \(error)")
        }
        return try await send(path: path, method: method, bodyData: payload, query: query, authorized: authorized, extraHeaders: extraHeaders)
    }

    private func send(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        authorized: Bool = true
    ) async throws -> Data {
        try await send(path: path, method: method, bodyData: nil, query: query, authorized: authorized, extraHeaders: [:])
    }

    private func send(
        path: String,
        method: String,
        bodyData: Data?,
        query: [URLQueryItem],
        authorized: Bool,
        extraHeaders: [String: String]
    ) async throws -> Data {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            request.httpBody = bodyData
        }

        for (key, value) in extraHeaders where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if authorized {
            guard let session = await sessionStore.read() else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(String(describing: error))
        }

        switch response.statusCode {
        case 200...299:
            return data
        case 401:
            await sessionStore.clear()
            throw APIError.unauthorized
        case 409:
            throw APIError.conflict
        default:
            throw APIError.server(statusCode: response.statusCode, message: errorMessage(from: data))
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        let baseURL = baseURLProvider()
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.transport("Invalid base URL")
        }
        let prefix = comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path
        comps.path = "\(prefix)\(path)"
        if !query.isEmpty {
            comps.queryItems = query
        }
        guard let url = comps.url else {
            throw APIError.transport("Failed to build URL")
        }
        return url
    }

    private func map(_ wire: WireAuthSession) -> AuthSession {
        let user = map(wire.user)
        let expiresAt = Date().addingTimeInterval(TimeInterval(wire.expiresIn))
        let tokens = AuthSessionTokens(
            accessToken: wire.accessToken,
            refreshToken: wire.refreshToken,
            expiresAt: expiresAt
        )
        return AuthSession(tokens: tokens, user: user)
    }

    private func map(_ wire: WireUser) -> User {
        User(
            id: wire.id,
            email: wire.email,
            appleSub: wire.appleSub,
            displayName: wire.displayName,
            timezone: wire.timezone,
            createdAt: Self.parseDateTime(wire.createdAt)
        )
    }

    private func map(_ wire: WireCategory) -> Category {
        Category(
            id: wire.id,
            userId: wire.userId,
            name: wire.name,
            icon: OneIconKey.normalizedTaskCategoryID(name: wire.name, storedIcon: wire.icon),
            color: wire.color,
            sortOrder: wire.sortOrder,
            isDefault: wire.isDefault,
            archivedAt: Self.parseDateTime(wire.archivedAt)
        )
    }

    private func map(_ wire: WireHabit) -> Habit {
        Habit(
            id: wire.id,
            userId: wire.userId,
            categoryId: wire.categoryId,
            title: wire.title,
            notes: wire.notes,
            recurrenceRule: wire.recurrenceRule,
            startDate: wire.startDate,
            endDate: wire.endDate,
            priorityWeight: wire.priorityWeight,
            preferredTime: wire.preferredTime,
            isActive: wire.isActive
        )
    }

    private func map(_ wire: WireTodo) -> Todo {
        Todo(
            id: wire.id,
            userId: wire.userId,
            categoryId: wire.categoryId,
            title: wire.title,
            notes: wire.notes,
            dueAt: Self.parseDateTime(wire.dueAt),
            priority: wire.priority,
            isPinned: wire.isPinned,
            status: TodoStatus(rawValue: wire.status) ?? .open,
            completedAt: Self.parseDateTime(wire.completedAt),
            createdAt: Self.parseDateTime(wire.createdAt) ?? Date(),
            updatedAt: Self.parseDateTime(wire.updatedAt) ?? Date()
        )
    }

    private func map(_ wire: WireTodayResponse) -> TodayResponse {
        TodayResponse(
            dateLocal: wire.dateLocal,
            items: wire.items.map {
                TodayItem(
                    itemType: ItemType(rawValue: $0.itemType) ?? .habit,
                    itemId: $0.itemId,
                    title: $0.title,
                    categoryId: $0.categoryId,
                    completed: $0.completed,
                    sortBucket: $0.sortBucket,
                    sortScore: $0.sortScore,
                    subtitle: $0.subtitle,
                    isPinned: $0.isPinned,
                    priority: $0.priority,
                    dueAt: Self.parseDateTime($0.dueAt),
                    preferredTime: $0.preferredTime
                )
            },
            completedCount: wire.completedCount,
            totalCount: wire.totalCount,
            completionRatio: wire.completionRatio
        )
    }

    private func map(_ wire: WireReflectionNote) -> ReflectionNote {
        ReflectionNote(
            id: wire.id,
            userId: wire.userId,
            periodType: PeriodType(rawValue: wire.periodType) ?? .daily,
            periodStart: wire.periodStart,
            periodEnd: wire.periodEnd,
            content: wire.content,
            sentiment: ReflectionSentiment(rawValue: wire.sentiment) ?? .okay,
            tags: wire.tags,
            createdAt: Self.parseDateTime(wire.createdAt),
            updatedAt: Self.parseDateTime(wire.updatedAt)
        )
    }

    private func map(_ wire: WireHabitStats) -> HabitStats {
        HabitStats(
            habitId: wire.habitId,
            anchorDate: wire.anchorDate,
            windowDays: wire.windowDays,
            streakCurrent: wire.streakCurrent,
            completedWindow: wire.completedWindow,
            expectedWindow: wire.expectedWindow,
            completionRateWindow: wire.completionRateWindow,
            lastCompletedDate: wire.lastCompletedDate
        )
    }

    private func map(_ wire: WireDailySummary) -> DailySummary {
        DailySummary(
            dateLocal: wire.dateLocal,
            completedItems: wire.completedItems,
            expectedItems: wire.expectedItems,
            completionRate: wire.completionRate,
            habitCompleted: wire.habitCompleted,
            habitExpected: wire.habitExpected,
            todoCompleted: wire.todoCompleted,
            todoExpected: wire.todoExpected
        )
    }

    private func map(_ wire: WirePeriodSummary) -> PeriodSummary {
        PeriodSummary(
            periodType: PeriodType(rawValue: wire.periodType) ?? .weekly,
            periodStart: wire.periodStart,
            periodEnd: wire.periodEnd,
            completedItems: wire.completedItems,
            expectedItems: wire.expectedItems,
            completionRate: wire.completionRate,
            activeDays: wire.activeDays,
            consistencyScore: wire.consistencyScore
        )
    }

    private func map(_ wire: WireUserPreferences) -> UserPreferences {
        UserPreferences(
            id: wire.id,
            userId: wire.userId,
            theme: Theme(rawValue: wire.theme) ?? .system,
            weekStart: wire.weekStart,
            defaultTab: wire.defaultTab,
            notificationFlags: wire.notificationFlags,
            quietHoursStart: wire.quietHoursStart,
            quietHoursEnd: wire.quietHoursEnd,
            coachEnabled: wire.coachEnabled
        )
    }

    private func map(_ wire: WireCoachCard) -> CoachCard {
        CoachCard(
            id: wire.id,
            title: wire.title,
            body: wire.body,
            verseRef: wire.verseRef,
            verseText: wire.verseText,
            tags: wire.tags,
            locale: wire.locale,
            activeFrom: wire.activeFrom,
            activeTo: wire.activeTo,
            isActive: wire.isActive
        )
    }

    private static func parseDateTime(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFraction.date(from: value) {
            return parsed
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private static func encodeDateTime(_ date: Date) -> String {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.string(from: date)
    }

    private func errorMessage(from data: Data) -> String {
        guard !data.isEmpty else {
            return "Unknown error"
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = json["detail"] as? String {
            return detail
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
}

public actor MockAPIClient: APIClient {
    private var todayResponse: TodayResponse
    private var preferences: UserPreferences
    private var habits: [Habit]
    private var todos: [String: Todo]
    private var categories: [Category]
    private var coachCards: [CoachCard]
    private var reflections: [ReflectionNote]
    private var session: AuthSessionTokens?
    private var user: User?

    public init() {
        self.todayResponse = TodayResponse(
            dateLocal: "2026-03-12",
            items: [],
            completedCount: 0,
            totalCount: 0,
            completionRatio: 0
        )
        self.preferences = UserPreferences(
            id: "p1",
            userId: "u1",
            notificationFlags: [
                "habit_reminders": true,
                "todo_reminders": true,
                "reflection_prompts": true,
                "weekly_summary": true,
            ]
        )
        self.habits = []
        self.todos = [:]
        self.categories = [
            Category(id: "c1", userId: "u1", name: "Gym", icon: OneIconKey.categoryGym.rawValue, sortOrder: 0, isDefault: true),
            Category(id: "c2", userId: "u1", name: "School", icon: OneIconKey.categorySchool.rawValue, sortOrder: 1, isDefault: true),
            Category(id: "c3", userId: "u1", name: "Personal Projects", icon: OneIconKey.categoryProjects.rawValue, sortOrder: 2, isDefault: true),
            Category(id: "c4", userId: "u1", name: "Wellbeing", icon: OneIconKey.categoryWellbeing.rawValue, sortOrder: 3, isDefault: true),
            Category(id: "c5", userId: "u1", name: "Life Admin", icon: OneIconKey.categoryLifeAdmin.rawValue, sortOrder: 4, isDefault: true),
        ]
        self.coachCards = [
            CoachCard(
                id: "coach-1",
                title: "Stay Consistent",
                body: "A little progress each day compounds over time.",
                verseRef: "Galatians 6:9",
                verseText: "Let us not become weary in doing good, for at the proper time we will reap a harvest if we do not give up."
            ),
            CoachCard(
                id: "coach-2",
                title: "Focus One Thing",
                body: "Pick one high-value action before distractions.",
                verseRef: "Proverbs 16:3",
                verseText: "Commit to the Lord whatever you do, and he will establish your plans."
            ),
            CoachCard(
                id: "coach-3",
                title: "Reset Cleanly",
                body: "Misses are not the story unless you keep carrying them. Restart at the next honest action.",
                verseRef: "Proverbs 24:16",
                verseText: "For a just man falleth seven times, and riseth up again."
            ),
            CoachCard(
                id: "coach-4",
                title: "Work From Calm",
                body: "Noise creates fake urgency. Protect the next clear step and let the rest wait its turn.",
                verseRef: "2 Timothy 1:7",
                verseText: "For God hath not given us the spirit of fear; but of power, and of love, and of a sound mind."
            ),
        ]
        self.reflections = []
    }

    public func setTodayResponse(_ response: TodayResponse) {
        self.todayResponse = response
    }

    public func setTodos(_ value: [String: Todo]) {
        self.todos = value
    }

    public func currentSession() async -> AuthSessionTokens? {
        session
    }

    public func clearSession() async {
        session = nil
        user = nil
    }

    public func login(email: String, password: String) async throws -> AuthSession {
        let now = Date()
        let tokens = AuthSessionTokens(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(3600)
        )
        let signedIn = User(id: "u1", email: email, displayName: "User", timezone: "America/Guatemala", createdAt: now)
        session = tokens
        user = signedIn
        return AuthSession(tokens: tokens, user: signedIn)
    }

    public func signup(email: String, password: String, displayName: String, timezone: String) async throws -> AuthSession {
        let now = Date()
        let tokens = AuthSessionTokens(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(3600)
        )
        let signedIn = User(id: "u1", email: email, displayName: displayName, timezone: timezone, createdAt: now)
        session = tokens
        user = signedIn
        return AuthSession(tokens: tokens, user: signedIn)
    }

    public func fetchMe() async throws -> User {
        guard let user else {
            throw APIError.unauthorized
        }
        return user
    }

    public func fetchCategories() async throws -> [Category] {
        categories
    }

    public func fetchHabits() async throws -> [Habit] {
        habits
    }

    public func fetchTodos() async throws -> [Todo] {
        Array(todos.values)
    }

    public func fetchCoachCards() async throws -> [CoachCard] {
        coachCards
    }

    public func createHabit(input: HabitCreateInput) async throws -> Habit {
        let habit = Habit(
            id: UUID().uuidString,
            userId: "u1",
            categoryId: input.categoryId,
            title: input.title,
            notes: input.notes,
            recurrenceRule: input.recurrenceRule,
            startDate: input.startDate ?? "2026-03-12",
            endDate: input.endDate,
            priorityWeight: input.priorityWeight,
            preferredTime: input.preferredTime,
            isActive: true
        )
        habits.append(habit)
        return habit
    }

    public func createTodo(input: TodoCreateInput) async throws -> Todo {
        let todo = Todo(
            id: UUID().uuidString,
            userId: "u1",
            categoryId: input.categoryId,
            title: input.title,
            notes: input.notes,
            dueAt: input.dueAt,
            priority: input.priority,
            isPinned: input.isPinned,
            status: .open
        )
        todos[todo.id] = todo
        return todo
    }

    public func fetchToday(date: String?) async throws -> TodayResponse {
        todayResponse
    }

    public func putTodayOrder(dateLocal: String, items: [TodayOrderItem]) async throws -> TodayResponse {
        var ordered: [TodayItem] = []
        var seen: Set<String> = []
        let lookup = Dictionary(uniqueKeysWithValues: todayResponse.items.map { ($0.id, $0) })

        for entry in items.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            let key = "\(entry.itemType.rawValue):\(entry.itemId)"
            guard let item = lookup[key] else {
                continue
            }
            ordered.append(item)
            seen.insert(key)
        }

        ordered.append(contentsOf: todayResponse.items.filter { !seen.contains($0.id) })
        let completed = ordered.filter(\.completed).count
        todayResponse = TodayResponse(
            dateLocal: dateLocal,
            items: ordered,
            completedCount: completed,
            totalCount: ordered.count,
            completionRatio: ordered.isEmpty ? 0 : Double(completed) / Double(ordered.count)
        )
        return todayResponse
    }

    public func updateCompletion(itemType: ItemType, itemId: String, dateLocal: String, state: CompletionState) async throws {
        var mutable = todayResponse.items
        if let idx = mutable.firstIndex(where: { $0.itemType == itemType && $0.itemId == itemId }) {
            mutable[idx].completed = (state == .completed)
        }
        let completed = mutable.filter { $0.completed }.count
        todayResponse = TodayResponse(
            dateLocal: dateLocal,
            items: mutable,
            completedCount: completed,
            totalCount: mutable.count,
            completionRatio: mutable.isEmpty ? 0 : Double(completed) / Double(mutable.count)
        )
    }

    public func fetchDaily(startDate: String, endDate: String) async throws -> [DailySummary] {
        [DailySummary(dateLocal: startDate, completedItems: 3, expectedItems: 4, completionRate: 0.75, habitCompleted: 2, habitExpected: 3, todoCompleted: 1, todoExpected: 1)]
    }

    public func fetchPeriod(anchorDate: String, periodType: PeriodType) async throws -> PeriodSummary {
        PeriodSummary(periodType: periodType, periodStart: anchorDate, periodEnd: anchorDate, completedItems: 10, expectedItems: 12, completionRate: 0.833, activeDays: 6, consistencyScore: 0.81)
    }

    public func fetchHabitStats(habitId: String, anchorDate: String?, windowDays: Int?) async throws -> HabitStats {
        HabitStats(
            habitId: habitId,
            anchorDate: anchorDate ?? "2026-03-12",
            windowDays: windowDays ?? 30,
            streakCurrent: 5,
            completedWindow: 18,
            expectedWindow: 30,
            completionRateWindow: 0.6,
            lastCompletedDate: "2026-03-11"
        )
    }

    public func fetchReflections(periodType: PeriodType?) async throws -> [ReflectionNote] {
        if let periodType {
            return reflections.filter { $0.periodType == periodType }
        }
        return reflections
    }

    public func upsertReflection(input: ReflectionWriteInput) async throws -> ReflectionNote {
        let note = ReflectionNote(
            id: UUID().uuidString,
            userId: "u1",
            periodType: input.periodType,
            periodStart: input.periodStart,
            periodEnd: input.periodEnd,
            content: input.content,
            sentiment: input.sentiment,
            tags: input.tags,
            createdAt: Date(),
            updatedAt: Date()
        )
        reflections.append(note)
        return note
    }

    public func deleteReflection(id: String) async throws {
        reflections.removeAll { $0.id == id }
    }

    public func fetchPreferences() async throws -> UserPreferences {
        preferences
    }

    public func patchPreferences(input: UserPreferencesUpdateInput) async throws -> UserPreferences {
        if let theme = input.theme {
            preferences.theme = theme
        }
        if let weekStart = input.weekStart {
            preferences.weekStart = weekStart
        }
        if let defaultTab = input.defaultTab {
            preferences.defaultTab = defaultTab
        }
        if let quietHoursStart = input.quietHoursStart {
            preferences.quietHoursStart = quietHoursStart
        }
        if let quietHoursEnd = input.quietHoursEnd {
            preferences.quietHoursEnd = quietHoursEnd
        }
        if let notificationFlags = input.notificationFlags {
            preferences.notificationFlags = notificationFlags
        }
        if let coachEnabled = input.coachEnabled {
            preferences.coachEnabled = coachEnabled
        }
        return preferences
    }

    public func patchUser(input: UserProfileUpdateInput) async throws -> User {
        guard var current = user else {
            throw APIError.unauthorized
        }
        if let displayName = input.displayName {
            current = User(
                id: current.id,
                email: current.email,
                appleSub: current.appleSub,
                displayName: displayName,
                timezone: current.timezone,
                createdAt: current.createdAt
            )
        }
        if let timezone = input.timezone {
            current = User(
                id: current.id,
                email: current.email,
                appleSub: current.appleSub,
                displayName: current.displayName,
                timezone: timezone,
                createdAt: current.createdAt
            )
        }
        user = current
        return current
    }

    public func patchTodo(id: String, fields: [String: String], clientUpdatedAt: Date?) async throws -> Todo {
        var todo = todos[id] ?? Todo(id: id, userId: "u1", categoryId: "c1", title: "task")
        if let clientUpdatedAt, clientUpdatedAt < todo.updatedAt {
            return todo
        }
        if let categoryId = fields["category_id"] {
            todo = Todo(
                id: todo.id,
                userId: todo.userId,
                categoryId: categoryId,
                title: todo.title,
                notes: todo.notes,
                dueAt: todo.dueAt,
                priority: todo.priority,
                isPinned: todo.isPinned,
                status: todo.status,
                completedAt: todo.completedAt,
                createdAt: todo.createdAt,
                updatedAt: todo.updatedAt
            )
        }
        if let title = fields["title"] {
            todo.title = title
        }
        if let notes = fields["notes"] {
            todo.notes = notes
        }
        if let priority = fields["priority"], let parsed = Int(priority) {
            todo.priority = parsed
        }
        if let isPinned = fields["is_pinned"] {
            todo.isPinned = (isPinned as NSString).boolValue
        }
        if let dueAt = fields["due_at"] {
            todo.dueAt = Self.parseDateTime(dueAt)
        }
        if let statusRaw = fields["status"], let status = TodoStatus(rawValue: statusRaw) {
            todo.status = status
            todo.completedAt = status == .completed ? Date() : nil
        }
        todo.updatedAt = Date()
        todos[id] = todo
        return todo
    }

    public func patchHabit(id: String, input: HabitUpdateInput, clientUpdatedAt: Date?) async throws -> Habit {
        guard let index = habits.firstIndex(where: { $0.id == id }) else {
            throw APIError.server(statusCode: 404, message: "Habit not found")
        }
        var habit = habits[index]
        if let categoryId = input.categoryId { habit = Habit(
            id: habit.id,
            userId: habit.userId,
            categoryId: categoryId,
            title: habit.title,
            notes: habit.notes,
            recurrenceRule: habit.recurrenceRule,
            startDate: habit.startDate,
            endDate: habit.endDate,
            priorityWeight: habit.priorityWeight,
            preferredTime: habit.preferredTime,
            isActive: habit.isActive
        ) }
        if let title = input.title { habit.title = title }
        if let notes = input.notes { habit.notes = notes }
        if let recurrenceRule = input.recurrenceRule { habit.recurrenceRule = recurrenceRule }
        if input.clearEndDate {
            habit.endDate = nil
        }
        if let endDate = input.endDate { habit.endDate = endDate }
        if let priorityWeight = input.priorityWeight { habit.priorityWeight = priorityWeight }
        if input.clearPreferredTime {
            habit.preferredTime = nil
        }
        if let preferredTime = input.preferredTime { habit.preferredTime = preferredTime }
        if let isActive = input.isActive { habit.isActive = isActive }
        habits[index] = habit
        return habit
    }

    public func patchTodo(id: String, input: TodoUpdateInput, clientUpdatedAt: Date?) async throws -> Todo {
        var todo = todos[id] ?? Todo(id: id, userId: "u1", categoryId: "c1", title: "task")
        if let clientUpdatedAt, clientUpdatedAt < todo.updatedAt {
            return todo
        }
        if let categoryId = input.categoryId {
            todo = Todo(
                id: todo.id,
                userId: todo.userId,
                categoryId: categoryId,
                title: todo.title,
                notes: todo.notes,
                dueAt: todo.dueAt,
                priority: todo.priority,
                isPinned: todo.isPinned,
                status: todo.status,
                completedAt: todo.completedAt,
                createdAt: todo.createdAt,
                updatedAt: todo.updatedAt
            )
        }
        if let title = input.title { todo.title = title }
        if let notes = input.notes { todo.notes = notes }
        if let priority = input.priority { todo.priority = priority }
        if let isPinned = input.isPinned { todo.isPinned = isPinned }
        if input.clearDueAt {
            todo.dueAt = nil
        }
        if let dueAt = input.dueAt { todo.dueAt = dueAt }
        if let status = input.status {
            todo.status = status
            todo.completedAt = status == .completed ? Date() : nil
        }
        todo.updatedAt = Date()
        todos[id] = todo
        return todo
    }

    public func deleteHabit(id: String) async throws {
        habits.removeAll { $0.id == id }
    }

    public func deleteTodo(id: String) async throws {
        todos.removeValue(forKey: id)
    }

    private static func parseDateTime(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFraction.date(from: value) {
            return parsed
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private static func encodeDateTime(_ date: Date) -> String {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.string(from: date)
    }
}

private struct WireEmailSignupRequest: Codable {
    let email: String
    let password: String
    let displayName: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case email
        case password
        case displayName = "display_name"
        case timezone
    }
}

private struct WireEmailLoginRequest: Codable {
    let email: String
    let password: String
}

private struct WireAuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: WireUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

private struct WireUser: Codable {
    let id: String
    let email: String
    let appleSub: String?
    let displayName: String
    let timezone: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case appleSub = "apple_sub"
        case displayName = "display_name"
        case timezone
        case createdAt = "created_at"
    }
}

private struct WireCategory: Codable {
    let id: String
    let userId: String
    let name: String
    let icon: String
    let color: String
    let sortOrder: Int
    let isDefault: Bool
    let archivedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case icon
        case color
        case sortOrder = "sort_order"
        case isDefault = "is_default"
        case archivedAt = "archived_at"
    }
}

private struct WireHabitCreateRequest: Codable {
    let categoryId: String
    let title: String
    let notes: String
    let recurrenceRule: String
    let startDate: String?
    let endDate: String?
    let priorityWeight: Int
    let preferredTime: String?

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case title
        case notes
        case recurrenceRule = "recurrence_rule"
        case startDate = "start_date"
        case endDate = "end_date"
        case priorityWeight = "priority_weight"
        case preferredTime = "preferred_time"
    }
}

private struct WireHabit: Codable {
    let id: String
    let userId: String
    let categoryId: String
    let title: String
    let notes: String
    let recurrenceRule: String
    let startDate: String
    let endDate: String?
    let priorityWeight: Int
    let preferredTime: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case categoryId = "category_id"
        case title
        case notes
        case recurrenceRule = "recurrence_rule"
        case startDate = "start_date"
        case endDate = "end_date"
        case priorityWeight = "priority_weight"
        case preferredTime = "preferred_time"
        case isActive = "is_active"
    }
}

private struct WireTodoCreateRequest: Codable {
    let categoryId: String
    let title: String
    let notes: String
    let dueAt: String?
    let priority: Int
    let isPinned: Bool

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case title
        case notes
        case dueAt = "due_at"
        case priority
        case isPinned = "is_pinned"
    }
}

private struct WireHabitUpdateRequest: Encodable {
    let categoryId: String?
    let title: String?
    let notes: String?
    let recurrenceRule: String?
    let endDate: String?
    let clearEndDate: Bool
    let priorityWeight: Int?
    let preferredTime: String?
    let clearPreferredTime: Bool
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case title
        case notes
        case recurrenceRule = "recurrence_rule"
        case endDate = "end_date"
        case priorityWeight = "priority_weight"
        case preferredTime = "preferred_time"
        case isActive = "is_active"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(recurrenceRule, forKey: .recurrenceRule)
        if clearEndDate {
            try container.encodeNil(forKey: .endDate)
        } else {
            try container.encodeIfPresent(endDate, forKey: .endDate)
        }
        try container.encodeIfPresent(priorityWeight, forKey: .priorityWeight)
        if clearPreferredTime {
            try container.encodeNil(forKey: .preferredTime)
        } else {
            try container.encodeIfPresent(preferredTime, forKey: .preferredTime)
        }
        try container.encodeIfPresent(isActive, forKey: .isActive)
    }
}

private struct WireTodoUpdateRequest: Encodable {
    let categoryId: String?
    let title: String?
    let notes: String?
    let dueAt: String?
    let clearDueAt: Bool
    let priority: Int?
    let isPinned: Bool?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case title
        case notes
        case dueAt = "due_at"
        case priority
        case isPinned = "is_pinned"
        case status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(notes, forKey: .notes)
        if clearDueAt {
            try container.encodeNil(forKey: .dueAt)
        } else {
            try container.encodeIfPresent(dueAt, forKey: .dueAt)
        }
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(status, forKey: .status)
    }
}

private struct WireTodo: Codable {
    let id: String
    let userId: String
    let categoryId: String
    let title: String
    let notes: String
    let dueAt: String?
    let priority: Int
    let isPinned: Bool
    let status: String
    let completedAt: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case categoryId = "category_id"
        case title
        case notes
        case dueAt = "due_at"
        case priority
        case isPinned = "is_pinned"
        case status
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct WireCompletionWriteRequest: Codable {
    let itemType: String
    let itemId: String
    let dateLocal: String
    let state: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case itemType = "item_type"
        case itemId = "item_id"
        case dateLocal = "date_local"
        case state
        case source
    }
}

private struct WireTodayItem: Codable {
    let itemType: String
    let itemId: String
    let title: String
    let categoryId: String
    let completed: Bool
    let sortBucket: Int
    let sortScore: Double
    let subtitle: String?
    let isPinned: Bool?
    let priority: Int?
    let dueAt: String?
    let preferredTime: String?

    enum CodingKeys: String, CodingKey {
        case itemType = "item_type"
        case itemId = "item_id"
        case title
        case categoryId = "category_id"
        case completed
        case sortBucket = "sort_bucket"
        case sortScore = "sort_score"
        case subtitle
        case isPinned = "is_pinned"
        case priority
        case dueAt = "due_at"
        case preferredTime = "preferred_time"
    }
}

private struct WireTodayResponse: Codable {
    let dateLocal: String
    let items: [WireTodayItem]
    let completedCount: Int
    let totalCount: Int
    let completionRatio: Double

    enum CodingKeys: String, CodingKey {
        case dateLocal = "date_local"
        case items
        case completedCount = "completed_count"
        case totalCount = "total_count"
        case completionRatio = "completion_ratio"
    }
}

private struct WireTodayOrderItemRequest: Codable {
    let itemType: String
    let itemId: String
    let orderIndex: Int

    enum CodingKeys: String, CodingKey {
        case itemType = "item_type"
        case itemId = "item_id"
        case orderIndex = "order_index"
    }
}

private struct WireTodayOrderWriteRequest: Codable {
    let dateLocal: String
    let items: [WireTodayOrderItemRequest]

    enum CodingKeys: String, CodingKey {
        case dateLocal = "date_local"
        case items
    }
}

private struct WireDailySummary: Codable {
    let dateLocal: String
    let completedItems: Int
    let expectedItems: Int
    let completionRate: Double
    let habitCompleted: Int
    let habitExpected: Int
    let todoCompleted: Int
    let todoExpected: Int

    enum CodingKeys: String, CodingKey {
        case dateLocal = "date_local"
        case completedItems = "completed_items"
        case expectedItems = "expected_items"
        case completionRate = "completion_rate"
        case habitCompleted = "habit_completed"
        case habitExpected = "habit_expected"
        case todoCompleted = "todo_completed"
        case todoExpected = "todo_expected"
    }
}

private struct WirePeriodSummary: Codable {
    let periodType: String
    let periodStart: String
    let periodEnd: String
    let completedItems: Int
    let expectedItems: Int
    let completionRate: Double
    let activeDays: Int
    let consistencyScore: Double

    enum CodingKeys: String, CodingKey {
        case periodType = "period_type"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case completedItems = "completed_items"
        case expectedItems = "expected_items"
        case completionRate = "completion_rate"
        case activeDays = "active_days"
        case consistencyScore = "consistency_score"
    }
}

private struct WireHabitStats: Codable {
    let habitId: String
    let anchorDate: String
    let windowDays: Int
    let streakCurrent: Int
    let completedWindow: Int
    let expectedWindow: Int
    let completionRateWindow: Double
    let lastCompletedDate: String?

    enum CodingKeys: String, CodingKey {
        case habitId = "habit_id"
        case anchorDate = "anchor_date"
        case windowDays = "window_days"
        case streakCurrent = "streak_current"
        case completedWindow = "completed_window"
        case expectedWindow = "expected_window"
        case completionRateWindow = "completion_rate_window"
        case lastCompletedDate = "last_completed_date"
    }
}

private struct WireReflectionWriteRequest: Codable {
    let periodType: String
    let periodStart: String
    let periodEnd: String
    let content: String
    let sentiment: String
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case periodType = "period_type"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case content
        case sentiment
        case tags
    }
}

private struct WireReflectionNote: Codable {
    let id: String
    let userId: String
    let periodType: String
    let periodStart: String
    let periodEnd: String
    let content: String
    let sentiment: String
    let tags: [String]
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case periodType = "period_type"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case content
        case sentiment
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct WireUserPreferences: Codable {
    let id: String
    let userId: String
    let theme: String
    let weekStart: Int
    let defaultTab: String
    let quietHoursStart: String?
    let quietHoursEnd: String?
    let notificationFlags: [String: Bool]
    let coachEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case theme
        case weekStart = "week_start"
        case defaultTab = "default_tab"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case notificationFlags = "notification_flags"
        case coachEnabled = "coach_enabled"
    }
}

private struct WireUserPreferencesPatchRequest: Codable {
    let theme: String?
    let weekStart: Int?
    let defaultTab: String?
    let quietHoursStart: String?
    let quietHoursEnd: String?
    let notificationFlags: [String: Bool]?
    let coachEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case theme
        case weekStart = "week_start"
        case defaultTab = "default_tab"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case notificationFlags = "notification_flags"
        case coachEnabled = "coach_enabled"
    }
}

private struct WireCoachCard: Codable {
    let id: String
    let title: String
    let body: String
    let verseRef: String?
    let verseText: String?
    let tags: [String]
    let locale: String
    let activeFrom: String?
    let activeTo: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case verseRef = "verse_ref"
        case verseText = "verse_text"
        case tags
        case locale
        case activeFrom = "active_from"
        case activeTo = "active_to"
        case isActive = "is_active"
    }
}

private struct WireUserPatchRequest: Codable {
    let displayName: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case timezone
    }
}
