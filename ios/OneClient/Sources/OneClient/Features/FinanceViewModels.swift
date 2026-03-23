import Foundation
import SwiftUI

private func financeUserFacingError(_ error: Error) -> String {
    if let apiError = error as? APIError {
        switch apiError {
        case .unauthorized:
            return "Session ended on this device. Continue to resume your saved profile."
        case .transport:
            return "Local data store is unavailable. Restart the app and try again."
        case .server(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .decoding:
            return "Received an unexpected response. Please update the app or try again."
        case .conflict:
            return "Data conflict detected. Reloading your latest data."
        }
    }
    return String(describing: error)
}

@MainActor
public final class FinanceViewModel: ObservableObject {
    @Published public private(set) var homeSnapshot: FinanceHomeSnapshot?
    @Published public private(set) var transactionSections: [FinanceTransactionDaySection] = []
    @Published public private(set) var categories: [FinanceCategory] = []
    @Published public private(set) var analyticsSnapshot: FinanceAnalyticsSnapshot?
    @Published public private(set) var recurringOverview: FinanceRecurringOverview?
    @Published public var selectedAnalyticsPeriod: FinanceAnalyticsPeriod = .week
    @Published public private(set) var pendingAnalyticsPeriod: FinanceAnalyticsPeriod?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isMutating = false
    @Published public private(set) var isSwitchingAnalyticsPeriod = false
    @Published public private(set) var errorMessage: String?

    private let repository: FinanceRepository
    private var activeAnalyticsLoadTask: Task<FinanceAnalyticsSnapshot, Error>?
    private var activeAnalyticsLoadID = UUID()

    public init(repository: FinanceRepository) {
        self.repository = repository
    }

    public var activeCategories: [FinanceCategory] {
        categories.filter { !$0.isArchived }
    }

    public var archivedCategories: [FinanceCategory] {
        categories.filter(\.isArchived)
    }

    public var suggestedPaymentMethod: FinancePaymentMethod {
        homeSnapshot?.suggestedPaymentMethod ?? .card
    }

    public var needsBalanceSetup: Bool {
        guard let balanceState = homeSnapshot?.balanceState else {
            return false
        }
        return abs(balanceState.totalBalance) < 0.009 && transactionSections.isEmpty
    }

    public func refreshAll(weekStart: Int) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let home = repository.loadHome(weekStart: weekStart)
            async let sections = repository.loadTransactionSections()
            async let categories = repository.loadCategories()
            async let analytics = repository.loadAnalytics(period: selectedAnalyticsPeriod, weekStart: weekStart)
            async let recurring = repository.loadRecurringOverview()
            let snapshot = try await home
            let sectionValues = try await sections
            let categoryValues = try await categories
            let analyticsValue = try await analytics
            let recurringValue = try await recurring
            withAnimation(OneMotion.animation(.calmRefresh)) {
                homeSnapshot = snapshot
                transactionSections = sectionValues
                self.categories = categoryValues
                analyticsSnapshot = analyticsValue
                recurringOverview = recurringValue
            }
            errorMessage = nil
        } catch {
            errorMessage = financeUserFacingError(error)
        }
    }

    public func selectAnalyticsPeriod(_ period: FinanceAnalyticsPeriod, weekStart: Int) async {
        let loadID = UUID()

        activeAnalyticsLoadID = loadID
        activeAnalyticsLoadTask?.cancel()
        pendingAnalyticsPeriod = period
        isSwitchingAnalyticsPeriod = true

        let repository = self.repository
        let task = Task<FinanceAnalyticsSnapshot, Error> {
            let next = try await repository.loadAnalytics(period: period, weekStart: weekStart)
            try Task.checkCancellation()
            return next
        }
        activeAnalyticsLoadTask = task

        do {
            let next = try await task.value
            guard activeAnalyticsLoadID == loadID else {
                return
            }
            withAnimation(OneMotion.animation(.stateChange)) {
                selectedAnalyticsPeriod = period
                analyticsSnapshot = next
            }
            pendingAnalyticsPeriod = nil
            isSwitchingAnalyticsPeriod = false
            OneHaptics.shared.trigger(.periodSwitched)
            errorMessage = nil
        } catch is CancellationError {
            guard activeAnalyticsLoadID == loadID else {
                return
            }
            pendingAnalyticsPeriod = nil
            isSwitchingAnalyticsPeriod = false
        } catch {
            guard activeAnalyticsLoadID == loadID else {
                return
            }
            pendingAnalyticsPeriod = nil
            isSwitchingAnalyticsPeriod = false
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = financeUserFacingError(error)
        }
    }

    @discardableResult
    public func saveBalance(_ input: FinanceBalanceUpdateInput, weekStart: Int) async -> Bool {
        await performMutation(weekStart: weekStart) {
            _ = try await self.repository.saveBalance(input)
        }
    }

    @discardableResult
    public func createTransaction(_ input: FinanceTransactionWriteInput, weekStart: Int) async -> FinanceTransaction? {
        var created: FinanceTransaction?
        let success = await performMutation(weekStart: weekStart) {
            created = try await self.repository.createTransaction(input)
        }
        return success ? created : nil
    }

    @discardableResult
    public func updateTransaction(id: String, input: FinanceTransactionWriteInput, weekStart: Int) async -> FinanceTransaction? {
        var updated: FinanceTransaction?
        let success = await performMutation(weekStart: weekStart) {
            updated = try await self.repository.updateTransaction(id: id, input: input)
        }
        return success ? updated : nil
    }

    public func duplicateTransaction(id: String, weekStart: Int) async {
        _ = await performMutation(weekStart: weekStart) {
            _ = try await self.repository.duplicateTransaction(id: id)
        }
    }

    public func deleteTransaction(id: String, weekStart: Int) async {
        _ = await performMutation(weekStart: weekStart) {
            try await self.repository.deleteTransaction(id: id)
        }
    }

    @discardableResult
    public func createCategory(_ input: FinanceCategoryCreateInput, weekStart: Int) async -> FinanceCategory? {
        var category: FinanceCategory?
        let success = await performMutation(weekStart: weekStart) {
            category = try await self.repository.createCategory(input)
        }
        return success ? category : nil
    }

    @discardableResult
    public func updateCategory(id: String, input: FinanceCategoryUpdateInput, weekStart: Int) async -> FinanceCategory? {
        var category: FinanceCategory?
        let success = await performMutation(weekStart: weekStart) {
            category = try await self.repository.updateCategory(id: id, input: input)
        }
        return success ? category : nil
    }

    public func setCategoryArchived(id: String, isArchived: Bool, weekStart: Int) async {
        _ = await performMutation(weekStart: weekStart) {
            _ = try await self.repository.setCategoryArchived(id: id, isArchived: isArchived)
        }
    }

    @discardableResult
    public func createRecurring(_ input: FinanceRecurringCreateInput, weekStart: Int) async -> RecurringFinanceTransaction? {
        var recurring: RecurringFinanceTransaction?
        let success = await performMutation(weekStart: weekStart) {
            recurring = try await self.repository.createRecurring(input)
        }
        return success ? recurring : nil
    }

    @discardableResult
    public func updateRecurring(id: String, input: FinanceRecurringUpdateInput, weekStart: Int) async -> RecurringFinanceTransaction? {
        var recurring: RecurringFinanceTransaction?
        let success = await performMutation(weekStart: weekStart) {
            recurring = try await self.repository.updateRecurring(id: id, input: input)
        }
        return success ? recurring : nil
    }

    public func setRecurringActive(id: String, isActive: Bool, weekStart: Int) async {
        _ = await performMutation(weekStart: weekStart) {
            _ = try await self.repository.setRecurringActive(id: id, isActive: isActive)
        }
    }

    public func deleteRecurring(id: String, weekStart: Int) async {
        _ = await performMutation(weekStart: weekStart) {
            try await self.repository.deleteRecurring(id: id)
        }
    }

    @discardableResult
    private func performMutation(
        weekStart: Int,
        action: @escaping () async throws -> Void
    ) async -> Bool {
        isMutating = true
        defer { isMutating = false }
        do {
            try await action()
            OneHaptics.shared.trigger(.saveSucceeded)
            await refreshAll(weekStart: weekStart)
            errorMessage = nil
            return true
        } catch {
            OneHaptics.shared.trigger(.saveFailed)
            errorMessage = financeUserFacingError(error)
            return false
        }
    }
}
