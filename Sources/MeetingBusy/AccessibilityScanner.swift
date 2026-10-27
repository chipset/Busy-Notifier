import AppKit
import ApplicationServices
import MeetingDetection

struct ApplicationTarget: Sendable {
    let pid: pid_t
    let bundleID: String
}

struct ScanResult: Sendable {
    var evidence: [MeetingEvidence] = []
    var incomplete = false
    var details: [String] = []
    var failureCodes: [Int] = []
}

/// Batched IPC and breadth-first traversal reach toolbars before deep chat history.
enum AccessibilityScanner {
    static let browserIDs: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "com.google.Chrome.beta",
        "com.microsoft.edgemac", "org.mozilla.firefox", "com.brave.Browser", "company.thebrowser.Browser"
    ]

    static func scanConcurrently(_ targets: [ApplicationTarget], enabledServices: Set<MeetingService> = Set(MeetingService.allCases)) async -> ScanResult {
        guard !targets.isEmpty else { return scan([], enabledServices: enabledServices) }
        return await withTaskGroup(of: ScanResult.self) { group in
            for target in targets { group.addTask { scan([target], enabledServices: enabledServices) } }
            var result = ScanResult()
            for await partial in group {
                result.evidence += partial.evidence
                result.details += partial.details
                result.failureCodes += partial.failureCodes
                result.incomplete = result.incomplete || partial.incomplete
            }
            result.details.sort()
            return result
        }
    }

    static func scan(_ targets: [ApplicationTarget], enabledServices: Set<MeetingService> = Set(MeetingService.allCases)) -> ScanResult {
        var result = ScanResult()
        if targets.isEmpty { result.details.append("No supported meeting apps or browsers are running.") }
        for target in targets {
            let native = Detection.nativeService(bundleID: target.bundleID)
            if let native, !enabledServices.contains(native) { continue }
            if enabledServices.isEmpty { continue }
            guard native != nil || browserIDs.contains(target.bundleID) else { continue }
            let app = AXUIElementCreateApplication(target.pid)
            AXUIElementSetMessagingTimeout(app, 0.12)
            if browserIDs.contains(target.bundleID) {
                _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            }
            var windowsRef: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
            guard error == .success, let windows = windowsRef as? [AXUIElement] else {
                result.incomplete = true
                result.failureCodes.append(Int(error.rawValue))
                result.details.append("\(target.bundleID): cannot read windows (AX error \(error.rawValue)).")
                continue
            }
            let startCount = result.evidence.count
            var controlsRead = 0
            var nodesRead = 0
            var menuControls: [Control] = []
            // Menu commands only corroborate a live meeting window; they never start a call alone.
            if native == .zoom, let menu = attribute(app, kAXMenuBarAttribute), CFGetTypeID(menu) == AXUIElementGetTypeID() {
                let element = unsafeDowncast(menu, to: AXUIElement.self)
                menuControls = walk(element, service: .zoom, title: nil, deadline: Date().addingTimeInterval(0.9),
                     allowMenuItems: true, controlsRead: &controlsRead, nodesRead: &nodesRead, result: &result, enabledServices: enabledServices)
            }
            let appDeadline = Date().addingTimeInterval(native == .zoom ? 3.5 : 2)
            for window in windows {
                guard Date() < appDeadline else { result.incomplete = true; break }
                let title = native == .zoom ? attribute(window, kAXTitleAttribute) as? String : nil
                walk(window, service: native, title: title,
                     deadline: min(appDeadline, Date().addingTimeInterval(1)), allowMenuItems: false,
                     controlsRead: &controlsRead, nodesRead: &nodesRead, result: &result, menuControls: menuControls, enabledServices: enabledServices)
            }
            let matched = result.evidence.count - startCount
            result.details.append("\(target.bundleID): \(windows.count) windows, \(nodesRead) elements, \(controlsRead) controls, \(matched) meeting matches.")
            for evidence in result.evidence.dropFirst(startCount) {
                result.details.append("\(evidence.service.rawValue): \(evidence.signal.rawValue).")
            }
        }
        if result.incomplete { result.details.append("Some reads failed or reached the scan limit.") }
        return result
    }

    @discardableResult private static func walk(_ root: AXUIElement, service: MeetingService?, title: String?, deadline: Date,
                             allowMenuItems: Bool, controlsRead: inout Int, nodesRead: inout Int,
                             result: inout ScanResult, menuControls: [Control] = [], enabledServices: Set<MeetingService>) -> [Control] {
        let attributes = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
            kAXHelpAttribute, kAXEnabledAttribute, kAXChildrenAttribute, kAXURLAttribute,
            kAXDocumentAttribute, kAXValueAttribute] as CFArray
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        var visited = Set<AXUIElement>()
        var controls: [Control] = []
        while index < queue.count {
            guard visited.count < 5000, Date() < deadline else { result.incomplete = true; break }
            let (element, depth) = queue[index]
            index += 1
            guard depth < 60, visited.insert(element).inserted else { continue }
            var valuesRef: CFArray?
            let error = AXUIElementCopyMultipleAttributeValues(element, attributes, [], &valuesRef)
            guard error == .success, let values = valuesRef as? [Any], values.count == 9 else {
                result.incomplete = true
                if !result.failureCodes.contains(Int(error.rawValue)) { result.failureCodes.append(Int(error.rawValue)) }
                continue
            }
            nodesRead += 1
            let role = values[0] as? String ?? ""
            if role == "AXWebArea", service == nil {
                let url = (values[6] as? URL)?.absoluteString ?? (values[6] as? String) ?? (values[7] as? String) ?? ""
                if let webService = Detection.webService(url: url, enabledServices: enabledServices) {
                    walk(element, service: webService, title: nil, deadline: deadline, allowMenuItems: false,
                         controlsRead: &controlsRead, nodesRead: &nodesRead, result: &result, enabledServices: enabledServices)
                }
                continue
            }
            let enabled = values[4] as? Bool
            let isMenuItem = allowMenuItems && role == "AXMenuItem" && enabled == true
            let isButton = ["AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXToggleButton"].contains(role)
            if service != nil, enabled != false, isButton || isMenuItem {
                controlsRead += 1
                for field in [1, 2, 3, 8] {
                    if let label = values[field] as? String, !label.isEmpty { controls.append(Control(label)) }
                }
            }
            if allowMenuItems && role == "AXMenuItem" && enabled == false { continue }
            let children = values[5] as? [AXUIElement] ?? []
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        if !allowMenuItems, let service, let evidence = Detection.evaluate(service: service, controls: controls, windowTitle: title, menuControls: menuControls) {
            result.evidence.append(evidence)
        }
        return controls
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
