package com.sajjad.locallink

import androidx.core.content.FileProvider

/**
 * Bundle 275: shares ONLY `<cache>/update275/` (the downloaded LinkUp APK)
 * with Android's installer. Own subclass so it never clashes with the
 * plugins' FileProviders in the merged manifest.
 */
class UpdateFileProvider275 : FileProvider()
