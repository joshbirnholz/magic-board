//
//  ImageLoader.swift
//  AsyncImage
//
//  Created by Vadym Bulavin on 2/13/20.
//  Copyright © 2020 Vadym Bulavin. All rights reserved.
//

import Combine
import UIKit
import CardService

class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    
    private(set) var isLoading = false
    
	private let card: MTGCard
	
	private let imageType: ImageType
    private var cancellable: AnyCancellable?
    
    private static let imageProcessingQueue = DispatchQueue(label: "image-processing")
    
	init(card: MTGCard, type: ImageType) {
        self.card = card
		self.imageType = type
    }
    
    deinit {
        cancellable?.cancel()
    }
    
    func load() {
        guard !isLoading else { return }
		
		let (exists, loadImage) = card.imageLoader(type: imageType)

		if exists {
			self.image = card.image(type: imageType, alwaysUpright: true)
			return
		}
		
		cancellable = loadImage
			.handleEvents(receiveSubscription: { [weak self] _ in self?.onStart() },
			receiveCompletion: { [weak self] _ in self?.onFinish() },
			receiveCancel: { [weak self] in self?.onFinish() })
		.subscribe(on: Self.imageProcessingQueue)
		.receive(on: DispatchQueue.main)
		.assign(to: \.image, on: self)
    }
    
    func cancel() {
        cancellable?.cancel()
    }
    
    private func onStart() {
        isLoading = true
    }
    
    private func onFinish() {
        isLoading = false
    }
    
}
