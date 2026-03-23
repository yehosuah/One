import Foundation

public enum FinanceTransactionType: String, Codable, Sendable, CaseIterable, Hashable {
    case expense
    case income
    case transfer

    public var title: String {
        switch self {
        case .expense:
            return "Expense"
        case .income:
            return "Income"
        case .transfer:
            return "Transfer"
        }
    }
}

public enum FinancePaymentMethod: String, Codable, Sendable, CaseIterable, Hashable {
    case cash
    case card

    public var title: String {
        rawValue.capitalized
    }
}

public enum FinanceTransactionSource: String, Codable, Sendable, CaseIterable, Hashable {
    case manual
    case voice
    case recurring
}

public enum FinanceRecurringCadenceType: String, Codable, Sendable, CaseIterable, Hashable {
    case weekly
    case biweekly
    case monthly
    case yearly
    case custom

    public var title: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .biweekly:
            return "Biweekly"
        case .monthly:
            return "Monthly"
        case .yearly:
            return "Yearly"
        case .custom:
            return "Custom"
        }
    }
}

public enum FinanceAnalyticsPeriod: String, Codable, Sendable, CaseIterable, Hashable {
    case week
    case month
    case year

    public var title: String {
        switch self {
        case .week:
            return "Week"
        case .month:
            return "Month"
        case .year:
            return "Year"
        }
    }
}

public enum FinanceWarningKind: String, Codable, Sendable, CaseIterable, Hashable {
    case weeklyPace
    case lowBalance
    case unusualSpending
}

public enum FinanceVoiceParseConfidence: String, Codable, Sendable, CaseIterable, Hashable {
    case low
    case medium
    case high
}

public enum FinanceVoiceAvailability: String, Codable, Sendable, CaseIterable, Hashable {
    case available
    case authorizationRequired
    case authorizationDenied
    case microphoneDenied
    case restricted
    case onDeviceUnavailable
    case unsupported

    public var message: String {
        switch self {
        case .available:
            return "Voice expense entry is ready on this device."
        case .authorizationRequired:
            return "Voice expense entry needs microphone and speech access first."
        case .authorizationDenied:
            return "Speech access is off for this app."
        case .microphoneDenied:
            return "Microphone access is off for this app."
        case .restricted:
            return "Voice expense entry is restricted on this device."
        case .onDeviceUnavailable:
            return "On-device speech recognition is not available here yet."
        case .unsupported:
            return "Voice expense entry is unavailable on this platform."
        }
    }
}

public struct FinanceTransaction: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public var type: FinanceTransactionType
    public var amount: Double
    public let currencyCode: String
    public var categoryId: String?
    public var paymentMethod: FinancePaymentMethod?
    public var transferCounterpartPaymentMethod: FinancePaymentMethod?
    public var note: String?
    public var occurredAt: Date
    public let createdAt: Date
    public var updatedAt: Date
    public var source: FinanceTransactionSource
    public var recurringInstanceId: String?

    public init(
        id: String,
        type: FinanceTransactionType,
        amount: Double,
        currencyCode: String,
        categoryId: String? = nil,
        paymentMethod: FinancePaymentMethod? = nil,
        transferCounterpartPaymentMethod: FinancePaymentMethod? = nil,
        note: String? = nil,
        occurredAt: Date,
        createdAt: Date,
        updatedAt: Date,
        source: FinanceTransactionSource,
        recurringInstanceId: String? = nil
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryId = categoryId
        self.paymentMethod = paymentMethod
        self.transferCounterpartPaymentMethod = transferCounterpartPaymentMethod
        self.note = note
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
        self.recurringInstanceId = recurringInstanceId
    }
}

public struct FinanceCategory: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var iconName: String
    public var isCustom: Bool
    public var isArchived: Bool
    public var sortOrder: Int
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        iconName: String,
        isCustom: Bool,
        isArchived: Bool = false,
        sortOrder: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.isCustom = isCustom
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct FinanceBalanceState: Codable, Sendable, Equatable, Hashable {
    public var totalBalance: Double
    public var cardBalance: Double
    public var cashBalance: Double
    public var defaultCurrencyCode: String
    public var lowBalanceThreshold: Double?
    public var weeklyPaceThreshold: Double?
    public var updatedAt: Date

    public init(
        totalBalance: Double,
        cardBalance: Double,
        cashBalance: Double,
        defaultCurrencyCode: String,
        lowBalanceThreshold: Double? = nil,
        weeklyPaceThreshold: Double? = nil,
        updatedAt: Date
    ) {
        self.totalBalance = totalBalance
        self.cardBalance = cardBalance
        self.cashBalance = cashBalance
        self.defaultCurrencyCode = defaultCurrencyCode
        self.lowBalanceThreshold = lowBalanceThreshold
        self.weeklyPaceThreshold = weeklyPaceThreshold
        self.updatedAt = updatedAt
    }
}

