import Foundation

/// Undo and redo for any value, kept in memory while a screen is open.
///
/// Before each edit, call `record(_:)` with the value as it was. `undo`
/// hands back the previous value (and remembers the current one for
/// `redo`). Making a new edit after undoing clears the redo list, the way
/// every editor works.
struct EditHistory<Value> {
    private(set) var undoStack: [Value] = []
    private(set) var redoStack: [Value] = []
    /// Oldest steps are dropped beyond this, to keep memory small.
    var limit = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func record(_ before: Value) {
        undoStack.append(before)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    /// The value to go back to, or nil if there is nothing to undo.
    mutating func undo(current: Value) -> Value? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// The value to go forward to, or nil if there is nothing to redo.
    mutating func redo(current: Value) -> Value? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
