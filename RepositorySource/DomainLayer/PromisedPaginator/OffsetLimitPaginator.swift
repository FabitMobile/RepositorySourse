import Foundation
import FoundationExtension
import PromiseKit

struct NilLoaderError: Error {}
struct IsLoadingError: Error {}
struct CancelledError: Error {}

public class OffsetLimitPaginator {
    public typealias LoaderClosure = (_ offset: Int, _ limit: Int) -> Promise<PromisedRemoteSourceResponse>
    public typealias LoadedAllObjectsClosure = () -> Void

    public var observer: PromisedDataObserverByIds
    public var nextOffset: Int
    public var limit: Int

    public var loader: LoaderClosure?
    public var onLoadedAllObjects: LoadedAllObjectsClosure?

    public var isLoadingNextPage: Atomic<Bool>

    public init(observer: PromisedDataObserverByIds,
                limit: Int) {
        self.observer = observer
        nextOffset = 0
        self.limit = limit

        isLoadingNextPage = Atomic(value: false)
    }

    public convenience init(observer: PromisedDataObserverByIds) {
        self.init(observer: observer, limit: 20)
    }

    // MARK: - load

    public func refresh(loader: @escaping LoaderClosure,
                        onLoadedAllObjects: @escaping LoadedAllObjectsClosure) -> Promise<Void> {
        self.loader = loader
        self.onLoadedAllObjects = onLoadedAllObjects

        observer.resetLoadedIds()
        nextOffset = 0
        isLoadingNextPage.value = false

        return loadNext()
    }

    public func loadNext() -> Promise<Void> {
        guard let loader = loader else { return Promise(error: NilLoaderError()) }
        guard !isLoadingNextPage.value else { return Promise(error: IsLoadingError()) }
        isLoadingNextPage.value = true

        let offset = nextOffset
        let limit = self.limit
        return loader(offset, limit)
            .then { [weak self] (response) -> Promise<PromisedRemoteSourceResponse> in
                guard let __self = self else { throw NilSelfError() }
                guard offset == __self.nextOffset else { throw CancelledError() }

                if let ids = response.loadedIdentifiers {
                    __self.observer.appendIds(ids)
                    __self.nextOffset += __self.limit

                    if ids.count < __self.limit,
                        let onLoadedAllObjects = __self.onLoadedAllObjects {
                        DispatchQueue.main.async {
                            onLoadedAllObjects()
                        }
                    }
                }

                __self.isLoadingNextPage.value = false
                return Promise.value(response)
            }.asVoid()
    }
}
