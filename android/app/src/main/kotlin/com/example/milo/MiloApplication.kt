package com.example.milo

import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * Application class for Milo app.
 *
 * This class is responsible for initializing the Flutter engine
 * and registering plugins, including our custom UnlockDetectorPlugin.
 */
class MiloApplication : FlutterApplication(), PluginRegistry.PluginRegistrantCallback {
    override fun onCreate() {
        super.onCreate()

        // Initialize and cache a FlutterEngine for better startup performance
        val flutterEngine = FlutterEngine(this)
        flutterEngine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())

        // Register the Flutter plugins
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // Register our custom plugin
        UnlockDetectorPluginRegistrant.registerWith(flutterEngine)

        // Cache the engine
        FlutterEngineCache.getInstance().put("milo_engine", flutterEngine)
    }

    override fun registerWith(registry: PluginRegistry) {
        // This is needed for backwards compatibility with older Flutter versions
        // Our UnlockDetectorPlugin will be registered via the FlutterEngine
    }
}