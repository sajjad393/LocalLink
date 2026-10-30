/// Bundle 163 (5.6): "Allow background" help per phone brand. Some brands
/// stop apps in the background on their own; each has its own setting page.
class BackgroundBrandGuide {
  /// Key sent to the native side to open the right page.
  final String key;
  final String title;
  final List<String> steps;

  const BackgroundBrandGuide(this.key, this.title, this.steps);
}

const _lock = 'Recents: lock LocalLink (tap its icon, choose Lock)';

const List<BackgroundBrandGuide> kBackgroundBrandGuides = [
  BackgroundBrandGuide('xiaomi', 'Xiaomi / Redmi / POCO (MIUI / HyperOS)', [
    'Tap Open settings',
    'Autostart: turn LocalLink ON',
    'App info > Battery saver: choose No restrictions',
    _lock,
  ]),
  BackgroundBrandGuide('samsung', 'Samsung (One UI)', [
    'Tap Open settings',
    'Battery: choose Unrestricted',
    'Settings > Battery > Background usage limits: LocalLink must not be in Sleeping or Deep sleeping apps',
    _lock,
  ]),
  BackgroundBrandGuide('oppo', 'Oppo / Realme / OnePlus (ColorOS)', [
    'Tap Open settings',
    'Auto launch: turn LocalLink ON',
    'App info > Battery: Allow background activity',
    _lock,
  ]),
  BackgroundBrandGuide('vivo', 'Vivo / iQOO (Funtouch / OriginOS)', [
    'Tap Open settings',
    'Background power use: allow LocalLink',
    'Autostart: turn LocalLink ON',
    _lock,
  ]),
  BackgroundBrandGuide('huawei', 'Huawei / Honor (EMUI / MagicOS)', [
    'Tap Open settings',
    'App launch: turn off Manage automatically for LocalLink',
    'Turn ON Auto-launch, Secondary launch and Run in background',
    _lock,
  ]),
  BackgroundBrandGuide('transsion', 'Tecno / Infinix / itel (HiOS / XOS)', [
    'Tap Open settings',
    'Auto-start: turn LocalLink ON',
    'Phone Master > Power saving: let LocalLink run in background',
    _lock,
  ]),
  BackgroundBrandGuide('zte', 'ZTE / Nubia (MyOS)', [
    'Tap Open settings',
    'Battery: Allow background activity (No restrictions)',
    'Power manager > Auto-start: allow LocalLink',
    _lock,
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
