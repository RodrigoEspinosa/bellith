import Foundation
import Darwin

/// A single network connection belonging to a process.
struct ConnectionInfo {
    let pid: pid_t
    let processName: String
    let family: Int32          // AF_INET / AF_INET6
    let proto: Int32           // IPPROTO_TCP / IPPROTO_UDP
    let localAddress: String
    let localPort: UInt16
    let remoteAddress: String
    let remotePort: UInt16
    let state: String          // TCP state name

    var protocolName: String {
        proto == IPPROTO_TCP ? "TCP" : (proto == IPPROTO_UDP ? "UDP" : "?")
    }

    var displayRemote: String {
        remotePort > 0 ? "\(remoteAddress):\(remotePort)" : remoteAddress
    }

    var displayLocal: String {
        "\(localAddress):\(localPort)"
    }
}

/// Inspects network connections for a set of PIDs using proc_pidinfo.
/// Works for the current user's processes without entitlements.
final class NetworkMonitor {

    /// Get all network connections for the given PIDs.
    static func connections(for pids: [pid_t]) -> [ConnectionInfo] {
        var results: [ConnectionInfo] = []
        for pid in pids {
            results.append(contentsOf: connections(for: pid))
        }
        return results
    }

    /// Get network connections for a single PID.
    static func connections(for pid: pid_t) -> [ConnectionInfo] {
        let name = processName(pid: pid)

        // Get file descriptor list size
        let bufSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufSize > 0 else { return [] }

        let fdCount = Int(bufSize) / MemoryLayout<proc_fdinfo>.size
        var fdInfos = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
        let actual = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fdInfos, bufSize)
        guard actual > 0 else { return [] }

        let actualCount = Int(actual) / MemoryLayout<proc_fdinfo>.size
        var results: [ConnectionInfo] = []

        for i in 0..<actualCount {
            let fd = fdInfos[i]
            guard fd.proc_fdtype == PROX_FDTYPE_SOCKET else { continue }

            var socketInfo = socket_fdinfo()
            let infoSize = MemoryLayout<socket_fdinfo>.size
            let ret = proc_pidfdinfo(
                pid, fd.proc_fd, PROC_PIDFDSOCKETINFO,
                &socketInfo, Int32(infoSize)
            )
            guard ret == infoSize else { continue }

            let sockInfo = socketInfo.psi
            let family = Int32(sockInfo.soi_family)
            let sockType = Int32(sockInfo.soi_type)

            // Only interested in TCP and UDP (inet sockets)
            guard family == AF_INET || family == AF_INET6 else { continue }
            guard sockType == SOCK_STREAM || sockType == SOCK_DGRAM else { continue }

            let proto = sockType == SOCK_STREAM ? IPPROTO_TCP : IPPROTO_UDP
            let state = proto == IPPROTO_TCP ? tcpStateName(Int32(sockInfo.soi_proto.pri_tcp.tcpsi_state)) : "—"

            let connInfo = sockInfo.soi_proto.pri_tcp.tcpsi_ini
            let (localAddr, localPort) = extractLocalAddress(family: family, ini: connInfo)
            let (remoteAddr, remotePort) = extractForeignAddress(family: family, ini: connInfo)

            results.append(ConnectionInfo(
                pid: pid, processName: name,
                family: family, proto: Int32(proto),
                localAddress: localAddr, localPort: localPort,
                remoteAddress: remoteAddr, remotePort: remotePort,
                state: state
            ))
        }

        return results
    }

    // MARK: - Helpers

    private static func extractLocalAddress(family: Int32, ini: in_sockinfo) -> (String, UInt16) {
        let portNum = UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_lport))
        if family == AF_INET {
            var sin = ini.insi_laddr.ina_46.i46a_addr4
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &sin, &buf, socklen_t(INET_ADDRSTRLEN))
            return (String(cString: buf), portNum)
        } else {
            var sin6 = ini.insi_laddr.ina_6
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            inet_ntop(AF_INET6, &sin6, &buf, socklen_t(INET6_ADDRSTRLEN))
            return (String(cString: buf), portNum)
        }
    }

    private static func extractForeignAddress(family: Int32, ini: in_sockinfo) -> (String, UInt16) {
        let portNum = UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_fport))
        if family == AF_INET {
            var sin = ini.insi_faddr.ina_46.i46a_addr4
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &sin, &buf, socklen_t(INET_ADDRSTRLEN))
            return (String(cString: buf), portNum)
        } else {
            var sin6 = ini.insi_faddr.ina_6
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            inet_ntop(AF_INET6, &sin6, &buf, socklen_t(INET6_ADDRSTRLEN))
            return (String(cString: buf), portNum)
        }
    }

    private static func tcpStateName(_ state: Int32) -> String {
        switch state {
        case 0:  return "CLOSED"
        case 1:  return "LISTEN"
        case 2:  return "SYN_SENT"
        case 3:  return "SYN_RCVD"
        case 4:  return "ESTABLISHED"
        case 5:  return "CLOSE_WAIT"
        case 6:  return "FIN_WAIT_1"
        case 7:  return "CLOSING"
        case 8:  return "LAST_ACK"
        case 9:  return "FIN_WAIT_2"
        case 10: return "TIME_WAIT"
        default: return "UNKNOWN"
        }
    }

    private static func processName(pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_name(pid, &buffer, UInt32(buffer.count))
        return ret > 0 ? String(cString: buffer) : "pid:\(pid)"
    }

    /// Resolve a remote address to a hostname asynchronously.
    static func resolveHostname(_ address: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var hints = addrinfo()
            hints.ai_flags = AI_NUMERICHOST
            var result: UnsafeMutablePointer<addrinfo>?

            guard getaddrinfo(address, nil, &hints, &result) == 0, let ai = result else {
                completion(nil)
                return
            }
            defer { freeaddrinfo(result) }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let ret = getnameinfo(
                ai.pointee.ai_addr, ai.pointee.ai_addrlen,
                &hostname, socklen_t(hostname.count),
                nil, 0, 0
            )
            if ret == 0 {
                let name = String(cString: hostname)
                completion(name != address ? name : nil)
            } else {
                completion(nil)
            }
        }
    }
}
