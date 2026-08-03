import Dispatch
import Foundation
import Testing
@testable import MuesliNativeApp

private final class SendableTestProcessBox: @unchecked Sendable {
    let process = Process()
}

private final class SendableEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [String] = []

    func append(_ event: String) {
        lock.lock()
        storedEvents.append(event)
        lock.unlock()
    }

    var events: [String] {
        lock.lock()
        let value = storedEvents
        lock.unlock()
        return value
    }
}

@Suite("Computer Use executor", .serialized)
struct ComputerUseExecutorTests {
    @Test("executor rejects actions while the main runtime is disabled")
    @MainActor
    func executorRequiresRuntime() async {
        SyntheticEventPostingGate.shared.setRuntimeEnabled(false)
        let result = await ComputerUseToolExecutor.execute(
            ComputerUseToolCall(tool: .listApps),
            registry: nil
        )
        #expect(result.status == .cancelled)
    }

    @Test("maps common app aliases to bundle identifiers")
    @MainActor
    func commonAppAliases() {
        #expect(ComputerUseExecutor.bundleIdentifierAlias(for: "Google Chrome") == "com.google.Chrome")
        #expect(ComputerUseExecutor.bundleIdentifierAlias(for: "chrome") == "com.google.Chrome")
        #expect(ComputerUseExecutor.bundleIdentifierAlias(for: "VS Code") == "com.microsoft.VSCode")
        #expect(ComputerUseExecutor.bundleIdentifierAlias(for: "tail scale") == "io.tailscale.ipn.macsys")
        #expect(ComputerUseExecutor.bundleIdentifierAlias(for: "Tailscale") == "io.tailscale.ipn.macsys")
    }

    @Test("maps spoken key names to virtual key codes")
    @MainActor
    func spokenKeyNames() {
        #expect(ComputerUseExecutor.keyCode(for: "l") == 37)
        #expect(ComputerUseExecutor.keyCode(for: "enter") == 36)
        #expect(ComputerUseExecutor.keyCode(for: "left arrow") == 123)
    }

    @Test("maps scroll directions to CG wheel deltas")
    @MainActor
    func scrollDirectionDeltas() {
        #expect(ComputerUseToolExecutor.scrollDeltas(direction: .up, pages: 1).vertical > 0)
        #expect(ComputerUseToolExecutor.scrollDeltas(direction: .down, pages: 1).vertical < 0)
        #expect(ComputerUseToolExecutor.scrollDeltas(direction: .left, pages: 1).horizontal < 0)
        #expect(ComputerUseToolExecutor.scrollDeltas(direction: .right, pages: 1).horizontal > 0)
    }

    @Test("element click fails stale snapshot instead of falling through")
    @MainActor
    func elementClickFailsStaleSnapshot() async {
        SyntheticEventPostingGate.shared.setRuntimeEnabled(true)
        defer { SyntheticEventPostingGate.shared.setRuntimeEnabled(false) }
        let registry = ComputerUseElementRegistry()
        let result = await ComputerUseToolExecutor.execute(
            ComputerUseToolCall(tool: .click, elementIndex: 9, label: "Search"),
            registry: registry
        )

        #expect(result.status == .failed)
        #expect(result.message.contains("Stale or unknown element_index 9"))
    }

    @Test("secondary action rejects stale snapshot")
    @MainActor
    func secondaryActionRejectsStaleSnapshot() async {
        SyntheticEventPostingGate.shared.setRuntimeEnabled(true)
        defer { SyntheticEventPostingGate.shared.setRuntimeEnabled(false) }
        let registry = ComputerUseElementRegistry()
        let result = await ComputerUseToolExecutor.execute(
            ComputerUseToolCall(tool: .performSecondaryAction, elementIndex: 9, actionName: "AXShowMenu", label: "More"),
            registry: registry
        )

        #expect(result.status == .failed)
        #expect(result.message.contains("Stale or unknown element_index 9"))
    }

    @Test("element scroll rejects stale snapshot")
    @MainActor
    func elementScrollRejectsStaleSnapshot() async {
        SyntheticEventPostingGate.shared.setRuntimeEnabled(true)
        defer { SyntheticEventPostingGate.shared.setRuntimeEnabled(false) }
        let registry = ComputerUseElementRegistry()
        let result = await ComputerUseToolExecutor.execute(
            ComputerUseToolCall(tool: .scroll, elementIndex: 9, direction: .down),
            registry: registry
        )

        #expect(result.status == .failed)
        #expect(result.message.contains("Stale or unknown element_index 9"))
    }

