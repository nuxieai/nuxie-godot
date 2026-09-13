import Foundation

private let queueLock = NSLock()
private var queue: [String] = []
private var queueOffset = 0
private var bridge: NuxieGodotRuntime?

private func deliver(_ value: String) {
  queueLock.lock(); defer { queueLock.unlock() }
  queue.append(value)
}

@_cdecl("NuxieGodot_Dispatch")
public func nuxieGodotDispatch(_ pointer: UnsafePointer<CChar>) {
  let json = String(cString: pointer)
  DispatchQueue.main.async {
    guard let data = json.data(using: .utf8),
      let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let id = request["requestId"] as? String,
      let method = request["method"] as? String,
      let arguments = request["arguments"] as? [String: Any] else { return }
    if bridge == nil {
      let next = NuxieGodotRuntime()
      next.emit = { deliver($0) }
      bridge = next
    }
    func reply(_ value: [String: Any]) {
      if let bytes = try? JSONSerialization.data(withJSONObject: value) { deliver(String(decoding: bytes, as: UTF8.self)) }
    }
    bridge!.invoke(method, arguments: arguments,
      resolve: { reply(["requestId": id, "result": $0 ?? NSNull()]) },
      reject: { code, message, _ in reply(["requestId": id, "error": ["code": code, "message": message]]) })
  }
}

@_cdecl("NuxieGodot_PopMessage")
public func nuxieGodotPopMessage() -> UnsafeMutablePointer<CChar>? {
  queueLock.lock(); defer { queueLock.unlock() }
  guard queueOffset < queue.count else { return nil }
  let value = queue[queueOffset]
  queueOffset += 1
  if queueOffset == queue.count { queue.removeAll(keepingCapacity: true); queueOffset = 0 }
  return strdup(value)
}

@_cdecl("NuxieGodot_FreeCString")
public func nuxieGodotFreeCString(_ pointer: UnsafeMutablePointer<CChar>?) { free(pointer) }

@_cdecl("NuxieGodot_Detach")
public func nuxieGodotDetach() {
  DispatchQueue.main.async {
    bridge?.invalidate(); bridge = nil
    queueLock.lock(); queue.removeAll(); queueOffset = 0; queueLock.unlock()
  }
}
