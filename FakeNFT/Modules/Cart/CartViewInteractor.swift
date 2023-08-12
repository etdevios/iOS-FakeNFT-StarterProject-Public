//
//  CartViewInteractor.swift
//  FakeNFT
//
//  Created by Aleksandr Bekrenev on 04.08.2023.
//

import Foundation

protocol CartViewInteractorProtocol {
    func fetchOrder(with id: String,
                    onSuccess: @escaping LoadingCompletionBlock<CartViewModel.ViewState>,
                    onFailure: @escaping LoadingFailureCompletionBlock)
    func changeOrder(with id: String,
                     nftIds: [String],
                     onSuccess: @escaping LoadingCompletionBlock<CartViewModel.ViewState>,
                     onFailure: @escaping LoadingFailureCompletionBlock)
}

final class CartViewInteractor {
    private var order: [NFTCartCellViewModel] = []
    private var orderCapacity = 0
    private var accumulatedCost: Double = 0

    private let fetchingQueue = DispatchQueue(label: "com.practicum.yandex.fetch-nft",
                                              attributes: .concurrent)

    private let nftService: NFTNetworkCartService
    private let orderService: OrderServiceProtocol
    private let imageLoadingService: ImageLoadingServiceProtocol

    init(
        nftService: NFTNetworkCartService,
        orderService: OrderServiceProtocol,
        imageLoadingService: ImageLoadingServiceProtocol
    ) {
        self.nftService = nftService
        self.orderService = orderService
        self.imageLoadingService = imageLoadingService
    }
}

// MARK: - CartViewInteractorProtocol
extension CartViewInteractor: CartViewInteractorProtocol {
    func fetchOrder(
        with id: String,
        onSuccess: @escaping LoadingCompletionBlock<CartViewModel.ViewState>,
        onFailure: @escaping LoadingFailureCompletionBlock
    ) {
        self.orderService.fetchOrder(id: id) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let order):
                guard order.nfts.isEmpty == false else {
                    onSuccess(.empty)
                    break
                }
                self.orderCapacity = order.nfts.count
                self.fetchNfts(ids: order.nfts, onSuccess: onSuccess, onFailure: onFailure)
            case .failure(let error):
                self.handleError(error: error, onFailure: onFailure)
            }
        }
    }

    func changeOrder(
        with id: String,
        nftIds: [String],
        onSuccess: @escaping LoadingCompletionBlock<CartViewModel.ViewState>,
        onFailure: @escaping LoadingFailureCompletionBlock
    ) {
        self.orderService.changeOrder(id: id, nftIds: nftIds) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.fetchOrder(with: id, onSuccess: onSuccess, onFailure: onFailure)
            case .failure(let error):
                self.handleError(error: error, onFailure: onFailure)
            }
        }
    }
}

private extension CartViewInteractor {
    func fetchNfts(
        ids: [String],
        onSuccess: @escaping LoadingCompletionBlock<CartViewModel.ViewState>,
        onFailure: @escaping LoadingFailureCompletionBlock
    ) {
        ids.forEach { [weak self] id in
            self?.fetchingQueue.async { [weak self] in
                guard let self = self else { return }
                self.fetchNft(with: id, onSuccess: onSuccess, onFailure: onFailure)
            }
        }
    }

    func fetchNft(
        with id: String,
        onSuccess: @escaping LoadingCompletionBlock<CartViewModel.ViewState>,
        onFailure: @escaping LoadingFailureCompletionBlock
    ) {
        self.nftService.getNFTItemBy(id: id) { [weak self] result in
            switch result {
            case .success(let model):
                self?.prepareNftWithImage(model: model, onSuccess: onSuccess, onFailure: onFailure)
            case .failure(let error):
                self?.handleError(error: error, onFailure: onFailure)
            }
        }
    }

    func prepareNftWithImage(
        model: NFTItemModel,
        onSuccess: @escaping LoadingCompletionBlock<CartViewModel.ViewState>,
        onFailure: @escaping LoadingFailureCompletionBlock
    ) {
        let imageUrl = URL(string: model.images.first ?? "")
        self.imageLoadingService.fetchImage(url: imageUrl) { [weak self] result in
            switch result {
            case .success(let image):
                let nft = NFTCartCellViewModelFactory.makeNFTCartCellViewModel(
                    id: model.id,
                    name: model.name,
                    image: image,
                    rating: model.rating,
                    price: model.price
                )
                self?.saveNft(nft, completion: onSuccess)
            case .failure(let error):
                self?.handleError(error: error, onFailure: onFailure)
            }
        }
    }

    func saveNft(
        _ nft: NFTCartCellViewModel,
        completion: @escaping LoadingCompletionBlock<CartViewModel.ViewState>
    ) {
        self.order.append(nft)
        self.accumulatedCost += nft.price
        if self.order.count == self.orderCapacity {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                completion(.loaded(self.order, self.accumulatedCost))
                self.order.removeAll()
                self.accumulatedCost = 0
            }
        }
    }
}

private extension CartViewInteractor {
    func handleError(error: Error, onFailure: @escaping LoadingFailureCompletionBlock) {
        DispatchQueue.main.async {
            onFailure(error)
        }
    }
}