public struct RecurringFinanceTransaction: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public var title: String
    public var amount: Double
    public let currencyCode: String
    public var categoryId: String
    public var paymentMethod: FinancePaymentMethod
    public var cadenceType: FinanceRecurringCadenceType
    public var cadenceInterval: Int?
    public var nextDueDate: String
    public var startDate: String
    public var endDate: String?
    public var note: String?
    public var isActive: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        amount: Double,
        currencyCode: String,
        categoryId: String,
        paymentMethod: FinancePaymentMethod,
        cadenceType: FinanceRecurringCadenceType,
        cadenceInterval: Int? = nil,
        nextDueDate: String,
        startDate: String,
        endDate: String? = nil,
        note: String? = nil,
        isActive: Bool = true,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryId = categoryId
        self.paymentMethod = paymentMethod
        self.cadenceType = cadenceType
        self.cadenceInterval = cadenceInterval
        self.nextDueDate = nextDueDate
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct FinanceCategoryTotal: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let categoryId: String
    public let categoryName: String
    public let iconName: String
    public let amount: Double

    public var id: String { categoryId }

    public init(categoryId: String, categoryName: String, iconName: String, amount: Double) {
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.iconName = iconName
        self.amount = amount
    }
}

public struct FinanceUpcomingRecurringCharge: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let recurringId: String
    public let title: String
    public let amount: Double
    public let currencyCode: String
    public let dueDate: String
    public let categoryId: String
    public let paymentMethod: FinancePaymentMethod

    public var id: String { "\(recurringId)-\(dueDate)" }

    public init(
        recurringId: String,
        title: String,
        amount: Double,
        currencyCode: String,
        dueDate: String,
        categoryId: String,
        paymentMethod: FinancePaymentMethod
    ) {
        self.recurringId = recurringId
        self.title = title
        self.amount = amount
        self.currencyCode = currencyCode
        self.dueDate = dueDate
        self.categoryId = categoryId
        self.paymentMethod = paymentMethod
    }
}

public struct FinanceInsightSummary: Codable, Sendable, Equatable, Hashable {
    public let weekSpent: Double
    public let weekIncome: Double
    public let weekNet: Double
    public let projectedMonthSpend: Double
    public let topCategories: [FinanceCategoryTotal]
    public let weeklyPaceVsBaseline: Double
    public let upcomingRecurringCharges: [FinanceUpcomingRecurringCharge]
    public let remainingBalanceProjection: Double

    public init(
        weekSpent: Double,
        weekIncome: Double,
        weekNet: Double,
        projectedMonthSpend: Double,
        topCategories: [FinanceCategoryTotal],
        weeklyPaceVsBaseline: Double,
        upcomingRecurringCharges: [FinanceUpcomingRecurringCharge],
        remainingBalanceProjection: Double
    ) {
        self.weekSpent = weekSpent
        self.weekIncome = weekIncome
        self.weekNet = weekNet
        self.projectedMonthSpend = projectedMonthSpend
        self.topCategories = topCategories
        self.weeklyPaceVsBaseline = weeklyPaceVsBaseline
        self.upcomingRecurringCharges = upcomingRecurringCharges
        self.remainingBalanceProjection = remainingBalanceProjection
    }
}

public struct FinanceWarning: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let kind: FinanceWarningKind
    public let title: String
    public let message: String

    public var id: FinanceWarningKind { kind }

    public init(kind: FinanceWarningKind, title: String, message: String) {
        self.kind = kind
        self.title = title
        self.message = message
    }
}

public struct FinanceBalanceComparison: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let label: String
    public let delta: Double

    public var id: String { label }

    public init(label: String, delta: Double) {
        self.label = label
        self.delta = delta
    }
}

public struct FinanceHomeSnapshot: Codable, Sendable, Equatable, Hashable {
    public let balanceState: FinanceBalanceState
    public let balanceComparisons: [FinanceBalanceComparison]
    public let insightSummary: FinanceInsightSummary
    public let warnings: [FinanceWarning]
    public let todayTransactions: [FinanceTransaction]
    public let categoryBreakdown: [FinanceCategoryTotal]
    public let monthlyRecurringTotal: Double
    public let yearlyRecurringTotal: Double
    public let suggestedPaymentMethod: FinancePaymentMethod

