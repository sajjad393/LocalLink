package com.sajjad.locallink

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * Android notification presentation boundary for messages and system events.
 * It owns channels and notification UI only; it never sends messages.
 */
object LocalLinkNotificationManager {
    const val ACTION_OPEN = "com.sajjad.locallink.ACTION_OPEN_MESSAGE_NOTIFICATION"
    const val ACTION_REPLY = "com.sajjad.locallink.ACTION_REPLY_MESSAGE_NOTIFICATION"
    const val ACTION_MARK_READ = "com.sajjad.locallink.ACTION_MARK_READ_MESSAGE_NOTIFICATION"

    const val EXTRA_ACTION = "notification_action"
    const val EXTRA_NOTIFICATION_ID = "notification_id"
    const val EXTRA_CONVERSATION_TYPE = "conversation_type"
    const val EXTRA_CONVERSATION_ID = "conversation_id"
    const val EXTRA_MESSAGE_ID = "message_id"
    const val EXTRA_SENDER_ID = "sender_id"
    const val EXTRA_RECIPIENT_ID = "recipient_id"
    const val EXTRA_ATTACHMENT_ID = "attachment_id"
    const val EXTRA_REPLY_TEXT = "reply_text"
    const val REMOTE_INPUT_KEY = "locallink_inline_reply"

    // v2 is intentional. Android O+ channel settings are persistent/user-owned
    // and cannot safely be changed in place after the channel is created.
    private const val MESSAGE_CHANNEL_ID = "locallink_messages_v2"
    private const val SYSTEM_CHANNEL_ID = "locallink_system_v2"
    private const val MESSAGE_TAG = "locallink_message"
    private const val REQUEST_PERMISSION = 7744

