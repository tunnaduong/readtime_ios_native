import XCTest
@testable import ReadTime

final class ReadTimeTests: XCTestCase {
    func testBookProgress() {
        let book = Book(id: UUID(), title: "T", author: "A", genre: "G", totalPages: 200, currentPage: 50, status: .reading)
        XCTAssertEqual(book.progress, 0.25, accuracy: 0.0001)
    }
}
