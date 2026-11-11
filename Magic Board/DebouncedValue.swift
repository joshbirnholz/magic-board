//
//  DebouncedValue.swift
//  Spellbook
//
//  Created by Josh Birnholz on 8/13/23.
//

import SwiftUI
import Combine

class DebouncedValue<Value>: ObservableObject {
  @Published var debouncedValue: Value
  @Published var liveValue: Value
  
  private var subscriptions: Set<AnyCancellable> = []
  
  init(initialValue: Value, delay: DispatchQueue.SchedulerTimeType.Stride) {
    self.liveValue = initialValue
    self.debouncedValue = initialValue
    
    $liveValue
      .debounce(for: delay, scheduler: DispatchQueue.main)
      .sink(receiveValue: { [weak self] t in
        self?.debouncedValue = t
      })
      .store(in: &subscriptions)
  }
}

extension DebouncedValue where Value == Optional<Any> {
  convenience init(delay: DispatchQueue.SchedulerTimeType.Stride) {
    self.init(initialValue: .none, delay: delay)
  }
}