    fun initialize(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val messageChannel = NotificationChannel(
            MESSAGE_CHANNEL_ID,
            "LocalLink messages",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "New LocalLink direct and group messages"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            enableVibration(true)
            val soundId = context.resources.getIdentifier(
                "locallink_message",
                "raw",
                context.packageName,
            )
            if (soundId != 0) {
                setSound(
                    Uri.parse("android.resource://${context.packageName}/$soundId"),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
            } else {
                setSound(null, null)
            }
        }
        manager.createNotificationChannel(messageChannel)

        val systemChannel = NotificationChannel(
            SYSTEM_CHANNEL_ID,
            "LocalLink system",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "LocalLink security, pairing, and system updates"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        manager.createNotificationChannel(systemChannel)
    }

    fun requestNotificationPermission(activity: MainActivity) {
        if (Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_PERMISSION,
            )
        }
    }

    fun notificationsEnabled(context: Context): Boolean {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return if (Build.VERSION.SDK_INT >= 24) manager.areNotificationsEnabled() else true
    }

    fun openSettings(context: Context) {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    fun showMessage(
        context: Context,
        notificationId: Int,
        conversationType: String,
        conversationId: String,
        messageId: String,
        senderId: String,
        recipientId: String,
        title: String,
        body: String,
        summary: String,
        publicTitle: String,
        publicBody: String,
        initials: String,
        avatarPath: String?,
        imagePath: String?,
        attachmentId: String?,
        unreadCount: Int,
        silent: Boolean,
        visibility: Int,
    ) {
        if (notificationId <= 0 ||
            conversationId.isBlank() ||
            messageId.isBlank() ||
            senderId.isBlank() ||
            recipientId.isBlank()
        ) return
        initialize(context)
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val openIntent = actionIntent(
            context = context,
            action = ACTION_OPEN,
            notificationId = notificationId,
            conversationType = conversationType,
            conversationId = conversationId,
            messageId = messageId,
            senderId = senderId,
            recipientId = recipientId,
            attachmentId = attachmentId,
        )
        val replyIntent = actionIntent(
            context = context,
            action = ACTION_REPLY,
            notificationId = notificationId,
            conversationType = conversationType,
            conversationId = conversationId,
            messageId = messageId,
            senderId = senderId,
            recipientId = recipientId,
            attachmentId = attachmentId,
        )
        val readIntent = actionIntent(
            context = context,
            action = ACTION_MARK_READ,
            notificationId = notificationId,
            conversationType = conversationType,
            conversationId = conversationId,
            messageId = messageId,
            senderId = senderId,
            recipientId = recipientId,
            attachmentId = attachmentId,
        )

        val openPending = PendingIntent.getBroadcast(
            context,
            requestCode(notificationId, 0),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val replyPending = PendingIntent.getBroadcast(
            context,
            requestCode(notificationId, 1),
            replyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        val readPending = PendingIntent.getBroadcast(
            context,
            requestCode(notificationId, 2),
            readIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, MESSAGE_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
            .setSmallIcon(android.R.drawable.ic_dialog_email)
            .setContentTitle(title.ifBlank { "LocalLink" })
            .setContentText(body.ifBlank { summary })
            .setContentIntent(openPending)
            // Deliberately no deleteIntent: dismissing a notification is not a
            // read acknowledgement.
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setGroup(groupKey(conversationType, conversationId))
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)

        if (unreadCount > 1) builder.setSubText("$unreadCount new messages")
        if (silent && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) builder.setSilent(true)

        when (visibility) {
            -1 -> builder.setVisibility(Notification.VISIBILITY_SECRET)
            0 -> {
                builder.setVisibility(Notification.VISIBILITY_PRIVATE)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val publicVersion = Notification.Builder(context)
                        .setSmallIcon(android.R.drawable.ic_dialog_email)
                        .setContentTitle(publicTitle.ifBlank { "LocalLink" })
                        .setContentText(publicBody.ifBlank { "New notification" })
                        .setCategory(Notification.CATEGORY_MESSAGE)
                        .setVisibility(Notification.VISIBILITY_PUBLIC)
                        .build()
                    builder.setPublicVersion(publicVersion)
                }
            }
            else -> builder.setVisibility(Notification.VISIBILITY_PUBLIC)
        }

        val avatar = loadAvatar(context, avatarPath, initials)
        if (avatar != null) builder.setLargeIcon(avatar)

        val image = loadImage(imagePath)
        if (image != null && visibility == 1) {
            builder.setStyle(
                Notification.BigPictureStyle()
                    .bigPicture(image)
                    .setSummaryText(summary)
            )
        } else {
            builder.setStyle(
                Notification.BigTextStyle()
                    .bigText(body)
                    .setSummaryText(summary)
            )
        }

        val replyAction = Notification.Action.Builder(
            Icon.createWithResource(context, android.R.drawable.ic_menu_send),
            "Reply",
            replyPending,
        ).addRemoteInput(
            android.app.RemoteInput.Builder(REMOTE_INPUT_KEY)
                .setLabel("Reply")
                .setAllowFreeFormInput(true)
                .build()
        ).build()

        val readAction = Notification.Action.Builder(
            Icon.createWithResource(context, android.R.drawable.ic_menu_view),
            "Mark read",
            readPending,
        ).build()

        builder.addAction(replyAction)
        builder.addAction(readAction)
        manager.notify(MESSAGE_TAG, notificationId, builder.build())
    }

    fun showSummary(
        context: Context,
        notificationId: Int,
        conversationType: String,
        conversationId: String,
        title: String,
        body: String,
        silent: Boolean,
        visibility: Int,
    ) {
        if (notificationId <= 0 || conversationId.isBlank()) return
        initialize(context)
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, MESSAGE_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
            .setSmallIcon(android.R.drawable.ic_dialog_email)
            .setContentTitle(title.ifBlank { "LocalLink" })
            .setContentText(body.ifBlank { "New messages" })
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setGroup(groupKey(conversationType, conversationId))
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)

        if (silent && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) builder.setSilent(true)
        when (visibility) {
            -1 -> builder.setVisibility(Notification.VISIBILITY_SECRET)
            0 -> builder.setVisibility(Notification.VISIBILITY_PRIVATE)
            else -> builder.setVisibility(Notification.VISIBILITY_PUBLIC)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) builder.setGroupSummary(true)
        manager.notify(MESSAGE_TAG, notificationId, builder.build())
    }

    fun showSystem(context: Context, notificationId: Int, title: String, body: String, silent: Boolean) {
        if (notificationId <= 0 || title.isBlank()) return
        initialize(context)
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, SYSTEM_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_STATUS)
            .setAutoCancel(true)
            .setPriority(Notification.PRIORITY_DEFAULT)
        if (silent && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) builder.setSilent(true)
        manager.notify(notificationId, builder.build())
    }

    fun cancel(context: Context, notificationId: Int) {
        if (notificationId <= 0) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(MESSAGE_TAG, notificationId)
    }

    fun cancelConversation(context: Context, conversationType: String, conversationId: String) {
        if (conversationId.isBlank()) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 23) {
            manager.activeNotifications
                .filter { active ->
                    active.tag == MESSAGE_TAG &&
                        active.notification.group == groupKey(conversationType, conversationId)
                }
                .forEach { active -> manager.cancel(active.tag, active.id) }
        }
    }

