import Foundation

public struct FinanceVoiceExpenseParser {
    public init() {}

    public func parse(_ phrase: String, categories: [FinanceCategory]) -> FinanceVoiceParseResult {
        let transcript = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalize(transcript)
        let amount = parseAmount(from: normalized)
        let paymentMethod = parsePaymentMethod(from: normalized)
        let category = parseCategory(from: normalized, categories: categories)
        let confidence = confidenceForParse(
            amount: amount,
            category: category,
            paymentMethod: paymentMethod
        )
        return FinanceVoiceParseResult(
            transcript: transcript,
            input: FinanceTransactionWriteInput(
                type: .expense,
                amount: amount,
                categoryId: category?.id,
                paymentMethod: paymentMethod,
                note: nil,
                occurredAt: Date(),
                source: .voice
            ),
            confidence: confidence
        )
    }

    private func parseAmount(from value: String) -> Double? {
        let pattern = #"\d+(?:[.,]\d{1,2})?"#
        guard let match = value.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let token = value[match].replacingOccurrences(of: ",", with: ".")
        return Double(token)
    }

    private func parsePaymentMethod(from value: String) -> FinancePaymentMethod? {
        if value.contains("cash") {
            return .cash
        }
        if value.contains("card") {
            return .card
        }
        return nil
    }

    private func parseCategory(from value: String, categories: [FinanceCategory]) -> FinanceCategory? {
        let aliases = categoryAliases(for: categories)
        return categories
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isCustom != rhs.isCustom {
                    return !lhs.isCustom
                }
                return lhs.sortOrder < rhs.sortOrder
            }
            .first { category in
                let tokens = aliases[category.id, default: []]
                return tokens.contains(where: value.contains)
            }
    }

    private func categoryAliases(for categories: [FinanceCategory]) -> [String: [String]] {
        categories.reduce(into: [String: [String]]()) { partial, category in
            let normalizedName = normalize(category.name)
            var values = [normalizedName]
            let fallback = builtInAliases[normalizedName] ?? []
            values.append(contentsOf: fallback)
            if normalizedName.contains("food") {
                values.append("coffee")
            }
            partial[category.id] = Array(Set(values))
        }
    }

    private func confidenceForParse(
        amount: Double?,
        category: FinanceCategory?,
        paymentMethod: FinancePaymentMethod?
    ) -> FinanceVoiceParseConfidence {
        let parsedCount = [amount != nil, category != nil, paymentMethod != nil].filter { $0 }.count
        switch parsedCount {
        case 3:
            return .high
        case 2:
            return .medium
        default:
            return .low
        }
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "quetzales", with: "")
            .replacingOccurrences(of: "quetzal", with: "")
            .replacingOccurrences(of: "with", with: " ")
            .replacingOccurrences(of: "on", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var builtInAliases: [String: [String]] {
        [
            "food": ["food", "coffee", "groceries", "meal", "lunch", "dinner", "breakfast", "snack"],
            "gas transport": ["gas", "transport", "uber", "taxi", "fuel", "bus", "parking"],
            "shopping": ["shopping", "store", "clothes", "market"],
            "entertainment": ["movie", "games", "cinema", "music", "entertainment"],
            "subscriptions": ["subscription", "subscriptions", "netflix", "spotify", "streaming"],
            "bills": ["bill", "bills", "utilities", "rent", "internet", "electricity", "water"],
            "health": ["health", "doctor", "medicine", "pharmacy"],
            "school": ["school", "books", "class", "tuition", "study"],
            "gifts": ["gift", "gifts", "present"],
            "savings": ["savings", "save"],
            "miscellaneous": ["misc", "miscellaneous", "other"]
        ]
    }
}
