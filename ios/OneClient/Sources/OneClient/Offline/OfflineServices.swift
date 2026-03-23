import Foundation

struct TodayOrderOverrideRecord: Sendable, Equatable {
    let itemType: ItemType
    let itemId: String
    let orderIndex: Int
}

struct LocalTodayMaterialization: Sendable {
    let response: TodayResponse
    let materializedLogs: [CompletionLog]
}

struct LocalOnboardingBundle: Sendable {
    let user: User
    let categories: [Category]
    let preferences: UserPreferences
}

struct LocalCoachingService {
    func seedCardsIfNeeded(existing: [CoachCard]) -> [CoachCard] {
        guard existing.isEmpty else {
            return existing
        }
        return [
            CoachCard(
                id: UUID().uuidString,
                title: "Finish the first rep",
                body: "Start with the smallest useful action. Momentum matters more than intensity.",
                verseRef: "Ecclesiastes 9:10",
                verseText: "Whatever your hand finds to do, do it with all your might.",
                tags: ["focus", "consistency"],
                locale: "en",
                isActive: true
            ),
            CoachCard(
                id: UUID().uuidString,
                title: "Do the next clear thing",
                body: "If the day feels heavy, reduce the target. Clarity beats motivation.",
                verseRef: "Proverbs 16:3",
                verseText: "Commit to the Lord whatever you do, and he will establish your plans.",
                tags: ["planning", "discipline"],
                locale: "en",
                isActive: true
            ),
            CoachCard(
                id: UUID().uuidString,
                title: "Stay steady",
                body: "Consistency over weeks is the real scoreboard. Protect the routine.",
                verseRef: "Galatians 6:9",
                verseText: "Let us not become weary in doing good, for at the proper time we will reap a harvest if we do not give up.",
                tags: ["streaks", "habits"],
                locale: "en",
                isActive: true
            ),
            CoachCard(
                id: UUID().uuidString,
                title: "Reset without drama",
                body: "If the day slipped, restart at the next honest step instead of negotiating with the miss.",
                verseRef: "Proverbs 24:16",
                verseText: "For a just man falleth seven times, and riseth up again.",
                tags: ["reset", "resilience"],
                locale: "en",
                isActive: true
            ),
            CoachCard(
                id: UUID().uuidString,
                title: "Work from a quiet center",
                body: "Pressure is a signal to simplify. Protect the next clear action and let the noise stay outside it.",
                verseRef: "2 Timothy 1:7",
                verseText: "For God hath not given us the spirit of fear; but of power, and of love, and of a sound mind.",
                tags: ["stress", "clarity"],
                locale: "en",
                isActive: true
            ),
            CoachCard(
                id: UUID().uuidString,
                title: "Give the tired part a structure",
                body: "Low energy does not require a lost day. Shrink the scope and keep the rhythm alive.",
                verseRef: "Isaiah 40:31",
                verseText: "But they that wait upon the Lord shall renew their strength.",
                tags: ["fatigue", "recovery"],
                locale: "en",
                isActive: true
            ),
            CoachCard(
                id: UUID().uuidString,
                title: "Stay faithful in the small work",
                body: "The invisible reps still count. Quiet consistency is usually what makes the visible progress possible.",
                verseRef: "Colossians 3:23",
                verseText: "And whatsoever ye do, do it heartily, as to the Lord, and not unto men.",
                tags: ["faithfulness", "discipline"],
                locale: "en",
                isActive: true
            ),
            CoachCard(
                id: UUID().uuidString,
                title: "Ask for help and keep moving",
                body: "When the day feels heavier than your plan, trade isolation for honesty and keep one step in motion.",
                verseRef: "Matthew 11:28",
                verseText: "Come unto me, all ye that labour and are heavy laden, and I will give you rest.",
                tags: ["rest", "encouragement"],
                locale: "en",
                isActive: true
            ),
        ]
    }