    fun cancelMessages(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 23) {
            manager.activeNotifications
                .filter { it.tag == MESSAGE_TAG }
                .forEach { manager.cancel(it.tag, it.id) }
        }
    }

    private fun actionIntent(
        context: Context,
        action: String,
        notificationId: Int,
        conversationType: String,
        conversationId: String,
        messageId: String,
        senderId: String,
        recipientId: String,
        attachmentId: String?,
    ): Intent = Intent(context, LocalLinkNotificationActionReceiver::class.java).apply {
        this.action = action
        putExtra(EXTRA_ACTION, action.removePrefix("com.sajjad.locallink.ACTION_").lowercase())
        putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        putExtra(EXTRA_CONVERSATION_TYPE, conversationType)
        putExtra(EXTRA_CONVERSATION_ID, conversationId)
        putExtra(EXTRA_MESSAGE_ID, messageId)
        putExtra(EXTRA_SENDER_ID, senderId)
        putExtra(EXTRA_RECIPIENT_ID, recipientId)
        if (!attachmentId.isNullOrBlank()) putExtra(EXTRA_ATTACHMENT_ID, attachmentId)
    }

    private fun groupKey(type: String, conversationId: String): String =
        "locallink:$type:$conversationId"

    private fun requestCode(notificationId: Int, action: Int): Int =
        22000 + (notificationId and 0x7fff) * 3 + action

    private fun loadImage(path: String?): Bitmap? {
        if (path.isNullOrBlank()) return null
        return try {
            BitmapFactory.decodeFile(path)
        } catch (_: Exception) {
            null
        }
    }

    private fun loadAvatar(context: Context, avatarPath: String?, initials: String): Bitmap? {
        val fromFile = loadImage(avatarPath)
        if (fromFile != null) return fromFile
        if (initials.trim().isNotEmpty()) return InitialsBitmap.create(initials, 128)
        return try {
            val drawable = context.applicationInfo.loadIcon(context.packageManager)
            val bitmap = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bitmap
        } catch (_: Exception) {
            null
        }
    }

    private object InitialsBitmap {
        fun create(value: String, size: Int): Bitmap? {
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bitmap)
            val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.DKGRAY
                textAlign = android.graphics.Paint.Align.CENTER
                textSize = size * 0.42f
                typeface = android.graphics.Typeface.DEFAULT_BOLD
            }
            canvas.drawColor(android.graphics.Color.LTGRAY)
            val metrics = paint.fontMetrics
            val baseline = size / 2f - (metrics.ascent + metrics.descent) / 2f
            val safe = value.trim().take(2).ifBlank { "L" }
            canvas.drawText(safe.uppercase(), size / 2f, baseline, paint)
            return bitmap
        }
    }
}
