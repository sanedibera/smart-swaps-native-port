import Foundation

/// JS `Map`, which iterates in insertion order. Swift's `Dictionary` does not.
///
/// Required wherever iteration order reaches the output: `candidateHits` in
/// receiptParser (its order picks which 120 candidates get scored), the four indexes in
/// foodIndex, `candidatesMap` on Home, `distinct` in recipes/ReceiptItemList,
/// `groupedItems` in ReceiptItemList. See PORTING_INVENTORY.md §5.2e.
public struct OrderedDictionary<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private(set) public var keys: [Key] = []

    public init() {}
    public init(minimumCapacity: Int) {
        storage.reserveCapacity(minimumCapacity)
        keys.reserveCapacity(minimumCapacity)
    }

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    public subscript(key: Key) -> Value? {
        get { storage[key] }
        set {
            if let newValue {
                if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
            } else if storage.removeValue(forKey: key) != nil {
                if let i = keys.firstIndex(of: key) { keys.remove(at: i) }
            }
        }
    }

    public func has(_ key: Key) -> Bool { storage.index(forKey: key) != nil }

    /// `map.get(k) ?? fallback`
    public func get(_ key: Key, default fallback: Value) -> Value { storage[key] ?? fallback }

    /// Values in insertion order - JS `[...map.values()]`.
    public var values: [Value] { keys.map { storage[$0]! } }

    /// Entries in insertion order - JS `[...map.entries()]`.
    public var entries: [(key: Key, value: Value)] { keys.map { (key: $0, value: storage[$0]!) } }

    public mutating func removeAll() { storage.removeAll(); keys.removeAll() }
}

extension OrderedDictionary: Sequence {
    public func makeIterator() -> AnyIterator<(key: Key, value: Value)> {
        var i = 0
        return AnyIterator {
            guard i < self.keys.count else { return nil }
            defer { i += 1 }
            let k = self.keys[i]
            return (key: k, value: self.storage[k]!)
        }
    }
}

/// JS `Set`, which iterates in insertion order.
public struct OrderedSet<Element: Hashable> {
    private var seen: Set<Element> = []
    private(set) public var elements: [Element] = []

    public init() {}
    public init(_ sequence: some Sequence<Element>) { for e in sequence { insert(e) } }

    public var count: Int { elements.count }
    public var isEmpty: Bool { elements.isEmpty }

    @discardableResult
    public mutating func insert(_ e: Element) -> Bool {
        if seen.insert(e).inserted { elements.append(e); return true }
        return false
    }

    public func has(_ e: Element) -> Bool { seen.contains(e) }

    public mutating func remove(_ e: Element) {
        if seen.remove(e) != nil, let i = elements.firstIndex(of: e) { elements.remove(at: i) }
    }
}

extension OrderedSet: Sequence {
    public func makeIterator() -> IndexingIterator<[Element]> { elements.makeIterator() }
}

/// An order-preserving reader for a flat `{ "key": "value" }` JSON object.
///
/// `brandDict.ts` sorts its keys by `b.length - a.length`, and JS's stable sort leaves
/// equal-length keys in JSON insertion order - which then decides which of two equally
/// long dictionary entries wins. `JSONDecoder` into a `Dictionary` destroys that order,
/// so `verifiedBrandMap.json` is read through here instead.
public enum OrderedJSON {
    public static func stringPairs(from data: Data) throws -> [(String, String)] {
        // JSONSerialization also loses order, so scan the bytes. The three data files this
        // reads are flat string->string maps with no nesting, which makes this safe.
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "OrderedJSON", code: 1)
        }
        var pairs: [(String, String)] = []
        var current = ""
        var inString = false
        var escaped = false
        var pendingKey: String? = nil
        for ch in text {
            if escaped {
                switch ch {
                case "n": current.append("\n")
                case "t": current.append("\t")
                case "r": current.append("\r")
                case "b": current.append("\u{08}")
                case "f": current.append("\u{0C}")
                default:  current.append(ch)     // covers \" \\ \/
                }
                escaped = false
                continue
            }
            if inString {
                if ch == "\\" { escaped = true }
                else if ch == "\"" {
                    inString = false
                    if let k = pendingKey { pairs.append((k, current)); pendingKey = nil }
                    else { pendingKey = current }
                    current = ""
                } else { current.append(ch) }
                continue
            }
            if ch == "\"" { inString = true; current = "" }
        }
        return pairs
    }
}
