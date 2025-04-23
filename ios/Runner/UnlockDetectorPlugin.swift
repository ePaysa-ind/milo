import Flutter
import UIKit
import Foundation
import NotificationCenter

/// Plugin for detecting device unlock events on iOS.
///
/// This Swift implementation handles device unlock detection for the Milo app's
/// therapeutic nudge system. It uses various iOS-specific APIs to detect unlocks
/// in a battery-efficient manner.
///
/// - Note: iOS doesn't have a direct "device unlock" broadcast like Android.
///   Instead, this plugin uses a combination of notifications about application state
///   changes and screen state to infer when unlocks happen.
@objc public class UnlockDetectorPlugin: NSObject, FlutterPlugin {
    // MARK: - Constants

    /// Name of the method channel
    private static let methodChannelName = "com.milo.unlock_detector/methods"

    /// Name of the event channel
    private static let eventChannelName = "com.milo.unlock_detector/events"

    /// User defaults suite name
    private static let userDefaultsSuiteName = "com.milo.unlock_detector"

    /// Key for last unlock time
    private static let keyLastUnlockTime = "last_unlock_time"

    /// Key for implementation mode
    private static let keyImplementationMode = "implementation_mode"

    // MARK: - Properties

    /// Method channel for Flutter communication
    private var methodChannel: FlutterMethodChannel?

    /// Event channel for Flutter communication
    private var eventChannel: FlutterEventChannel?

    /// Event sink for sending events to Flutter
    private var eventSink: FlutterEventSink?

    /// Flag indicating if the plugin is initialized
    private var isInitialized = false

    /// Flag indicating if the plugin is listening for events
    private var isListening = false

    /// Implementation mode for different iOS versions
    private var implementationMode = "default"

    /// Last time a device unlock was detected
    private var lastUnlockTime: TimeInterval = 0

    /// User defaults for persistence
    private var userDefaults: UserDefaults?

    /// Background task identifier
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

    /// Reference to the shared plugin instance
    private static var sharedInstance: UnlockDetectorPlugin?

    /// Total number of events detected
    private var totalEventsDetected = 0

    /// Total number of unlock events detected
    private var totalUnlockEvents = 0

    /// Total number of errors encountered
    private var totalErrors = 0

    // MARK: - Plugin Registration

