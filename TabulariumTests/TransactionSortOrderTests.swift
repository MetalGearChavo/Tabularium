import Foundation
import Testing
@testable import Tabularium

/// Unit tests for `TransactionSortOrder`: sorting dates and day groups in
/// descending (`newestFirst`, latest date on top) vs. ascending (`oldestFirst`,
/// earliest date on top) order.
struct TransactionSortOrderTests {

    @Test func sortsDatesNewestFirstOrOldestFirst() {
        let d1 = Date(timeIntervalSince1970: 1_000)
        let d2 = Date(timeIntervalSince1970: 2_000)
        let d3 = Date(timeIntervalSince1970: 3_000)
        let input = [d2, d1, d3]

        let newest = TransactionSortOrder.newestFirst.sort(input, by: { $0 })
        #expect(newest == [d3, d2, d1])

        let oldest = TransactionSortOrder.oldestFirst.sort(input, by: { $0 })
        #expect(oldest == [d1, d2, d3])
    }

    @Test func togglesBetweenNewestAndOldest() {
        #expect(TransactionSortOrder.newestFirst.toggled == .oldestFirst)
        #expect(TransactionSortOrder.oldestFirst.toggled == .newestFirst)
    }
}
