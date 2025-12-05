//
//  TransactionSummaryModel.swift
//  ByoSync
//
//  Created by Hari's Mac on 02.11.2025.
//

import Foundation

// MARK: - Summary Transaction Response
struct SummaryTransactionResponse: Codable {
    let statusCode: Int
    let data: SummaryTransactionData
    let message: String
    let success: Bool
}

// MARK: - Summary Transaction Data
struct SummaryTransactionData: Codable {
    let totalOrders: Int
    let totalAmount: Double
    let totalDiscount: Double
    let totalPaidByUser: Double
    let paidOrders: Int
    let paidAmount: Double
    let failedOrders: Int
    let pendingOrders: Int
    
    // Computed properties for better UI display
    var paidByByoSync: Double {
        return totalAmount - totalPaidByUser
    }
    
    var averageTransaction: Double {
        return totalOrders > 0 ? totalAmount / Double(totalOrders) : 0
    }
    
    var successRate: Double {
        return totalOrders > 0 ? (Double(paidOrders) / Double(totalOrders)) * 100 : 0
    }
}
