import Foundation
import Testing
@testable import Tabularium

/// Tests for `StatementChunker` — see CLAUDE.md → "Development Process"
/// (spec-driven: written before `StatementChunker` existed, to fix a real
/// observed failure — a single ~50-line call to a local 7B model caused it to
/// silently stop partway through instead of covering every transaction).
struct StatementChunkerTests {
    @Test func splitsIntoChunksOfTheGivenSize() {
        let lines = (1...25).map { "line \($0)" }.joined(separator: "\n")
        let chunks = StatementChunker.chunk(lines, linesPerChunk: 10)
        #expect(chunks.count == 3)
        #expect(chunks[0].components(separatedBy: "\n").count == 10)
        #expect(chunks[1].components(separatedBy: "\n").count == 10)
        #expect(chunks[2].components(separatedBy: "\n").count == 5)
    }

    @Test func singleChunkWhenUnderTheLimit() {
        let chunks = StatementChunker.chunk("a\nb\nc", linesPerChunk: 10)
        #expect(chunks == ["a\nb\nc"])
    }

    @Test func emptyInputProducesNoChunks() {
        #expect(StatementChunker.chunk("", linesPerChunk: 10).isEmpty)
    }

    @Test func blankLinesDontCountTowardsChunkSize() {
        let lines = "a\n\nb\n\nc"
        let chunks = StatementChunker.chunk(lines, linesPerChunk: 10)
        #expect(chunks.count == 1)
        #expect(chunks[0] == "a\nb\nc")
    }
}