    @Test("parses browser tab Apple Events output")
    func parsesBrowserTabs() {
        let tabs = ComputerUseBrowserAutomation.parseTabs(
            output: "1\t1\ttrue\tHacker News\thttps://news.ycombinator.com/\n1\t2\tfalse\tYouTube\thttps://youtube.com/\n",
            appBundleID: "com.google.Chrome"
        )

        #expect(tabs.count == 2)
        #expect(tabs[0].windowIndex == 1)
        #expect(tabs[0].tabIndex == 1)
        #expect(tabs[0].isActive)
        #expect(tabs[1].title == "YouTube")
    }

    @Test("lists browser tabs with mocked Apple Events adapter")
    func listsBrowserTabs() async {
        ComputerUseBrowserAutomation.runAppleScriptForTests = { script in
            #expect(script.contains("application id \"com.google.Chrome\""))
            return "1\t1\ttrue\tHacker News\thttps://news.ycombinator.com/\n"
        }
        defer { ComputerUseBrowserAutomation.runAppleScriptForTests = nil }

        let result = await ComputerUseBrowserAutomation.listTabs(appBundleID: "com.google.Chrome")

        #expect(result.status == .executed)
        #expect(result.message.contains("Hacker News"))
    }

    @Test("activates browser tab with mocked Apple Events adapter")
    func activatesBrowserTab() async {
        ComputerUseBrowserAutomation.runAppleScriptForTests = { script in
            #expect(script.contains("active tab index of window 2 to 3"))
            return ""
        }
        defer { ComputerUseBrowserAutomation.runAppleScriptForTests = nil }

        let result = await ComputerUseBrowserAutomation.activateTab(appBundleID: "com.google.Chrome", windowIndex: 2, tabIndex: 3)

        #expect(result.status == .executed)
    }

    @Test("browser automation preserves cancellation")
    func browserAutomationPreservesCancellation() async {
        ComputerUseBrowserAutomation.runAppleScriptForTests = { _ in
            throw CancellationError()
        }
        defer { ComputerUseBrowserAutomation.runAppleScriptForTests = nil }

        let result = await ComputerUseBrowserAutomation.listTabs(appBundleID: "com.google.Chrome")

        #expect(result.status == .cancelled)
    }

    @Test("cancellation requested before child launch prevents a PID")
    func browserProcessPreLaunchCancellationIsDeterministic() {
        let launchHookReached = DispatchSemaphore(value: 0)
        let allowLaunch = DispatchSemaphore(value: 0)
        let cancellationRequested = DispatchSemaphore(value: 0)
        let launchFinished = DispatchSemaphore(value: 0)
        let cancelFinished = DispatchSemaphore(value: 0)
        let testProcess = SendableTestProcessBox()
        testProcess.process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        testProcess.process.arguments = ["10"]
        let processBox = AppleScriptProcessBox(
            beforeLaunch: {
                launchHookReached.signal()
                _ = allowLaunch.wait(timeout: .now() + 1)
            },
            onCancellationRequested: {
                cancellationRequested.signal()
            }
        )

        DispatchQueue.global().async {
            try? processBox.launch(testProcess.process)
            launchFinished.signal()
        }
        #expect(launchHookReached.wait(timeout: .now() + 1) == .success)

        DispatchQueue.global().async {
            processBox.cancel()
            cancelFinished.signal()
        }
        #expect(cancellationRequested.wait(timeout: .now() + 1) == .success)

        allowLaunch.signal()
        #expect(launchFinished.wait(timeout: .now() + 1) == .success)
        #expect(cancelFinished.wait(timeout: .now() + 1) == .success)
        #expect(testProcess.process.processIdentifier == 0)
    }

    @Test("cancellation terminates an already launched child promptly")
    func browserProcessCancellationTerminatesChild() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["10"]
        let processBox = AppleScriptProcessBox()

        try processBox.launch(process)
        #expect(process.processIdentifier > 0)
        let cancelledAt = Date()
        processBox.cancel()
        process.waitUntilExit()

