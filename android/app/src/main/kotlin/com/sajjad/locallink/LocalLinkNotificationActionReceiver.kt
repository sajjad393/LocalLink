package com.sajjad.locallink

import android.content.BroadcastReceiver
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Build

/** Converts notification actions into validated Flutter-layer events. */
class LocalLinkNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = when (intent.action) {
            LocalLinkNotificationManager.ACTION_OPEN -> "open"
            LocalLinkNotificationManager.ACTION_REPLY -> "reply"
            LocalLinkNotificationManager.ACTION_MARK_READ -> "mark_read"
            else -> return
        }
        val declaredAction = intent
            .getStringExtra(LocalLinkNotificationManager.EXTRA_ACTION)
            ?.trim()
            .orEmpty()
        if (declaredAction != action) return

        val conversationType = intent.getStringExtra(LocalLinkNotificationManager.EXTRA_CONVERSATION_TYPE)?.trim().orEmpty()
        val conversationId = intent.getStringExtra(LocalLinkNotificationManager.EXTRA_CONVERSATION_ID)?.trim().orEmpty()
        val messageId = intent.getStringExtra(LocalLinkNotificationManager.EXTRA_MESSAGE_ID)?.trim().orEmpty()
        val senderId = intent.getStringExtra(LocalLinkNotificationManager.EXTRA_SENDER_ID)?.trim().orEmpty()
        val recipientId = intent.getStringExtra(LocalLinkNotificationManager.EXTRA_RECIPIENT_ID)?.trim().orEmpty()
        val notificationId = intent.getIntExtra(LocalLinkNotificationManager.EXTRA_NOTIFICATION_ID, 0)
        if (conversationType !in setOf("direct", "group") ||
            conversationId.isEmpty() ||
            messageId.isEmpty() ||
            senderId.isEmpty() ||
            recipientId.isEmpty() ||
            notificationId <= 0
        ) return

        val replyText = if (action == "reply") {
            RemoteInput.getResultsFromIntent(intent)
                ?.getCharSequence(LocalLinkNotificationManager.REMOTE_INPUT_KEY)
                ?.toString()
                ?.trim()
        } else null

        val dispatchIntent = Intent(context, MainActivity::class.java).apply {
            this.action = intent.action
            putExtra(LocalLinkNotificationManager.EXTRA_ACTION, action)
            putExtra(LocalLinkNotificationManager.EXTRA_NOTIFICATION_ID, notificationId)
            putExtra(LocalLinkNotificationManager.EXTRA_CONVERSATION_TYPE, conversationType)
            putExtra(LocalLinkNotificationManager.EXTRA_CONVERSATION_ID, conversationId)
            putExtra(LocalLinkNotificationManager.EXTRA_MESSAGE_ID, messageId)
            putExtra(LocalLinkNotificationManager.EXTRA_SENDER_ID, senderId)
            putExtra(LocalLinkNotificationManager.EXTRA_RECIPIENT_ID, recipientId)
            if (!intent.getStringExtra(LocalLinkNotificationManager.EXTRA_ATTACHMENT_ID).isNullOrBlank()) {
                putExtra(
                    LocalLinkNotificationManager.EXTRA_ATTACHMENT_ID,
                    intent.getStringExtra(LocalLinkNotificationManager.EXTRA_ATTACHMENT_ID),
                )
            }
            if (!replyText.isNullOrBlank()) {
                putExtra(LocalLinkNotificationManager.EXTRA_REPLY_TEXT, replyText)
            }
        }

        // Bundle 151: message actions go to the MESSAGE handler.
        if (MainActivity.dispatchMessageNotificationAction(dispatchIntent)) return
        // Bundle 162 (4.1): the app screen is closed. Android 12+ blocks
        // opening it from a notification button, so Reply / Mark read are
        // saved and handed to the app when it starts — never lost.
        if (action != "open" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (action == "reply" && replyText.isNullOrBlank()) return
            NotificationActionOutbox.add(context, mapOf(
                "action" to action,
                "notification_id" to notificationId,
                "conversation_type" to conversationType,
                "conversation_id" to conversationId,
                "message_id" to messageId,
                "sender_id" to senderId,
                "recipient_id" to recipientId,
                "attachment_id" to intent.getStringExtra(LocalLinkNotificationManager.EXTRA_ATTACHMENT_ID)?.takeIf { it.isNotBlank() },
                "reply_text" to replyText?.takeIf { it.isNotBlank() },
            ))
            android.util.Log.i("LocalLinkNotify", "NOTIFICATION_ACTION_SAVED action=$action pending=${NotificationActionOutbox.count(context)}")
            LocalLinkNotificationManager.cancel(context, notificationId)
            if (action == "reply") {
                LocalLinkNotificationManager.showReplySaved(context, notificationId)
            }
            return
        }
        dispatchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        context.startActivity(dispatchIntent)
    }
}
