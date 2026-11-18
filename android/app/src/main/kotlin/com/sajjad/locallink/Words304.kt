package com.sajjad.locallink

import android.content.Context

/**
 * 304 (H3): the few notification words made on the Android side. The app tells
 * this phone the chosen language (Settings > Language) with `language304`;
 * Urdu -> these words, anything else -> the English text as written in the code.
 * Names stay as they are. The words start with a right-to-left mark so a
 * Latin name at the start does not flip the line.
 */
object Words304 {
    private const val PREFS = "linkup_language_304"
    private const val KEY = "code"
    private const val RLM = "\u200F"

    private val ur: Map<String, String> = mapOf(
        "LinkUp incoming calls" to "LinkUp آنے والی کالز",
        "Incoming LinkUp calls" to "LinkUp پر آنے والی کالز",
        "Incoming call" to "آنے والی کال",
        "Accept" to "قبول کریں",
        "Reject" to "مسترد کریں",
        "Decline" to "مسترد کریں",
        "LinkUp messages" to "LinkUp میسجز",
        "New LinkUp direct and group messages" to "LinkUp کے نئے ذاتی اور گروپ میسجز",
        "LinkUp system" to "LinkUp سسٹم",
        "LinkUp security, pairing, and system updates" to "LinkUp سیکیورٹی، پیئرنگ اور سسٹم اپ ڈیٹس",
        // Bundle 324: the silent "update coming" notification (UpdateNotice324).
        "LinkUp update" to "LinkUp اپ ڈیٹ",
        "The update coming to this phone (silent)" to "یہ اپ ڈیٹ اس فون پر آ رہی ہے (خاموش)",
        "Friends" to "دوست",
        "Someone added you as a friend" to "کسی نے آپ کو دوست بنایا",
        "New notification" to "نیا نوٹیفکیشن",
        "Reply" to "جواب دیں",
        "Mark read" to "پڑھا ہوا",
        "Remove" to "ہٹائیں",
        "Block" to "بلاک کریں",
        "Someone" to "کوئی",
        "%s added you as a friend" to "%s نے آپ کو دوست بنایا",
        "Saved in your contacts" to "آپ کے کانٹیکٹس میں محفوظ",
        "%s wants to add you" to "%s آپ کو شامل کرنا چاہتے ہیں",
        "%s is near you. Accept to become friends." to "%s آپ کے قریب ہیں۔ دوست بننے کے لیے قبول کریں۔",
        "%s accepted your request" to "%s نے آپ کی درخواست قبول کر لی",
        "You are friends now. Tap to say hello." to "اب آپ دوست ہیں۔ سلام کہنے کے لیے ٹیپ کریں۔",
        "%s new messages" to "%s نئے میسجز",
        "Background service" to "بیک گراؤنڈ سروس",
        "Lets messages arrive while LinkUp is closed" to "LinkUp بند ہونے پر بھی میسجز آنے دیتی ہے",
        "LinkUp is running" to "LinkUp چل رہی ہے",
        "Messages can arrive while the app is closed" to "ایپ بند ہونے پر بھی میسجز آ سکتے ہیں",
        "Open" to "کھولیں",
        "New messages" to "نئے میسجز",
    )

    /** Saved by the app: "ur" or "en". */
    fun save(context: Context, code: String) {
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY, if (code == "ur") "ur" else "en").apply()
        } catch (_: Exception) {}
    }

    fun isUrdu(context: Context): Boolean = try {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "en") == "ur"
    } catch (_: Exception) {
        false
    }

    /** [english] in the chosen language. */
    fun w(context: Context, english: String): String {
        if (!isUrdu(context)) return english
        return ur[english]?.let { RLM + it } ?: english
    }

    /** "%s ..." with a name or number. */
    fun w(context: Context, english: String, value: Any): String {
        val tmpl = if (isUrdu(context)) ur[english]?.let { RLM + it } ?: english else english
        return tmpl.replace("%s", value.toString())
    }
}
