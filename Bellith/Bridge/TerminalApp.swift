import AppKit
import GhosttyKit

/// Wraps ghostty_app_t — the core terminal application instance.
/// Manages the runtime config callbacks and the app tick loop.
final class TerminalApp {
    private(set) var app: ghostty_app_t?
    private var tickTimer: Timer?

    /// Callback fired when libghostty requests an action (new tab, title change, etc.)
    var onAction: ((ghostty_target_s, ghostty_action_s) -> Bool)?

    init(config: TerminalConfig) {
        guard config.config != nil else { return }

        var runtimeCfg = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: { ud in
                guard let ud else { return }
                let app = Unmanaged<TerminalApp>.fromOpaque(ud).takeUnretainedValue()
                DispatchQueue.main.async { app.tick() }
            },
            action_cb: { appPtr, target, action in
                guard let appPtr, let ud = ghostty_app_userdata(appPtr) else { return false }
                let termApp = Unmanaged<TerminalApp>.fromOpaque(ud).takeUnretainedValue()
                return termApp.onAction?(target, action) ?? false
            },
            read_clipboard_cb: { ud, loc, state in
                // ud = surface userdata (TerminalSurfaceView)
                guard let ud else { return false }
                let surfaceView = Unmanaged<TerminalSurfaceView>.fromOpaque(ud).takeUnretainedValue()
                guard let surface = surfaceView.surface else { return false }

                let pasteboard = NSPasteboard.general
                guard let str = pasteboard.string(forType: .string) else { return false }
                str.withCString { ptr in
                    ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
                }
                return true
            },
            confirm_read_clipboard_cb: { ud, str, state, request in
                // Auto-confirm clipboard reads
                guard let ud else { return }
                let surfaceView = Unmanaged<TerminalSurfaceView>.fromOpaque(ud).takeUnretainedValue()
                guard let surface = surfaceView.surface else { return }

                let pasteboard = NSPasteboard.general
                guard let clipStr = pasteboard.string(forType: .string) else { return }
                clipStr.withCString { ptr in
                    ghostty_surface_complete_clipboard_request(surface, ptr, state, true)
                }
            },
            write_clipboard_cb: { ud, loc, content, len, confirm in
                guard let content, len > 0 else { return }
                let item = content.pointee
                if let data = item.data {
                    let str = String(cString: data)
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(str, forType: .string)
                }
            },
            close_surface_cb: { ud, processAlive in
                // ud = surface userdata (TerminalSurfaceView)
                guard let ud else { return }
                let surfaceView = Unmanaged<TerminalSurfaceView>.fromOpaque(ud).takeUnretainedValue()
                surfaceView.onClose?(processAlive)
            }
        )

        app = ghostty_app_new(&runtimeCfg, config.config)
        guard app != nil else { return }

        // Start the tick timer — drives the terminal event loop
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(tickTimer!, forMode: .common)
    }

    deinit {
        tickTimer?.invalidate()
        if let app { ghostty_app_free(app) }
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    func setFocus(_ focused: Bool) {
        guard let app else { return }
        ghostty_app_set_focus(app, focused)
    }

    func setColorScheme(_ scheme: ghostty_color_scheme_e) {
        guard let app else { return }
        ghostty_app_set_color_scheme(app, scheme)
    }

}
