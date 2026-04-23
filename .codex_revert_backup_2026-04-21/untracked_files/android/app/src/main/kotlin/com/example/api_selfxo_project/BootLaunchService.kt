package com.example.api_selfxo_project

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock

class BootLaunchService : Service() {
    companion object {
        private const val EXTRA_BOOT_ACTION = "boot_action"
        private const val EXTRA_TRIGGER = "trigger"
        private const val EXTRA_LAUNCH_NOW = "launch_now"
        private const val CHANNEL_ID = "selfx_boot_launch"
        private const val NOTIFICATION_ID = 4107
        private val LAUNCH_ATTEMPTS_MS = longArrayOf(3000L, 10000L, 20000L, 35000L)
        private val ALARM_RETRY_DELAYS_MS = longArrayOf(5000L, 15000L, 30000L, 45000L)
        private const val WAKE_LOCK_TAG = "selfx:boot_launch"
        private const val WAKE_LOCK_MS = 60_000L
        private const val PREFS_NAME = "selfx_boot_runtime"
        private const val KEY_UI_READY_AT = "ui_ready_at"
        private const val UI_READY_WINDOW_MS = 120_000L

        fun startNow(
            context: Context,
            reason: String,
            trigger: String,
            launchNow: Boolean = false,
        ) {
            val serviceIntent =
                Intent(context, BootLaunchService::class.java).apply {
                    putExtra(EXTRA_BOOT_ACTION, reason)
                    putExtra(EXTRA_TRIGGER, trigger)
                    putExtra(EXTRA_LAUNCH_NOW, launchNow)
                }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        }

        fun scheduleRetryAlarms(
            context: Context,
            reason: String,
        ) {
            val alarmManager =
                context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            ALARM_RETRY_DELAYS_MS.forEachIndexed { index, delayMs ->
            val pendingIntent =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        PendingIntent.getForegroundService(
                            context,
                            41070 + index,
                            Intent(context, BootLaunchService::class.java).apply {
                                putExtra(EXTRA_BOOT_ACTION, reason)
                                putExtra(EXTRA_TRIGGER, "alarm_${index + 1}")
                                putExtra(EXTRA_LAUNCH_NOW, true)
                            },
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                    } else {
                        PendingIntent.getService(
                            context,
                            41070 + index,
                            Intent(context, BootLaunchService::class.java).apply {
                                putExtra(EXTRA_BOOT_ACTION, reason)
                                putExtra(EXTRA_TRIGGER, "alarm_${index + 1}")
                                putExtra(EXTRA_LAUNCH_NOW, true)
                            },
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                    }
                val triggerAt = SystemClock.elapsedRealtime() + delayMs
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        pendingIntent,
                    )
                } else {
                    alarmManager.set(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        pendingIntent,
                    )
                }
            }
        }

        fun cancelRetryAlarms(context: Context) {
            val alarmManager =
                context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            ALARM_RETRY_DELAYS_MS.forEachIndexed { index, _ ->
                val pendingIntent =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        PendingIntent.getForegroundService(
                            context,
                            41070 + index,
                            Intent(context, BootLaunchService::class.java),
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                    } else {
                        PendingIntent.getService(
                            context,
                            41070 + index,
                            Intent(context, BootLaunchService::class.java),
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                    }
                alarmManager.cancel(pendingIntent)
            }
        }

        fun markUiReady(context: Context) {
            prefs(context)
                .edit()
                .putLong(KEY_UI_READY_AT, System.currentTimeMillis())
                .apply()
            cancelRetryAlarms(context)
        }

        fun clearUiReady(context: Context) {
            prefs(context)
                .edit()
                .remove(KEY_UI_READY_AT)
                .apply()
        }

        fun wasUiReadyRecently(context: Context): Boolean {
            val markedAt = prefs(context).getLong(KEY_UI_READY_AT, 0L)
            if (markedAt <= 0L) return false
            return System.currentTimeMillis() - markedAt <= UI_READY_WINDOW_MS
        }

        private fun prefs(context: Context) =
            context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private val handler = Handler(Looper.getMainLooper())
    private var launchScheduled = false
    private var stopRunnable: Runnable? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!AutoStartPrefs.isEnabled(applicationContext)) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (wasUiReadyRecently(applicationContext)) {
            stopSelf()
            return START_NOT_STICKY
        }

