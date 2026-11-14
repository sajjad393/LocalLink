import 'package:locallink/l10n/l10n.dart';
/// Bundle 163 (5.6): "Allow background" help per phone brand. Some brands
/// stop apps in the background on their own; each has its own setting page.
class BackgroundBrandGuide {
  /// Key sent to the native side to open the right page.
  final String key;
  final String title;
  final List<String> steps;

  const BackgroundBrandGuide(this.key, this.title, this.steps);
}

String get _lock => L.t.recentsLockLinkupTapItsIcon;

List<BackgroundBrandGuide> get kBackgroundBrandGuides => [
  BackgroundBrandGuide('xiaomi', 'Xiaomi / Redmi / POCO (MIUI / HyperOS)', [
    L.t.tapOpenSettings,
    L.t.autostartTurnLinkupOn,
    L.t.appInfoBatterySaverChooseNo,
    _lock,
  ]),
  BackgroundBrandGuide('samsung', 'Samsung (One UI)', [
    L.t.tapOpenSettings,
    L.t.batteryChooseUnrestricted,
    L.t.settingsBatteryBackgroundUsageLimitsLinkup,
    _lock,
  ]),
  BackgroundBrandGuide('oppo', 'Oppo / Realme / OnePlus (ColorOS)', [
    L.t.tapOpenSettings,
    L.t.autoLaunchTurnLinkupOn,
    L.t.appInfoBatteryAllowBackgroundActivity,
    // Bundle 179 (3.6): Realme showed no call notification at all.
    L.t.notificationsAllowLinkupTurnOnBanners,
    _lock,
  ]),
  BackgroundBrandGuide('vivo', 'Vivo / iQOO (Funtouch / OriginOS)', [
    L.t.tapOpenSettings,
    L.t.backgroundPowerUseAllowLinkup,
    L.t.autostartTurnLinkupOn,
    _lock,
  ]),
  BackgroundBrandGuide('huawei', 'Huawei / Honor (EMUI / MagicOS)', [
    L.t.tapOpenSettings,
    L.t.appLaunchTurnOffManageAutomatically,
    L.t.turnOnAutoLaunchSecondaryLaunch,
    _lock,
  ]),
  BackgroundBrandGuide('transsion', 'Tecno / Infinix / itel (HiOS / XOS)', [
    L.t.tapOpenSettings,
    L.t.autoStartTurnLinkupOn,
    L.t.phoneMasterPowerSavingLetLinkup,
    _lock,
  ]),
  // Bundle 185 (B2): the ZTE Blade A35 closed LinkUp a few seconds after it
  // went behind another app. These 3 settings are what keeps it alive.
  BackgroundBrandGuide('zte', 'ZTE / Nubia (MyOS)', [
    L.t.tapOpenSettings,
    L.t.t1AppInfoBatteryChooseUnrestricted,
    L.t.t2PowerManagerPowerManagementFor,
    '3. $_lock',
  ]),
  BackgroundBrandGuide('other', L.t.otherPhonesPixelMotorolaNokia, [
    L.t.tapOpenSettings,
    L.t.batteryChooseUnrestricted,
    L.t.keepKeepRunningInBackgroundOn,
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
