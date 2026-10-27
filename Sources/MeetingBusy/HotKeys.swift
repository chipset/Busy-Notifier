import AppKit
import Carbon
import MeetingDetection

enum HotKeyAction: UInt32 { case automatic = 1, busy = 2, presenting = 3 }

@MainActor
final class HotKeyController {
    var onAction: ((HotKeyAction) -> Void)?
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private(set) var failureDescription: String?

    func configure(enabled: Bool, configuration: ShortcutConfiguration = ShortcutConfiguration()) -> OSStatus {
        unregister()
        failureDescription = nil
        guard enabled else { return noErr }
        if let message = configuration.validationMessage { failureDescription = message; return OSStatus(paramErr) }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let error = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard error == noErr, identifier.signature == 0x4D425359, let action = HotKeyAction(rawValue: identifier.id) else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<HotKeyController>.fromOpaque(context).takeUnretainedValue().onAction?(action)
            }
            return noErr
        }
        let installed = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return installed }
        for (index, action) in [HotKeyAction.automatic, .busy, .presenting].enumerated() {
            let binding = configuration.bindings[index]
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.key.keyCode, binding.carbonModifiers,
                                            EventHotKeyID(signature: 0x4D425359, id: action.rawValue), GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else {
                failureDescription = "\(["Automatic", "Busy", "Presenting"][index]) shortcut \(binding.label) is unavailable (error \(status)). Choose another combination or disable the conflicting shortcut."
                unregister()
                return status == noErr ? OSStatus(paramErr) : status
            }
            references.append(reference)
        }
        return noErr
    }

    func unregister() {
        for reference in references { UnregisterEventHotKey(reference) }
        references = []
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}

extension ShortcutBinding {
    var carbonModifiers: UInt32 {
        UInt32((command ? cmdKey : 0) | (option ? optionKey : 0) | (control ? controlKey : 0) | (shift ? shiftKey : 0))
    }
    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        if shift { flags.insert(.shift) }
        return flags
    }
    var menuKey: String {
        if key.rawValue.hasPrefix("F"), let number = Int(key.rawValue.dropFirst()), (1...12).contains(number),
           let scalar = UnicodeScalar(0xF704 + number - 1) { return String(scalar) }
        return key.rawValue.lowercased()
    }
}
