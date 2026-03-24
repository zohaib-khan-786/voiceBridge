package com.voicebridge.voicebridge_flutter

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.os.*
import android.view.*
import android.widget.*
import androidx.core.app.NotificationCompat

/**
 * OverlayService — draws a draggable floating bubble over any app (including WhatsApp).
 *
 * Lifecycle:
 *   startForegroundService(Intent(ctx, OverlayService::class.java))
 *   stopService(Intent(ctx, OverlayService::class.java))
 *
 * Tapping the bubble launches MainActivity with SHOW_OVERLAY_DRAWER = true.
 */
class OverlayService : Service() {

    private lateinit var windowManager: WindowManager
    private var bubbleView: View? = null
    private val CHANNEL_ID = "voicebridge_overlay"
    private val NOTIF_ID   = 1001

    // ── Service lifecycle ──────────────────────────────────────────────────

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
        showBubble()
    }

    override fun onDestroy() {
        removeBubble()
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    // ── Bubble ─────────────────────────────────────────────────────────────

    private fun showBubble() {
        val bubble = buildBubbleView()
        bubbleView = bubble

        val params = WindowManager.LayoutParams(
            dpToPx(64), dpToPx(64),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dpToPx(16)
            y = dpToPx(200)
        }

        windowManager.addView(bubble, params)
        makeDraggable(bubble, params)
    }

    private fun buildBubbleView(): View {
        val ctx = this

        // Outer container
        val frame = FrameLayout(ctx).apply {
            elevation = dpToPx(8).toFloat()
        }

        // Circle background
        val circle = View(ctx).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                colors = intArrayOf(Color.parseColor("#25D366"), Color.parseColor("#128C7E"))
                gradientType = GradientDrawable.LINEAR_GRADIENT
                setStroke(dpToPx(2), Color.parseColor("#075E54"))
            }
        }
        frame.addView(circle, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Globe emoji label
        val label = TextView(ctx).apply {
            text = "🌐"
            textSize = 26f
            gravity = Gravity.CENTER
        }
        frame.addView(label, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        return frame
    }

    private fun removeBubble() {
        bubbleView?.let {
            try { windowManager.removeView(it) } catch (_: Exception) {}
            bubbleView = null
        }
    }

    // ── Drag + tap ─────────────────────────────────────────────────────────

    private fun makeDraggable(view: View, params: WindowManager.LayoutParams) {
        var initialX = 0; var initialY = 0
        var touchX   = 0f; var touchY  = 0f
        var moved    = false

        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x;  initialY = params.y
                    touchX   = event.rawX; touchY  = event.rawY
                    moved    = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - touchX).toInt()
                    val dy = (event.rawY - touchY).toInt()
                    if (Math.abs(dx) > 5 || Math.abs(dy) > 5) moved = true
                    params.x = initialX + dx
                    params.y = initialY + dy
                    windowManager.updateViewLayout(view, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) openOverlayDrawer()
                    true
                }
                else -> false
            }
        }
    }

    // ── Open drawer ────────────────────────────────────────────────────────

    private fun openOverlayDrawer() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_SHOW_OVERLAY, true)
        }
        startActivity(intent)
    }

    // ── Notification ───────────────────────────────────────────────────────

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("VoiceBridge Active")
            .setContentText("Tap the 🌐 bubble to translate")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "VoiceBridge Overlay",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Floating bubble for quick translation"
                setShowBadge(false)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private fun dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density).toInt()

    companion object {
        const val EXTRA_SHOW_OVERLAY = "show_overlay_drawer"

        fun start(context: Context) {
            val intent = Intent(context, OverlayService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                context.startForegroundService(intent)
            else
                context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, OverlayService::class.java))
        }
    }
}