        val reason = intent?.getStringExtra(EXTRA_BOOT_ACTION) ?: "unknown"
        val trigger = intent?.getStringExtra(EXTRA_TRIGGER) ?: "service"
        val launchNow = intent?.getBooleanExtra(EXTRA_LAUNCH_NOW, false) == true

        startForeground(NOTIFICATION_ID, buildNotification())
        acquireWakeLock()

        NativeLogStore.append(
            applicationContext,
            "[BOOT] service start, trigger=$trigger, reason=$reason, launchNow=$launchNow",
        )

        if (launchNow) {
            handler.post {
                launchApp(
                    reason = reason,
                    attempt = 0,
                    totalAttempts = LAUNCH_ATTEMPTS_MS.size,
                    trigger = trigger,
                )
            }
        }

        if (!launchScheduled) {
            launchScheduled = true
            scheduleLaunchAttempts(reason)
        }

        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        releaseWakeLock()
        super.onDestroy()
    }

    private fun scheduleLaunchAttempts(reason: String) {
        for ((index, delayMs) in LAUNCH_ATTEMPTS_MS.withIndex()) {
            handler.postDelayed(
                {
                    launchApp(
                        reason = reason,
                        attempt = index + 1,
                        totalAttempts = LAUNCH_ATTEMPTS_MS.size,
                    )
                },
                delayMs,
            )
        }

        stopRunnable =
            Runnable {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }.also { runnable ->
                handler.postDelayed(
                    runnable,
                    LAUNCH_ATTEMPTS_MS.last() + 5_000L,
                )
            }
    }

    private fun launchApp(
        reason: String,
        attempt: Int,
        totalAttempts: Int,
        trigger: String = "service",
    ) {
        if (wasUiReadyRecently(applicationContext)) {
            NativeLogStore.append(
                applicationContext,
                "[BOOT] ui already ready, skip launch attempt=$attempt/$totalAttempts, trigger=$trigger, reason=$reason",
            )
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        if (isAppInForeground()) {
            NativeLogStore.append(
                applicationContext,
                "[BOOT] app already in foreground on attempt=$attempt/$totalAttempts, trigger=$trigger, reason=$reason",
            )
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        val launchIntent =
            packageManager.getLaunchIntentForPackage(packageName)
                ?.apply {
                    action = Intent.ACTION_MAIN
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
                    )
                }
                ?: Intent(Intent.ACTION_MAIN).apply {
                    setClass(this@BootLaunchService, MainActivity::class.java)
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
                    )
                }

        try {
            startActivity(launchIntent)
            NativeLogStore.append(
                applicationContext,
                "[BOOT] launched app from service, attempt=$attempt/$totalAttempts, trigger=$trigger, reason=$reason",
            )
        } catch (e: Exception) {
            NativeLogStore.append(
                applicationContext,
                "[BOOT] service launch failed, attempt=$attempt/$totalAttempts, trigger=$trigger, reason=$reason, error=${e.message}",
            )
        }
    }

    private fun acquireWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        if (wakeLock?.isHeld == true) return
        wakeLock =
            powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
                setReferenceCounted(false)
                acquire(WAKE_LOCK_MS)
            }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {
        } finally {
            wakeLock = null
        }
    }

    private fun isAppInForeground(): Boolean {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return false
        val processes = activityManager.runningAppProcesses ?: return false
        return processes.any { process ->
            process.processName == packageName &&
                process.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
        }
    }

    private fun buildNotification(): Notification {
        ensureChannel()
        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                Notification.Builder(this)
            }

        return builder
            .setContentTitle("SELFX")
            .setContentText("Starting kiosk")
            .setSmallIcon(android.R.drawable.sym_def_app_icon)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "SELFX Boot",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Starts SELFX automatically after device boot"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
        manager.createNotificationChannel(channel)
    }
}
