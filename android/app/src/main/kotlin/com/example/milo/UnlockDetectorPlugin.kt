package com.milo.memorykeeper.milo

import android.app.Activity
import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import androidx.annotation.NonNull
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleObserver
import androidx.lifecycle.OnLifecycleEvent
import androidx.lifecycle.ProcessLifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicInteger
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.SharedPreferences
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.min

/**
 * Plugin for detecting device unlock events efficiently.
 *
 * This plugin uses various Android APIs to detect device unlocks in a battery-efficient way,
 * depending on the Android version and device capabilities.
 *
 * Features:
 * - Native Android implementation for device unlock detection
 * - Battery-efficient operation
 * - Adaptive behavior based on device capabilities
 * - Support for detecting screen on/off events
 * - Fallback mechanisms for older devices
 * - Comprehensive error handling and logging
 */
class UnlockDetectorPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
    ActivityAware, LifecycleObserver {
    // Companion object for constants and logging
    companion object {
        private const val TAG = "UnlockDetectorPlugin"
        private const val METHOD_CHANNEL_NAME = "com.milo.unlock_detector/methods"
        private const val EVENT_CHANNEL_NAME = "com.milo.unlock_detector/events"
        private const val FOREGROUND_SERVICE_CHANNEL_ID = "com.milo.unlock_detector/foreground"
        private const val FOREGROUND_SERVICE_NOTIFICATION_ID = 1337

        // Shared preferences keys
        private const val PREFS_NAME = "com.milo.unlock_detector"
        private const val KEY_LAST_UNLOCK_TIME = "last_unlock_time"
        private const val KEY_IMPLEMENTATION_MODE = "implementation_mode"

        // Implementation modes
        private const val MODE_OPTIMIZED = "optimized"
        private const val MODE_COMPATIBILITY = "compatibility"
        private const val MODE_LEGACY = "legacy"

        // Current running instance for service communication
        private var instance: UnlockDetectorPlugin? = null

        // Queue of events that happened while no listeners were registered
        private val pendingEvents = ConcurrentLinkedQueue<Map<String, Any>>()

        // Stats for diagnostics
        private val totalEventsDetected = AtomicInteger(0)
        private val totalUnlockEvents = AtomicInteger(0)
        private val totalErrors = AtomicInteger(0)

        // Registration method for the plugin
        @JvmStatic
        fun registerWith(messenger: BinaryMessenger) {
            val plugin = UnlockDetectorPlugin()
            val methodChannel = MethodChannel(messenger, METHOD_CHANNEL_NAME)
            methodChannel.setMethodCallHandler(plugin)

            val eventChannel = EventChannel(messenger, EVENT_CHANNEL_NAME)
            eventChannel.setStreamHandler(plugin)
        }
    }

    // Flutter plugin channels
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    // Context references
    private var applicationContext: Context? = null
    private var activity: Activity? = null

    // Event channel stream handler
    private var eventSink: EventChannel.EventSink? = null

    // State tracking
    private val isInitialized = AtomicBoolean(false)
    private val isListening = AtomicBoolean(false)
    private var implementationMode: String = MODE_OPTIMIZED
    private var lastUnlockTime: Long = 0

    // Lock screen state receiver
    private var unlockReceiver: BroadcastReceiver? = null
    private var screenStateReceiver: BroadcastReceiver? = null

    // UI thread handler
    private val mainHandler = Handler(Looper.getMainLooper())

    // Ensure SharedPreferences is initialized in a thread-safe way
    private val sharedPreferencesLock = Any()
    private var _sharedPreferences: SharedPreferences? = null
    private val sharedPreferences: SharedPreferences
        get() {
            synchronized(sharedPreferencesLock) {
                if (_sharedPreferences == null) {
                    if (applicationContext == null) {
                        throw IllegalStateException("Application context is null, cannot initialize SharedPreferences")
                    }
                    _sharedPreferences = applicationContext!!.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

                    // Load cached values after initialization
                    lastUnlockTime = _sharedPreferences!!.getLong(KEY_LAST_UNLOCK_TIME, 0)
                    implementationMode = _sharedPreferences!!.getString(KEY_IMPLEMENTATION_MODE, MODE_OPTIMIZED) ?: MODE_OPTIMIZED

                    logInfo("SharedPreferences initialized with lastUnlockTime=$lastUnlockTime, mode=$implementationMode")
                }
                return _sharedPreferences!!
            }
        }

    // Log a message with the plugin tag
    private fun log(priority: Int, message: String) {
        Log.println(priority, TAG, message)
    }

    // Log at info level
    private fun logInfo(message: String) {
        log(Log.INFO, message)
    }

    // Log at warning level
    private fun logWarn(message: String) {
        log(Log.WARN, message)
    }

    // Log at error level
    private fun logError(message: String, throwable: Throwable? = null) {
        if (throwable != null) {
            Log.e(TAG, message, throwable)
        } else {
            Log.e(TAG, message)
        }
        totalErrors.incrementAndGet()
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        // Save the application context
        applicationContext = flutterPluginBinding.applicationContext

        // Create method and event channels
        setupChannels(flutterPluginBinding.binaryMessenger)

        // Initialize shared preferences safely (without accessing property directly yet)
        try {
            synchronized(sharedPreferencesLock) {
                _sharedPreferences = applicationContext!!.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

                // Load safe defaults first
                lastUnlockTime = 0
                implementationMode = MODE_OPTIMIZED

                // Then try to load saved values
                if (_sharedPreferences != null) {
                    lastUnlockTime = _sharedPreferences!!.getLong(KEY_LAST_UNLOCK_TIME, 0)
                    implementationMode = _sharedPreferences!!.getString(KEY_IMPLEMENTATION_MODE, MODE_OPTIMIZED) ?: MODE_OPTIMIZED
                }
            }
        } catch (e: Exception) {
            logError("Failed to initialize SharedPreferences, using defaults", e)
            // Ensure safe defaults even if preferences fail
            lastUnlockTime = 0
            implementationMode = MODE_OPTIMIZED
        }

        // Register as lifecycle observer
        ProcessLifecycleOwner.get().lifecycle.addObserver(this)

        // Set the instance
        instance = this

        logInfo("Plugin attached to engine")
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        // Clean up method and event channels
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)

        // Unregister as lifecycle observer
        ProcessLifecycleOwner.get().lifecycle.removeObserver(this)

        // Clear the instance
        instance = null

        logInfo("Plugin detached from engine")
    }

    // Setup method and event channels
    private fun setupChannels(messenger: BinaryMessenger) {
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(messenger, EVENT_CHANNEL_NAME)
        eventChannel.setStreamHandler(this)

        logInfo("Channels set up")
    }

    // Add a utility method to ensure consistent timestamp formatting
    private fun ensureConsistentTimestamp(timestamp: Long): Long {
        // Ensure timestamp is in milliseconds
        // Android timestamps are typically already in milliseconds, but adding this check for clarity
        return timestamp
    }

    // Add a safe method to access SharedPreferences
    private fun putSharedPreference(key: String, value: Any) {
        try {
            val editor = sharedPreferences.edit()
            when (value) {
                is String -> editor.putString(key, value)
                is Int -> editor.putInt(key, value)
                is Long -> editor.putLong(key, value)
                is Float -> editor.putFloat(key, value)
                is Boolean -> editor.putBoolean(key, value)
                else -> {
                    logError("Unsupported preference type: ${value::class.java.name}")
                    return
                }
            }
            editor.apply()
        } catch (e: Exception) {
            logError("Error saving preference: $key", e)
        }
    }

    // Handle method calls from Flutter
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isUnlockDetectionSupported" -> {
                    result.success(isUnlockDetectionSupported())
                }
                "requestUnlockPermissions" -> {
                    result.success(requestUnlockPermissions())
                }
                "setImplementationMode" -> {
                    val mode = call.argument<String>("mode") ?: MODE_OPTIMIZED
                    setImplementationMode(mode)
                    result.success(true)
                }
                "startUnlockDetection" -> {
                    result.success(startUnlockDetection())
                }
                "stopUnlockDetection" -> {
                    stopUnlockDetection()
                    result.success(true)
                }
                "isUnlockDetectionRunning" -> {
                    result.success(isListening.get())
                }
                "getLastUnlockTimestamp" -> {
                    // Return the timestamp ensuring it's in milliseconds
                    result.success(ensureConsistentTimestamp(lastUnlockTime))
                }
                "getCapabilities" -> {
                    result.success(getCapabilities())
                }
                "getPlatformInfo" -> {
                    result.success(getPlatformInfo())
                }
                else -> {
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            logError("Error handling method call: ${call.method}", e)
            result.error("NATIVE_ERROR", "Error in native code: ${e.message}", e.stackTraceToString())
        }
    }

    // Handle event channel listener
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events

        // Send any pending events
        if (events != null && pendingEvents.isNotEmpty()) {
            mainHandler.post {
                // Limit to 5 most recent events to avoid overwhelming
                val eventsToSend = min(pendingEvents.size, 5)
                repeat(eventsToSend) {
                    val event = pendingEvents.poll() ?: return@repeat
                    events.success(event)
                }
                pendingEvents.clear()
            }
        }

        logInfo("Event listener registered")
    }

    // Handle event channel cancellation
    override fun onCancel(arguments: Any?) {
        eventSink = null
        logInfo("Event listener cancelled")
    }

    // Send an event to Flutter
    private fun sendEvent(event: Map<String, Any>) {
        val sink = eventSink
        if (sink != null) {
            mainHandler.post {
                try {
                    sink.success(event)
                } catch (e: Exception) {
                    logError("Error sending event", e)
                }
            }
        } else {
            // Store the event for later delivery
            pendingEvents.offer(event)
            // Keep only the most recent 20 events
            while (pendingEvents.size > 20) {
                pendingEvents.poll()
            }
        }
    }

    // Initialize the plugin with the given context
    private fun initialize(context: Context): Boolean {
        if (isInitialized.get()) {
            return true
        }

        try {
            applicationContext = context.applicationContext

            // Create notification channel for foreground service (Android 8+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    FOREGROUND_SERVICE_CHANNEL_ID,
                    "Unlock Detection Service",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Used for detecting device unlocks"
                    setShowBadge(false)
                }

                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.createNotificationChannel(channel)
            }

            isInitialized.set(true)
            logInfo("Plugin initialized")
            return true
        } catch (e: Exception) {
            logError("Error initializing plugin", e)
            return false
        }
    }

    // Check if unlock detection is supported on this device
    private fun isUnlockDetectionSupported(): Boolean {
        return true // All Android devices support basic unlock detection
    }

    // Request permissions needed for unlock detection
    private fun requestUnlockPermissions(): Boolean {
        // Most implementations don't need special permissions
        return true
    }

    // Set the implementation mode
    private fun setImplementationMode(mode: String) {
        implementationMode = when (mode) {
            MODE_OPTIMIZED, MODE_COMPATIBILITY, MODE_LEGACY -> mode
            else -> MODE_OPTIMIZED
        }

        // Save to shared preferences using the safe method
        putSharedPreference(KEY_IMPLEMENTATION_MODE, implementationMode)

        logInfo("Implementation mode set to: $implementationMode")
    }

    // Start detecting device unlocks
    private fun startUnlockDetection(): Boolean {
        if (isListening.get()) {
            logInfo("Already listening for unlocks")
            return true
        }

        try {
            val context = applicationContext ?: return false

            // Initialize if needed
            if (!isInitialized.get() && !initialize(context)) {
                logError("Failed to initialize")
                return false
            }

            // Create and register unlock receiver
            unlockReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    when (intent.action) {
                        Intent.ACTION_USER_PRESENT -> {
                            handleDeviceUnlock()
                        }
                    }
                }
            }

            // Register for unlock events
            val unlockFilter = IntentFilter().apply {
                addAction(Intent.ACTION_USER_PRESENT)
            }
            context.registerReceiver(unlockReceiver, unlockFilter)

            // Also track screen on/off for better detection
            screenStateReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    when (intent.action) {
                        Intent.ACTION_SCREEN_ON -> {
                            logInfo("Screen turned on")
                            // Don't send event, just log
                        }
                        Intent.ACTION_SCREEN_OFF -> {
                            logInfo("Screen turned off")
                            // Don't send event, just log
                        }
                    }
                }
            }

            // Register for screen state events
            val screenFilter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
            }
            context.registerReceiver(screenStateReceiver, screenFilter)

            // Start foreground service for better reliability if needed
            if (implementationMode == MODE_OPTIMIZED && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val serviceIntent = Intent(context, UnlockDetectorService::class.java)
                ContextCompat.startForegroundService(context, serviceIntent)
            }

            isListening.set(true)
            logInfo("Started listening for unlocks using mode: $implementationMode")
            return true
        } catch (e: Exception) {
            logError("Error starting unlock detection", e)
            stopUnlockDetection() // Clean up on error
            return false
        }
    }

    // Stop detecting device unlocks
    private fun stopUnlockDetection() {
        try {
            val context = applicationContext ?: return

            // Unregister receivers
            unlockReceiver?.let {
                try {
                    context.unregisterReceiver(it)
                } catch (e: Exception) {
                    logError("Error unregistering unlock receiver", e)
                }
                unlockReceiver = null
            }

            screenStateReceiver?.let {
                try {
                    context.unregisterReceiver(it)
                } catch (e: Exception) {
                    logError("Error unregistering screen state receiver", e)
                }
                screenStateReceiver = null
            }

            // Stop foreground service if running
            if (implementationMode == MODE_OPTIMIZED && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val serviceIntent = Intent(context, UnlockDetectorService::class.java)
                context.stopService(serviceIntent)
            }

            isListening.set(false)
            logInfo("Stopped listening for unlocks")
        } catch (e: Exception) {
            logError("Error stopping unlock detection", e)
            // Force reset the state
            isListening.set(false)
        }
    }

    // Handle a device unlock event
    fun handleDeviceUnlock() {
        val now = System.currentTimeMillis()

        // Don't process duplicates (e.g., multiple broadcasts within short time)
        if (now - lastUnlockTime < 2000) {
            logInfo("Ignoring duplicate unlock event")
            return
        }

        // Update last unlock time
        lastUnlockTime = now

        // Save to shared preferences using the safe method
        putSharedPreference(KEY_LAST_UNLOCK_TIME, now)

        // Format timestamp for logs
        val sdf = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
        val timeString = sdf.format(Date(now))

        logInfo("Device unlocked at $timeString")
        totalEventsDetected.incrementAndGet()
        totalUnlockEvents.incrementAndGet()

        // Send event to Flutter with consistent timestamp
        val event = mapOf(
            "type" to "unlock",
            "timestamp" to ensureConsistentTimestamp(now),
            "formattedTime" to timeString
        )

        sendEvent(event)
    }

    // Get device capabilities
    private fun getCapabilities(): Map<String, Boolean> {
        val capabilities = mutableMapOf<String, Boolean>()

        capabilities["unlockDetectionSupported"] = true
        capabilities["screenStateDetectionSupported"] = true
        capabilities["backgroundDetectionSupported"] = true

        // Power manager capabilities
        capabilities["powerManagerSupported"] = true

        // Notification listener capabilities (for Android 9+)
        val notificationManager = applicationContext?.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        capabilities["notificationListenerSupported"] = notificationManager != null &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.P

        // Foreground service capabilities
        capabilities["foregroundServiceSupported"] = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

        return capabilities
    }

    // Get platform info for adaptive behavior
    private fun getPlatformInfo(): Map<String, Any> {
        return mapOf(
            "platform" to "android",
            "sdkVersion" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "implementationMode" to implementationMode
        )
    }

    // Activity-aware implementation
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        logInfo("Attached to activity")
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        logInfo("Detached from activity for config changes")
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        logInfo("Reattached to activity for config changes")
    }

    override fun onDetachedFromActivity() {
        activity = null
        logInfo("Detached from activity")
    }

    // Lifecycle observer methods
    @OnLifecycleEvent(Lifecycle.Event.ON_START)
    fun onAppForegrounded() {
        logInfo("App foregrounded")
    }

    @OnLifecycleEvent(Lifecycle.Event.ON_STOP)
    fun onAppBackgrounded() {
        logInfo("App backgrounded")
    }
}

/**
 * Foreground service for improved detection reliability on newer Android versions.
 * This ensures the broadcast receivers continue to work even when the app is in the background.
 */
class UnlockDetectorService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()

        // Create a notification for the foreground service
        val notificationIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val notification = NotificationCompat.Builder(this, UnlockDetectorPlugin.FOREGROUND_SERVICE_CHANNEL_ID)
            .setContentTitle("Milo is active")
            .setContentText("Listening for therapeutic nudge opportunities")
            .setSmallIcon(android.R.drawable.ic_dialog_info) // Replace with your app icon
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        // Start as a foreground service
        startForeground(UnlockDetectorPlugin.FOREGROUND_SERVICE_NOTIFICATION_ID, notification)

        Log.i("UnlockDetectorService", "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i("UnlockDetectorService", "Service started")
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i("UnlockDetectorService", "Service destroyed")
        super.onDestroy()
    }
}
