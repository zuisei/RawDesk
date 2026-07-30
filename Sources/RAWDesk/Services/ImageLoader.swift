import Foundation
import AppKit

actor ImageLoadGate {
    enum Priority: Int, Sendable {
        case thumbnail
        case preview
    }

    private struct Waiter {
        let id: UUID
        let priority: Priority
        let continuation:
            CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var activeCount = 0
    private var waiters: [Waiter] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire(
        priority: Priority
    ) async -> Bool {
        guard !Task.isCancelled else {
            return false
        }
        if activeCount < limit {
            activeCount += 1
            return true
        }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation {
                (continuation:
                    CheckedContinuation<Bool, Never>) in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                let waiter = Waiter(
                    id: id,
                    priority: priority,
                    continuation: continuation
                )
                if let insertionIndex =
                    waiters.firstIndex(
                        where: {
                            $0.priority.rawValue
                                < priority.rawValue
                        }
                    ) {
                    waiters.insert(
                        waiter,
                        at: insertionIndex
                    )
                } else {
                    waiters.append(waiter)
                }
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id)
            }
        }
    }

    func release() {
        precondition(activeCount > 0)
        activeCount -= 1
        guard !waiters.isEmpty else {
            return
        }
        let waiter = waiters.removeFirst()
        // Reserve the slot before resuming so a newly arriving request cannot
        // race the resumed task and exceed the concurrency limit.
        activeCount += 1
        waiter.continuation.resume(returning: true)
    }

    func counts() -> (
        active: Int,
        pending: Int
    ) {
        (activeCount, waiters.count)
    }

    private func cancelWaiter(
        _ id: UUID
    ) {
        guard let index =
            waiters.firstIndex(
                where: { $0.id == id }
            ) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}

/// Coordinated, concurrency-limited image loader.
public actor ImageLoader {

    public static let shared = ImageLoader()

    private let cache: ImageCache
    private let gate: ImageLoadGate
    private var rawDecodeSources:
        [String: RAWImageLoader.DecodeSource] = [:]

    public init(cache: ImageCache = .shared, maxConcurrent: Int = 3) {
        self.cache = cache
        gate = ImageLoadGate(
            limit: maxConcurrent
        )
    }

    public enum LoadKind: Sendable {
        case thumbnail(target: CGFloat)
        case preview(target: CGFloat)

        fileprivate var gatePriority:
            ImageLoadGate.Priority {
            switch self {
            case .thumbnail:
                return .thumbnail
            case .preview:
                return .preview
            }
        }
    }

    public struct LoadOutcome: Sendable {
        public let image: NSImage?
        public let state: ImageLoadState
        public let rawDecodeSource:
            RAWImageLoader.DecodeSource?

        public init(
            image: NSImage?,
            state: ImageLoadState,
            rawDecodeSource:
                RAWImageLoader.DecodeSource? = nil
        ) {
            self.image = image
            self.state = state
            self.rawDecodeSource = rawDecodeSource
        }
    }

    public func load(asset: PhotoAsset, kind: LoadKind) async -> LoadOutcome {
        let target: CGFloat
        let quality: ThumbnailGenerator.Quality
        let cacheLookup: (String) -> NSImage?
        let cacheSourceLookup:
            (String) -> RAWImageLoader.DecodeSource?
        let cacheStore:
            (
                NSImage,
                String,
                RAWImageLoader.DecodeSource?
            ) -> Void
        switch kind {
        case .thumbnail(let t):
            target = t
            quality = .grid
            cacheLookup = { [cache] in cache.thumbnail(for: $0) }
            cacheSourceLookup = {
                [cache] in
                cache.thumbnailDecodeSource(for: $0)
            }
            cacheStore = {
                [cache] image, key, source in
                cache.storeThumbnail(
                    image,
                    for: key,
                    rawDecodeSource: source
                )
            }
        case .preview(let t):
            target = t
            quality = .preview
            cacheLookup = { [cache] in cache.preview(for: $0) }
            cacheSourceLookup = { _ in nil }
            cacheStore = {
                [cache] image, key, _ in
                cache.storePreview(image, for: key)
            }
        }

        let key = ImageCache.key(for: asset, target: target, scale: 1.0)
        let rawSourceKey =
            asset.format.isRaw
                ? Self.rawSourceKey(for: asset)
                : nil
        if let cached = cacheLookup(key) {
            if let rawSourceKey {
                let source =
                    rawDecodeSources[rawSourceKey]
                    ?? cacheSourceLookup(key)
                if let source {
                    rawDecodeSources[rawSourceKey] =
                        source
                }
                // A legacy cache may not include decoder metadata. Display it
                // immediately with an unknown source; Info performs a
                // background decoder inspection only when the photo is used.
                return LoadOutcome(
                    image: cached,
                    state: .loaded,
                    rawDecodeSource: source
                )
            } else {
                return LoadOutcome(
                    image: cached,
                    state: .loaded
                )
            }
        }

        guard await gate.acquire(
            priority: kind.gatePriority
        ) else {
            return LoadOutcome(
                image: nil,
                state: .idle
            )
        }
        if Task.isCancelled {
            await gate.release()
            return LoadOutcome(
                image: nil,
                state: .idle
            )
        }

        if let cached = cacheLookup(key) {
            if let rawSourceKey,
               let source =
                    rawDecodeSources[rawSourceKey]
                    ?? cacheSourceLookup(key) {
                rawDecodeSources[rawSourceKey] =
                    source
                await gate.release()
                return LoadOutcome(
                    image: cached,
                    state: .loaded,
                    rawDecodeSource: source
                )
            } else {
                await gate.release()
                return LoadOutcome(
                    image: cached,
                    state: .loaded
                )
            }
        }

        let result: LoadOutcome = await Task.detached(priority: .userInitiated) {
            do {
                if asset.format.isRaw {
                    if case .thumbnail = kind,
                       let thumbnail =
                        RAWImageLoader
                            .loadGridThumbnail(
                                url: asset.url,
                                targetLongestEdge:
                                    target
                            ) {
                        return LoadOutcome(
                            image: thumbnail,
                            state: .loaded
                        )
                    }
                    let decoded =
                        try RAWImageLoader.loadResult(
                            url: asset.url,
                            targetLongestEdge: target,
                            preserveWideGamut:
                                quality == .preview
                        )
                    return LoadOutcome(
                        image: decoded.image,
                        state: .loaded,
                        rawDecodeSource: decoded.source
                    )
                }
                let image =
                    try ThumbnailGenerator.generate(
                        for: asset,
                        targetPixelSize: target,
                        quality: quality
                    )
                return LoadOutcome(
                    image: image,
                    state: .loaded
                )
            } catch {
                if asset.format.isRaw {
                    return LoadOutcome(
                        image: nil,
                        state: .failed(
                            reason:
                                "RAW decode failed: "
                                + error.localizedDescription
                        )
                    )
                }
                return LoadOutcome(
                    image: nil,
                    state: .failed(
                        reason:
                            error.localizedDescription
                    )
                )
            }
        }.value
        await gate.release()

        if let rawSourceKey,
           let source = result.rawDecodeSource {
            rawDecodeSources[rawSourceKey] = source
        }
        if let img = result.image {
            cacheStore(
                img,
                key,
                result.rawDecodeSource
            )
        }
        return result
    }

    private static func rawSourceKey(
        for asset: PhotoAsset
    ) -> String {
        let modification =
            asset.modificationDate?
                .timeIntervalSinceReferenceDate
            ?? 0
        return
            "\(asset.path)|\(asset.fileSize)|"
            + "\(modification)"
    }

}
