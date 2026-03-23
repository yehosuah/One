import Foundation

#if canImport(SwiftData)
import SwiftData
#endif

public protocol FinanceRepository: Sendable {
    func loadHome(weekStart: Int) async throws -> FinanceHomeSnapshot
    func loadTransactionSections() async throws -> [FinanceTransactionDaySection]
    func loadCategories() async throws -> [FinanceCategory]
    func loadAnalytics(period: FinanceAnalyticsPeriod, weekStart: Int) async throws -> FinanceAnalyticsSnapshot
    func loadRecurringOverview() async throws -> FinanceRecurringOverview
    func saveBalance(_ input: FinanceBalanceUpdateInput) async throws -> FinanceBalanceState
    func createTransaction(_ input: FinanceTransactionWriteInput) async throws -> FinanceTransaction
    func updateTransaction(id: String, input: FinanceTransactionWriteInput) async throws -> FinanceTransaction
    func duplicateTransaction(id: String) async throws -> FinanceTransaction
    func deleteTransaction(id: String) async throws
    func createCategory(_ input: FinanceCategoryCreateInput) async throws -> FinanceCategory
    func updateCategory(id: String, input: FinanceCategoryUpdateInput) async throws -> FinanceCategory
    func setCategoryArchived(id: String, isArchived: Bool) async throws -> FinanceCategory
    func createRecurring(_ input: FinanceRecurringCreateInput) async throws -> RecurringFinanceTransaction
    func updateRecurring(id: String, input: FinanceRecurringUpdateInput) async throws -> RecurringFinanceTransaction
    func setRecurringActive(id: String, isActive: Bool) async throws -> RecurringFinanceTransaction
    func deleteRecurring(id: String) async throws
}

public struct NoopFinanceRepository: FinanceRepository {
    public init() {}

    public func loadHome(weekStart: Int) async throws -> FinanceHomeSnapshot {
        throw APIError.transport("Finance repository unavailable")
    }

    public func loadTransactionSections() async throws -> [FinanceTransactionDaySection] {
        throw APIError.transport("Finance repository unavailable")
    }

    public func loadCategories() async throws -> [FinanceCategory] {
        throw APIError.transport("Finance repository unavailable")
    }

    public func loadAnalytics(period: FinanceAnalyticsPeriod, weekStart: Int) async throws -> FinanceAnalyticsSnapshot {
        throw APIError.transport("Finance repository unavailable")
    }

    public func loadRecurringOverview() async throws -> FinanceRecurringOverview {
        throw APIError.transport("Finance repository unavailable")
    }

    public func saveBalance(_ input: FinanceBalanceUpdateInput) async throws -> FinanceBalanceState {
        throw APIError.transport("Finance repository unavailable")
    }

    public func createTransaction(_ input: FinanceTransactionWriteInput) async throws -> FinanceTransaction {
        throw APIError.transport("Finance repository unavailable")
    }

    public func updateTransaction(id: String, input: FinanceTransactionWriteInput) async throws -> FinanceTransaction {
        throw APIError.transport("Finance repository unavailable")
    }

    public func duplicateTransaction(id: String) async throws -> FinanceTransaction {
        throw APIError.transport("Finance repository unavailable")
    }

    public func deleteTransaction(id: String) async throws {
        throw APIError.transport("Finance repository unavailable")
    }

    public func createCategory(_ input: FinanceCategoryCreateInput) async throws -> FinanceCategory {
        throw APIError.transport("Finance repository unavailable")
    }

    public func updateCategory(id: String, input: FinanceCategoryUpdateInput) async throws -> FinanceCategory {
        throw APIError.transport("Finance repository unavailable")
    }

    public func setCategoryArchived(id: String, isArchived: Bool) async throws -> FinanceCategory {
        throw APIError.transport("Finance repository unavailable")
    }

    public func createRecurring(_ input: FinanceRecurringCreateInput) async throws -> RecurringFinanceTransaction {
        throw APIError.transport("Finance repository unavailable")
    }

    public func updateRecurring(id: String, input: FinanceRecurringUpdateInput) async throws -> RecurringFinanceTransaction {
        throw APIError.transport("Finance repository unavailable")
    }