    /// Register the plugin with the Flutter engine.
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = UnlockDetectorPlugin()
        instance.setupChannels(registrar: registrar)
        sharedInstance = instance
    }

    /// Set up method and event channels
    private func setupChannels(registrar: FlutterPluginRegistrar) {
        methodChannel = FlutterMethodChannel(
            name: UnlockDetectorPlugin.methodChannelName,
            binaryMessenger: registrar.messenger()
        )

        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else {
                result(FlutterError(code: "PLUGIN_DEALLOCATED",
                                   message: "Plugin instance has been deallocated",
                                   details: nil))
                return
            }

            self.handleMethodCall(call, result: result)
        }

        eventChannel = FlutterEventChannel(
            name: UnlockDetectorPlugin.eventChannelName,
            binaryMessenger: registrar.messenger()
        )

        eventChannel?.setStreamHandler(self)

        // Initialize user defaults
        userDefaults = UserDefaults(suiteName: UnlockDetectorPlugin.userDefaultsSuiteName)

        // Load last unlock time from user defaults
        if let defaults = userDefaults {
            lastUnlockTime = defaults.double(forKey: UnlockDetectorPlugin.keyLastUnlockTime)
            implementationMode = defaults.string(forKey: UnlockDetectorPlugin.keyImplementationMode) ?? "default"
        }

        logInfo("Channels set up")
    }

    // MARK: - Method Call Handling

    /// Handle method calls from Flutter
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isUnlockDetectionSupported":
            result(isUnlockDetectionSupported())

        case "requestUnlockPermissions":
            requestUnlockPermissions { granted in
                result(granted)
            }

        case "setImplementationMode":
            if let args = call.arguments as? [String: Any],
               let mode = args["mode"] as? String {
                setImplementationMode(mode)
                result(true)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS",
                                   message: "Invalid arguments for setImplementationMode",
                                   details: nil))
            }

        case "startUnlockDetection":
            startUnlockDetection { success in
                result(success)
            }

        case "stopUnlockDetection":
            stopUnlockDetection()
            result(true)

        case "isUnlockDetectionRunning":
            result(isListening)

        case "getLastUnlockTimestamp":
            // Convert to milliseconds for consistency with Android
            result(Int(lastUnlockTime * 1000))

        case "getCapabilities":
            result(getCapabilities())

        case "getPlatformInfo":
            result(getPlatformInfo())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Initialization and Device Capabilities

    /// Initialize the plugin with required setup
    private func initialize() -> Bool {
        if isInitialized {
            return true
        }

        do {
            // No special initialization needed for iOS
            isInitialized = true
            logInfo("Plugin initialized")
            return true
        } catch {
            logError("Error initializing plugin: \(error.localizedDescription)")
            return false
        }
    }

    /// Check if unlock detection is supported on this device
    private func isUnlockDetectionSupported() -> Bool {
        // All iOS devices support basic detection through app state notifications
        return true
    }

    /// Request permissions needed for unlock detection
    private func requestUnlockPermissions(completion: @escaping (Bool) -> Void) {
        // No special permissions needed for basic functionality on iOS
        completion(true)
    }

    /// Set the implementation mode
    private func setImplementationMode(_ mode: String) {
        implementationMode = mode

        // Save to user defaults
        userDefaults?.set(implementationMode, forKey: UnlockDetectorPlugin.keyImplementationMode)

        logInfo("Implementation mode set to: \(implementationMode)")
    }

    // MARK: - Device Unlock Detection

    /// Start detecting device unlocks
    private func startUnlockDetection(completion: @escaping (Bool) -> Void) {
        if isListening {
            logInfo("Already listening for unlocks")
            completion(true)
            return
        }

        guard initialize() else {
            completion(false)
            return
        }

        // Register for notifications about application state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        // Register for screen lock/unlock notifications via Darwin notification center
        // This is a private API technique that works on recent iOS versions
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()

        // com.apple.springboard.lockstate is a private notification on iOS
        let lockStateNotification = "com.apple.springboard.lockstate" as CFString

        CFNotificationCenterAddObserver(
            notificationCenter,
            Unmanaged.passUnretained(self).toOpaque(),
            { (_, observer, name, _, _) in
                let plugin = Unmanaged<UnlockDetectorPlugin>.fromOpaque(observer!).takeUnretainedValue()
                if let notificationName = name {
                    if CFEqual(notificationName, "com.apple.springboard.lockstate" as CFString) {
                        plugin.handleLockStateChange()
                    }
                }
            },
            lockStateNotification,
            nil,
            .deliverImmediately
        )

        isListening = true
        logInfo("Started listening for unlocks")
        completion(true)
    }

    /// Stop detecting device unlocks
    private func stopUnlockDetection() {
        // Remove all observers
        NotificationCenter.default.removeObserver(self)

        // Remove Darwin notification center observer
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(
            notificationCenter,
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil
        )

        isListening = false
        logInfo("Stopped listening for unlocks")
    }

    /// Handle lock state changes from Darwin notification center
    private func handleLockStateChange() {
        // This gets called when the device lock state changes
        // We'll check our app state to determine if this is an unlock event

        // If the app is active, this might be an unlock event
        if UIApplication.shared.applicationState == .active {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.checkForUnlock()
            }
        }
    }

    /// Handle the application transitioning to foreground
    @objc private func applicationWillEnterForeground(_ notification: Notification) {
        logInfo("App will enter foreground")

        // Start a background task to ensure we have time to process
        beginBackgroundTaskIfNeeded()

        // This might be from an unlock, schedule a check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkForUnlock()
        }
    }

    /// Handle the application becoming active
    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        logInfo("App did become active")

        // End background task if running
        endBackgroundTaskIfNeeded()

        // This is the most reliable indicator of an unlock on iOS
        // when the app is in the foreground
        checkForUnlock()
    }

    /// Handle the application resigning active state
    @objc private func applicationWillResignActive(_ notification: Notification) {
        logInfo("App will resign active")

        // Start a background task to ensure we have time to process
        beginBackgroundTaskIfNeeded()
    }

    /// Handle the application entering background
    @objc private func applicationDidEnterBackground(_ notification: Notification) {
        logInfo("App did enter background")

        // End background task with delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.endBackgroundTaskIfNeeded()
        }
    }

    /// Begin a background task if needed to ensure processing time
    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTaskIdentifier == .invalid else {
            return
        }

        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "UnlockDetectionTask") {
            // Expiration handler
            self.endBackgroundTaskIfNeeded()
        }
    }

    /// End the background task if it's running
    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskIdentifier != .invalid else {
            return
        }

        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
    }

    /// Check if a device unlock has occurred
    private func checkForUnlock() {
        let now = Date().timeIntervalSince1970

        // Don't process duplicates (events within short time of each other)
        if now - lastUnlockTime < 2.0 {
            logInfo("Ignoring duplicate unlock event")
            return
        }

        // Update last unlock time
        lastUnlockTime = now

        // Save to user defaults
        userDefaults?.set(lastUnlockTime, forKey: UnlockDetectorPlugin.keyLastUnlockTime)

        // Format time for logs
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timeString = formatter.string(from: Date(timeIntervalSince1970: now))

        logInfo("Device unlocked at \(timeString)")
        totalEventsDetected += 1
        totalUnlockEvents += 1

        // Send event to Flutter
        let event: [String: Any] = [
            "type": "unlock",
            "timestamp": Int(now * 1000), // Convert to milliseconds
            "formattedTime": timeString
        ]

        sendEvent(event)
    }

    /// Send an event to Flutter
    private func sendEvent(_ event: [String: Any]) {
        if let eventSink = eventSink {
            DispatchQueue.main.async {
                eventSink(event)
            }
        }
    }

    // MARK: - Device Capabilities

    /// Get device capabilities for adaptive behavior
    private func getCapabilities() -> [String: Bool] {
        var capabilities = [String: Bool]()

        capabilities["unlockDetectionSupported"] = true
        capabilities["screenStateDetectionSupported"] = true
        capabilities["backgroundDetectionSupported"] = true

        // iOS-specific capabilities
        capabilities["userNotificationsSupported"] = true
        capabilities["appStateTrackingSupported"] = true
        capabilities["backgroundProcessingSupported"] = true

        return capabilities
    }

    /// Get platform information for adaptive behavior
    private func getPlatformInfo() -> [String: Any] {
        let systemVersion = UIDevice.current.systemVersion

        return [
            "platform": "ios",
            "systemVersion": systemVersion,
            "model": UIDevice.current.model,
            "implementationMode": implementationMode
        ]
    }

    // MARK: - Logging

    /// Log an info message
    private func logInfo(_ message: String) {
        NSLog("[UnlockDetectorPlugin] INFO: \(message)")
    }

    /// Log a warning message
    private func logWarn(_ message: String) {
        NSLog("[UnlockDetectorPlugin] WARN: \(message)")
    }

    /// Log an error message
    private func logError(_ message: String) {
        NSLog("[UnlockDetectorPlugin] ERROR: \(message)")
        totalErrors += 1
    }

    // MARK: - Deinitialization

    deinit {
        // Clean up observers
        NotificationCenter.default.removeObserver(self)

        // Remove Darwin notification center observer
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(
            notificationCenter,
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil
        )

        // End any background tasks
        endBackgroundTaskIfNeeded()

        logInfo("Plugin deinitialized")
    }
}

// MARK: - FlutterStreamHandler Implementation

extension UnlockDetectorPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        logInfo("Event listener registered")
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        logInfo("Event listener cancelled")
        return nil
    }
}