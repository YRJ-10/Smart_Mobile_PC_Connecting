package com.smartmpc.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (intent.action == Intent.ACTION_SEND && "text/plain" == intent.type) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (text != null) {
                sendOrQueueSharedText(text)
            }
        }

        // Finish immediately so the user stays in the current app
        finish()
    }

    private fun sendOrQueueSharedText(text: String) {
        val prefs = getSharedPreferences("smart_mpc", MODE_PRIVATE)
        val baseUrl = prefs.getString("baseUrl", "") ?: ""
        val deviceId = prefs.getString("deviceId", "") ?: ""
        val deviceToken = prefs.getString("deviceToken", "") ?: ""

        if (baseUrl.isBlank() || deviceId.isBlank() || deviceToken.isBlank()) {
            queueSharedText(text)
            return
        }

        thread {
            try {
                val connection = URL("${baseUrl.trimEnd('/')}/api/links")
                    .openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.connectTimeout = 3000
                connection.readTimeout = 5000
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setRequestProperty("X-Device-Id", deviceId)
                connection.setRequestProperty("X-Device-Token", deviceToken)

                val body = JSONObject().put("links", JSONArray().put(text)).toString()
                connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

                val responseCode = connection.responseCode
                if (responseCode in 200..299) {
                    runOnUiThread {
                        Toast.makeText(this@ShareReceiverActivity, "Link sent to PC", Toast.LENGTH_SHORT).show()
                    }
                } else {
                    queueSharedText(text)
                }
            } catch (e: Exception) {
                e.printStackTrace()
                queueSharedText(text)
            }
        }
    }

    private fun queueSharedText(text: String) {
        runOnUiThread {
            val prefs = getSharedPreferences("smart_mpc", MODE_PRIVATE)
            val currentQueue = prefs.getString("queued_links", "[]") ?: "[]"
            try {
                val array = JSONArray(currentQueue)
                array.put(text)
                prefs.edit().putString("queued_links", array.toString()).apply()
                
                // Show toast
                Toast.makeText(this@ShareReceiverActivity, "Link saved to queue (offline)", Toast.LENGTH_SHORT).show()

                // Notify MainActivity if it's running
                ShareEventBus.notifyLinksQueued(array.length())
            } catch (e: Exception) {
                e.printStackTrace()
                Toast.makeText(this@ShareReceiverActivity, "Failed to save link", Toast.LENGTH_SHORT).show()
            }
        }
    }
}

