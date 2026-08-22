package com.tivuq.iptv

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.Surface
import android.view.WindowManager
import kotlin.math.abs

/**
 * Matches long-running video to a refresh-rate family without hard-coding a
 * Fire TV model. Resolution is never changed and repeated requests in the same
 * family are ignored, which keeps HDMI handshakes to the minimum required.
 */
class DisplayRefreshRateManager(private val activity: Activity) {
    companion object {
        private const val PREFS_NAME = "tivuq_display_refresh"
        private const val KEY_LAST_TARGET_HZ = "last_target_hz"
    }

    data class Snapshot(
        val sourceFps: Float,
        val targetHz: Float,
        val displayHz: Float,
        val method: String,
        val status: String,
        val requestedModeId: Int
    )

    private val handler = Handler(Looper.getMainLooper())
    private val applyRunnable = Runnable { applyPendingRequest() }

    private val initialWindowAttributes = activity.window.attributes
    private val originalPreferredModeId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        initialWindowAttributes.preferredDisplayModeId
    } else {
        0
    }
    private val originalPreferredRefreshRate = initialWindowAttributes.preferredRefreshRate

    private var pendingSourceFps = 0f
    private var pendingSurface: Surface? = null
    private var sourceFps = 0f
    private var targetHz = 0f
    private var requestedModeId = 0
    private var method = "WAITING"
    private var status = "WAITING"

    /**
     * Applies the last successful refresh-rate family before Flutter creates
     * its first frame. The unavoidable HDMI handshake then happens during the
     * Android launch window instead of after live video becomes visible.
     */
    fun applyRememberedModeForStartup() {
        val rememberedHz = activity
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getFloat(KEY_LAST_TARGET_HZ, 0f)
        if (!rememberedHz.isFinite() || rememberedHz < 20f || rememberedHz > 120f) return

        val matchingMode = findModeForRefreshRate(rememberedHz) ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        targetHz = rememberedHz
        requestedModeId = matchingMode.modeId
        method = "startupPreferredDisplayModeId"
        if (isRefreshRateMatched(currentDisplayHz(), rememberedHz)) {
            status = "ACTIVE"
            return
        }

        val attributes = activity.window.attributes
        attributes.preferredDisplayModeId = matchingMode.modeId
        attributes.preferredRefreshRate = matchingMode.refreshRate
        activity.window.attributes = attributes
        status = "SWITCHING"
        verifySwitch(rememberedHz)
    }

    /** Locks Live TV to the selected 50/60 Hz family for the screen lifetime. */
    fun applyFixedLiveMode(desiredHz: Float = 50f) {
        val safeDesiredHz = if (desiredHz >= 55f) 60f else 50f
        handler.removeCallbacks(applyRunnable)
        pendingSourceFps = 0f
        pendingSurface = null
        sourceFps = safeDesiredHz
        targetHz = safeDesiredHz

        val matchingMode = findModeForRefreshRate(safeDesiredHz)
        if (matchingMode == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            status = "UNSUPPORTED"
            method = "FIXED_LIVE_${safeDesiredHz.toInt()}_UNSUPPORTED"
            return
        }

        requestedModeId = matchingMode.modeId
        method = "FIXED_LIVE_${safeDesiredHz.toInt()}"
        rememberTargetRefreshRate(safeDesiredHz)
        if (isRefreshRateMatched(currentDisplayHz(), safeDesiredHz)) {
            status = "ACTIVE"
            return
        }

        val attributes = activity.window.attributes
        attributes.preferredDisplayModeId = matchingMode.modeId
        attributes.preferredRefreshRate = matchingMode.refreshRate
        activity.window.attributes = attributes
        status = "SWITCHING"
        verifySwitch(safeDesiredHz)
    }

    fun requestContentFrameRate(
        fps: Float,
        surface: Surface? = null,
        stabilizationDelayMs: Long = 900L
    ) {
        if (!fps.isFinite() || fps < 10f || fps > 120f) return
        handler.post {
            pendingSourceFps = quantizeSourceFps(fps)
            pendingSurface = surface

            val requestedTarget = targetRefreshRate(pendingSourceFps)
            if (sameRateFamily(requestedTarget, targetHz) &&
                (isRefreshRateMatched(currentDisplayHz(), requestedTarget) ||
                    status == "SWITCHING")
            ) {
                sourceFps = pendingSourceFps
                if (isRefreshRateMatched(currentDisplayHz(), requestedTarget)) {
                    status = "ACTIVE"
                }
                return@post
            }

            status = "WAITING"
            handler.removeCallbacks(applyRunnable)
            // Exact decoder format metadata is applied before the first frame.
            // Measured fallback FPS keeps a short stabilization delay.
            handler.postDelayed(applyRunnable, stabilizationDelayMs.coerceAtLeast(0L))
        }
    }

    fun restoreImmediately() {
        val restore = Runnable {
            handler.removeCallbacks(applyRunnable)
            restoreOriginalModeNow()
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            restore.run()
        } else {
            handler.post(restore)
        }
    }

    fun snapshot(): Snapshot = Snapshot(
        sourceFps = sourceFps,
        targetHz = targetHz,
        displayHz = currentDisplayHz(),
        method = method,
        status = status,
        requestedModeId = requestedModeId
    )

    private fun applyPendingRequest() {
        val stableSourceFps = pendingSourceFps
        if (stableSourceFps <= 0f) return

        sourceFps = stableSourceFps
        val desiredHz = targetRefreshRate(stableSourceFps)
        targetHz = desiredHz

        val currentHz = currentDisplayHz()
        if (isRefreshRateMatched(currentHz, desiredHz)) {
            method = "ALREADY_MATCHED"
            status = "ACTIVE"
            rememberTargetRefreshRate(desiredHz)
            return
        }

        val matchingMode = findModeForRefreshRate(desiredHz)
        if (matchingMode != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val attributes = activity.window.attributes
            if (attributes.preferredDisplayModeId != matchingMode.modeId) {
                attributes.preferredDisplayModeId = matchingMode.modeId
                attributes.preferredRefreshRate = matchingMode.refreshRate
                activity.window.attributes = attributes
            }
            requestedModeId = matchingMode.modeId
            method = "preferredDisplayModeId"
            status = "SWITCHING"
            rememberTargetRefreshRate(desiredHz)
            verifySwitch(desiredHz)
            return
        }

        val surface = pendingSurface
        if (surface != null && surface.isValid && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    surface.setFrameRate(
                        stableSourceFps,
                        Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                        Surface.CHANGE_FRAME_RATE_ALWAYS
                    )
                } else {
                    @Suppress("DEPRECATION")
                    surface.setFrameRate(
                        stableSourceFps,
                        Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE
                    )
                }
                method = "Surface.setFrameRate"
                status = "REQUESTED"
                verifySwitch(desiredHz)
                return
            } catch (_: Throwable) {
                // Fall through to the window-level refresh-rate hint.
            }
        }

        val attributes = activity.window.attributes
        attributes.preferredRefreshRate = desiredHz
        activity.window.attributes = attributes
        method = "preferredRefreshRate"
        status = "REQUESTED"
        verifySwitch(desiredHz)
    }

    private fun rememberTargetRefreshRate(refreshRate: Float) {
        activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putFloat(KEY_LAST_TARGET_HZ, refreshRate)
            .apply()
    }

    private fun verifySwitch(desiredHz: Float) {
        handler.postDelayed({
            status = if (isRefreshRateMatched(currentDisplayHz(), desiredHz)) {
                "ACTIVE"
            } else {
                "REQUESTED"
            }
        }, 1800L)
    }

    private fun restoreOriginalModeNow() {
        val attributes = activity.window.attributes
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            attributes.preferredDisplayModeId = originalPreferredModeId
        }
        attributes.preferredRefreshRate = originalPreferredRefreshRate
        activity.window.attributes = attributes
        pendingSourceFps = 0f
        pendingSurface = null
        sourceFps = 0f
        targetHz = 0f
        requestedModeId = 0
        method = "RESTORED"
        status = "WAITING"
    }

    @Suppress("DEPRECATION")
    private fun display(): Display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        activity.display ?: activity.windowManager.defaultDisplay
    } else {
        activity.windowManager.defaultDisplay
    }

    private fun currentDisplayHz(): Float = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            display().mode.refreshRate
        } else {
            @Suppress("DEPRECATION")
            display().refreshRate
        }
    } catch (_: Throwable) {
        60f
    }

    private fun findModeForRefreshRate(desiredHz: Float): Display.Mode? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val currentMode = display().mode
        return display().supportedModes
            .asSequence()
            .filter {
                it.physicalWidth == currentMode.physicalWidth &&
                    it.physicalHeight == currentMode.physicalHeight
            }
            .minByOrNull { abs(it.refreshRate - desiredHz) }
            ?.takeIf { abs(it.refreshRate - desiredHz) <= 0.65f }
    }

    private fun quantizeSourceFps(fps: Float): Float {
        val standards = floatArrayOf(23.976f, 24f, 25f, 29.97f, 30f, 50f, 59.94f, 60f)
        val closest = standards.minByOrNull { abs(it - fps) } ?: fps
        return if (abs(closest - fps) <= 1f) closest else fps
    }

    private fun targetRefreshRate(fps: Float): Float = when {
        abs(fps - 23.976f) < 0.02f -> 23.976f
        abs(fps - 24f) < 0.5f -> 24f
        abs(fps - 25f) < 0.6f -> 50f
        abs(fps - 29.97f) < 0.1f -> 59.94f
        abs(fps - 30f) < 0.6f -> 60f
        abs(fps - 50f) < 1f -> 50f
        abs(fps - 59.94f) < 0.1f -> 59.94f
        abs(fps - 60f) < 1f -> 60f
        else -> fps
    }

    private fun sameRateFamily(first: Float, second: Float): Boolean =
        first > 0f && second > 0f && abs(first - second) <= 0.65f

    private fun isRefreshRateMatched(actualHz: Float, desiredHz: Float): Boolean =
        abs(actualHz - desiredHz) <= 0.65f
}
