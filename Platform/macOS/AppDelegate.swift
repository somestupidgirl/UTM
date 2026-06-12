//
// Copyright © 2021 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

@MainActor class AppDelegate: NSObject, NSApplicationDelegate {
    private enum TerminateError: Error {
        case wrapped(originalError: any Error, window: NSWindow?)
    }

    var data: UTMData?

    @Setting("KeepRunningAfterLastWindowClosed") private var isKeepRunningAfterLastWindowClosed: Bool = false
    @Setting("HideDockIcon") private var isDockIconHidden: Bool = false
    @Setting("NoQuitConfirmation") private var isNoQuitConfirmation: Bool = false
    @Setting("PauseOnSleep") private var isPauseOnSleep: Bool = true

    /// IDs of VMs that were running when the host went to sleep and were auto-paused.
    /// Only these VMs will be auto-resumed on wake — VMs the user paused manually are not touched.
    private var sleepPausedVMIds: Set<UUID> = []
    private var sleepObserver: Any?
    private var wakeObserver: Any?
    
    private var runningVirtualMachines: [VMData] {
        guard let vmList = data?.vmWindows.keys else {
            return []
        }
        return vmList.filter({ $0.wrapped?.state == .started || ($0.wrapped?.state == .paused && !$0.hasSuspendState) })
    }
    
    @MainActor
    @objc var scriptingVirtualMachines: [UTMScriptingVirtualMachineImpl] {
        guard let data = data else {
            return []
        }
        return data.virtualMachines.compactMap { vm in
            if vm.wrapped != nil {
                return UTMScriptingVirtualMachineImpl(for: vm, data: data)
            } else {
                return nil
            }
        }
    }
    
    @MainActor
    @objc var isAutoTerminate: Bool {
        get {
            !isKeepRunningAfterLastWindowClosed
        }
        
        set {
            isKeepRunningAfterLastWindowClosed = !newValue
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !isKeepRunningAfterLastWindowClosed && runningVirtualMachines.isEmpty
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let data = data else {
            return .terminateNow
        }
        guard !isNoQuitConfirmation else {
            return .terminateNow
        }

        let vmList = data.vmWindows.keys
        let runningList = runningVirtualMachines
        if !runningList.isEmpty { // There is at least 1 running VM
            handleTerminateAfterSaving(candidates: runningList, sender: sender)
            return .terminateLater
        } else if vmList.allSatisfy({ !$0.isLoaded || $0.wrapped?.state == .stopped }) { // All VMs are stopped or suspended
            return .terminateNow
        } else { // There could be some VMs in other states (starting, pausing, etc.)
            return .terminateCancel
        }
    }
    
    private func handleTerminateAfterSaving(candidates: some Sequence<VMData>, sender: NSApplication) {
        Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for vm in candidates {
                        group.addTask {
                            let vc = await self.data?.vmWindows[vm] as? VMDisplayWindowController
                            let window = await vc?.window
                            guard let vm = await vm.wrapped else {
                                throw UTMVirtualMachineError.notImplemented
                            }
                            do {
                                try await vm.saveSnapshot(name: nil)
                                vm.delegate = nil
                                await vc?.enterSuspended(isBusy: false)
                                if let window = window {
                                    await window.close()
                                }
                            } catch {
                                throw TerminateError.wrapped(originalError: error, window: window)
                            }
                        }
                    }
                    try await group.waitForAll()
                }
                NSApplication.shared.reply(toApplicationShouldTerminate: true)
            } catch TerminateError.wrapped(let originalError, let window) {
                handleTerminateAfterConfirmation(sender, window: window, error: originalError)
            } catch {
                handleTerminateAfterConfirmation(sender, error: error)
            }
        }
    }
    
    private func handleTerminateAfterConfirmation(_ sender: NSApplication, window: NSWindow? = nil, error: Error? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        if error == nil {
            alert.messageText = NSLocalizedString("Confirmation", comment: "AppDelegate")
        } else {
            alert.messageText = NSLocalizedString("Failed to save suspend state", comment: "AppDelegate")
        }
        alert.informativeText = NSLocalizedString("Quitting UTM will kill all running VMs.", comment: "VMQemuDisplayMetalWindowController")
        if let error = error {
            alert.informativeText = error.localizedDescription + "\n" + alert.informativeText
        }
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "VMDisplayWindowController"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "VMDisplayWindowController"))
        alert.showsSuppressionButton = true
        let confirm = { (response: NSApplication.ModalResponse) in
            switch response {
            case .alertFirstButtonReturn:
                if alert.suppressionButton?.state == .on {
                    self.isNoQuitConfirmation = true
                }
                NSApplication.shared.reply(toApplicationShouldTerminate: true)
            default:
                NSApplication.shared.reply(toApplicationShouldTerminate: false)
            }
        }
        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: confirm)
        } else {
            let response = alert.runModal()
            confirm(response)
        }
    }
    
    // MARK: - Sleep / wake

    private func registerSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        sleepObserver = nc.addObserver(forName: NSWorkspace.willSleepNotification,
                                       object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleSystemWillSleep() }
        }
        wakeObserver = nc.addObserver(forName: NSWorkspace.didWakeNotification,
                                      object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleSystemDidWake() }
        }
    }

    private func handleSystemWillSleep() {
        guard isPauseOnSleep, let data = data else { return }
        sleepPausedVMIds = []
        for vm in data.vmWindows.keys {
            guard let wrapped = vm.wrapped, wrapped.state == .started else { continue }
            wrapped.requestVmPause(save: false)
            sleepPausedVMIds.insert(vm.id)
        }
        logger.debug("Sleep: paused \(self.sleepPausedVMIds.count) VM(s)")
    }

    private func handleSystemDidWake() {
        guard isPauseOnSleep, !sleepPausedVMIds.isEmpty, let data = data else { return }
        for vm in data.vmWindows.keys {
            guard sleepPausedVMIds.contains(vm.id),
                  let wrapped = vm.wrapped,
                  wrapped.state == .paused else { continue }
            wrapped.requestVmResume()
        }
        logger.debug("Wake: resumed \(self.sleepPausedVMIds.count) VM(s)")
        sleepPausedVMIds = []
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let sleepObserver = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        if let wakeObserver = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        /// Synchronize registry
        UTMRegistry.shared.sync()
        /// Clean up caches
        let fileManager = FileManager.default
        guard let cacheUrl = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        guard let urls = try? fileManager.contentsOfDirectory(at: cacheUrl, includingPropertiesForKeys: nil, options: []) else {
            return
        }
        for url in urls {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue {
                try? fileManager.removeItem(at: url)
            }
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if isDockIconHidden {
            NSApp.setActivationPolicy(.accessory)
        }
        registerSleepWakeObservers()
    }
    
    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        switch key {
        case "scriptingVirtualMachines": return true
        case "scriptingUsbDevices": return true
        case "isAutoTerminate": return true
        default: return false
        }
    }
}
