import Foundation
import CoreServices

/// Raw Apple Events to a running process addressed by pid. Addressing by pid never launches the target:
/// an event to a dead pid fails with -600 (procNotFound). Synchronous; must never run on the main thread.
enum SpotifyAppleEvents {
    static let timeout: TimeInterval = 2

    static func code(_ s: String) -> FourCharCode {
        s.utf8.prefix(4).reduce(FourCharCode(0)) { ($0 << 8) | FourCharCode($1) }
    }

    static func property(_ code: String, of container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let spec = NSAppleEventDescriptor.record()
        spec.setDescriptor(NSAppleEventDescriptor(typeCode: Self.code("prop")), forKeyword: Self.code("want"))
        spec.setDescriptor(NSAppleEventDescriptor(enumCode: Self.code("prop")), forKeyword: Self.code("form"))
        spec.setDescriptor(NSAppleEventDescriptor(typeCode: Self.code(code)), forKeyword: Self.code("seld"))
        spec.setDescriptor(container, forKeyword: Self.code("from"))
        return spec.coerce(toDescriptorType: typeObjectSpecifier) ?? spec
    }

    static func get(_ specifier: NSAppleEventDescriptor, pid: pid_t) throws -> NSAppleEventDescriptor {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let event = makeEvent(eventClass: "core", id: "getd", pid: pid)
        event.setParam(specifier, forKeyword: Self.code("----"))
        let reply = try send(event)
        if let err = reply.paramDescriptor(forKeyword: Self.code("errn")), err.int32Value != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(err.int32Value))
        }
        return reply.paramDescriptor(forKeyword: Self.code("----")) ?? .null()
    }

    static func command(eventClass: String, id: String, pid: pid_t) throws {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let reply = try send(makeEvent(eventClass: eventClass, id: id, pid: pid))
        if let err = reply.paramDescriptor(forKeyword: Self.code("errn")), err.int32Value != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(err.int32Value))
        }
    }

    private static func makeEvent(eventClass: String, id: String, pid: pid_t) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: code(eventClass), eventID: code(id),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
    }

    private static func send(_ event: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        do {
            return try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout)
        } catch let error as NSError {
            throw NSError(domain: NSOSStatusErrorDomain, code: error.code)
        }
    }
}
