import Foundation

func installWatcherLaunchAgent(paths: [String], noDownload: Bool = false) throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let launchAgentsDir = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

    let plistURL = launchAgentsDir.appendingPathComponent("com.privateindex.watcher.plist")

    let execPath: String
    if let bundlePath = Bundle.main.executablePath, FileManager.default.fileExists(atPath: bundlePath) {
        execPath = bundlePath
    } else {
        execPath = CommandLine.arguments[0]
    }

    let logsDir = home.appendingPathComponent(".private-index", isDirectory: true)
    try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    let logPath = logsDir.appendingPathComponent("watcher.log").path
    let errPath = logsDir.appendingPathComponent("watcher.err.log").path

    var argsLines: [String] = [
        "            <string>\(execPath)</string>",
        "            <string>watch</string>"
    ]
    for p in paths {
        argsLines.append("            <string>\(p)</string>")
    }
    if noDownload {
        argsLines.append("            <string>--no-download</string>")
    }
    let argsArray = argsLines.joined(separator: "\n")

    let plistContent = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.privateindex.watcher</string>
        <key>ProgramArguments</key>
        <array>
    \(argsArray)
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>StandardOutPath</key>
        <string>\(logPath)</string>
        <key>StandardErrorPath</key>
        <string>\(errPath)</string>
    </dict>
    </plist>
    """

    try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)

    // Unload existing if loaded (suppress stdout/stderr so unneeded "Unload failed" is not printed)
    let unloadProcess = Process()
    unloadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    unloadProcess.arguments = ["unload", plistURL.path]
    unloadProcess.standardOutput = Pipe()
    unloadProcess.standardError = Pipe()
    try? unloadProcess.run()
    unloadProcess.waitUntilExit()

    let loadProcess = Process()
    loadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    loadProcess.arguments = ["load", plistURL.path]
    try? loadProcess.run()
    loadProcess.waitUntilExit()

    let pathsDisplay = paths.joined(separator: ", ")
    print("""
    \(ANSI.bold)\(ANSI.green)✔ LaunchAgent installed successfully!\(ANSI.reset)
      • Plist:        \(ANSI.dim)\(plistURL.path)\(ANSI.reset)
      • Executable:   \(ANSI.dim)\(execPath)\(ANSI.reset)
      • Watch Target: \(ANSI.cyan)\(pathsDisplay)\(ANSI.reset)
      • Output Log:   \(ANSI.dim)\(logPath)\(ANSI.reset)
      • Error Log:    \(ANSI.dim)\(errPath)\(ANSI.reset)
      • Status:       Loaded into launchd (runs 24/7 headlessly on login)
    """)
}

func installWatcherLaunchAgent(path: String) throws {
    try installWatcherLaunchAgent(paths: [path])
}

func uninstallWatcherLaunchAgent() throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let plistURL = home.appendingPathComponent("Library/LaunchAgents/com.privateindex.watcher.plist")

    guard FileManager.default.fileExists(atPath: plistURL.path) else {
        print("\(ANSI.yellow)LaunchAgent is not currently installed.\(ANSI.reset) (\(plistURL.path) does not exist)")
        return
    }

    // Unload existing service, suppressing stderr/stdout
    let unloadProcess = Process()
    unloadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    unloadProcess.arguments = ["unload", plistURL.path]
    unloadProcess.standardOutput = Pipe()
    unloadProcess.standardError = Pipe()
    try? unloadProcess.run()
    unloadProcess.waitUntilExit()

    let bootoutProcess = Process()
    bootoutProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    bootoutProcess.arguments = ["bootout", "gui/\(getuid())/com.privateindex.watcher"]
    bootoutProcess.standardOutput = Pipe()
    bootoutProcess.standardError = Pipe()
    try? bootoutProcess.run()
    bootoutProcess.waitUntilExit()

    try FileManager.default.removeItem(at: plistURL)

    print("""
    \(ANSI.bold)\(ANSI.green)✔ LaunchAgent uninstalled successfully!\(ANSI.reset)
      • Plist removed:  \(ANSI.dim)\(plistURL.path)\(ANSI.reset)
      • Daemon stopped: \(ANSI.cyan)com.privateindex.watcher\(ANSI.reset)
    """)
}
