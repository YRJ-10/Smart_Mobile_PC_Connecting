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
        val appContext = applicationContext
        val prefs = getSharedPreferences("smart_mpc", MODE_PRIVATE)
        val baseUrl = prefs.getString("baseUrl", "") ?: ""
        val deviceId = prefs.getString("deviceId", "") ?: ""
        val deviceToken = prefs.getString("deviceToken", "") ?: ""

        thread {
            var sentLocally = false
            if (baseUrl.isNotBlank() && deviceId.isNotBlank() && deviceToken.isNotBlank()) {
                try {
                    val connection = URL("${baseUrl.trimEnd('/')}/api/links")
                        .openConnection() as HttpURLConnection
                    connection.requestMethod = "POST"
                    connection.connectTimeout = 2000
                    connection.readTimeout = 3000
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.setRequestProperty("X-Device-Id", deviceId)
                    connection.setRequestProperty("X-Device-Token", deviceToken)

                    val body = JSONObject().put("links", JSONArray().put(text)).toString()
                    connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

                    val responseCode = connection.responseCode
                    if (responseCode in 200..299) {
                        sentLocally = true
                        runOnUiThread {
                            Toast.makeText(appContext, "Link sent to PC", Toast.LENGTH_SHORT).show()
                        }
                    }
                } catch (e: Exception) {
                    sentLocally = false
                }
            }

            if (!sentLocally) {
                queueSharedText(text)
            }
        }
    }

    private fun queueSharedText(text: String) {
        val appContext = applicationContext

        // 1. Try pushing directly to Firestore queue
        val pushedToCloud = try {
            pushToFirestoreQueue(text)
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }

        if (pushedToCloud) {
            runOnUiThread {
                Toast.makeText(appContext, "Link dikirim ke antrean cloud (PC offline)", Toast.LENGTH_SHORT).show()
            }
            return
        }

        // 2. Fallback to local SharedPreferences if cloud push fails (e.g. no internet)
        runOnUiThread {
            val prefs = getSharedPreferences("smart_mpc", MODE_PRIVATE)
            val currentQueue = prefs.getString("queued_links", "[]") ?: "[]"
            try {
                val array = JSONArray(currentQueue)
                array.put(text)
                prefs.edit().putString("queued_links", array.toString()).apply()

                Toast.makeText(appContext, "Link saved to queue (offline)", Toast.LENGTH_SHORT).show()

                // Notify MainActivity if it's running
                ShareEventBus.notifyLinksQueued(array.length())
            } catch (e: Exception) {
                e.printStackTrace()
                Toast.makeText(appContext, "Failed to save link", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun pushToFirestoreQueue(text: String): Boolean {
        val resId = resources.getIdentifier("project_id", "string", packageName)
        val projectId = if (resId != 0) getString(resId) else "otomatis100"
        val firestoreUrl = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/smart_mpc_queue"

        val connection = URL(firestoreUrl).openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.connectTimeout = 4000
        connection.readTimeout = 4000
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8")

        val fields = JSONObject().apply {
            put("type", JSONObject().put("stringValue", "link"))
            put("content", JSONObject().put("stringValue", text))
            put("autoLaunch", JSONObject().put("booleanValue", false))
            put("createdAt", JSONObject().put("integerValue", System.currentTimeMillis().toString()))
        }
        val payload = JSONObject().put("fields", fields).toString()
        connection.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }

        val responseCode = connection.responseCode
        return responseCode in 200..299
    }
}
