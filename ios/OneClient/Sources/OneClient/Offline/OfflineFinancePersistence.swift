import Foundation

#if canImport(SwiftData)
import SwiftData

@Model
final class LocalFinanceTransactionEntity {
    @Attribute(.unique) var id: String
    var userId: String
    var type: String
    var amount: Double
    var currencyCode: String
    var categoryId: String?
    var paymentMethod: String?
    var transferCounterpartPaymentMethod: String?
    var note: String?
    var occurredAt: Date
    var createdAt: Date
    var updatedAt: Date
    var source: String
    var recurringInstanceId: String?
    var deletedAt: Date?

    init(
        id: String,
        userId: String,
        type: String,
        amount: Double,
        currencyCode: String,
        categoryId: String?,
        paymentMethod: String?,
        transferCounterpartPaymentMethod: String?,
        note: String?,
        occurredAt: Date,
        createdAt: Date,
        updatedAt: Date,
        source: String,
        recurringInstanceId: String?,
        deletedAt: Date?
    ) {
        self.id = id
        self.userId = userId
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
        self.deletedAt = deletedAt
    }
}

@Model
final class LocalFinanceCategoryEntity {
    @Attribute(.unique) var id: String
    var userId: String
    var name: String
    var iconName: String
    var isCustom: Bool
    var isArchived: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: String,
        userId: String,
        name: String,
        iconName: String,
        isCustom: Bool,
        isArchived: Bool,
        sortOrder: Int,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.iconName = iconName
        self.isCustom = isCustom
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class LocalFinanceBalanceEntity {
    @Attribute(.unique) var userId: String
    var totalBalance: Double
    var cardBalance: Double
    var cashBalance: Double
    var defaultCurrencyCode: String
    var lowBalanceThreshold: Double?
    var weeklyPaceThreshold: Double?
    var updatedAt: Date
    var manualAdjustmentAt: Date?

    init(
        userId: String,
        totalBalance: Double,
        cardBalance: Double,
        cashBalance: Double,
        defaultCurrencyCode: String,
        lowBalanceThreshold: Double?,
        weeklyPaceThreshold: Double?,
        updatedAt: Date,
        manualAdjustmentAt: Date?
    ) {
        self.userId = userId
        self.totalBalance = totalBalance
        self.cardBalance = cardBalance
        self.cashBalance = cashBalance
        self.defaultCurrencyCode = defaultCurrencyCode
        self.lowBalanceThreshold = lowBalanceThreshold
        self.weeklyPaceThreshold = weeklyPaceThreshold
        self.updatedAt = updatedAt
        self.manualAdjustmentAt = manualAdjustmentAt
    }
}

@Model
final class LocalRecurringFinanceTransactionEntity {
    @Attribute(.unique) var id: String
    var userId: String
    var title: String
    var amount: Double
    var currencyCode: String
    var categoryId: String
    var paymentMethod: String
    var cadenceType: String
    var cadenceInterval: Int?
    var nextDueDate: String
    var startDate: String
    var endDate: String?
    var note: String?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: String,
        userId: String,
        title: String,
        amount: Double,
        currencyCode: String,
        categoryId: String,
        paymentMethod: String,
        cadenceType: String,
        cadenceInterval: Int?,
        nextDueDate: String,
        startDate: String,
        endDate: String?,
        note: String?,
        isActive: Bool,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?
    ) {
        self.id = id
        self.userId = userId
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
        self.deletedAt = deletedAt
    }
}
#endif
