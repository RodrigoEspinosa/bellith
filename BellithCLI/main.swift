import Foundation

let version = "0.1.0"

func printUsage() {
    let usage = """
    bellith \(version) — drive the Bellith terminal from the shell

    Usage:
      bellith open [path]              Open a new tab, optionally at <path> (default: cwd)
      bellith split [--right|--down] [cmd...]
                                       Split the active pane and optionally run a command
      bellith ssh <profile>            Launch a saved SSH profile by name
      bellith creative status          Read saved Resolve evidence as JSON (not live state)
      bellith review <resolve|logic|logic-track> <proposal-id> [--print-url]
                                       Open a proposal for native review; never execute it
      bellith mcp                      Serve saved evidence and review-only proposals over MCP stdio
      bellith --help                   Show this help
      bellith --version                Print the CLI version

    The running Bellith app handles the request via the bellith:// URL scheme.
    """
    FileHandle.standardError.write(Data((usage + "\n").utf8))
}

func die(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data(("bellith: " + message + "\n").utf8))
    exit(code)
}

func absolutePath(_ raw: String) -> String {
    let expanded = (raw as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") { return expanded }
    let cwd = FileManager.default.currentDirectoryPath
    return (cwd as NSString).appendingPathComponent(expanded)
}

func buildURL(host: String, items: [URLQueryItem]) -> URL {
    var components = URLComponents()
    components.scheme = "bellith"
    components.host = host
    components.queryItems = items.isEmpty ? nil : items
    guard let url = components.url else { die("failed to build URL") }
    return url
}

func openURL(_ url: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-b", "com.rec.bellith", url.absoluteString]
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            die("'open' exited with status \(process.terminationStatus)", code: process.terminationStatus)
        }
    } catch {
        die("failed to launch 'open': \(error.localizedDescription)")
    }
}

let args = Array(CommandLine.arguments.dropFirst())

guard let command = args.first else {
    printUsage()
    exit(1)
}

switch command {
case "review":
    guard args.count == 3 || (args.count == 4 && args[3] == "--print-url"),
          let tool = CreativeReviewLink.Tool(rawValue: args[1]), let id = UUID(uuidString: args[2]) else {
        die("usage: bellith review <resolve|logic|logic-track> <proposal-id> [--print-url]")
    }
    let url = CreativeReviewLink(tool: tool, proposalID: id).url
    if args.count == 4 { print(url.absoluteString) }
    else { openURL(url) }
case "--help", "-h", "help":
    printUsage()
    exit(0)

case "--version", "-v":
    print("bellith \(version)")
    exit(0)

case "creative", "mcp":
    var file = CreativeEvidence.defaultSessionFile
    var logicFile = LogicTransportInbox.defaultFile
    var creativeScope: String?
    var logicObservationID: UUID?
    let remaining = command == "creative" ? Array(args.dropFirst(2)) : Array(args.dropFirst())
    if command == "creative", args.count < 2 || args[1] != "status" { die("usage: bellith creative status") }
    var index = 0
    var seen = Set<String>()
    while index < remaining.count {
        let option = remaining[index]
        guard index + 1 < remaining.count, seen.insert(option).inserted else { die("unexpected evidence arguments") }
        let url = URL(fileURLWithPath: absolutePath(remaining[index + 1]))
        switch option {
        case "--session-file": file = url
        case "--logic-session-file": logicFile = url
        case "--creative-scope":
            guard command == "mcp", ["resolve", "logic"].contains(remaining[index + 1]) else { die("invalid creative scope") }
            creativeScope = remaining[index + 1]
        case "--logic-observation-id":
            guard command == "mcp", let id = UUID(uuidString: remaining[index + 1]) else { die("invalid Logic observation ID") }
            logicObservationID = id
        default: die("unexpected evidence arguments")
        }
        index += 2
    }
    if command == "mcp" { CreativeEvidence.serve(file: file, logicFile: logicFile, logicObservationID: logicObservationID, scope: creativeScope) }
    else {
        do {
            let data = try JSONSerialization.data(withJSONObject: CreativeEvidence.read(file), options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data + Data([10]))
        } catch { die("saved session could not be read or validated") }
    }

case "open":
    let rawPath = args.count >= 2 ? args[1] : FileManager.default.currentDirectoryPath
    let path = absolutePath(rawPath)
    let url = buildURL(host: "open", items: [URLQueryItem(name: "path", value: path)])
    openURL(url)

case "split":
    var direction = "right"
    var rest: [String] = []
    var i = 1
    while i < args.count {
        let token = args[i]
        switch token {
        case "--right": direction = "right"
        case "--down": direction = "down"
        case "--":
            rest.append(contentsOf: args[(i + 1)...])
            i = args.count
        default:
            rest.append(contentsOf: args[i...])
            i = args.count
        }
        i += 1
    }
    var items = [URLQueryItem(name: "direction", value: direction)]
    if !rest.isEmpty {
        items.append(URLQueryItem(name: "cmd", value: rest.joined(separator: " ")))
    }
    let url = buildURL(host: "split", items: items)
    openURL(url)

case "ssh":
    guard args.count >= 2 else { die("usage: bellith ssh <profile>") }
    let name = args[1...].joined(separator: " ")
    let url = buildURL(host: "ssh", items: [URLQueryItem(name: "profile", value: name)])
    openURL(url)

default:
    die("unknown command '\(command)'. Run 'bellith --help' for usage.")
}
