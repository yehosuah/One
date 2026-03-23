import Foundation

enum OneAddContext: Equatable {
    case app
    case finance

    init(tab: OneAppShell.Tab) {
        switch tab {
        case .finance:
            self = .finance
        case .today, .review, .settings:
            self = .app
        }
    }

    var actions: [OneAddAction] {
        switch self {
        case .app:
            return [.task, .habit, .note]
        case .finance:
            return [.income, .expense, .transfer]
        }
    }

    var openAccessibilityLabel: String {
        switch self {
        case .app:
            return "Open quick add"
        case .finance:
            return "Open finance add"
        }
    }

    var closeAccessibilityLabel: String {
        switch self {
        case .app:
            return "Close quick add"
        case .finance:
            return "Close finance add"
        }
    }
}

enum OneAddAction: String, CaseIterable, Identifiable {
    case task
    case habit
    case note
    case income
    case expense
    case transfer

    var id: String { rawValue }

    var iconKey: OneIconKey {
        switch self {
        case .task:
            return .task
        case .habit:
            return .habit
        case .note:
            return .note
        case .income:
            return .income
        case .expense:
            return .expense
        case .transfer:
            return .transfer
        }
    }

    var title: String {
        switch self {
        case .task:
            return "Task"
        case .habit:
            return "Habit"
        case .note:
            return "Note"
        case .income:
            return "Income"
        case .expense:
            return "Expense"
        case .transfer:
            return "Transfer"
        }
    }

    var subtitle: String {
        switch self {
        case .task:
            return "Queue it"
        case .habit:
            return "Repeat it"
        case .note:
            return "Capture it"
        case .income:
            return "Log money in"
        case .expense:
            return "Track money out"
        case .transfer:
            return "Move between accounts"
        }
    }

    var financeTransactionType: FinanceTransactionType? {
        switch self {
        case .income:
            return .income
        case .expense:
            return .expense
        case .transfer:
            return .transfer
        case .task, .habit, .note:
            return nil
        }
    }

    var financeSheetTitle: String? {
        switch self {
        case .income:
            return "Add Income"
        case .expense:
            return "Add Expense"
        case .transfer:
            return "Add Transfer"
        case .task, .habit, .note:
            return nil
        }
    }

    var isFinanceAction: Bool {
        financeTransactionType != nil
    }
}
