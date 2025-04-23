package com.milo.memorykeeper.milo

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.shim.ShimPluginRegistry

/**
 * Plugin registrant for the UnlockDetectorPlugin.
 *
 * This class helps register our native code with Flutter without modifying MainActivity.
 */
object UnlockDetectorPluginRegistrant {
    // Register the plugin in the FlutterEngine's plugin registry
    fun registerWith(flutterEngine: FlutterEngine) {
        // Register our custom unlock detector plugin
        val unlockDetectorPlugin = UnlockDetectorPlugin()
        flutterEngine.plugins.add(unlockDetectorPlugin)
    }
}

