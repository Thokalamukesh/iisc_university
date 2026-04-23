package com.example.api_selfxo_project

import android.content.Context
import android.os.Build

object AutoStartPrefs {
    private const val PREFS_NAME = "selfx_power_prefs"
    private const val KEY_AUTO_START_ON_BOOT = "auto_start_on_boot"

    fun isEnabled(context: Context): Boolean {
        val appContext = context.applicationContext
        val deviceContext = deviceProtectedContext(appContext)
        val devicePrefs = deviceContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (devicePrefs.contains(KEY_AUTO_START_ON_BOOT)) {
            return devicePrefs.getBoolean(KEY_AUTO_START_ON_BOOT, true)
        }

        val appPrefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val enabled = appPrefs.getBoolean(KEY_AUTO_START_ON_BOOT, true)
        devicePrefs.edit().putBoolean(KEY_AUTO_START_ON_BOOT, enabled).apply()
        return enabled
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        val appContext = context.applicationContext
        val deviceContext = deviceProtectedContext(appContext)
        deviceContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_AUTO_START_ON_BOOT, enabled)
            .apply()
        if (deviceContext !== appContext) {
            appContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_AUTO_START_ON_BOOT, enabled)
                .apply()
        }
    }

    private fun deviceProtectedContext(context: Context): Context {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return context
        }
        return context.createDeviceProtectedStorageContext() ?: context
    }
}
