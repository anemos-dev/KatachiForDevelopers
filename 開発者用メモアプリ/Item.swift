//
//  Item.swift
//  開発者用メモアプリ
//
//  Created by 木村風葉 on 2026/04/11.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
