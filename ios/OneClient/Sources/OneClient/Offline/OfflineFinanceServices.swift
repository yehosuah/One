import Foundation

struct FinanceStarterCategoryTemplate: Sendable, Equatable {
    let name: String
    let iconName: String
    let aliases: [String]
}

struct LocalFinanceCategoryService {
    let starterTemplates: [FinanceStarterCategoryTemplate] = [
        FinanceStarterCategoryTemplate(name: "Food", iconName: "fork.knife", aliases: ["food", "coffee", "groceries", "lunch", "dinner", "breakfast", "snack"]),
        FinanceStarterCategoryTemplate(name: "Gas / Transport", iconName: "car.fill", aliases: ["gas", "transport", "uber", "taxi", "fuel", "bus", "parking"]),
        FinanceStarterCategoryTemplate(name: "Shopping", iconName: "bag.fill", aliases: ["shopping", "store", "clothes", "market"]),
        FinanceStarterCategoryTemplate(name: "Entertainment", iconName: "popcorn.fill", aliases: ["entertainment", "movie", "games", "cinema", "music"]),
        FinanceStarterCategoryTemplate(name: "Subscriptions", iconName: "repeat.circle.fill", aliases: ["subscription", "subscriptions", "netflix", "spotify", "streaming"]),
        FinanceStarterCategoryTemplate(name: "Bills", iconName: "doc.text.fill", aliases: ["bill", "bills", "utilities", "internet", "rent", "electricity", "water"]),
        FinanceStarterCategoryTemplate(name: "Health", iconName: "heart.text.square.fill", aliases: ["health", "doctor", "medicine", "pharmacy", "clinic"]),
        FinanceStarterCategoryTemplate(name: "School", iconName: "book.closed.fill", aliases: ["school", "study", "books", "class", "tuition"]),
        FinanceStarterCategoryTemplate(name: "Gifts", iconName: "gift.fill", aliases: ["gift", "gifts", "present"]),
        FinanceStarterCategoryTemplate(name: "Savings", iconName: "archivebox.fill", aliases: ["savings", "save"]),
        FinanceStarterCategoryTemplate(name: "Miscellaneous", iconName: "ellipsis.circle.fill", aliases: ["misc", "miscellaneous", "other"])
    ]

    func defaultCurrencyCode() -> String {
        Locale.autoupdatingCurrent.currency?.identifier ?? "USD"
    }
}

