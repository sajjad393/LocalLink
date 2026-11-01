/// Bundle 163 (5.6): "Allow background" help per phone brand. Some brands
/// stop apps in the background on their own; each has its own setting page.
class BackgroundBrandGuide {
  /// Key sent to the native side to open the right page.
  final String key;
  final String title;
  final List<String> steps;

  const BackgroundBrandGuide(this.key, this.title, this.steps);
}

const _lock = 'Recents: lock LinkUp (tap its icon, choose Lock)';

const List<BackgroundBrandGuide> kBackgroundBrandGuides = [
  BackgroundBrandGuide('xiaomi', 'Xiaomi / Redmi / POCO (MIUI / HyperOS)', [
    'Tap Open settings',
    'Autostart: turn LinkUp ON',
    'App info > Battery saver: choose No restrictions',
    _lock,
  ]),
  BackgroundBrandGuide('samsung', 'Samsung (One UI)', [
    'Tap Open settings',
    'Battery: choose Unrestricted',
    'Settings > Battery > Background usage limits: LinkUp must not be in Sleeping or Deep sleeping apps',
    _lock,
  ]),
  BackgroundBrandGuide('oppo', 'Oppo / Realme / OnePlus (ColorOS)', [
    'Tap Open settings',
    'Auto launch: turn LinkUp ON',
    'App info > Battery: Allow background activity',
    // Bundle 179 (3.6): Realme showed no call notification at all.
    'Notifications: allow LinkUp, turn on Banners, Lock screen and Full-screen',
    _lock,
  ]),
  BackgroundBrandGuide('vivo', 'Vivo / iQOO (Funtouch / OriginOS)', [
    'Tap Open settings',
    'Background power use: allow LinkUp',
    'Autostart: turn LinkUp ON',
    _lock,
  ]),
  BackgroundBrandGuide('huawei', 'Huawei / Honor (EMUI / MagicOS)', [
    'Tap Open settings',
    'App launch: turn off Manage automatically for LinkUp',
    'Turn ON Auto-launch, Secondary launch and Run in background',
    _lock,
  ]),
  BackgroundBrandGuide('transsion', 'Tecno / Infinix / itel (HiOS / XOS)', [
    'Tap Open settings',
    'Auto-start: turn LinkUp ON',
    'Phone Master > Power saving: let LinkUp run in background',
    _lock,
  ]),
  // Bundle 185 (B2): the ZTE Blade A35 closed LinkUp a few seconds after it
  // went behind another app. These 3 settings are what keeps it alive.
  BackgroundBrandGuide('zte', 'ZTE / Nubia (MyOS)', [
    'Tap Open settings',
    '1. App info > Battery: choose Unrestricted',
    '2. Power manager > Power management for apps > LinkUp: turn OFF screen-lock cleaning',
    '3. $_lock',
  ]),
  BackgroundBrandGuide('other', 'Other phones (Pixel, Motorola, Nokia...)', [
    'Tap Open settings',
    'Battery: choose Unrestricted',
    'Keep "Keep running in background" on (above)',
  ]),
];

/// Picks the guide from Android's manufacturer / brand text.
BackgroundBrandGuide backgroundBrandFor(String manufacturerAndBrand) {
  final text = manufacturerAndBrand.toLowerCase();
  bool has(List<String> words) => words.any(text.contains);
  final key = has(['xiaomi', 'redmi', 'poco'])
      ? 'xiaomi'
      : has(['samsung'])
          ? 'samsung'
          : has(['oppo', 'realme', 'oneplus'])
              ? 'oppo'
              : has(['vivo', 'iqoo'])
                  ? 'vivo'
                  : has(['huawei', 'honor'])
                      ? 'huawei'
                      : has(['tecno', 'infinix', 'itel', 'transsion'])
                          ? 'transsion'
                          : has(['zte', 'nubia'])
                              ? 'zte'
                              : 'other';
  return backgroundBrandByKey(key);
}

BackgroundBrandGuide backgroundBrandByKey(String key) =>
    kBackgroundBrandGuides.firstWhere((g) => g.key == key,
        orElse: () => kBackgroundBrandGuides.last);