    public func setRecurringActive(id: String, isActive: Bool) async throws -> RecurringFinanceTransaction {
        throw APIError.transport("Finance repository unavailable")
    }

    public func deleteRecurring(id: String) async throws {
        throw APIError.transport("Finance repository unavailable")
    }
}

#if canImport(SwiftData)
private enum FinanceRepositoryError: LocalizedError {
    case unauthorized
    case invalidAmount
    case missingExpenseCategory
    case missingPaymentMethod
    case invalidTransferDirection
    case recurringRequiresExpense
    case missingDueDate
    case categoryNotFound
    case transactionNotFound
    case recurringNotFound

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Finance is unavailable until a local profile is active."
        case .invalidAmount:
            return "Amount must be greater than zero."
        case .missingExpenseCategory:
            return "Choose a category before saving this expense."
        case .missingPaymentMethod:
            return "Choose how this money moved before saving."
        case .invalidTransferDirection:
            return "Transfers need different source and destination methods."
        case .recurringRequiresExpense:
            return "Recurring items support expenses only in this version."
        case .missingDueDate:
            return "A next due date is required."
        case .categoryNotFound:
            return "Category could not be found."
        case .transactionNotFound:
            return "Transaction could not be found."
        case .recurringNotFound:
            return "Recurring item could not be found."
        }
    }
}

