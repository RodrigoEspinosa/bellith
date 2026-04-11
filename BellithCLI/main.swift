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
    process.arguments = ["-a", "Bellith", url.absoluteString]
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
case "--help", "-h", "help":
    printUsage()
    exit(0)

case "--version", "-v":
    print("bellith \(version)")
    exit(0)

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