    func activeCards(cards: [CoachCard], targetDate: Date = Date()) -> [CoachCard] {
        let today = OfflineDateCoding.isoDateString(from: targetDate)
        return cards
            .filter { $0.isActive }
            .filter { card in
                if let activeFrom = card.activeFrom, activeFrom > today {
                    return false
                }
                if let activeTo = card.activeTo, activeTo < today {
                    return false
                }
                return true
            }
            .sorted { ($0.activeFrom ?? today, $0.title) < ($1.activeFrom ?? today, $1.title) }
    }
}

struct LocalOnboardingService {
    private let defaultCategoryNames = [
        "Gym",
        "School",
        "Personal Projects",
        "Wellbeing",
        "Life Admin",
    ]

    func bootstrap(userID: String, email: String, displayName: String, timezone: String) -> LocalOnboardingBundle {
        let now = Date()
        let user = User(
            id: userID,
            email: email,
            displayName: displayName,
            timezone: timezone,
            createdAt: now
        )
        let categories = defaultCategoryNames.enumerated().map { index, name in
            Category(
                id: UUID().uuidString,
                userId: userID,
                name: name,
                icon: Self.defaultCategoryIcon(for: name),
                sortOrder: index,
                isDefault: true
            )
        }
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
        return LocalOnboardingBundle(user: user, categories: categories, preferences: preferences)
    }

    private static func defaultCategoryIcon(for name: String) -> String {
        switch name {
        case "Gym":
            return "🏋️"
        case "School":
            return "🎓"
        case "Personal Projects":
            return "💡"
        case "Wellbeing":
            return "🌿"
        case "Life Admin":
            return "🧾"
        default:
            return "circle"
        }
    }
}

struct LocalReflectionService {
    func create(existing notes: [ReflectionNote], incoming: ReflectionNote) -> [ReflectionNote] {
        var mutable = notes
        mutable.append(incoming)
        return mutable
    }

    func list(notes: [ReflectionNote], userID: String, periodType: PeriodType?) -> [ReflectionNote] {
        notes
            .filter { $0.userId == userID }
            .filter { periodType == nil || $0.periodType == periodType }
            .sorted { lhs, rhs in
                if lhs.periodStart != rhs.periodStart {
                    return lhs.periodStart > rhs.periodStart
                }
                let lhsDate = lhs.createdAt ?? lhs.updatedAt ?? .distantPast
                let rhsDate = rhs.createdAt ?? rhs.updatedAt ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.id > rhs.id
            }
    }
}

struct LocalTodayService {
    func materialize(
        user: User,
        targetDate: String,
        habits: [Habit],
        todos: [Todo],
        completionLogs: [CompletionLog],
        overrides: [TodayOrderOverrideRecord]
    ) -> LocalTodayMaterialization {
        let scheduledHabits = habits.filter { $0.userId == user.id && isHabitScheduled($0, on: targetDate) }
        let dayLogs = completionLogs.filter { $0.userId == user.id && $0.dateLocal == targetDate }
        let existingKeys = Set(dayLogs.map { "\($0.itemType.rawValue)|\($0.itemId)|\($0.dateLocal)" })

        var materializedLogs: [CompletionLog] = []
        for habit in scheduledHabits {
            let key = "\(ItemType.habit.rawValue)|\(habit.id)|\(targetDate)"
            guard !existingKeys.contains(key) else {
                continue
            }
            materializedLogs.append(
                CompletionLog(
                    id: UUID().uuidString,
                    userId: user.id,
                    itemType: .habit,
                    itemId: habit.id,
                    dateLocal: targetDate,
                    state: .notCompleted,
                    source: "materializer"
                )
            )
        }

        let logs = dayLogs + materializedLogs
        let items = applyOverrides(
            to: buildTodayItems(
                user: user,
                targetDate: targetDate,
                habits: habits,
                todos: todos,
                completionLogs: logs
            ),
            overrides: overrides
        )
        let completed = items.filter(\.completed).count
        let response = TodayResponse(
            dateLocal: targetDate,
            items: items,
            completedCount: completed,
            totalCount: items.count,
            completionRatio: items.isEmpty ? 0 : Double(completed) / Double(items.count)
        )
        return LocalTodayMaterialization(response: response, materializedLogs: materializedLogs)
    }

