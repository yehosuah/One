import Foundation

#if canImport(SwiftData)
import SwiftData

@Model
final class PendingMutationEntity {
    @Attribute(.unique) var id: UUID
    var kind: String
    var payloadData: Data
    var createdAt: Date

    init(id: UUID, kind: String, payloadData: Data, createdAt: Date) {
        self.id = id
        self.kind = kind
        self.payloadData = payloadData
        self.createdAt = createdAt
    }
}

public actor SwiftDataSyncQueue: SyncQueue, ModelActor {
    nonisolated public let modelContainer: ModelContainer
    nonisolated public let modelExecutor: any ModelExecutor
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var context: ModelContext {
        modelContext
    }

    public init(container: ModelContainer) {
        let context = ModelContext(container)
        self.modelContainer = container
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    public func enqueue(_ mutation: PendingMutation) async {
        guard let payloadData = try? encoder.encode(mutation.payload) else {
            return
        }
        let entity = PendingMutationEntity(
            id: mutation.id,
            kind: mutation.kind.rawValue,
            payloadData: payloadData,
            createdAt: Date()
        )
        context.insert(entity)
        try? context.save()
    }

    public func all() async -> [PendingMutation] {
        var descriptor = FetchDescriptor<PendingMutationEntity>()
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .forward)]
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.compactMap(mapMutation)
    }

    public func drain(using apiClient: APIClient) async {
        var descriptor = FetchDescriptor<PendingMutationEntity>()
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .forward)]
        let rows = (try? context.fetch(descriptor)) ?? []

        for row in rows {
            guard let mutation = mapMutation(row) else {
                context.delete(row)
                continue
            }
            do {
                try await mutation.apply(using: apiClient)
                context.delete(row)
            } catch {
                if case APIError.unauthorized = error {
                    break
                }
                // keep in queue for retry
            }
        }
        try? context.save()
    }

    private func mapMutation(_ row: PendingMutationEntity) -> PendingMutation? {
        guard let kind = PendingMutationKind(rawValue: row.kind),
              let payload = try? decoder.decode(PendingMutationPayload.self, from: row.payloadData) else {
            return nil
        }
        return PendingMutation(id: row.id, kind: kind, payload: payload)
    }
}

#endif
