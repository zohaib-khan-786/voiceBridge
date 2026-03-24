package com.voicebridge.voicebridge_flutter

import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * WhatsAppAccessibilityService
 *
 * Watches for WhatsApp window events.  When [pasteAndSend] is called:
 *   1. Copies the translated text to clipboard.
 *   2. Finds WhatsApp's message input field and sets text via ACTION_SET_TEXT.
 *   3. Clicks the send button.
 *
 * The service is enabled from Settings → Accessibility → VoiceBridge.
 * Enable programmatically by directing user to the Accessibility settings.
 */
class WhatsAppAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "VB_Accessibility"

        // WhatsApp package names
        private val WHATSAPP_PACKAGES = setOf(
            "com.whatsapp",
            "com.whatsapp.w4b",   // WhatsApp Business
        )

        // Known input field resource IDs across WhatsApp versions
        private val INPUT_IDS = listOf(
            "com.whatsapp:id/entry",
            "com.whatsapp.w4b:id/entry",
            "com.whatsapp:id/message_text",
        )

        // Known send button resource IDs
        private val SEND_IDS = listOf(
            "com.whatsapp:id/send",
            "com.whatsapp.w4b:id/send",
            "com.whatsapp:id/send_btn",
        )

        /** Singleton reference — set on service connect, cleared on disconnect. */
        var instance: WhatsAppAccessibilityService? = null
            private set
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastActivePackage: String? = null

    // ── Service lifecycle ──────────────────────────────────────────────────

    override fun onServiceConnected() {
        instance = this
        Log.i(TAG, "Accessibility service connected")
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onInterrupt() { /* required */ }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        val pkg = event.packageName?.toString() ?: return
        if (pkg in WHATSAPP_PACKAGES) lastActivePackage = pkg
    }

    // ── Public API ─────────────────────────────────────────────────────────

    /**
     * Paste [text] into the active WhatsApp chat input and click Send.
     * Call this from the main thread (or it will be posted to main).
     */
    fun pasteAndSend(text: String) {
        handler.post { doPasteAndSend(text) }
    }

    // ── Implementation ─────────────────────────────────────────────────────

    private fun doPasteAndSend(text: String) {
        // Copy to clipboard as fallback
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("VoiceBridge", text))

        val root = rootInActiveWindow
        if (root == null) {
            Log.w(TAG, "No active window — clipboard copy done, manual paste needed")
            return
        }

        // Try to find input field by known resource IDs first
        var inputNode = findNodeById(root, INPUT_IDS)

        // Fallback: find editable field
        if (inputNode == null) {
            inputNode = findEditableNode(root)
        }

        if (inputNode == null) {
            Log.w(TAG, "Input node not found — text is in clipboard for manual paste")
            root.recycle()
            return
        }

        // Set text via ACTION_SET_TEXT
        val args = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                text
            )
        }
        val setOk = inputNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        Log.d(TAG, "ACTION_SET_TEXT result: $setOk")

        // If ACTION_SET_TEXT unsupported (older Android), paste from clipboard
        if (!setOk) {
            inputNode.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            inputNode.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        }

        inputNode.recycle()

        // Small delay to let WhatsApp process the text before clicking Send
        handler.postDelayed({
            val freshRoot = rootInActiveWindow ?: return@postDelayed
            val sendNode  = findNodeById(freshRoot, SEND_IDS)
                ?: findSendButton(freshRoot)
            if (sendNode != null) {
                sendNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                sendNode.recycle()
                Log.i(TAG, "Send clicked ✅")
            } else {
                Log.w(TAG, "Send button not found — text set but not sent")
            }
            freshRoot.recycle()
        }, 300)
    }

    // ── Node finders ───────────────────────────────────────────────────────

    private fun findNodeById(
        root: AccessibilityNodeInfo,
        ids: List<String>
    ): AccessibilityNodeInfo? {
        for (id in ids) {
            val nodes = root.findAccessibilityNodeInfosByViewId(id)
            if (nodes.isNotEmpty()) return nodes[0]
        }
        return null
    }

    private fun findEditableNode(root: AccessibilityNodeInfo): AccessibilityNodeInfo? =
        traverseForEditable(root)

    private fun traverseForEditable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isEditable) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = traverseForEditable(child)
            if (found != null) return found
            child.recycle()
        }
        return null
    }

    private fun findSendButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        // Look for ImageButton with content description "Send"
        return traverseForSend(root)
    }

    private fun traverseForSend(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val desc = node.contentDescription?.toString()?.lowercase() ?: ""
        if (node.isClickable && (desc.contains("send") || desc.contains("إرسال"))) {
            return node
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = traverseForSend(child)
            if (found != null) return found
            child.recycle()
        }
        return null
    }
}