        #expect(!process.isRunning)
        #expect(Date().timeIntervalSince(cancelledAt) < 2)
    }

    @Test("cancellation after process exit suppresses successful completion")
    func browserProcessLateCancellationSuppressesCompletion() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let processBox = AppleScriptProcessBox()
        var delivered = false

        try processBox.launch(process)
        process.waitUntilExit()
        processBox.cancel()
        let completed = processBox.completeIfNotCancelled {
            delivered = true
        }

        #expect(!completed)
        #expect(!delivered)
    }

    @Test("completion delivery is atomic against concurrent cancellation")
    func browserProcessCompletionLinearizesBeforeCancellation() {
        let completionBoundaryReached = DispatchSemaphore(value: 0)
        let allowCompletion = DispatchSemaphore(value: 0)
        let cancellationAttempted = DispatchSemaphore(value: 0)
        let completionFinished = DispatchSemaphore(value: 0)
        let cancellationFinished = DispatchSemaphore(value: 0)
        let recorder = SendableEventRecorder()
        let processBox = AppleScriptProcessBox(
            beforeCompletion: {
                completionBoundaryReached.signal()
                _ = allowCompletion.wait(timeout: .now() + 1)
            },
            onCancellationAttempt: {
                cancellationAttempted.signal()
            },
            onCancellationRequested: {
                recorder.append("cancelled")
            }
        )

        DispatchQueue.global().async {
            _ = processBox.completeIfNotCancelled {
                recorder.append("delivered")
            }
            completionFinished.signal()
        }
        #expect(completionBoundaryReached.wait(timeout: .now() + 1) == .success)

        DispatchQueue.global().async {
            processBox.cancel()
            cancellationFinished.signal()
        }
        #expect(cancellationAttempted.wait(timeout: .now() + 1) == .success)

        allowCompletion.signal()
        #expect(completionFinished.wait(timeout: .now() + 1) == .success)
        #expect(cancellationFinished.wait(timeout: .now() + 1) == .success)
        #expect(recorder.events == ["delivered", "cancelled"])
    }

    @Test("browser process drains stdout larger than a pipe buffer")
    func browserProcessDrainsLargeOutput() async throws {
        ComputerUseBrowserAutomation.runAppleScriptForTests = nil
        let chunk = String(repeating: "x", count: 1024)
        let script = """
        set outputText to ""
        set outputChunk to "\(chunk)"
        repeat 256 times
            set outputText to outputText & outputChunk
        end repeat
        return outputText
        """

        let output = try await ComputerUseBrowserAutomation.runAppleScript(script)

        #expect(output.count == 256 * 1024)
    }

    @Test("navigates safe URLs and rejects unsafe URLs")
    func navigatesSafeURLsAndRejectsUnsafeURLs() async {
        var capturedScript = ""
        ComputerUseBrowserAutomation.runAppleScriptForTests = { script in
            capturedScript = script
            return ""
        }
        defer { ComputerUseBrowserAutomation.runAppleScriptForTests = nil }

        let safe = await ComputerUseBrowserAutomation.navigate(
            appBundleID: "com.google.Chrome",
            windowIndex: 1,
            tabIndex: 1,
            url: "https://www.google.com/search?q=hello&hl=en"
        )
        let unsafe = await ComputerUseBrowserAutomation.navigate(
            appBundleID: "com.google.Chrome",
            windowIndex: nil,
            tabIndex: nil,
            url: "javascript:alert(1)"
        )

        #expect(safe.status == .executed)
        #expect(capturedScript.contains("https://www.google.com/search?q=hello&hl=en"))
        #expect(unsafe.status == .needsConfirmation)
    }

    @Test("navigate URL validates tab hints before targeting")
    func navigateURLValidatesTabHintsBeforeTargeting() {
        let script = ComputerUseBrowserAutomation.navigateScript(
            appBundleID: "com.google.Chrome",
            windowIndex: 1,
            tabIndex: 16,
            url: "https://www.youtube.com/results?search_query=Drake+latest+song"
        )

        #expect(script.contains("set targetTab to active tab of targetWindow"))
        #expect(script.contains("if 16 <= (count of tabs of targetWindow) then"))
        #expect(script.contains("set targetTab to tab 16 of targetWindow"))
        #expect(!script.contains("tab 16 of window 1"))
        #expect(script.contains("used active tab fallback"))
    }

    @Test("opens new browser tab with mocked Apple Events adapter")
    func opensNewBrowserTab() async {
        var capturedScript = ""
        ComputerUseBrowserAutomation.runAppleScriptForTests = { script in
            capturedScript = script
            return ""
        }
        defer { ComputerUseBrowserAutomation.runAppleScriptForTests = nil }

        let result = await ComputerUseBrowserAutomation.openNewTab(appBundleID: "com.google.Chrome")

        #expect(result.status == .executed)
        #expect(capturedScript.contains("make new tab"))
        #expect(capturedScript.contains("active tab index of front window"))
    }

    @Test("page text and DOM query use read-only JavaScript")
    func pageTextAndDOMQueryUseReadOnlyJavaScript() async {
        var scripts: [String] = []
        ComputerUseBrowserAutomation.runAppleScriptForTests = { script in
            scripts.append(script)
            return "result"
        }
        defer { ComputerUseBrowserAutomation.runAppleScriptForTests = nil }

        let text = await ComputerUseBrowserAutomation.pageText(appBundleID: "com.google.Chrome", windowIndex: 1, tabIndex: 1)
        let dom = await ComputerUseBrowserAutomation.queryDOM(
            appBundleID: "com.google.Chrome",
            windowIndex: 1,
            tabIndex: 1,
            selector: "a.storylink",
            attributes: ["href"]
        )

        #expect(text.status == .executed)
        #expect(dom.status == .executed)
        #expect(scripts.allSatisfy { $0.contains("execute javascript") })
        #expect(scripts[1].contains("querySelectorAll"))
    }
}