    public init(
        balanceState: FinanceBalanceState,
        balanceComparisons: [FinanceBalanceComparison],
        insightSummary: FinanceInsightSummary,
        warnings: [FinanceWarning],
        todayTransactions: [FinanceTransaction],
        categoryBreakdown: [FinanceCategoryTotal],
        monthlyRecurringTotal: Double,
        yearlyRecurringTotal: Double,
        suggestedPaymentMethod: FinancePaymentMethod
    ) {
        self.balanceState = balanceState
        self.balanceComparisons = balanceComparisons
        self.insightSummary = insightSummary
        self.warnings = warnings
        self.todayTransactions = todayTransactions
        self.categoryBreakdown = categoryBreakdown
        self.monthlyRecurringTotal = monthlyRecurringTotal
        self.yearlyRecurringTotal = yearlyRecurringTotal
        self.suggestedPaymentMethod = suggestedPaymentMethod
    }
}

public struct FinanceTransactionDaySection: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let dateLocal: String
    public let total: Double
    public let transactions: [FinanceTransaction]

    public var id: String { dateLocal }

    public init(dateLocal: String, total: Double, transactions: [FinanceTransaction]) {
        self.dateLocal = dateLocal
        self.total = total
        self.transactions = transactions
    }
}

public struct FinanceAmountChartPoint: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let label: String
    public let spent: Double
    public let income: Double
    public let net: Double

    public var id: String { label }

    public init(label: String, spent: Double, income: Double, net: Double) {
        self.label = label
        self.spent = spent
        self.income = income
        self.net = net
    }
}

public struct FinanceComparisonPoint: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let label: String
    public let spent: Double
    public let income: Double
    public let net: Double

    public var id: String { label }

    public init(label: String, spent: Double, income: Double, net: Double) {
        self.label = label
        self.spent = spent
        self.income = income
        self.net = net
    }
}

public struct FinanceAnalyticsSnapshot: Codable, Sendable, Equatable, Hashable {
    public let period: FinanceAnalyticsPeriod
    public let startDate: String
    public let endDate: String
    public let totalSpent: Double
    public let totalIncome: Double
    public let netMovement: Double
    public let projectedMonthSpend: Double?
    public let recurringBurden: Double
    public let insightMessage: String
    public let chartPoints: [FinanceAmountChartPoint]
    public let topCategories: [FinanceCategoryTotal]
    public let comparisonPoints: [FinanceComparisonPoint]

    public init(
        period: FinanceAnalyticsPeriod,
        startDate: String,
        endDate: String,
        totalSpent: Double,
        totalIncome: Double,
        netMovement: Double,
        projectedMonthSpend: Double?,
        recurringBurden: Double,
        insightMessage: String,
        chartPoints: [FinanceAmountChartPoint],
        topCategories: [FinanceCategoryTotal],
        comparisonPoints: [FinanceComparisonPoint]
    ) {
        self.period = period
        self.startDate = startDate
        self.endDate = endDate
        self.totalSpent = totalSpent
        self.totalIncome = totalIncome
        self.netMovement = netMovement
        self.projectedMonthSpend = projectedMonthSpend
        self.recurringBurden = recurringBurden
        self.insightMessage = insightMessage
        self.chartPoints = chartPoints
        self.topCategories = topCategories
        self.comparisonPoints = comparisonPoints
    }
}

public struct FinanceRecurringOverview: Codable, Sendable, Equatable, Hashable {
    public let activeItems: [RecurringFinanceTransaction]
    public let monthlyTotal: Double
    public let yearlyTotal: Double
    public let upcomingCharges: [FinanceUpcomingRecurringCharge]

    public init(
        activeItems: [RecurringFinanceTransaction],
        monthlyTotal: Double,
        yearlyTotal: Double,
        upcomingCharges: [FinanceUpcomingRecurringCharge]
    ) {
        self.activeItems = activeItems
        self.monthlyTotal = monthlyTotal
        self.yearlyTotal = yearlyTotal
        self.upcomingCharges = upcomingCharges
    }
}

public struct FinanceTransactionWriteInput: Sendable, Equatable, Hashable {
    public var type: FinanceTransactionType
    public var amount: Double?
    public var currencyCode: String?
    public var categoryId: String?
    public var paymentMethod: FinancePaymentMethod?
    public var transferCounterpartPaymentMethod: FinancePaymentMethod?
    public var note: String?
    public var occurredAt: Date?
    public var source: FinanceTransactionSource

