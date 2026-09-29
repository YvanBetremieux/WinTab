import AppKit

// Launch smoke test for scripts/check-bundle.sh: dyld resolves Sparkle.framework
// before main runs, so reaching this line proves the bundle can load it.
if CommandLine.arguments.dropFirst().first == "--version" {
    print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