public actor LocalFinanceRepository: FinanceRepository {
    private let container: ModelContainer
    private let sessionStore: AuthSessionStore
    private let categoryService = LocalFinanceCategoryService()
    private let recurringService = LocalFinanceRecurringService()
    private let analyticsService = LocalFinanceAnalyticsService()
    private var cachedContext: ModelContext?

    public init(container: ModelContainer, sessionStore: AuthSessionStore) {
        self.container = container
        self.sessionStore = sessionStore
    }

    private var context: ModelContext {
        if let cachedContext {
            return cachedContext
        }
        let context = ModelContext(container)
        cachedContext = context
        return context
    }

    public func loadHome(weekStart: Int) async throws -> FinanceHomeSnapshot {
        let user = try await currentUser()
        try ensureFinanceCategoriesIfNeeded(userID: user.id)
        try materializeRecurringTransactionsIfNeeded(userID: user.id, timezoneID: user.timezone)
        let categories = try financeCategories(userID: user.id)
        let transactions = try financeTransactions(userID: user.id)
        let balanceEntity = try resolvedBalanceEntity(userID: user.id)
        let recurringItems = try recurringTransactions(userID: user.id)
        let currentDateLocal = FinanceDateCoding.localDateString(from: Date(), timezoneID: user.timezone)
        return analyticsService.homeSnapshot(
            balanceState: mapBalance(balanceEntity),
            manualAdjustmentAt: balanceEntity.manualAdjustmentAt,
            categories: categories,
            transactions: transactions,
            recurringItems: recurringItems,
            currentDateLocal: currentDateLocal,
            weekStart: weekStart,
            timezoneID: user.timezone
        )
    }

    public func loadTransactionSections() async throws -> [FinanceTransactionDaySection] {
        let user = try await currentUser()
        try ensureFinanceCategoriesIfNeeded(userID: user.id)
        try materializeRecurringTransactionsIfNeeded(userID: user.id, timezoneID: user.timezone)
        return analyticsService.transactionSections(
            transactions: try financeTransactions(userID: user.id),
            timezoneID: user.timezone
        )
    }

    public func loadCategories() async throws -> [FinanceCategory] {
        let user = try await currentUser()
        try ensureFinanceCategoriesIfNeeded(userID: user.id)
        return try financeCategoryEntities(userID: user.id)
            .map(mapCategory)
            .sorted { lhs, rhs in
                if lhs.isArchived != rhs.isArchived {
                    return !lhs.isArchived
                }
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.name < rhs.name
            }
    }

    public func loadAnalytics(period: FinanceAnalyticsPeriod, weekStart: Int) async throws -> FinanceAnalyticsSnapshot {
        let user = try await currentUser()
        try ensureFinanceCategoriesIfNeeded(userID: user.id)
        try materializeRecurringTransactionsIfNeeded(userID: user.id, timezoneID: user.timezone)
        return analyticsService.analyticsSnapshot(
            period: period,
            categories: try financeCategories(userID: user.id),
            transactions: try financeTransactions(userID: user.id),
            recurringItems: try recurringTransactions(userID: user.id),
            currentDateLocal: FinanceDateCoding.localDateString(from: Date(), timezoneID: user.timezone),
            weekStart: weekStart,
            timezoneID: user.timezone
        )
    }

    public func loadRecurringOverview() async throws -> FinanceRecurringOverview {
        let user = try await currentUser()
        try materializeRecurringTransactionsIfNeeded(userID: user.id, timezoneID: user.timezone)
        return analyticsService.recurringOverview(for: try recurringTransactions(userID: user.id))
    }

    public func saveBalance(_ input: FinanceBalanceUpdateInput) async throws -> FinanceBalanceState {
        let user = try await currentUser()
        let entity = try resolvedBalanceEntity(userID: user.id)
        entity.cardBalance = input.cardBalance
        entity.cashBalance = input.cashBalance
        entity.totalBalance = input.cardBalance + input.cashBalance
        if let defaultCurrencyCode = input.defaultCurrencyCode, !defaultCurrencyCode.isEmpty {
            entity.defaultCurrencyCode = defaultCurrencyCode
        }
        entity.lowBalanceThreshold = input.lowBalanceThreshold
        entity.weeklyPaceThreshold = input.weeklyPaceThreshold
        entity.updatedAt = Date()
        entity.manualAdjustmentAt = Date()
        try save()
        return mapBalance(entity)
    }

    public func createTransaction(_ input: FinanceTransactionWriteInput) async throws -> FinanceTransaction {
        let user = try await currentUser()
        try ensureFinanceCategoriesIfNeeded(userID: user.id)
        let balanceEntity = try resolvedBalanceEntity(userID: user.id)
        let transaction = try buildTransaction(
            existing: nil,
            input: input,
            defaultCurrencyCode: balanceEntity.defaultCurrencyCode,
            recurringInstanceId: nil
        )
        if let categoryId = transaction.categoryId {
            try ensureCategoryExists(id: categoryId, userID: user.id)
        }
        try applyBalanceDelta(for: transaction, to: balanceEntity, direction: .forward)
        context.insert(makeTransactionEntity(transaction, userID: user.id))
        try save()
        return transaction
    }

    public func updateTransaction(id: String, input: FinanceTransactionWriteInput) async throws -> FinanceTransaction {
        let user = try await currentUser()
        guard let entity = try financeTransactionEntities(userID: user.id).first(where: { $0.id == id }) else {
            throw FinanceRepositoryError.transactionNotFound
        }
        let existing = mapTransaction(entity)
        let balanceEntity = try resolvedBalanceEntity(userID: user.id)
        let updated = try buildTransaction(
            existing: existing,
            input: input,
            defaultCurrencyCode: existing.currencyCode,
            recurringInstanceId: existing.recurringInstanceId
        )
        if let categoryId = updated.categoryId {
            try ensureCategoryExists(id: categoryId, userID: user.id)
        }
        try applyBalanceDelta(for: existing, to: balanceEntity, direction: .reverse)
        try applyBalanceDelta(for: updated, to: balanceEntity, direction: .forward)
        hydrate(entity: entity, from: updated)
        try save()
        return updated
    }

    public func duplicateTransaction(id: String) async throws -> FinanceTransaction {
        let user = try await currentUser()
        guard let original = try financeTransactions(userID: user.id).first(where: { $0.id == id }) else {
            throw FinanceRepositoryError.transactionNotFound
        }
        return try await createTransaction(
            FinanceTransactionWriteInput(
                type: original.type,
                amount: original.amount,
                currencyCode: original.currencyCode,
                categoryId: original.categoryId,
                paymentMethod: original.paymentMethod,
                transferCounterpartPaymentMethod: original.transferCounterpartPaymentMethod,
                note: original.note,
                occurredAt: Date(),
                source: .manual
            )
        )
    }

    public func deleteTransaction(id: String) async throws {
        let user = try await currentUser()
        guard let entity = try financeTransactionEntities(userID: user.id).first(where: { $0.id == id }) else {
            return
        }
        let existing = mapTransaction(entity)
        let balanceEntity = try resolvedBalanceEntity(userID: user.id)
        try applyBalanceDelta(for: existing, to: balanceEntity, direction: .reverse)
        entity.deletedAt = Date()
        entity.updatedAt = Date()
        try save()
    }

    public func createCategory(_ input: FinanceCategoryCreateInput) async throws -> FinanceCategory {
        let user = try await currentUser()
        let trimmedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let sortOrder = (try financeCategoryEntities(userID: user.id).map(\.sortOrder).max() ?? -1) + 1
        let category = FinanceCategory(
            id: UUID().uuidString,
            name: trimmedName.isEmpty ? "Custom" : trimmedName,
            iconName: input.iconName.isEmpty ? "tag.fill" : input.iconName,
            isCustom: true,
            isArchived: false,
            sortOrder: sortOrder,
            createdAt: now,
            updatedAt: now
        )
        context.insert(
            LocalFinanceCategoryEntity(
                id: category.id,
                userId: user.id,
                name: category.name,
                iconName: category.iconName,
                isCustom: true,
                isArchived: false,
                sortOrder: sortOrder,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
        )
        try save()
        return category
    }

    public func updateCategory(id: String, input: FinanceCategoryUpdateInput) async throws -> FinanceCategory {
        let user = try await currentUser()
        guard let entity = try financeCategoryEntities(userID: user.id).first(where: { $0.id == id }) else {
            throw FinanceRepositoryError.categoryNotFound
        }
        if let name = input.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            entity.name = name
        }
        if let iconName = input.iconName, !iconName.isEmpty {
            entity.iconName = iconName
        }
        entity.updatedAt = Date()
        try save()
        return mapCategory(entity)
    }

    public func setCategoryArchived(id: String, isArchived: Bool) async throws -> FinanceCategory {
        let user = try await currentUser()
        guard let entity = try financeCategoryEntities(userID: user.id).first(where: { $0.id == id }) else {
            throw FinanceRepositoryError.categoryNotFound
        }
        entity.isArchived = isArchived
        entity.updatedAt = Date()
        try save()
        return mapCategory(entity)
    }

    public func createRecurring(_ input: FinanceRecurringCreateInput) async throws -> RecurringFinanceTransaction {
        let user = try await currentUser()
        try ensureFinanceCategoriesIfNeeded(userID: user.id)
        try ensureCategoryExists(id: input.categoryId, userID: user.id)
        let now = Date()
        let recurring = try buildRecurring(existing: nil, input: input, defaultCurrencyCode: try resolvedBalanceEntity(userID: user.id).defaultCurrencyCode)
        context.insert(
            LocalRecurringFinanceTransactionEntity(
                id: recurring.id,
                userId: user.id,
                title: recurring.title,
                amount: recurring.amount,
                currencyCode: recurring.currencyCode,
                categoryId: recurring.categoryId,
                paymentMethod: recurring.paymentMethod.rawValue,
                cadenceType: recurring.cadenceType.rawValue,
                cadenceInterval: recurring.cadenceInterval,
                nextDueDate: recurring.nextDueDate,
                startDate: recurring.startDate,
                endDate: recurring.endDate,
                note: recurring.note,
                isActive: recurring.isActive,
                createdAt: recurring.createdAt,
                updatedAt: now,
                deletedAt: nil
            )
        )
        try save()
        try materializeRecurringTransactionsIfNeeded(userID: user.id, timezoneID: user.timezone)
        return recurring
    }

    public func updateRecurring(id: String, input: FinanceRecurringUpdateInput) async throws -> RecurringFinanceTransaction {
        let user = try await currentUser()
        guard let entity = try recurringEntities(userID: user.id).first(where: { $0.id == id }) else {
            throw FinanceRepositoryError.recurringNotFound
        }
        let updated = try buildRecurring(
            existing: mapRecurring(entity),
            input: input,
            defaultCurrencyCode: entity.currencyCode
        )
        try ensureCategoryExists(id: updated.categoryId, userID: user.id)
        hydrate(entity: entity, from: updated)
        try save()
        try materializeRecurringTransactionsIfNeeded(userID: user.id, timezoneID: user.timezone)
        return updated
    }

    public func setRecurringActive(id: String, isActive: Bool) async throws -> RecurringFinanceTransaction {
        let user = try await currentUser()
        guard let entity = try recurringEntities(userID: user.id).first(where: { $0.id == id }) else {
            throw FinanceRepositoryError.recurringNotFound
        }
        entity.isActive = isActive
        entity.updatedAt = Date()
        try save()
        return mapRecurring(entity)
    }

    public func deleteRecurring(id: String) async throws {
        let user = try await currentUser()
        guard let entity = try recurringEntities(userID: user.id).first(where: { $0.id == id }) else {
            return
        }
        entity.deletedAt = Date()
        entity.updatedAt = Date()
        try save()
    }

    private func materializeRecurringTransactionsIfNeeded(userID: String, timezoneID: String) throws {
        let recurringItems = try recurringTransactions(userID: userID)
        guard !recurringItems.isEmpty else {
            return
        }
        let materialization = recurringService.materializeDueTransactions(
            recurringItems: recurringItems,
            existingTransactions: try financeTransactions(userID: userID),
            currentDateLocal: FinanceDateCoding.localDateString(from: Date(), timezoneID: timezoneID),
            timezoneID: timezoneID
        )
        guard !materialization.transactions.isEmpty || !materialization.updatedRecurringItems.isEmpty else {
            return
        }

        let balanceEntity = try resolvedBalanceEntity(userID: userID)
        for transaction in materialization.transactions {
            try applyBalanceDelta(for: transaction, to: balanceEntity, direction: .forward)
            context.insert(makeTransactionEntity(transaction, userID: userID))
        }
        for updatedRecurring in materialization.updatedRecurringItems {
            guard let entity = try recurringEntities(userID: userID).first(where: { $0.id == updatedRecurring.id }) else {
                continue
            }
            hydrate(entity: entity, from: updatedRecurring)
        }
        try save()
    }

    private func buildTransaction(
        existing: FinanceTransaction?,
        input: FinanceTransactionWriteInput,
        defaultCurrencyCode: String,
        recurringInstanceId: String?
    ) throws -> FinanceTransaction {
        let amount = input.amount ?? existing?.amount
        guard let amount, amount > 0 else {
            throw FinanceRepositoryError.invalidAmount
        }
        let type = input.type
        let categoryId = input.categoryId ?? existing?.categoryId
        if type == .expense && (categoryId?.isEmpty ?? true) {
            throw FinanceRepositoryError.missingExpenseCategory
        }
        switch type {
        case .expense, .income:
            guard (input.paymentMethod ?? existing?.paymentMethod) != nil else {
                throw FinanceRepositoryError.missingPaymentMethod
            }
        case .transfer:
            guard let source = input.paymentMethod ?? existing?.paymentMethod,
                  let destination = input.transferCounterpartPaymentMethod ?? existing?.transferCounterpartPaymentMethod else {
                throw FinanceRepositoryError.missingPaymentMethod
            }
            guard source != destination else {
                throw FinanceRepositoryError.invalidTransferDirection
            }
        }

        let now = Date()
        return FinanceTransaction(
            id: existing?.id ?? UUID().uuidString,
            type: type,
            amount: amount,
            currencyCode: input.currencyCode ?? existing?.currencyCode ?? defaultCurrencyCode,
            categoryId: categoryId,
            paymentMethod: input.paymentMethod ?? existing?.paymentMethod,
            transferCounterpartPaymentMethod: type == .transfer
                ? (input.transferCounterpartPaymentMethod ?? existing?.transferCounterpartPaymentMethod)
                : nil,
            note: input.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? existing?.note,
            occurredAt: input.occurredAt ?? existing?.occurredAt ?? now,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            source: existing?.source ?? input.source,
            recurringInstanceId: recurringInstanceId
        )
    }

    private func buildRecurring(
        existing: RecurringFinanceTransaction?,
        input: FinanceRecurringCreateInput,
        defaultCurrencyCode: String
    ) throws -> RecurringFinanceTransaction {
        guard input.amount > 0 else {
            throw FinanceRepositoryError.invalidAmount
        }
        guard !input.nextDueDate.isEmpty else {
            throw FinanceRepositoryError.missingDueDate
        }
        let now = Date()
        return RecurringFinanceTransaction(
            id: existing?.id ?? UUID().uuidString,
            title: input.title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: input.amount,
            currencyCode: input.currencyCode ?? existing?.currencyCode ?? defaultCurrencyCode,
            categoryId: input.categoryId,
            paymentMethod: input.paymentMethod,
            cadenceType: input.cadenceType,
            cadenceInterval: input.cadenceInterval,
            nextDueDate: input.nextDueDate,
            startDate: input.startDate,
            endDate: input.endDate,
            note: input.note?.trimmingCharacters(in: .whitespacesAndNewlines),
            isActive: existing?.isActive ?? true,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }

    private func buildRecurring(
        existing: RecurringFinanceTransaction,
        input: FinanceRecurringUpdateInput,
        defaultCurrencyCode: String
    ) throws -> RecurringFinanceTransaction {
        let amount = input.amount ?? existing.amount
        guard amount > 0 else {
            throw FinanceRepositoryError.invalidAmount
        }
        let nextDueDate = input.nextDueDate ?? existing.nextDueDate
        guard !nextDueDate.isEmpty else {
            throw FinanceRepositoryError.missingDueDate
        }
        let trimmedTitle = input.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RecurringFinanceTransaction(
            id: existing.id,
            title: (trimmedTitle?.isEmpty == false ? trimmedTitle : nil) ?? existing.title,
            amount: amount,
            currencyCode: defaultCurrencyCode,
            categoryId: input.categoryId ?? existing.categoryId,
            paymentMethod: input.paymentMethod ?? existing.paymentMethod,
            cadenceType: input.cadenceType ?? existing.cadenceType,
            cadenceInterval: input.cadenceInterval ?? existing.cadenceInterval,
            nextDueDate: nextDueDate,
            startDate: input.startDate ?? existing.startDate,
            endDate: input.endDate ?? existing.endDate,
            note: input.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? existing.note,
            isActive: input.isActive ?? existing.isActive,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
    }

    private func applyBalanceDelta(
        for transaction: FinanceTransaction,
        to balanceEntity: LocalFinanceBalanceEntity,
        direction: BalanceDirection
    ) throws {
        let multiplier = direction == .forward ? 1.0 : -1.0
        switch transaction.type {
        case .expense:
            guard let paymentMethod = transaction.paymentMethod else {
                throw FinanceRepositoryError.missingPaymentMethod
            }
            mutate(balanceEntity: balanceEntity, paymentMethod: paymentMethod, delta: -transaction.amount * multiplier)
        case .income:
            guard let paymentMethod = transaction.paymentMethod else {
                throw FinanceRepositoryError.missingPaymentMethod
            }
            mutate(balanceEntity: balanceEntity, paymentMethod: paymentMethod, delta: transaction.amount * multiplier)
        case .transfer:
            guard let source = transaction.paymentMethod,
                  let destination = transaction.transferCounterpartPaymentMethod,
                  source != destination else {
                throw FinanceRepositoryError.invalidTransferDirection
            }
            mutate(balanceEntity: balanceEntity, paymentMethod: source, delta: -transaction.amount * multiplier)
            mutate(balanceEntity: balanceEntity, paymentMethod: destination, delta: transaction.amount * multiplier)
        }
        balanceEntity.totalBalance = balanceEntity.cardBalance + balanceEntity.cashBalance
        balanceEntity.updatedAt = Date()
    }

    private func mutate(balanceEntity: LocalFinanceBalanceEntity, paymentMethod: FinancePaymentMethod, delta: Double) {
        switch paymentMethod {
        case .cash:
            balanceEntity.cashBalance += delta
        case .card:
            balanceEntity.cardBalance += delta
        }
    }

    private func resolvedBalanceEntity(userID: String) throws -> LocalFinanceBalanceEntity {
        if let existing = try financeBalanceEntity(userID: userID) {
            return existing
        }
        let now = Date()
        let entity = LocalFinanceBalanceEntity(
            userId: userID,
            totalBalance: 0,
            cardBalance: 0,
            cashBalance: 0,
            defaultCurrencyCode: categoryService.defaultCurrencyCode(),
            lowBalanceThreshold: nil,
            weeklyPaceThreshold: nil,
            updatedAt: now,
            manualAdjustmentAt: nil
        )
        context.insert(entity)
        try save()
        return entity
    }

    private func ensureFinanceCategoriesIfNeeded(userID: String) throws {
        guard try financeCategoryEntities(userID: userID).isEmpty else {
            return
        }
        let now = Date()
        for (index, template) in categoryService.starterTemplates.enumerated() {
            context.insert(
                LocalFinanceCategoryEntity(
                    id: UUID().uuidString,
                    userId: userID,
                    name: template.name,
                    iconName: template.iconName,
                    isCustom: false,
                    isArchived: false,
                    sortOrder: index,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil
                )
            )
        }
        try save()
    }

    private func ensureCategoryExists(id: String, userID: String) throws {
        guard try financeCategoryEntities(userID: userID).contains(where: { $0.id == id }) else {
            throw FinanceRepositoryError.categoryNotFound
        }
    }

    private func financeTransactions(userID: String) throws -> [FinanceTransaction] {
        try financeTransactionEntities(userID: userID)
            .map(mapTransaction)
            .sorted { lhs, rhs in
                if lhs.occurredAt != rhs.occurredAt {
                    return lhs.occurredAt > rhs.occurredAt
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private func financeCategories(userID: String) throws -> [FinanceCategory] {
        try financeCategoryEntities(userID: userID).map(mapCategory)
    }

    private func recurringTransactions(userID: String) throws -> [RecurringFinanceTransaction] {
        try recurringEntities(userID: userID).map(mapRecurring)
    }

    private func financeTransactionEntities(userID: String) throws -> [LocalFinanceTransactionEntity] {
        try context.fetch(FetchDescriptor<LocalFinanceTransactionEntity>())
            .filter { $0.userId == userID && $0.deletedAt == nil }
    }

    private func financeCategoryEntities(userID: String) throws -> [LocalFinanceCategoryEntity] {
        try context.fetch(FetchDescriptor<LocalFinanceCategoryEntity>())
            .filter { $0.userId == userID && $0.deletedAt == nil }
    }

    private func financeBalanceEntity(userID: String) throws -> LocalFinanceBalanceEntity? {
        try context.fetch(FetchDescriptor<LocalFinanceBalanceEntity>())
            .first(where: { $0.userId == userID })
    }

    private func recurringEntities(userID: String) throws -> [LocalRecurringFinanceTransactionEntity] {
        try context.fetch(FetchDescriptor<LocalRecurringFinanceTransactionEntity>())
            .filter { $0.userId == userID && $0.deletedAt == nil }
    }

    private func currentUser() async throws -> (id: String, timezone: String) {
        guard let session = await ensuredSessionTokens(),
              let entity = try activeUserEntity(userID: session.accessToken) else {
            throw FinanceRepositoryError.unauthorized
        }
        return (entity.id, entity.timezone)
    }

    private func ensuredSessionTokens() async -> AuthSessionTokens? {
        if let session = await sessionStore.read() {
            return session
        }
        guard await sessionStore.isRecoverySuppressed() == false,
              let entity = try? activeUserEntities().first else {
            return nil
        }
        let session = AuthSessionTokens(
            accessToken: entity.id,
            refreshToken: "offline-\(entity.id)",
            expiresAt: nil
        )
        try? await sessionStore.write(session)
        return session
    }

    private func activeUserEntities() throws -> [LocalUserEntity] {
        try context.fetch(FetchDescriptor<LocalUserEntity>())
            .filter { $0.deletedAt == nil }
            .sorted {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.createdAt > $1.createdAt
            }
    }

    private func activeUserEntity(userID: String) throws -> LocalUserEntity? {
        try activeUserEntities().first(where: { $0.id == userID })
    }

    private func makeTransactionEntity(_ transaction: FinanceTransaction, userID: String) -> LocalFinanceTransactionEntity {
        LocalFinanceTransactionEntity(
            id: transaction.id,
            userId: userID,
            type: transaction.type.rawValue,
            amount: transaction.amount,
            currencyCode: transaction.currencyCode,
            categoryId: transaction.categoryId,
            paymentMethod: transaction.paymentMethod?.rawValue,
            transferCounterpartPaymentMethod: transaction.transferCounterpartPaymentMethod?.rawValue,
            note: transaction.note,
            occurredAt: transaction.occurredAt,
            createdAt: transaction.createdAt,
            updatedAt: transaction.updatedAt,
            source: transaction.source.rawValue,
            recurringInstanceId: transaction.recurringInstanceId,
            deletedAt: nil
        )
    }

    private func hydrate(entity: LocalFinanceTransactionEntity, from transaction: FinanceTransaction) {
        entity.type = transaction.type.rawValue
        entity.amount = transaction.amount
        entity.currencyCode = transaction.currencyCode
        entity.categoryId = transaction.categoryId
        entity.paymentMethod = transaction.paymentMethod?.rawValue
        entity.transferCounterpartPaymentMethod = transaction.transferCounterpartPaymentMethod?.rawValue
        entity.note = transaction.note
        entity.occurredAt = transaction.occurredAt
        entity.updatedAt = transaction.updatedAt
        entity.source = transaction.source.rawValue
    }

    private func hydrate(entity: LocalRecurringFinanceTransactionEntity, from recurring: RecurringFinanceTransaction) {
        entity.title = recurring.title
        entity.amount = recurring.amount
        entity.currencyCode = recurring.currencyCode
        entity.categoryId = recurring.categoryId
        entity.paymentMethod = recurring.paymentMethod.rawValue
        entity.cadenceType = recurring.cadenceType.rawValue
        entity.cadenceInterval = recurring.cadenceInterval
        entity.nextDueDate = recurring.nextDueDate
        entity.startDate = recurring.startDate
        entity.endDate = recurring.endDate
        entity.note = recurring.note
        entity.isActive = recurring.isActive
        entity.updatedAt = recurring.updatedAt
    }

    private func mapTransaction(_ entity: LocalFinanceTransactionEntity) -> FinanceTransaction {
        FinanceTransaction(
            id: entity.id,
            type: FinanceTransactionType(rawValue: entity.type) ?? .expense,
            amount: entity.amount,
            currencyCode: entity.currencyCode,
            categoryId: entity.categoryId,
            paymentMethod: entity.paymentMethod.flatMap(FinancePaymentMethod.init(rawValue:)),
            transferCounterpartPaymentMethod: entity.transferCounterpartPaymentMethod.flatMap(FinancePaymentMethod.init(rawValue:)),
            note: entity.note,
            occurredAt: entity.occurredAt,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            source: FinanceTransactionSource(rawValue: entity.source) ?? .manual,
            recurringInstanceId: entity.recurringInstanceId
        )
    }

    private func mapCategory(_ entity: LocalFinanceCategoryEntity) -> FinanceCategory {
        FinanceCategory(
            id: entity.id,
            name: entity.name,
            iconName: entity.iconName,
            isCustom: entity.isCustom,
            isArchived: entity.isArchived,
            sortOrder: entity.sortOrder,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    private func mapBalance(_ entity: LocalFinanceBalanceEntity) -> FinanceBalanceState {
        FinanceBalanceState(
            totalBalance: entity.totalBalance,
            cardBalance: entity.cardBalance,
            cashBalance: entity.cashBalance,
            defaultCurrencyCode: entity.defaultCurrencyCode,
            lowBalanceThreshold: entity.lowBalanceThreshold,
            weeklyPaceThreshold: entity.weeklyPaceThreshold,
            updatedAt: entity.updatedAt
        )
    }

    private func mapRecurring(_ entity: LocalRecurringFinanceTransactionEntity) -> RecurringFinanceTransaction {
        RecurringFinanceTransaction(
            id: entity.id,
            title: entity.title,
            amount: entity.amount,
            currencyCode: entity.currencyCode,
            categoryId: entity.categoryId,
            paymentMethod: FinancePaymentMethod(rawValue: entity.paymentMethod) ?? .card,
            cadenceType: FinanceRecurringCadenceType(rawValue: entity.cadenceType) ?? .monthly,
            cadenceInterval: entity.cadenceInterval,
            nextDueDate: entity.nextDueDate,
            startDate: entity.startDate,
            endDate: entity.endDate,
            note: entity.note,
            isActive: entity.isActive,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    private func save() throws {
        try context.save()
    }
}

private enum BalanceDirection {
    case forward
    case reverse
}
#endif
