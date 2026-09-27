package com.sajjad.locallink

import android.content.BroadcastReceiver
import android.app.RemoteInput
import android.content.Context
import android.content.Intent

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

        if (MainActivity.dispatchNotificationAction(dispatchIntent)) return
        dispatchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        context.startActivity(dispatchIntent)
    }
}