    public init(
        type: FinanceTransactionType = .expense,
        amount: Double? = nil,
        currencyCode: String? = nil,
        categoryId: String? = nil,
        paymentMethod: FinancePaymentMethod? = nil,
        transferCounterpartPaymentMethod: FinancePaymentMethod? = nil,
        note: String? = nil,
        occurredAt: Date? = nil,
        source: FinanceTransactionSource = .manual
    ) {
        self.type = type
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryId = categoryId
        self.paymentMethod = paymentMethod
        self.transferCounterpartPaymentMethod = transferCounterpartPaymentMethod
        self.note = note
        self.occurredAt = occurredAt
        self.source = source
    }
}

public struct FinanceBalanceUpdateInput: Sendable, Equatable, Hashable {
    public var cardBalance: Double
    public var cashBalance: Double
    public var defaultCurrencyCode: String?
    public var lowBalanceThreshold: Double?
    public var weeklyPaceThreshold: Double?

    public init(
        cardBalance: Double,
        cashBalance: Double,
        defaultCurrencyCode: String? = nil,
        lowBalanceThreshold: Double? = nil,
        weeklyPaceThreshold: Double? = nil
    ) {
        self.cardBalance = cardBalance
        self.cashBalance = cashBalance
        self.defaultCurrencyCode = defaultCurrencyCode
        self.lowBalanceThreshold = lowBalanceThreshold
        self.weeklyPaceThreshold = weeklyPaceThreshold
    }
}

public struct FinanceCategoryCreateInput: Sendable, Equatable, Hashable {
    public let name: String
    public let iconName: String

    public init(name: String, iconName: String) {
        self.name = name
        self.iconName = iconName
    }
}

public struct FinanceCategoryUpdateInput: Sendable, Equatable, Hashable {
    public var name: String?
    public var iconName: String?

    public init(name: String? = nil, iconName: String? = nil) {
        self.name = name
        self.iconName = iconName
    }
}

public struct FinanceRecurringCreateInput: Sendable, Equatable, Hashable {
    public let title: String
    public let amount: Double
    public let currencyCode: String?
    public let categoryId: String
    public let paymentMethod: FinancePaymentMethod
    public let cadenceType: FinanceRecurringCadenceType
    public let cadenceInterval: Int?
    public let nextDueDate: String
    public let startDate: String
    public let endDate: String?
    public let note: String?

    public init(
        title: String,
        amount: Double,
        currencyCode: String? = nil,
        categoryId: String,
        paymentMethod: FinancePaymentMethod,
        cadenceType: FinanceRecurringCadenceType,
        cadenceInterval: Int? = nil,
        nextDueDate: String,
        startDate: String,
        endDate: String? = nil,
        note: String? = nil
    ) {
        self.title = title
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryId = categoryId
        self.paymentMethod = paymentMethod
        self.cadenceType = cadenceType
        self.cadenceInterval = cadenceInterval
        self.nextDueDate = nextDueDate
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
    }
}

public struct FinanceRecurringUpdateInput: Sendable, Equatable, Hashable {
    public var title: String?
    public var amount: Double?
    public var categoryId: String?
    public var paymentMethod: FinancePaymentMethod?
    public var cadenceType: FinanceRecurringCadenceType?
    public var cadenceInterval: Int?
    public var nextDueDate: String?
    public var startDate: String?
    public var endDate: String?
    public var note: String?
    public var isActive: Bool?

    public init(
        title: String? = nil,
        amount: Double? = nil,
        categoryId: String? = nil,
        paymentMethod: FinancePaymentMethod? = nil,
        cadenceType: FinanceRecurringCadenceType? = nil,
        cadenceInterval: Int? = nil,
        nextDueDate: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        note: String? = nil,
        isActive: Bool? = nil
    ) {
        self.title = title
        self.amount = amount
        self.categoryId = categoryId
        self.paymentMethod = paymentMethod
        self.cadenceType = cadenceType
        self.cadenceInterval = cadenceInterval
        self.nextDueDate = nextDueDate
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
        self.isActive = isActive
    }
}

public struct FinanceVoiceParseResult: Sendable, Equatable, Hashable {
    public let transcript: String
    public let input: FinanceTransactionWriteInput
    public let confidence: FinanceVoiceParseConfidence

    public init(
        transcript: String,
        input: FinanceTransactionWriteInput,
        confidence: FinanceVoiceParseConfidence
    ) {
        self.transcript = transcript
        self.input = input
        self.confidence = confidence
    }
}
