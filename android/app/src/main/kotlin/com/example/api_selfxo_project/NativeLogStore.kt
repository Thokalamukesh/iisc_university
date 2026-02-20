package com.example.api_selfxo_project

import android.content.Context
import java.io.File

object NativeLogStore {
    private const val FILE_NAME = "printer_debug.log"
    private val lock = Any()

    fun append(context: Context, message: String) {
        synchronized(lock) {
            val file = File(context.filesDir, FILE_NAME)
            file.appendText(message + "\n")
        }
    }

    fun readLines(context: Context, maxLines: Int = 300): List<String> {
        synchronized(lock) {
            val file = File(context.filesDir, FILE_NAME)
            if (!file.exists()) return emptyList()
            val lines = file.readLines()
            return if (lines.size <= maxLines) lines else lines.takeLast(maxLines)
        }
    }

    fun clear(context: Context) {
        synchronized(lock) {
            val file = File(context.filesDir, FILE_NAME)
            if (file.exists()) {
                file.delete()
            }
        }
    }
}
