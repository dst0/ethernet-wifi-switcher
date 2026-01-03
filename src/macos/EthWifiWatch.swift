import Foundation
import SystemConfiguration

// Configuration from command line arguments
let args = CommandLine.arguments
if args.count < 7 {
    print("Usage: \(args[0]) <helperPath> <helperLog> <helperErr> <daemonLabel> <wifiDev> <ethDev>")
    exit(1)
}

let helperPath = args[1]
let helperLog = args[2]
let helperErr = args[3]
let daemonLabel = args[4]
let wifiDev = args[5]
let ethDev = args[6]

// Single check after delay to let network settle
let retryDelays: [TimeInterval] = [2.0]

// Prevent callback storms from spawning multiple batches
let minGapBetweenBatches: TimeInterval = 5.0
var lastBatch = Date(timeIntervalSince1970: 0)

func log(_ msg: String) {
    print("[\(Date())] \(msg)")
    fflush(stdout)
}

func runHelper(reason: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-lc", "\(helperPath) >> \"\(helperLog)\" 2>> \"\(helperErr)\""]
    do {
        try p.run()
        p.waitUntilExit()
        log("helper-ran: \(reason) exit=\(p.terminationStatus)")
    } catch {
        log("helper-failed: \(reason) error=\(error)")
    }
}

func runBatch(reason: String) {
    let now = Date()
    if now.timeIntervalSince(lastBatch) < minGapBetweenBatches {
        return // quiet: no debounce logs
    }
    lastBatch = now

    log("batch-start: \(reason) retries=\(retryDelays.count)")
    for (i, d) in retryDelays.enumerated() {
        DispatchQueue.global().asyncAfter(deadline: .now() + d) {
            runHelper(reason: "\(reason)#\(i+1) delay=\(d)s")
        }
    }
}

let callback: SCDynamicStoreCallBack = { _, _, _ in
    runBatch(reason: "network-change")
}

guard let store = SCDynamicStoreCreate(nil, daemonLabel as CFString, callback, nil) else {
    fputs("Failed to create SCDynamicStore\n", stderr)
    exit(1)
}

// Global + interface keys to capture unplug/plug reliably
let keys = [
    "State:/Network/Global/IPv4",
    "State:/Network/Global/IPv6",
    "State:/Network/Interface/\(wifiDev)/IPv4",
    "State:/Network/Interface/\(ethDev)/IPv4"
] as CFArray

SCDynamicStoreSetNotificationKeys(store, keys, nil)

guard let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) else {
    fputs("Failed to create run loop source\n", stderr)
    exit(1)
}

CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)

// Startup batch
runBatch(reason: "startup")

CFRunLoopRun()
