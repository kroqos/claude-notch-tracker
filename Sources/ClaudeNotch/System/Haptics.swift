import AppKit
import os

private let hapticLog = Logger(subsystem: "com.claudenotch.app", category: "haptics")

/// One hard trackpad thump.
///
/// NSHapticFeedbackManager has three fixed patterns and none of them hits hard. The trackpad's
/// own actuator, reached through the MultitouchSupport framework (the route "haptic key" style
/// apps take), has stronger actuations. That framework is not public API, so everything is
/// looked up at runtime and the public pattern is the fallback whenever any step is missing.
@MainActor
enum Haptics {
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias GetDeviceID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias ActuatorCreate = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias ActuatorOpen = @convention(c) (CFTypeRef) -> Int32
    private typealias Actuate = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32

    /// Actuation ids climb in strength; 6 is the hardest one the actuator exposes.
    static var strength: Int32 = 6

    private static let actuator: (ref: CFTypeRef, actuate: Actuate)? = {
        guard let lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let listSym = dlsym(lib, "MTDeviceCreateList"),
              let idSym = dlsym(lib, "MTDeviceGetDeviceID"),
              let createSym = dlsym(lib, "MTActuatorCreateFromDeviceID"),
              let openSym = dlsym(lib, "MTActuatorOpen"),
              let actuateSym = dlsym(lib, "MTActuatorActuate")
        else { hapticLog.log("actuator: framework or symbols missing, using public patterns"); return nil }
        let createList = unsafeBitCast(listSym, to: CreateList.self)
        let getID = unsafeBitCast(idSym, to: GetDeviceID.self)
        let create = unsafeBitCast(createSym, to: ActuatorCreate.self)
        let open = unsafeBitCast(openSym, to: ActuatorOpen.self)
        let actuate = unsafeBitCast(actuateSym, to: Actuate.self)
        guard let devices = createList()?.takeRetainedValue() as? [AnyObject] else {
            hapticLog.log("actuator: no multitouch devices"); return nil
        }
        for device in devices {
            var id: UInt64 = 0
            guard getID(Unmanaged.passUnretained(device).toOpaque(), &id) == 0,
                  let ref = create(id)?.takeRetainedValue() else { continue }
            if open(ref) == 0 {
                hapticLog.log("actuator: opened device \(id, privacy: .public)")
                return (ref, actuate)
            }
        }
        hapticLog.log("actuator: no device would open, using public patterns")
        return nil
    }()

    static func thump() {
        if let actuator, actuator.actuate(actuator.ref, strength, 0, 0, 0) == 0 { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