    func setCompletion(
        currentLogs: [CompletionLog],
        userID: String,
        itemType: ItemType,
        itemID: String,
        dateLocal: String,
        state: CompletionState
    ) -> [CompletionLog] {
        var mutable = currentLogs
        if let index = mutable.firstIndex(where: {
            $0.userId == userID &&
                $0.itemType == itemType &&
                $0.itemId == itemID &&
                $0.dateLocal == dateLocal
        }) {
            mutable[index].state = state
            mutable[index].completedAt = state == .completed ? Date() : nil
            mutable[index].updatedAt = Date()
            mutable[index].source = "ios"
            return mutable
        }

        mutable.append(
            CompletionLog(
                id: UUID().uuidString,
                userId: userID,
                itemType: itemType,
                itemId: itemID,
                dateLocal: dateLocal,
                state: state,
                completedAt: state == .completed ? Date() : nil,
                source: "ios"
            )
        )
        return mutable
    }

    private func buildTodayItems(
        user: User,
        targetDate: String,
        habits: [Habit],
        todos: [Todo],
        completionLogs: [CompletionLog]
    ) -> [TodayItem] {
        let habitLogs = Dictionary(
            uniqueKeysWithValues: completionLogs
                .filter { $0.itemType == .habit && $0.dateLocal == targetDate }
                .map { ($0.itemId, $0) }
        )

        let pinnedTodos = sortedTodosForToday(
            todos.filter { $0.userId == user.id && $0.status == .open && $0.isPinned },
            targetDate: targetDate,
            timezoneID: user.timezone
        )
        let urgentTodos = sortedTodosForToday(
            todos
                .filter { $0.userId == user.id && $0.status == .open && !$0.isPinned }
                .filter { todo in
                    guard let dueAt = todo.dueAt else {
                        return false
                    }
                    return OfflineDateCoding.localDateString(from: dueAt, timezoneID: user.timezone) <= targetDate
                },
            targetDate: targetDate,
            timezoneID: user.timezone
        )
        let remainingTodos = sortedTodosForToday(
            todos
                .filter { $0.userId == user.id && $0.status == .open && !$0.isPinned }
                .filter { todo in
                    !urgentTodos.contains(where: { $0.id == todo.id })
                },
            targetDate: targetDate,
            timezoneID: user.timezone
        )
        let completedTodos = sortedTodosForToday(
            todos
                .filter { $0.userId == user.id && $0.status == .completed }
                .filter { todo in
                    if let dueAt = todo.dueAt {
                        return OfflineDateCoding.localDateString(from: dueAt, timezoneID: user.timezone) == targetDate
                    }
                    return OfflineDateCoding.localDateString(from: todo.createdAt, timezoneID: user.timezone) == targetDate
                },
            targetDate: targetDate,
            timezoneID: user.timezone
        )
        let scheduledHabits = sortedHabitsForToday(
            habits.filter { $0.userId == user.id && isHabitScheduled($0, on: targetDate) }
        )

        var items: [TodayItem] = []

        for todo in pinnedTodos {
            items.append(
                TodayItem(
                    itemType: .todo,
                    itemId: todo.id,
                    title: todo.title,
                    categoryId: todo.categoryId,
                    completed: false,
                    sortBucket: 0,
                    sortScore: todoUrgencyScore(todo, today: targetDate, timezoneID: user.timezone),
                    subtitle: todoSubtitle(todo, timezoneID: user.timezone),
                    isPinned: todo.isPinned,
                    priority: todo.priority,
                    dueAt: todo.dueAt
                )
            )
        }

        for todo in urgentTodos {
            items.append(
                TodayItem(
                    itemType: .todo,
                    itemId: todo.id,
                    title: todo.title,
                    categoryId: todo.categoryId,
                    completed: false,
                    sortBucket: 1,
                    sortScore: todoUrgencyScore(todo, today: targetDate, timezoneID: user.timezone),
                    subtitle: todoSubtitle(todo, timezoneID: user.timezone),
                    isPinned: todo.isPinned,
                    priority: todo.priority,
                    dueAt: todo.dueAt
                )
            )
        }

        for habit in scheduledHabits {
            let log = habitLogs[habit.id]
            let isCompleted = log?.state == .completed
            let subtitle = habit.preferredTime.map { "Habit · \($0)" } ?? "Habit"
            items.append(
                TodayItem(
                    itemType: .habit,
                    itemId: habit.id,
                    title: habit.title,
                    categoryId: habit.categoryId,
                    completed: isCompleted,
                    sortBucket: 2,
                    sortScore: habitSortScore(habit),
                    subtitle: subtitle,
                    isPinned: false,
                    priority: habit.priorityWeight,
                    dueAt: nil,
                    preferredTime: habit.preferredTime
                )
            )
        }

        for todo in remainingTodos {
            items.append(
                TodayItem(
                    itemType: .todo,
                    itemId: todo.id,
                    title: todo.title,
                    categoryId: todo.categoryId,
                    completed: false,
                    sortBucket: 3,
                    sortScore: todoUrgencyScore(todo, today: targetDate, timezoneID: user.timezone),
                    subtitle: todoSubtitle(todo, timezoneID: user.timezone),
                    isPinned: todo.isPinned,
                    priority: todo.priority,
                    dueAt: todo.dueAt
                )
            )
        }

        for todo in completedTodos {
            let completedTime = todo.completedAt.map {
                OfflineDateCoding.localTimeString(from: $0, timezoneID: user.timezone)
            }
            let subtitle = completedTime.map { "Task · completed · \($0)" } ?? "Task · completed"
            items.append(
                TodayItem(
                    itemType: .todo,
                    itemId: todo.id,
                    title: todo.title,
                    categoryId: todo.categoryId,
                    completed: true,
                    sortBucket: 4,
                    sortScore: todoUrgencyScore(todo, today: targetDate, timezoneID: user.timezone),
                    subtitle: subtitle,
                    isPinned: todo.isPinned,
                    priority: todo.priority,
                    dueAt: todo.dueAt
                )
            )
        }

        return items.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.sortBucket != rhs.element.sortBucket {
                    return lhs.element.sortBucket < rhs.element.sortBucket
                }
                if lhs.element.sortScore != rhs.element.sortScore {
                    return lhs.element.sortScore > rhs.element.sortScore
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func applyOverrides(to items: [TodayItem], overrides: [TodayOrderOverrideRecord]) -> [TodayItem] {
        guard !overrides.isEmpty else {
            return items
        }
        let orderLookup = Dictionary(uniqueKeysWithValues: overrides.map { ("\($0.itemType.rawValue):\($0.itemId)", $0.orderIndex) })
        return items.enumerated()
            .sorted { lhs, rhs in
                let lhsKey = lhs.element.id
                let rhsKey = rhs.element.id
                let lhsOrder = orderLookup[lhsKey]
                let rhsOrder = orderLookup[rhsKey]
                switch (lhsOrder, rhsOrder) {
                case let (left?, right?):
                    if left != right {
                        return left < right
                    }
                    return lhs.offset < rhs.offset
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    private func todoSubtitle(_ todo: Todo, timezoneID: String) -> String {
        var subtitle = "Task"
        if let dueAt = todo.dueAt {
            let time = OfflineDateCoding.localTimeString(from: dueAt, timezoneID: timezoneID)
            subtitle += " · due \(time)"
        }
        return subtitle
    }

    private func todoUrgencyScore(_ todo: Todo, today: String, timezoneID: String) -> Double {
        var score = Double(todo.priority)
        guard let dueAt = todo.dueAt else {
            return score
        }
        let todayDate = OfflineDateCoding.date(from: today) ?? Date()
        let dueDate = OfflineDateCoding.date(
            from: OfflineDateCoding.localDateString(from: dueAt, timezoneID: timezoneID)
        ) ?? dueAt
        let delta = OfflineDateCoding.canonicalCalendar.dateComponents([.day], from: todayDate, to: dueDate).day ?? 0
        if delta < 0 {
            score += 200 + Double(abs(delta) * 10)
        } else if delta == 0 {
            score += 150
        } else if delta == 1 {
            score += 100
        } else {
            score += max(0, Double(40 - delta))
        }
        return score
    }

    private func sortedTodosForToday(_ todos: [Todo], targetDate: String, timezoneID: String) -> [Todo] {
        todos.sorted { lhs, rhs in
            let lhsScore = todoUrgencyScore(lhs, today: targetDate, timezoneID: timezoneID)
            let rhsScore = todoUrgencyScore(rhs, today: targetDate, timezoneID: timezoneID)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func habitSortScore(_ habit: Habit) -> Double {
        var score = Double(habit.priorityWeight)
        if let preferredTime = habit.preferredTime,
           let minutes = OfflineDateCoding.minutesFromClock(preferredTime) {
            score += max(0, Double(1_440 - minutes) / 1_440.0)
        }
        return score
    }

    private func sortedHabitsForToday(_ habits: [Habit]) -> [Habit] {
        habits.sorted { lhs, rhs in
            let lhsScore = habitSortScore(lhs)
            let rhsScore = habitSortScore(rhs)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func isHabitScheduled(_ habit: Habit, on targetDate: String) -> Bool {
        guard habit.isActive else {
            return false
        }
        guard let target = OfflineDateCoding.date(from: targetDate),
              let startDate = OfflineDateCoding.date(from: habit.startDate) else {
            return false
        }
        if target < startDate {
            return false
        }
        if let endDate = habit.endDate.flatMap(OfflineDateCoding.date(from:)), target > endDate {
            return false
        }

        let rule = habit.recurrenceRule.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if rule.isEmpty || rule == "DAILY" {
            return true
        }
        if rule.hasPrefix("WEEKLY:") {
            let validDays = Set(rule.replacingOccurrences(of: "WEEKLY:", with: "").split(separator: ",").map { String($0) })
            let weekday = OfflineDateCoding.weekdayCode(for: target)
            return validDays.contains(weekday)
        }
        if rule.hasPrefix("MONTHLY:") {
            let validDays = Set(rule.replacingOccurrences(of: "MONTHLY:", with: "").split(separator: ",").compactMap { Int($0) })
            let day = OfflineDateCoding.canonicalCalendar.component(.day, from: target)
            return validDays.contains(day)
        }
        if rule.hasPrefix("YEARLY:") {
            let validMonthDays = Set(rule.replacingOccurrences(of: "YEARLY:", with: "").split(separator: ",").map { String($0) })
            let components = OfflineDateCoding.canonicalCalendar.dateComponents([.month, .day], from: target)
            let monthDay = String(format: "%02d-%02d", components.month ?? 0, components.day ?? 0)
            return validMonthDays.contains(monthDay)
        }
        return false
    }
}

struct LocalAnalyticsService {
    func dailySummaries(
        user: User,
        startDate: String,
        endDate: String,
        habits: [Habit],
        todos: [Todo],
        completionLogs: [CompletionLog]
    ) -> [DailySummary] {
        guard let start = OfflineDateCoding.date(from: startDate),
              let end = OfflineDateCoding.date(from: endDate) else {
            return []
        }
        var summaries: [DailySummary] = []
        var cursor = start
        let calendar = OfflineDateCoding.canonicalCalendar
        while cursor <= end {
            let dateLocal = OfflineDateCoding.isoDateString(from: cursor)
            let scheduledHabits = habits.filter { $0.userId == user.id && LocalTodayService().isHabitScheduled($0, on: dateLocal) }
            let relevantLogs = completionLogs.filter { $0.userId == user.id && $0.dateLocal == dateLocal && $0.state == .completed }
            let habitCompleted = scheduledHabits.filter { habit in
                relevantLogs.contains { $0.itemType == .habit && $0.itemId == habit.id }
            }.count

            let dayTodos = todos.filter { todo in
                todo.userId == user.id &&
                    todo.status != .canceled &&
                    todoActionDate(todo, timezoneID: user.timezone) == dateLocal
            }
            let todoCompleted = dayTodos.filter { $0.status == .completed }.count
            let expected = scheduledHabits.count + dayTodos.count
            let completed = habitCompleted + todoCompleted

            summaries.append(
                DailySummary(
                    dateLocal: dateLocal,
                    completedItems: completed,
                    expectedItems: expected,
                    completionRate: expected == 0 ? 0 : Double(completed) / Double(expected),
                    habitCompleted: habitCompleted,
                    habitExpected: scheduledHabits.count,
                    todoCompleted: todoCompleted,
                    todoExpected: dayTodos.count
                )
            )
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
        }
        return summaries
    }

    func periodSummary(
        user: User,
        anchorDate: String,
        periodType: PeriodType,
        weekStart: Int,
        habits: [Habit],
        todos: [Todo],
        completionLogs: [CompletionLog]
    ) -> PeriodSummary {
        let bounds = periodBounds(anchorDate: anchorDate, periodType: periodType, weekStart: weekStart)
        let summaries = dailySummaries(
            user: user,
            startDate: bounds.start,
            endDate: bounds.end,
            habits: habits,
            todos: todos,
            completionLogs: completionLogs
        )
        let completed = summaries.reduce(0) { $0 + $1.completedItems }
        let expected = summaries.reduce(0) { $0 + $1.expectedItems }
        let activeDays = summaries.filter { $0.completedItems > 0 }.count
        let rates = summaries.filter { $0.expectedItems > 0 }.map(\.completionRate)
        let consistency = rates.isEmpty ? 0 : rates.reduce(0, +) / Double(rates.count)
        return PeriodSummary(
            periodType: periodType,
            periodStart: bounds.start,
            periodEnd: bounds.end,
            completedItems: completed,
            expectedItems: expected,
            completionRate: expected == 0 ? 0 : Double(completed) / Double(expected),
            activeDays: activeDays,
            consistencyScore: consistency
        )
    }

    func habitStats(
        user: User,
        habit: Habit,
        anchorDate: String,
        windowDays: Int,
        completionLogs: [CompletionLog]
    ) -> HabitStats {
        let bounds = rollingWindow(anchorDate: anchorDate, windowDays: windowDays)
        let summaries = dailyCompletionDays(
            habit: habit,
            startDate: bounds.start,
            endDate: bounds.end,
            completionLogs: completionLogs
        )
        let expectedWindow = summaries.count
        let completedWindow = summaries.filter(\.completed).count
        let lastCompletedDate = summaries.filter(\.completed).map(\.dateLocal).sorted().last
        return HabitStats(
            habitId: habit.id,
            anchorDate: anchorDate,
            windowDays: windowDays,
            streakCurrent: currentHabitStreak(habit: habit, anchorDate: anchorDate, completionLogs: completionLogs),
            completedWindow: completedWindow,
            expectedWindow: expectedWindow,
            completionRateWindow: expectedWindow == 0 ? 0 : Double(completedWindow) / Double(expectedWindow),
            lastCompletedDate: lastCompletedDate
        )
    }

    private func dailyCompletionDays(habit: Habit, startDate: String, endDate: String, completionLogs: [CompletionLog]) -> [(dateLocal: String, completed: Bool)] {
        guard let start = OfflineDateCoding.date(from: startDate),
              let end = OfflineDateCoding.date(from: endDate) else {
            return []
        }
        let completedDates = Set(
            completionLogs
                .filter { $0.itemType == .habit && $0.itemId == habit.id && $0.state == .completed }
                .map(\.dateLocal)
        )
        var rows: [(String, Bool)] = []
        let calendar = OfflineDateCoding.canonicalCalendar
        var cursor = start
        let todayService = LocalTodayService()
        while cursor <= end {
            let dateLocal = OfflineDateCoding.isoDateString(from: cursor)
            if todayService.isHabitScheduled(habit, on: dateLocal) {
                rows.append((dateLocal, completedDates.contains(dateLocal)))
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
        }
        return rows
    }

    private func currentHabitStreak(habit: Habit, anchorDate: String, completionLogs: [CompletionLog]) -> Int {
        guard let anchor = OfflineDateCoding.date(from: anchorDate) else {
            return 0
        }
        let completedDates = Set(
            completionLogs
                .filter { $0.itemType == .habit && $0.itemId == habit.id && $0.state == .completed }
                .map(\.dateLocal)
        )
        var streak = 0
        let calendar = OfflineDateCoding.canonicalCalendar
        let todayService = LocalTodayService()
        var cursor = anchor
        while true {
            let dateLocal = OfflineDateCoding.isoDateString(from: cursor)
            if let startDate = OfflineDateCoding.date(from: habit.startDate), cursor < startDate {
                break
            }
            if let endDate = habit.endDate.flatMap(OfflineDateCoding.date(from:)), cursor > endDate {
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
                continue
            }
            if !todayService.isHabitScheduled(habit, on: dateLocal) {
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
                continue
            }
            if completedDates.contains(dateLocal) {
                streak += 1
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
                continue
            }
            break
        }
        return streak
    }

    private func periodBounds(anchorDate: String, periodType: PeriodType, weekStart: Int) -> (start: String, end: String) {
        guard let anchor = OfflineDateCoding.date(from: anchorDate) else {
            return (anchorDate, anchorDate)
        }
        let calendar = OfflineDateCoding.canonicalCalendar
        switch periodType {
        case .daily:
            return (anchorDate, anchorDate)
        case .weekly:
            let weekday = calendar.component(.weekday, from: anchor)
            let normalizedWeekday = (weekday + 5) % 7
            let offset = (normalizedWeekday - weekStart + 7) % 7
            let start = calendar.date(byAdding: .day, value: -offset, to: anchor) ?? anchor
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return (OfflineDateCoding.isoDateString(from: start), OfflineDateCoding.isoDateString(from: end))
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: anchor)
            let start = calendar.date(from: components) ?? anchor
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? anchor
            return (OfflineDateCoding.isoDateString(from: start), OfflineDateCoding.isoDateString(from: end))
        case .yearly:
            let year = calendar.component(.year, from: anchor)
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? anchor
            let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? anchor
            return (OfflineDateCoding.isoDateString(from: start), OfflineDateCoding.isoDateString(from: end))
        }
    }

    private func rollingWindow(anchorDate: String, windowDays: Int) -> (start: String, end: String) {
        guard let anchor = OfflineDateCoding.date(from: anchorDate) else {
            return (anchorDate, anchorDate)
        }
        let calendar = OfflineDateCoding.canonicalCalendar
        let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: anchor) ?? anchor
        return (OfflineDateCoding.isoDateString(from: start), anchorDate)
    }

    private func todoActionDate(_ todo: Todo, timezoneID: String) -> String {
        if let dueAt = todo.dueAt {
            return OfflineDateCoding.localDateString(from: dueAt, timezoneID: timezoneID)
        }
        return OfflineDateCoding.localDateString(from: todo.createdAt, timezoneID: timezoneID)
    }
}

enum OfflineDateCoding {
    static let canonicalTimeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    static var deviceTimeZone: TimeZone { .autoupdatingCurrent }
    static var deviceTimeZoneIdentifier: String { deviceTimeZone.identifier }
    static let canonicalCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = canonicalTimeZone
        return calendar
    }()

    static func date(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = canonicalCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = canonicalTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    static func isoDateString(from value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = canonicalCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = canonicalTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    static func localDate(from value: Date, timezoneID: String) -> Date {
        _ = timezoneID
        let timezone = deviceTimeZone
        var localCalendar = canonicalCalendar
        localCalendar.timeZone = timezone
        let components = localCalendar.dateComponents([.year, .month, .day], from: value)
        return localCalendar.date(from: components) ?? value
    }

    static func localDateString(from value: Date, timezoneID: String) -> String {
        isoDateString(from: localDate(from: value, timezoneID: timezoneID))
    }

    static func localTimeString(from value: Date, timezoneID: String) -> String {
        _ = timezoneID
        let formatter = DateFormatter()
        formatter.calendar = canonicalCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = deviceTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: value)
    }

    static func minutesFromClock(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return (hour * 60) + minute
    }

    static func weekdayCode(for value: Date) -> String {
        let weekday = canonicalCalendar.component(.weekday, from: value)
        switch weekday {
        case 2: return "MON"
        case 3: return "TUE"
        case 4: return "WED"
        case 5: return "THU"
        case 6: return "FRI"
        case 7: return "SAT"
        default: return "SUN"
        }
    }
}