enum FinanceDateCoding {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    static func calendar(timezoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezoneID) ?? .autoupdatingCurrent
        return calendar
    }

    static func date(from value: String, timezoneID: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar(timezoneID: timezoneID)
        formatter.locale = posixLocale
        formatter.timeZone = formatter.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    static func isoDateString(from value: Date, timezoneID: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar(timezoneID: timezoneID)
        formatter.locale = posixLocale
        formatter.timeZone = formatter.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    static func localDateString(from value: Date, timezoneID: String) -> String {
        OfflineDateCoding.localDateString(from: value, timezoneID: timezoneID)
    }

    static func dateTime(for isoDate: String, timezoneID: String) -> Date {
        guard let base = date(from: isoDate, timezoneID: timezoneID) else {
            return Date()
        }
        let localCalendar = calendar(timezoneID: timezoneID)
        return localCalendar.date(byAdding: .hour, value: 12, to: base) ?? base
    }

    static func bounds(
        for period: FinanceAnalyticsPeriod,
        anchorDate: String,
        weekStart: Int,
        timezoneID: String
    ) -> (startDate: String, endDate: String) {
        guard let anchor = date(from: anchorDate, timezoneID: timezoneID) else {
            return (anchorDate, anchorDate)
        }
        let localCalendar = calendar(timezoneID: timezoneID)
        switch period {
        case .week:
            let weekday = localCalendar.component(.weekday, from: anchor)
            let normalizedWeekday = (weekday + 5) % 7
            let offset = (normalizedWeekday - weekStart + 7) % 7
            let start = localCalendar.date(byAdding: .day, value: -offset, to: anchor) ?? anchor
            let end = localCalendar.date(byAdding: .day, value: 6, to: start) ?? start
            return (isoDateString(from: start, timezoneID: timezoneID), isoDateString(from: end, timezoneID: timezoneID))
        case .month:
            let components = localCalendar.dateComponents([.year, .month], from: anchor)
            let start = localCalendar.date(from: components) ?? anchor
            let end = localCalendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? anchor
            return (isoDateString(from: start, timezoneID: timezoneID), isoDateString(from: end, timezoneID: timezoneID))
        case .year:
            let year = localCalendar.component(.year, from: anchor)
            let start = localCalendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? anchor
            let end = localCalendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? anchor
            return (isoDateString(from: start, timezoneID: timezoneID), isoDateString(from: end, timezoneID: timezoneID))
        }
    }

    static func daysElapsedInMonth(anchorDate: String, timezoneID: String) -> Int {
        Int(dayNumber(from: anchorDate)) ?? 1
    }

    static func daysInMonth(anchorDate: String, timezoneID: String) -> Int {
        guard let anchor = date(from: anchorDate, timezoneID: timezoneID) else {
            return 30
        }
        let localCalendar = calendar(timezoneID: timezoneID)
        return localCalendar.range(of: .day, in: .month, for: anchor)?.count ?? 30
    }

    static func shortWeekday(from isoDate: String, timezoneID: String) -> String {
        guard let date = date(from: isoDate, timezoneID: timezoneID) else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar(timezoneID: timezoneID)
        formatter.locale = posixLocale
        formatter.timeZone = formatter.calendar.timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    static func shortMonth(for month: Int, timezoneID: String) -> String {
        let localCalendar = calendar(timezoneID: timezoneID)
        guard let date = localCalendar.date(from: DateComponents(year: 2026, month: month, day: 1)) else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.calendar = localCalendar
        formatter.locale = posixLocale
        formatter.timeZone = formatter.calendar.timeZone
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }

    static func dayNumber(from isoDate: String) -> String {
        String(isoDate.suffix(2))
    }

    static func weekOfMonth(from isoDate: String, timezoneID: String) -> Int {
        guard let date = date(from: isoDate, timezoneID: timezoneID) else {
            return 1
        }
        return calendar(timezoneID: timezoneID).component(.weekOfMonth, from: date)
    }

    static func addCadence(
        to isoDate: String,
        cadenceType: FinanceRecurringCadenceType,
        cadenceInterval: Int?,
        timezoneID: String
    ) -> String {
        guard let base = date(from: isoDate, timezoneID: timezoneID) else {
            return isoDate
        }
        let localCalendar = calendar(timezoneID: timezoneID)
        let next: Date
        switch cadenceType {
        case .weekly:
            next = localCalendar.date(byAdding: .day, value: 7, to: base) ?? base
        case .biweekly:
            next = localCalendar.date(byAdding: .day, value: 14, to: base) ?? base
        case .monthly:
            next = localCalendar.date(byAdding: .month, value: 1, to: base) ?? base
        case .yearly:
            next = localCalendar.date(byAdding: .year, value: 1, to: base) ?? base
        case .custom:
            let days = max(cadenceInterval ?? 30, 1)
            next = localCalendar.date(byAdding: .day, value: days, to: base) ?? base
        }
        return isoDateString(from: next, timezoneID: timezoneID)
    }

    static func sequenceDates(startDate: String, endDate: String, timezoneID: String) -> [String] {
        guard let start = date(from: startDate, timezoneID: timezoneID),
              let end = date(from: endDate, timezoneID: timezoneID) else {
            return []
        }
        let localCalendar = calendar(timezoneID: timezoneID)
        var cursor = start
        var values: [String] = []
        while cursor <= end {
            values.append(isoDateString(from: cursor, timezoneID: timezoneID))
            cursor = localCalendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
        }
        return values
    }
}

private enum FinanceComputation {
    static func expenseAmount(for transaction: FinanceTransaction) -> Double {
        transaction.type == .expense ? transaction.amount : 0
    }

    static func incomeAmount(for transaction: FinanceTransaction) -> Double {
        transaction.type == .income ? transaction.amount : 0
    }

    static func netAmount(for transaction: FinanceTransaction) -> Double {
        switch transaction.type {
        case .expense:
            return -transaction.amount
        case .income:
            return transaction.amount
        case .transfer:
            return 0
        }
    }
}

struct LocalFinanceRecurringMaterialization {
    let transactions: [FinanceTransaction]
    let updatedRecurringItems: [RecurringFinanceTransaction]
}

struct LocalFinanceRecurringService {
    func materializeDueTransactions(
        recurringItems: [RecurringFinanceTransaction],
        existingTransactions: [FinanceTransaction],
        currentDateLocal: String,
        timezoneID: String
    ) -> LocalFinanceRecurringMaterialization {
        let existingInstanceIDs = Set(existingTransactions.compactMap(\.recurringInstanceId))
        var createdTransactions: [FinanceTransaction] = []
        var updatedRecurringItems: [RecurringFinanceTransaction] = []
        let now = Date()

        for var item in recurringItems where item.isActive {
            guard item.nextDueDate <= currentDateLocal else {
                continue
            }

            while item.isActive && item.nextDueDate <= currentDateLocal {
                if let endDate = item.endDate, item.nextDueDate > endDate {
                    item.isActive = false
                    item.updatedAt = now
                    break
                }

                let instanceID = "\(item.id)|\(item.nextDueDate)"
                if !existingInstanceIDs.contains(instanceID) {
                    createdTransactions.append(
                        FinanceTransaction(
                            id: UUID().uuidString,
                            type: .expense,
                            amount: item.amount,
                            currencyCode: item.currencyCode,
                            categoryId: item.categoryId,
                            paymentMethod: item.paymentMethod,
                            note: item.note,
                            occurredAt: FinanceDateCoding.dateTime(for: item.nextDueDate, timezoneID: timezoneID),
                            createdAt: now,
                            updatedAt: now,
                            source: .recurring,
                            recurringInstanceId: instanceID
                        )
                    )
                }
                item.nextDueDate = FinanceDateCoding.addCadence(
                    to: item.nextDueDate,
                    cadenceType: item.cadenceType,
                    cadenceInterval: item.cadenceInterval,
                    timezoneID: timezoneID
                )
                item.updatedAt = now
                if let endDate = item.endDate, item.nextDueDate > endDate {
                    item.isActive = false
                }
            }
            updatedRecurringItems.append(item)
        }

        return LocalFinanceRecurringMaterialization(
            transactions: createdTransactions.sorted { $0.occurredAt < $1.occurredAt },
            updatedRecurringItems: updatedRecurringItems
        )
    }

    func monthlyTotal(for items: [RecurringFinanceTransaction]) -> Double {
        items
            .filter(\.isActive)
            .reduce(0) { partial, item in
                partial + monthlyAmount(for: item)
            }
    }

    func yearlyTotal(for items: [RecurringFinanceTransaction]) -> Double {
        items
            .filter(\.isActive)
            .reduce(0) { partial, item in
                partial + yearlyAmount(for: item)
            }
    }

    func upcomingCharges(
        for items: [RecurringFinanceTransaction],
        limit: Int = 6
    ) -> [FinanceUpcomingRecurringCharge] {
        items
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.nextDueDate != rhs.nextDueDate {
                    return lhs.nextDueDate < rhs.nextDueDate
                }
                return lhs.title < rhs.title
            }
            .prefix(limit)
            .map {
                FinanceUpcomingRecurringCharge(
                    recurringId: $0.id,
                    title: $0.title,
                    amount: $0.amount,
                    currencyCode: $0.currencyCode,
                    dueDate: $0.nextDueDate,
                    categoryId: $0.categoryId,
                    paymentMethod: $0.paymentMethod
                )
            }
    }

    private func monthlyAmount(for item: RecurringFinanceTransaction) -> Double {
        switch item.cadenceType {
        case .weekly:
            return item.amount * (52.0 / 12.0)
        case .biweekly:
            return item.amount * (26.0 / 12.0)
        case .monthly:
            return item.amount
        case .yearly:
            return item.amount / 12.0
        case .custom:
            let interval = Double(max(item.cadenceInterval ?? 30, 1))
            return item.amount * (30.0 / interval)
        }
    }

    private func yearlyAmount(for item: RecurringFinanceTransaction) -> Double {
        switch item.cadenceType {
        case .weekly:
            return item.amount * 52.0
        case .biweekly:
            return item.amount * 26.0
        case .monthly:
            return item.amount * 12.0
        case .yearly:
            return item.amount
        case .custom:
            let interval = Double(max(item.cadenceInterval ?? 30, 1))
            return item.amount * (365.0 / interval)
        }
    }
}

struct LocalFinanceAnalyticsService {
    private let recurringService = LocalFinanceRecurringService()

    func transactionSections(
        transactions: [FinanceTransaction],
        timezoneID: String
    ) -> [FinanceTransactionDaySection] {
        let grouped = Dictionary(grouping: transactions) { transaction in
            FinanceDateCoding.localDateString(from: transaction.occurredAt, timezoneID: timezoneID)
        }
        return grouped.keys.sorted(by: >).map { dateLocal in
            let dayTransactions = (grouped[dateLocal] ?? []).sorted { $0.occurredAt > $1.occurredAt }
            let total = dayTransactions.reduce(0) { $0 + FinanceComputation.netAmount(for: $1) }
            return FinanceTransactionDaySection(dateLocal: dateLocal, total: total, transactions: dayTransactions)
        }
    }

    func homeSnapshot(
        balanceState: FinanceBalanceState,
        manualAdjustmentAt: Date?,
        categories: [FinanceCategory],
        transactions: [FinanceTransaction],
        recurringItems: [RecurringFinanceTransaction],
        currentDateLocal: String,
        weekStart: Int,
        timezoneID: String
    ) -> FinanceHomeSnapshot {
        let weekBounds = FinanceDateCoding.bounds(
            for: .week,
            anchorDate: currentDateLocal,
            weekStart: weekStart,
            timezoneID: timezoneID
        )
        let monthBounds = FinanceDateCoding.bounds(
            for: .month,
            anchorDate: currentDateLocal,
            weekStart: weekStart,
            timezoneID: timezoneID
        )
        let weekTransactions = filter(transactions: transactions, startDate: weekBounds.startDate, endDate: weekBounds.endDate, timezoneID: timezoneID)
        let monthTransactions = filter(transactions: transactions, startDate: monthBounds.startDate, endDate: monthBounds.endDate, timezoneID: timezoneID)
        let todayTransactions = transactions
            .filter { FinanceDateCoding.localDateString(from: $0.occurredAt, timezoneID: timezoneID) == currentDateLocal }
            .sorted { $0.occurredAt > $1.occurredAt }
        let categoryBreakdown = topCategories(
            from: weekTransactions,
            categories: categories,
            limit: 4
        )
        let monthlyRecurringTotal = recurringService.monthlyTotal(for: recurringItems)
        let yearlyRecurringTotal = recurringService.yearlyTotal(for: recurringItems)
        let upcomingRecurringCharges = recurringService.upcomingCharges(for: recurringItems)
        let weekSpent = weekTransactions.reduce(0) { $0 + FinanceComputation.expenseAmount(for: $1) }
        let weekIncome = weekTransactions.reduce(0) { $0 + FinanceComputation.incomeAmount(for: $1) }
        let weekNet = weekTransactions.reduce(0) { $0 + FinanceComputation.netAmount(for: $1) }
        let monthSpent = monthTransactions.reduce(0) { $0 + FinanceComputation.expenseAmount(for: $1) }
        let projectedMonthSpend = projectedMonthSpend(
            anchorDate: currentDateLocal,
            monthSpent: monthSpent,
            timezoneID: timezoneID
        )
        let baseline = weeklyBaseline(
            transactions: transactions,
            currentWeekStart: weekBounds.startDate,
            weekStart: weekStart,
            timezoneID: timezoneID
        )
        let paceComparisonBase = baseline > 0 ? baseline : (balanceState.weeklyPaceThreshold ?? 0)
        let weeklyPaceVsBaseline = paceComparisonBase > 0 ? weekSpent / paceComparisonBase : 0
        let projectedRemainingSpend = max(projectedMonthSpend - monthSpent, 0)
        let remainingProjection = balanceState.totalBalance - projectedRemainingSpend - upcomingRecurringWithinMonth(
            currentDateLocal: currentDateLocal,
            recurringItems: recurringItems
        )
        let insightSummary = FinanceInsightSummary(
            weekSpent: weekSpent,
            weekIncome: weekIncome,
            weekNet: weekNet,
            projectedMonthSpend: projectedMonthSpend,
            topCategories: topCategories(from: monthTransactions, categories: categories, limit: 4),
            weeklyPaceVsBaseline: weeklyPaceVsBaseline,
            upcomingRecurringCharges: upcomingRecurringCharges,
            remainingBalanceProjection: remainingProjection
        )
        let warnings = warnings(
            balanceState: balanceState,
            weekSpent: weekSpent,
            weeklyBaseline: baseline,
            transactions: transactions,
            currentDateLocal: currentDateLocal,
            weekStart: weekStart,
            timezoneID: timezoneID
        )

        return FinanceHomeSnapshot(
            balanceState: balanceState,
            balanceComparisons: balanceComparisons(
                balanceState: balanceState,
                manualAdjustmentAt: manualAdjustmentAt,
                transactions: transactions,
                weekBounds: weekBounds,
                monthBounds: monthBounds,
                timezoneID: timezoneID
            ),
            insightSummary: insightSummary,
            warnings: warnings,
            todayTransactions: Array(todayTransactions.prefix(5)),
            categoryBreakdown: categoryBreakdown,
            monthlyRecurringTotal: monthlyRecurringTotal,
            yearlyRecurringTotal: yearlyRecurringTotal,
            suggestedPaymentMethod: suggestedPaymentMethod(from: transactions)
        )
    }

    func analyticsSnapshot(
        period: FinanceAnalyticsPeriod,
        categories: [FinanceCategory],
        transactions: [FinanceTransaction],
        recurringItems: [RecurringFinanceTransaction],
        currentDateLocal: String,
        weekStart: Int,
        timezoneID: String
    ) -> FinanceAnalyticsSnapshot {
        let bounds = FinanceDateCoding.bounds(
            for: period,
            anchorDate: currentDateLocal,
            weekStart: weekStart,
            timezoneID: timezoneID
        )
        let periodTransactions = filter(
            transactions: transactions,
            startDate: bounds.startDate,
            endDate: bounds.endDate,
            timezoneID: timezoneID
        )
        let totalSpent = periodTransactions.reduce(0) { $0 + FinanceComputation.expenseAmount(for: $1) }
        let totalIncome = periodTransactions.reduce(0) { $0 + FinanceComputation.incomeAmount(for: $1) }
        let netMovement = periodTransactions.reduce(0) { $0 + FinanceComputation.netAmount(for: $1) }
        let topCategories = topCategories(from: periodTransactions, categories: categories, limit: 5)
        let chartPoints = chartPoints(
            period: period,
            transactions: periodTransactions,
            bounds: bounds,
            timezoneID: timezoneID
        )
        let comparisonPoints = comparisonPoints(
            period: period,
            transactions: transactions,
            currentDateLocal: currentDateLocal,
            weekStart: weekStart,
            timezoneID: timezoneID
        )
        let projected = period == .month ? projectedMonthSpend(anchorDate: currentDateLocal, monthSpent: totalSpent, timezoneID: timezoneID) : nil
        let recurringBurden = period == .year
            ? recurringService.yearlyTotal(for: recurringItems)
            : recurringService.monthlyTotal(for: recurringItems)
        return FinanceAnalyticsSnapshot(
            period: period,
            startDate: bounds.startDate,
            endDate: bounds.endDate,
            totalSpent: totalSpent,
            totalIncome: totalIncome,
            netMovement: netMovement,
            projectedMonthSpend: projected,
            recurringBurden: recurringBurden,
            insightMessage: insightMessage(
                period: period,
                totalSpent: totalSpent,
                totalIncome: totalIncome,
                comparisonPoints: comparisonPoints
            ),
            chartPoints: chartPoints,
            topCategories: topCategories,
            comparisonPoints: comparisonPoints
        )
    }

    func recurringOverview(for recurringItems: [RecurringFinanceTransaction]) -> FinanceRecurringOverview {
        FinanceRecurringOverview(
            activeItems: recurringItems.filter(\.isActive).sorted { lhs, rhs in
                if lhs.nextDueDate != rhs.nextDueDate {
                    return lhs.nextDueDate < rhs.nextDueDate
                }
                return lhs.title < rhs.title
            },
            monthlyTotal: recurringService.monthlyTotal(for: recurringItems),
            yearlyTotal: recurringService.yearlyTotal(for: recurringItems),
            upcomingCharges: recurringService.upcomingCharges(for: recurringItems)
        )
    }

    private func filter(
        transactions: [FinanceTransaction],
        startDate: String,
        endDate: String,
        timezoneID: String
    ) -> [FinanceTransaction] {
        transactions.filter { transaction in
            let localDate = FinanceDateCoding.localDateString(from: transaction.occurredAt, timezoneID: timezoneID)
            return localDate >= startDate && localDate <= endDate
        }
    }

    private func topCategories(
        from transactions: [FinanceTransaction],
        categories: [FinanceCategory],
        limit: Int
    ) -> [FinanceCategoryTotal] {
        let expenseTransactions = transactions.filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenseTransactions, by: { $0.categoryId ?? "uncategorized" })
        return grouped
            .map { categoryID, items in
                let total = items.reduce(0) { $0 + $1.amount }
                let category = categories.first(where: { $0.id == categoryID })
                return FinanceCategoryTotal(
                    categoryId: categoryID,
                    categoryName: category?.name ?? "Uncategorized",
                    iconName: category?.iconName ?? "questionmark.circle",
                    amount: total
                )
            }
            .sorted { lhs, rhs in
                if lhs.amount != rhs.amount {
                    return lhs.amount > rhs.amount
                }
                return lhs.categoryName < rhs.categoryName
            }
            .prefix(limit)
            .map { $0 }
    }

    private func projectedMonthSpend(anchorDate: String, monthSpent: Double, timezoneID: String) -> Double {
        let elapsed = Double(max(FinanceDateCoding.daysElapsedInMonth(anchorDate: anchorDate, timezoneID: timezoneID), 1))
        let days = Double(max(FinanceDateCoding.daysInMonth(anchorDate: anchorDate, timezoneID: timezoneID), 1))
        return (monthSpent / elapsed) * days
    }

    private func weeklyBaseline(
        transactions: [FinanceTransaction],
        currentWeekStart: String,
        weekStart: Int,
        timezoneID: String
    ) -> Double {
        guard let currentWeekStartDate = FinanceDateCoding.date(from: currentWeekStart, timezoneID: timezoneID) else {
            return 0
        }
        let localCalendar = FinanceDateCoding.calendar(timezoneID: timezoneID)
        var priorTotals: [Double] = []
        for offset in 1...4 {
            guard let weekStartDate = localCalendar.date(byAdding: .day, value: -(7 * offset), to: currentWeekStartDate) else {
                continue
            }
            let start = FinanceDateCoding.isoDateString(from: weekStartDate, timezoneID: timezoneID)
            let endDate = localCalendar.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
            let end = FinanceDateCoding.isoDateString(from: endDate, timezoneID: timezoneID)
            let total = filter(transactions: transactions, startDate: start, endDate: end, timezoneID: timezoneID)
                .reduce(0) { $0 + FinanceComputation.expenseAmount(for: $1) }
            if total > 0 {
                priorTotals.append(total)
            }
        }
        guard !priorTotals.isEmpty else {
            return 0
        }
        return priorTotals.reduce(0, +) / Double(priorTotals.count)
    }

    private func upcomingRecurringWithinMonth(
        currentDateLocal: String,
        recurringItems: [RecurringFinanceTransaction]
    ) -> Double {
        let currentMonthPrefix = String(currentDateLocal.prefix(7))
        return recurringItems
            .filter(\.isActive)
            .filter { $0.nextDueDate.hasPrefix(currentMonthPrefix) && $0.nextDueDate >= currentDateLocal }
            .reduce(0) { $0 + $1.amount }
    }

    private func warnings(
        balanceState: FinanceBalanceState,
        weekSpent: Double,
        weeklyBaseline: Double,
        transactions: [FinanceTransaction],
        currentDateLocal: String,
        weekStart: Int,
        timezoneID: String
    ) -> [FinanceWarning] {
        var results: [FinanceWarning] = []
        if let lowBalanceThreshold = balanceState.lowBalanceThreshold,
           balanceState.totalBalance < lowBalanceThreshold {
            results.append(
                FinanceWarning(
                    kind: .lowBalance,
                    title: "Balance is nearing your floor",
                    message: "Current balance is below the local threshold you set."
                )
            )
        }
        if let weeklyThreshold = balanceState.weeklyPaceThreshold,
           weekSpent > weeklyThreshold {
            results.append(
                FinanceWarning(
                    kind: .weeklyPace,
                    title: "This week is running above your pace cap",
                    message: "Spending for the week is above the threshold saved on this device."
                )
            )
        } else if weeklyBaseline > 0, weekSpent > (weeklyBaseline * 1.15) {
            results.append(
                FinanceWarning(
                    kind: .weeklyPace,
                    title: "This week is moving faster than usual",
                    message: "Spending is above your recent weekly baseline."
                )
            )
        }
        if unusualRecentSpending(
            transactions: transactions,
            currentDateLocal: currentDateLocal,
            timezoneID: timezoneID
        ) {
            results.append(
                FinanceWarning(
                    kind: .unusualSpending,
                    title: "Recent spending is above your recent pattern",
                    message: "The last few days are coming in heavier than your recent baseline."
                )
            )
        }
        return Array(results.prefix(2))
    }

    private func unusualRecentSpending(
        transactions: [FinanceTransaction],
        currentDateLocal: String,
        timezoneID: String
    ) -> Bool {
        let localCalendar = FinanceDateCoding.calendar(timezoneID: timezoneID)
        guard let anchor = FinanceDateCoding.date(from: currentDateLocal, timezoneID: timezoneID),
              let recentStart = localCalendar.date(byAdding: .day, value: -2, to: anchor),
              let baselineStart = localCalendar.date(byAdding: .day, value: -16, to: anchor),
              let baselineEnd = localCalendar.date(byAdding: .day, value: -3, to: anchor) else {
            return false
        }
        let recentSpent = filter(
            transactions: transactions,
            startDate: FinanceDateCoding.isoDateString(from: recentStart, timezoneID: timezoneID),
            endDate: currentDateLocal,
            timezoneID: timezoneID
        ).reduce(0) { $0 + FinanceComputation.expenseAmount(for: $1) }
        let baselineSpent = filter(
            transactions: transactions,
            startDate: FinanceDateCoding.isoDateString(from: baselineStart, timezoneID: timezoneID),
            endDate: FinanceDateCoding.isoDateString(from: baselineEnd, timezoneID: timezoneID),
            timezoneID: timezoneID
        ).reduce(0) { $0 + FinanceComputation.expenseAmount(for: $1) }
        guard baselineSpent > 0 else {
            return false
        }
        let baselineDaily = baselineSpent / 14.0
        return recentSpent > max(baselineDaily * 3.0 * 1.35, 20.0)
    }

    private func balanceComparisons(
        balanceState: FinanceBalanceState,
        manualAdjustmentAt: Date?,
        transactions: [FinanceTransaction],
        weekBounds: (startDate: String, endDate: String),
        monthBounds: (startDate: String, endDate: String),
        timezoneID: String
    ) -> [FinanceBalanceComparison] {
        var comparisons: [FinanceBalanceComparison] = []
        let currentTotal = balanceState.totalBalance
        if shouldShowComparison(startDate: weekBounds.startDate, manualAdjustmentAt: manualAdjustmentAt, timezoneID: timezoneID) {
            let weekNet = filter(transactions: transactions, startDate: weekBounds.startDate, endDate: weekBounds.endDate, timezoneID: timezoneID)
                .reduce(0) { $0 + FinanceComputation.netAmount(for: $1) }
            comparisons.append(FinanceBalanceComparison(label: "Week", delta: weekNet))
        }
        if shouldShowComparison(startDate: monthBounds.startDate, manualAdjustmentAt: manualAdjustmentAt, timezoneID: timezoneID) {
            let monthNet = filter(transactions: transactions, startDate: monthBounds.startDate, endDate: monthBounds.endDate, timezoneID: timezoneID)
                .reduce(0) { $0 + FinanceComputation.netAmount(for: $1) }
            if abs(monthNet) > 0.009 || comparisons.isEmpty || currentTotal != 0 {
                comparisons.append(FinanceBalanceComparison(label: "Month", delta: monthNet))
            }
        }
        return comparisons
    }

    private func shouldShowComparison(startDate: String, manualAdjustmentAt: Date?, timezoneID: String) -> Bool {
        guard let manualAdjustmentAt else {
            return true
        }
        let manualDate = FinanceDateCoding.localDateString(from: manualAdjustmentAt, timezoneID: timezoneID)
        return manualDate <= startDate
    }

    private func suggestedPaymentMethod(from transactions: [FinanceTransaction]) -> FinancePaymentMethod {
        transactions
            .sorted { $0.occurredAt > $1.occurredAt }
            .first(where: { $0.type == .expense && $0.paymentMethod != nil })?
            .paymentMethod ?? .card
    }

    private func chartPoints(
        period: FinanceAnalyticsPeriod,
        transactions: [FinanceTransaction],
        bounds: (startDate: String, endDate: String),
        timezoneID: String
    ) -> [FinanceAmountChartPoint] {
        switch period {
        case .week:
            let dates = FinanceDateCoding.sequenceDates(
                startDate: bounds.startDate,
                endDate: bounds.endDate,
                timezoneID: timezoneID
            )
            let grouped = Dictionary(grouping: transactions) {
                FinanceDateCoding.localDateString(from: $0.occurredAt, timezoneID: timezoneID)
            }
            return dates.map { dateLocal in
                let items = grouped[dateLocal] ?? []
                return FinanceAmountChartPoint(
                    label: FinanceDateCoding.shortWeekday(from: dateLocal, timezoneID: timezoneID),
                    spent: items.reduce(0) { $0 + FinanceComputation.expenseAmount(for: $1) },
                    income: items.reduce(0) { $0 + FinanceComputation.incomeAmount(for: $1) },
                    net: items.reduce(0) { $0 + FinanceComputation.netAmount(for: $1) }
                )
            }
        case .month:
            let grouped = Dictionary(grouping: transactions) {
                FinanceDateCoding.weekOfMonth(
                    from: FinanceDateCoding.localDateString(from: $0.occurredAt, timezoneID: timezoneID),
                    timezoneID: timezoneID
                )
            }
            let allWeeks = Set(grouped.keys).union(Set([1, 2, 3, 4, 5]))
            return allWeeks.sorted().map { week in
                let items = grouped[week] ?? []
                return FinanceAmountChartPoint(
                    label: "W\(week)",
                    spent: items.reduce(0) { $0 + FinanceComputation.expenseAmount(for: $1) },
                    income: items.reduce(0) { $0 + FinanceComputation.incomeAmount(for: $1) },
                    net: items.reduce(0) { $0 + FinanceComputation.netAmount(for: $1) }
                )
            }
        case .year:
            let grouped = Dictionary(grouping: transactions) {
                let localDate = FinanceDateCoding.localDateString(from: $0.occurredAt, timezoneID: timezoneID)
                return Int(localDate.split(separator: "-")[safe: 1] ?? "1") ?? 1
            }
            return (1...12).map { month in
                let items = grouped[month] ?? []
                return FinanceAmountChartPoint(
                    label: FinanceDateCoding.shortMonth(for: month, timezoneID: timezoneID),
                    spent: items.reduce(0) { $0 + FinanceComputation.expenseAmount(for: $1) },
                    income: items.reduce(0) { $0 + FinanceComputation.incomeAmount(for: $1) },
                    net: items.reduce(0) { $0 + FinanceComputation.netAmount(for: $1) }
                )
            }
        }
    }

    private func comparisonPoints(
        period: FinanceAnalyticsPeriod,
        transactions: [FinanceTransaction],
        currentDateLocal: String,
        weekStart: Int,
        timezoneID: String
    ) -> [FinanceComparisonPoint] {
        let localCalendar = FinanceDateCoding.calendar(timezoneID: timezoneID)
        guard let anchor = FinanceDateCoding.date(from: currentDateLocal, timezoneID: timezoneID) else {
            return []
        }
        switch period {
        case .week:
            return (0..<4).compactMap { offset in
                guard let reference = localCalendar.date(byAdding: .day, value: -(7 * offset), to: anchor) else {
                    return nil
                }
                let referenceDate = FinanceDateCoding.isoDateString(from: reference, timezoneID: timezoneID)
                let bounds = FinanceDateCoding.bounds(for: .week, anchorDate: referenceDate, weekStart: weekStart, timezoneID: timezoneID)
                let items = filter(transactions: transactions, startDate: bounds.startDate, endDate: bounds.endDate, timezoneID: timezoneID)
                return FinanceComparisonPoint(
                    label: offset == 0 ? "Current" : "-\(offset)w",
                    spent: items.reduce(0) { $0 + FinanceComputation.expenseAmount(for: $1) },
                    income: items.reduce(0) { $0 + FinanceComputation.incomeAmount(for: $1) },
                    net: items.reduce(0) { $0 + FinanceComputation.netAmount(for: $1) }
                )
            }.reversed()
        case .month:
            return (0..<4).compactMap { offset in
                guard let reference = localCalendar.date(byAdding: .month, value: -offset, to: anchor) else {
                    return nil
                }
                let referenceDate = FinanceDateCoding.isoDateString(from: reference, timezoneID: timezoneID)
                let bounds = FinanceDateCoding.bounds(for: .month, anchorDate: referenceDate, weekStart: weekStart, timezoneID: timezoneID)
                let items = filter(transactions: transactions, startDate: bounds.startDate, endDate: bounds.endDate, timezoneID: timezoneID)
                let month = localCalendar.component(.month, from: reference)
                return FinanceComparisonPoint(
                    label: offset == 0 ? "Current" : FinanceDateCoding.shortMonth(for: month, timezoneID: timezoneID),
                    spent: items.reduce(0) { $0 + FinanceComputation.expenseAmount(for: $1) },
                    income: items.reduce(0) { $0 + FinanceComputation.incomeAmount(for: $1) },
                    net: items.reduce(0) { $0 + FinanceComputation.netAmount(for: $1) }
                )
            }.reversed()
        case .year:
            let yearBounds = FinanceDateCoding.bounds(for: .year, anchorDate: currentDateLocal, weekStart: weekStart, timezoneID: timezoneID)
            let yearTransactions = filter(transactions: transactions, startDate: yearBounds.startDate, endDate: yearBounds.endDate, timezoneID: timezoneID)
            let grouped = Dictionary(grouping: yearTransactions) {
                let localDate = FinanceDateCoding.localDateString(from: $0.occurredAt, timezoneID: timezoneID)
                return Int(localDate.split(separator: "-")[safe: 1] ?? "1") ?? 1
            }
            return (1...12).map { month in
                let items = grouped[month] ?? []
                return FinanceComparisonPoint(
                    label: FinanceDateCoding.shortMonth(for: month, timezoneID: timezoneID),
                    spent: items.reduce(0) { $0 + FinanceComputation.expenseAmount(for: $1) },
                    income: items.reduce(0) { $0 + FinanceComputation.incomeAmount(for: $1) },
                    net: items.reduce(0) { $0 + FinanceComputation.netAmount(for: $1) }
                )
            }
        }
    }

    private func insightMessage(
        period: FinanceAnalyticsPeriod,
        totalSpent: Double,
        totalIncome: Double,
        comparisonPoints: [FinanceComparisonPoint]
    ) -> String {
        if totalSpent == 0 && totalIncome == 0 {
            return "This \(period.title.lowercased()) has no finance activity recorded yet."
        }
        let priorPoint = comparisonPoints.dropLast().last
        if let priorPoint, priorPoint.spent > 0 {
            let ratio = totalSpent / priorPoint.spent
            if ratio > 1.15 {
                return "Spending is higher than the previous \(period.title.lowercased()) reference."
            }
            if ratio < 0.9 {
                return "Spending is lighter than the previous \(period.title.lowercased()) reference."
            }
        }
        if totalIncome > totalSpent {
            return "Income is covering spending in this \(period.title.lowercased()) range."
        }
        return "Spending is the main movement in this \(period.title.lowercased()) range."
    }
}
