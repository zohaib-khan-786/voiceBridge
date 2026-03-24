package com.voicebridge.voicebridge_flutter

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

/**
 * MainActivity — Flutter host + native bridge.
 *
 * MethodChannel  "voicebridge/overlay"  handles:
 *   checkOverlayPermission     → Boolean
 *   requestOverlayPermission   → void (opens Settings)
 *   startOverlayService        → void
 *   stopOverlayService         → void
 *   checkAccessibility         → Boolean
 *   requestAccessibility       → void (opens Accessibility settings)
 *   sendToWhatsApp(text)       → void (paste + send via Accessibility)
 *   copyToClipboard(text)      → void
 *   goBackToWhatsApp           → void
 *
 * EventChannel "voicebridge/overlay_events" pushes:
 *   "show_drawer"  — when the floating bubble is tapped
 */
class MainActivity : FlutterActivity() {

    private val CHANNEL      = "voicebridge/overlay"
    private val EVENT_CHANNEL = "voicebridge/overlay_events"

    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Method channel ────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "checkOverlayPermission" -> {
                        result.success(hasOverlayPermission())
                    }

                    "requestOverlayPermission" -> {
                        if (!hasOverlayPermission()) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    }

                    "startOverlayService" -> {
                        if (hasOverlayPermission()) {
                            OverlayService.start(this)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }

                    "stopOverlayService" -> {
                        OverlayService.stop(this)
                        result.success(null)
                    }

                    "checkAccessibility" -> {
                        result.success(isAccessibilityEnabled())
                    }

                    "requestAccessibility" -> {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(null)
                    }

                    "sendToWhatsApp" -> {
                        val text = call.argument<String>("text") ?: ""
                        val service = WhatsAppAccessibilityService.instance
                        if (service != null && text.isNotBlank()) {
                            // Go back to WhatsApp first, then paste
                            goToWhatsApp()
                            android.os.Handler(mainLooper).postDelayed({
                                service.pasteAndSend(text)
                            }, 500)
                            result.success(true)
                        } else {
                            // Fallback: copy to clipboard + open WhatsApp
                            copyToClipboard(text)
                            goToWhatsApp()
                            result.success(false) // false = clipboard fallback
                        }
                    }

                    "copyToClipboard" -> {
                        val text = call.argument<String>("text") ?: ""
                        copyToClipboard(text)
                        result.success(null)
                    }

                    "goBackToWhatsApp" -> {
                        goToWhatsApp()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        // ── Event channel ─────────────────────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }
                override fun onCancel(args: Any?) {
                    eventSink = null
                }
            })
    }

    // ── Handle bubble tap via new intent ──────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleOverlayIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleOverlayIntent(intent)
    }

    private fun handleOverlayIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(OverlayService.EXTRA_SHOW_OVERLAY, false) == true) {
            // Small delay to let Flutter engine finish mounting
            android.os.Handler(mainLooper).postDelayed({
                eventSink?.success("show_drawer")
            }, 300)
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private fun hasOverlayPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            Settings.canDrawOverlays(this)
        else
            true

    private fun isAccessibilityEnabled(): Boolean {
        val serviceName = "$packageName/${WhatsAppAccessibilityService::class.java.name}"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return TextUtils.SimpleStringSplitter(':').apply {
            setString(enabledServices)
        }.any { it.equals(serviceName, ignoreCase = true) }
    }

    private fun copyToClipboard(text: String) {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("VoiceBridge", text))
    }

    private fun goToWhatsApp() {
        // Try to bring WhatsApp to the foreground
        val pm = packageManager
        val packages = listOf("com.whatsapp", "com.whatsapp.w4b")
        for (pkg in packages) {
            val launchIntent = pm.getLaunchIntentForPackage(pkg)
            if (launchIntent != null) {
                launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(launchIntent)
                return
            }
        }
        // WhatsApp not installed — just minimise VoiceBridge
        moveTaskToBack(true)
    }
}