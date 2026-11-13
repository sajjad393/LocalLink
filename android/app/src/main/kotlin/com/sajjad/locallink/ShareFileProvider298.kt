package com.sajjad.locallink

import androidx.core.content.FileProvider

/**
 * Bundle 298 (I): shares ONLY `<cache>/share298/` (the recovery code card
 * picture) with WhatsApp. Own subclass, like UpdateFileProvider275, so it
 * never clashes with the plugins' FileProviders in the merged manifest.
 */
class ShareFileProvider298 : FileProvider()
