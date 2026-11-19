import Foundation

public struct PetDirectionLayout: Codable, Equatable {
  public struct Cell: Codable, Equatable {
    public var source: Int
    public var mirrored = false
  }

  // Two running rows followed by the two V2 gaze rows.
  private static let rows = [1, 2, 9, 10]
  public private(set) var cells = (0..<32).map { Cell(source: $0) }
  public init() {}

  public mutating func swap(_ first: Int, _ second: Int) {
    guard cells.indices.contains(first), cells.indices.contains(second), (first < 16) == (second < 16)
    else { return }
    cells.swapAt(first, second)
  }

  public mutating func swapRunningRows() {
    for index in 0..<8 { swap(index, index + 8) }
  }

  public mutating func mirror(_ index: Int) {
    guard cells.indices.contains(index) else { return }
    cells[index].mirrored.toggle()
  }

  public static func frame(at index: Int) -> AnimationFrame {
    AnimationFrame(rowIndex: rows[index / 8], columnIndex: index % 8, frameDurationMs: 0)
  }

  public func resolve(_ frame: AnimationFrame) -> (frame: AnimationFrame, mirrored: Bool) {
    guard let row = Self.rows.firstIndex(of: frame.rowIndex), (0..<8).contains(frame.columnIndex)
    else { return (frame, false) }
    let cell = cells[row * 8 + frame.columnIndex]
    return (Self.frame(at: cell.source), cell.mirrored)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let cells = try container.decode([Cell].self)
    guard cells.count == 32, Set(cells.map(\.source)) == Set(0..<32),
      cells.enumerated().allSatisfy({ ($0.offset < 16) == ($0.element.source < 16) })
    else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid direction layout") }
    self.cells = cells
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(cells)
  }
}

public struct SavedPetDirectionLayout: Codable {
  public let spritesheetHash: String
  public let layout: PetDirectionLayout

  public init(spritesheetHash: String, layout: PetDirectionLayout) {
    self.spritesheetHash = spritesheetHash
    self.layout = layout
  }
}
