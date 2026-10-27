import AppKit
import Carbon

enum HotKeyAction: UInt32 { case automatic = 1, busy = 2, presenting = 3 }

@MainActor
final class HotKeyController {
    var onAction: ((HotKeyAction) -> Void)?
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func configure(enabled: Bool) -> OSStatus {
        unregister()
        guard enabled else { return noErr }
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
        for (key, action) in [(kVK_ANSI_1, HotKeyAction.automatic), (kVK_ANSI_2, .busy), (kVK_ANSI_3, .presenting)] {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey | cmdKey),
                                            EventHotKeyID(signature: 0x4D425359, id: action.rawValue), GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else { unregister(); return status }
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
