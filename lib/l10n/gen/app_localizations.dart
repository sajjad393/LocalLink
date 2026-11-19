import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ur.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ur')
  ];

  /// No description provided for @aConsistentCopyOfTheLinkup.
  ///
  /// In en, this message translates to:
  /// **'A consistent copy of the LinkUp database will be written to the server backup directory.'**
  String get aConsistentCopyOfTheLinkup;

  /// No description provided for @aLinkupPhoneHelpingToPass.
  ///
  /// In en, this message translates to:
  /// **'A LinkUp phone helping to pass your messages. It can\'t read them.'**
  String get aLinkupPhoneHelpingToPass;

  /// No description provided for @aNearbyPhone.
  ///
  /// In en, this message translates to:
  /// **'a nearby phone'**
  String get aNearbyPhone;

  /// No description provided for @aNearbyPhone2.
  ///
  /// In en, this message translates to:
  /// **'a nearby phone ({firstCarrier})'**
  String aNearbyPhone2(Object? firstCarrier);

  /// No description provided for @aNewAccountIdentityKeyWill.
  ///
  /// In en, this message translates to:
  /// **'A new account identity key will become active. The previous key is retained on this phone as local key history. Other devices will learn the new public key automatically.'**
  String get aNewAccountIdentityKeyWill;

  /// No description provided for @aNewerLinkupIsNeededPlease.
  ///
  /// In en, this message translates to:
  /// **'A newer LinkUp is needed. Please update.'**
  String get aNewerLinkupIsNeededPlease;

  /// No description provided for @aSmallMapOfYourContacts.
  ///
  /// In en, this message translates to:
  /// **'A small map of your contacts at the top of Chats'**
  String get aSmallMapOfYourContacts;

  /// No description provided for @aboutFreeSpace.
  ///
  /// In en, this message translates to:
  /// **'About {sizeLabel} free space'**
  String aboutFreeSpace(Object? sizeLabel);

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @acceptNewCode.
  ///
  /// In en, this message translates to:
  /// **'Accept new code'**
  String get acceptNewCode;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @accountClosed.
  ///
  /// In en, this message translates to:
  /// **'Account closed'**
  String get accountClosed;

  /// No description provided for @accountClosedByAdmin.
  ///
  /// In en, this message translates to:
  /// **'Account closed by admin'**
  String get accountClosedByAdmin;

  /// No description provided for @accountClosedByAdminYouCan.
  ///
  /// In en, this message translates to:
  /// **'Account closed by admin. You can read old chats but can\'t send or call.'**
  String get accountClosedByAdminYouCan;

  /// No description provided for @accountDataRestored.
  ///
  /// In en, this message translates to:
  /// **'Account data restored'**
  String get accountDataRestored;

  /// No description provided for @accountPhonesBackup.
  ///
  /// In en, this message translates to:
  /// **'@{nickname} · Account, phones, backup'**
  String accountPhonesBackup(Object? nickname);

  /// No description provided for @accountPhonesBackup2.
  ///
  /// In en, this message translates to:
  /// **'Account, phones, backup'**
  String get accountPhonesBackup2;

  /// No description provided for @accountProfileMetadataDevicesGroupsMessages.
  ///
  /// In en, this message translates to:
  /// **'Account/profile metadata, devices, groups, messages, group messages and call history. File content is not downloaded automatically.'**
  String get accountProfileMetadataDevicesGroupsMessages;

  /// No description provided for @accountRecoveredOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Account recovered on this phone.'**
  String get accountRecoveredOnThisPhone;

  /// No description provided for @accountRecoveredPreviousActiveDevicesWere.
  ///
  /// In en, this message translates to:
  /// **'Account recovered. Previous active devices were revoked.'**
  String get accountRecoveredPreviousActiveDevicesWere;

  /// No description provided for @accountRecoveredSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Account recovered successfully.'**
  String get accountRecoveredSuccessfully;

  /// No description provided for @accountRecovery.
  ///
  /// In en, this message translates to:
  /// **'Account recovery'**
  String get accountRecovery;

  /// No description provided for @accountRecoveryQueue.
  ///
  /// In en, this message translates to:
  /// **'Account recovery queue'**
  String get accountRecoveryQueue;

  /// No description provided for @accountStopped.
  ///
  /// In en, this message translates to:
  /// **'Account stopped'**
  String get accountStopped;

  /// No description provided for @accountTurnedOnAgain.
  ///
  /// In en, this message translates to:
  /// **'Account turned on again'**
  String get accountTurnedOnAgain;

  /// No description provided for @accountsAndProfiles.
  ///
  /// In en, this message translates to:
  /// **'Accounts and profiles'**
  String get accountsAndProfiles;

  /// No description provided for @actionsGoToHerPhoneBy.
  ///
  /// In en, this message translates to:
  /// **'Actions go to her phone by card (Pending until done). More actions after she joins the server.'**
  String get actionsGoToHerPhoneBy;

  /// No description provided for @actionsThePhonesDidShowHere.
  ///
  /// In en, this message translates to:
  /// **'Actions the phones did show here.'**
  String get actionsThePhonesDidShowHere;

  /// No description provided for @actionsWaitHereUntilEachPhone.
  ///
  /// In en, this message translates to:
  /// **'Actions wait here until each phone does it. There is no time limit.'**
  String get actionsWaitHereUntilEachPhone;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @activeAgain.
  ///
  /// In en, this message translates to:
  /// **'Active again'**
  String get activeAgain;

  /// No description provided for @activeCalls.
  ///
  /// In en, this message translates to:
  /// **'Active calls'**
  String get activeCalls;

  /// No description provided for @activeSessions.
  ///
  /// In en, this message translates to:
  /// **'Active sessions'**
  String get activeSessions;

  /// No description provided for @activityAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Activity analytics'**
  String get activityAnalytics;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @addAContactOrDiscoverNearby.
  ///
  /// In en, this message translates to:
  /// **'Add a contact or discover nearby LinkUp phones.'**
  String get addAContactOrDiscoverNearby;

  /// No description provided for @addAsAFriend.
  ///
  /// In en, this message translates to:
  /// **'Add {displayName} as a friend?'**
  String addAsAFriend(Object? displayName);

  /// No description provided for @addContact.
  ///
  /// In en, this message translates to:
  /// **'Add Contact'**
  String get addContact;

  /// No description provided for @addContact2.
  ///
  /// In en, this message translates to:
  /// **'Add contact'**
  String get addContact2;

  /// No description provided for @addFriend.
  ///
  /// In en, this message translates to:
  /// **'Add friend'**
  String get addFriend;

  /// No description provided for @addGroupDescription.
  ///
  /// In en, this message translates to:
  /// **'Add group description'**
  String get addGroupDescription;

  /// No description provided for @addGroupPhotoOptional.
  ///
  /// In en, this message translates to:
  /// **'Add group photo (optional)'**
  String get addGroupPhotoOptional;

  /// No description provided for @addMeOnLinkup.
  ///
  /// In en, this message translates to:
  /// **'ADD ME ON LINKUP'**
  String get addMeOnLinkup;

  /// No description provided for @addMember.
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get addMember;

  /// No description provided for @addMembers.
  ///
  /// In en, this message translates to:
  /// **'Add members'**
  String get addMembers;

  /// No description provided for @addOption.
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get addOption;

  /// No description provided for @addPeopleUpTo.
  ///
  /// In en, this message translates to:
  /// **'Add people · up to {kNewGroupMax}'**
  String addPeopleUpTo(Object? kNewGroupMax);

  /// No description provided for @addToGroup.
  ///
  /// In en, this message translates to:
  /// **'Add to group'**
  String get addToGroup;

  /// No description provided for @added.
  ///
  /// In en, this message translates to:
  /// **'Added · {atMs}'**
  String added(Object? atMs);

  /// No description provided for @added2.
  ///
  /// In en, this message translates to:
  /// **'{name} added'**
  String added2(Object? name);

  /// No description provided for @addedByYou.
  ///
  /// In en, this message translates to:
  /// **'Added by you'**
  String get addedByYou;

  /// No description provided for @addedByYou2.
  ///
  /// In en, this message translates to:
  /// **'Added by you · {day} {month}'**
  String addedByYou2(Object? day, Object? month);

  /// No description provided for @addedByYouToday.
  ///
  /// In en, this message translates to:
  /// **'Added by you · today {hh}:{mm}'**
  String addedByYouToday(Object? hh, Object? mm);

  /// No description provided for @addedMembers304.
  ///
  /// In en, this message translates to:
  /// **'{actor} added {targets}'**
  String addedMembers304(Object? actor, Object? targets);

  /// No description provided for @addedToTheGroup.
  ///
  /// In en, this message translates to:
  /// **'{selected} added to the group.'**
  String addedToTheGroup(Object? selected);

  /// No description provided for @addedYou.
  ///
  /// In en, this message translates to:
  /// **'{actor} added you'**
  String addedYou(Object? actor);

  /// No description provided for @adding.
  ///
  /// In en, this message translates to:
  /// **'Adding {invites}'**
  String adding(Object? invites);

  /// No description provided for @adding2.
  ///
  /// In en, this message translates to:
  /// **'Adding {phone}…'**
  String adding2(Object? phone);

  /// No description provided for @addingNowNearby.
  ///
  /// In en, this message translates to:
  /// **'Adding now · Nearby'**
  String get addingNowNearby;

  /// No description provided for @addingPeople.
  ///
  /// In en, this message translates to:
  /// **'Adding people'**
  String get addingPeople;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @admin2.
  ///
  /// In en, this message translates to:
  /// **'Admin · {level}'**
  String admin2(Object? level);

  /// No description provided for @admin3.
  ///
  /// In en, this message translates to:
  /// **'Admin · {r}{substring}'**
  String admin3(Object? r, Object? substring);

  /// No description provided for @adminActions.
  ///
  /// In en, this message translates to:
  /// **'Admin actions'**
  String get adminActions;

  /// No description provided for @adminActionsAreNotReadyOn.
  ///
  /// In en, this message translates to:
  /// **'Admin actions are not ready on this phone'**
  String get adminActionsAreNotReadyOn;

  /// No description provided for @adminActionsSaved.
  ///
  /// In en, this message translates to:
  /// **'Admin actions saved'**
  String get adminActionsSaved;

  /// No description provided for @adminBadge.
  ///
  /// In en, this message translates to:
  /// **'Admin badge'**
  String get adminBadge;

  /// No description provided for @adminBecomesTheNewOwner.
  ///
  /// In en, this message translates to:
  /// **' (admin) becomes the new owner.'**
  String get adminBecomesTheNewOwner;

  /// No description provided for @adminBlocked.
  ///
  /// In en, this message translates to:
  /// **'Admin blocked'**
  String get adminBlocked;

  /// No description provided for @adminConsole.
  ///
  /// In en, this message translates to:
  /// **'Admin console'**
  String get adminConsole;

  /// No description provided for @adminPolicy.
  ///
  /// In en, this message translates to:
  /// **'admin policy'**
  String get adminPolicy;

  /// No description provided for @adminSessionExpiredPleaseSignIn.
  ///
  /// In en, this message translates to:
  /// **'Admin session expired. Please sign in again.'**
  String get adminSessionExpiredPleaseSignIn;

  /// No description provided for @adminSettings.
  ///
  /// In en, this message translates to:
  /// **'Admin settings'**
  String get adminSettings;

  /// No description provided for @adminSettings2.
  ///
  /// In en, this message translates to:
  /// **'Admin Settings'**
  String get adminSettings2;

  /// No description provided for @adminTools.
  ///
  /// In en, this message translates to:
  /// **'admin tools'**
  String get adminTools;

  /// No description provided for @adminToolsAreNotAvailableRight.
  ///
  /// In en, this message translates to:
  /// **'Admin tools are not available right now'**
  String get adminToolsAreNotAvailableRight;

  /// No description provided for @adminToolsAreOffOnThis.
  ///
  /// In en, this message translates to:
  /// **'Admin tools are off on this phone.'**
  String get adminToolsAreOffOnThis;

  /// No description provided for @administration.
  ///
  /// In en, this message translates to:
  /// **'Administration / {title}'**
  String administration(Object? title);

  /// No description provided for @administratorNote.
  ///
  /// In en, this message translates to:
  /// **'Administrator note'**
  String get administratorNote;

  /// No description provided for @admins.
  ///
  /// In en, this message translates to:
  /// **'Admins'**
  String get admins;

  /// No description provided for @adminsApprovePeopleWhoJoinBy.
  ///
  /// In en, this message translates to:
  /// **'Admins approve people who join by QR'**
  String get adminsApprovePeopleWhoJoinBy;

  /// No description provided for @adminsDecide.
  ///
  /// In en, this message translates to:
  /// **'Admins decide'**
  String get adminsDecide;

  /// No description provided for @adminsOnlyNotifyEveryone.
  ///
  /// In en, this message translates to:
  /// **'Admins only: notify everyone'**
  String get adminsOnlyNotifyEveryone;

  /// No description provided for @adminsSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Admins signed in'**
  String get adminsSignedIn;

  /// No description provided for @affectsPhoneSeenNearby.
  ///
  /// In en, this message translates to:
  /// **'Affects {affects} phone{s} seen nearby'**
  String affectsPhoneSeenNearby(Object? affects, Object? s);

  /// No description provided for @alertAfter.
  ///
  /// In en, this message translates to:
  /// **'Alert after'**
  String get alertAfter;

  /// No description provided for @alertsAndPolicy.
  ///
  /// In en, this message translates to:
  /// **'Alerts and policy'**
  String get alertsAndPolicy;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All {reactions}'**
  String all(Object? reactions);

  /// No description provided for @all2.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all2;

  /// No description provided for @allAreYoursAndLessThan.
  ///
  /// In en, this message translates to:
  /// **'All {count} are yours and less than 5 minutes old, so \"Delete for everyone\" is shown. A copy someone saved to the Gallery stays.'**
  String allAreYoursAndLessThan(Object? count);

  /// No description provided for @allGood.
  ///
  /// In en, this message translates to:
  /// **'All good'**
  String get allGood;

  /// No description provided for @allMembers.
  ///
  /// In en, this message translates to:
  /// **'All members'**
  String get allMembers;

  /// No description provided for @allMembersAddPeople.
  ///
  /// In en, this message translates to:
  /// **'All members add people'**
  String get allMembersAddPeople;

  /// No description provided for @allMessagesPhotosAndFilesIn.
  ///
  /// In en, this message translates to:
  /// **'All messages, photos and files in this chat are '**
  String get allMessagesPhotosAndFilesIn;

  /// No description provided for @allMessagesPhotosAndFilesOf.
  ///
  /// In en, this message translates to:
  /// **'All messages, photos and files of this group are removed from this phone.'**
  String get allMessagesPhotosAndFilesOf;

  /// No description provided for @allTools.
  ///
  /// In en, this message translates to:
  /// **'all tools'**
  String get allTools;

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// No description provided for @allowNameSearchesToReturnYour.
  ///
  /// In en, this message translates to:
  /// **'Allow name searches to return your profile'**
  String get allowNameSearchesToReturnYour;

  /// No description provided for @allowNearbyDevicesToReachPeople.
  ///
  /// In en, this message translates to:
  /// **'Allow nearby devices to reach people without internet.'**
  String get allowNearbyDevicesToReachPeople;

  /// No description provided for @allowPeopleToFindYouWith.
  ///
  /// In en, this message translates to:
  /// **'Allow people to find you with your phone number'**
  String get allowPeopleToFindYouWith;

  /// No description provided for @allowTheNearbyDevicesPermissionThen.
  ///
  /// In en, this message translates to:
  /// **'Allow the \"Nearby devices\" permission, then tap Add friend again.'**
  String get allowTheNearbyDevicesPermissionThen;

  /// No description provided for @allowed.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get allowed;

  /// No description provided for @allowedRequired.
  ///
  /// In en, this message translates to:
  /// **'Allowed — required'**
  String get allowedRequired;

  /// No description provided for @alreadyInTheGroup.
  ///
  /// In en, this message translates to:
  /// **'Already in the group'**
  String get alreadyInTheGroup;

  /// No description provided for @alsoStopVeryOldApps.
  ///
  /// In en, this message translates to:
  /// **'Also stop very old apps'**
  String get alsoStopVeryOldApps;

  /// No description provided for @always.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get always;

  /// No description provided for @alwaysOff.
  ///
  /// In en, this message translates to:
  /// **'Always off'**
  String get alwaysOff;

  /// No description provided for @alwaysOn.
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get alwaysOn;

  /// No description provided for @alwaysUseTheDarkTheme.
  ///
  /// In en, this message translates to:
  /// **'Always use the dark theme.'**
  String get alwaysUseTheDarkTheme;

  /// No description provided for @alwaysUseTheLightTheme.
  ///
  /// In en, this message translates to:
  /// **'Always use the light theme.'**
  String get alwaysUseTheLightTheme;

  /// No description provided for @anAdmin.
  ///
  /// In en, this message translates to:
  /// **'An admin'**
  String get anAdmin;

  /// No description provided for @anAdmin2.
  ///
  /// In en, this message translates to:
  /// **'an admin'**
  String get anAdmin2;

  /// No description provided for @anAdminMustAddYouThis.
  ///
  /// In en, this message translates to:
  /// **'An admin must add you. This stays for 24 hours. You get \"{from} added you\" when it is done.'**
  String anAdminMustAddYouThis(Object? from);

  /// No description provided for @anAdminMustSayYesThis.
  ///
  /// In en, this message translates to:
  /// **'An admin must say yes. This stays for 24 hours. The group opens in your Chats when it is done.'**
  String get anAdminMustSayYesThis;

  /// No description provided for @anAndroidPhone.
  ///
  /// In en, this message translates to:
  /// **'•  An Android phone'**
  String get anAndroidPhone;

  /// No description provided for @and.
  ///
  /// In en, this message translates to:
  /// **'{join} and {parts}'**
  String and(Object? join, Object? parts);

  /// No description provided for @andAreTyping.
  ///
  /// In en, this message translates to:
  /// **'{clean} and {clean2} are typing…'**
  String andAreTyping(Object? clean, Object? clean2);

  /// No description provided for @andItLeavesYourChatsList.
  ///
  /// In en, this message translates to:
  /// **' and it leaves your Chats list.'**
  String get andItLeavesYourChatsList;

  /// No description provided for @andMoreAskedToJoin.
  ///
  /// In en, this message translates to:
  /// **'{first} and {n} more asked to join'**
  String andMoreAskedToJoin(Object? first, Object? n);

  /// No description provided for @android.
  ///
  /// In en, this message translates to:
  /// **'Android'**
  String get android;

  /// No description provided for @android14FullScreenWhenLocked.
  ///
  /// In en, this message translates to:
  /// **'Android 14+: full screen when locked'**
  String get android14FullScreenWhenLocked;

  /// No description provided for @androidControls.
  ///
  /// In en, this message translates to:
  /// **'Android controls'**
  String get androidControls;

  /// No description provided for @androidTurnedTheLinkupWiFi.
  ///
  /// In en, this message translates to:
  /// **'Android turned the LinkUp Wi-Fi off.'**
  String get androidTurnedTheLinkupWiFi;

  /// No description provided for @androidWillAskConnectEachTime.
  ///
  /// In en, this message translates to:
  /// **'Android will ask \"Connect?\" each time this phone joins another group or hotspot. Tap Connect to allow it. Needs Android 10 or newer.'**
  String get androidWillAskConnectEachTime;

  /// No description provided for @androidWillAskYouToAllow.
  ///
  /// In en, this message translates to:
  /// **'Android will ask you to allow installs from LinkUp. Turn it on, then come back.'**
  String get androidWillAskYouToAllow;

  /// No description provided for @anotherAccount.
  ///
  /// In en, this message translates to:
  /// **'another account'**
  String get anotherAccount;

  /// No description provided for @anotherCallIsAlreadyActive.
  ///
  /// In en, this message translates to:
  /// **'Another call is already active'**
  String get anotherCallIsAlreadyActive;

  /// No description provided for @answer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get answer;

  /// No description provided for @answerTheyCanChangeItFor.
  ///
  /// In en, this message translates to:
  /// **' answer. They can change it for 3 minutes after voting, then it\'s final.'**
  String get answerTheyCanChangeItFor;

  /// No description provided for @anyoneCanFindYouByName.
  ///
  /// In en, this message translates to:
  /// **'Anyone can find you by name and see your phone number.'**
  String get anyoneCanFindYouByName;

  /// No description provided for @anyoneThisPhoneHasSeenOr.
  ///
  /// In en, this message translates to:
  /// **'Anyone this phone has seen, or nearby'**
  String get anyoneThisPhoneHasSeenOr;

  /// No description provided for @anyoneWhoScansThisNearA.
  ///
  /// In en, this message translates to:
  /// **'Anyone who scans this near a member can ask to join. It works without internet.\n'**
  String get anyoneWhoScansThisNearA;

  /// No description provided for @anyoneWithLinkupWhoOpensThis.
  ///
  /// In en, this message translates to:
  /// **'Anyone with LinkUp who opens this link can ask to join, from anywhere. It needs internet (the server). With \"Approve new members\" on, an admin must say yes.'**
  String get anyoneWithLinkupWhoOpensThis;

  /// No description provided for @anyoneWithTheLinkCanAsk.
  ///
  /// In en, this message translates to:
  /// **'Anyone with the link can ask to join'**
  String get anyoneWithTheLinkCanAsk;

  /// No description provided for @anyoneWithThisCodeCanReset.
  ///
  /// In en, this message translates to:
  /// **'Anyone with this code can reset your password. LinkUp will never ask for it.'**
  String get anyoneWithThisCodeCanReset;

  /// No description provided for @appInfoBatteryAllowBackgroundActivity.
  ///
  /// In en, this message translates to:
  /// **'App info > Battery: Allow background activity'**
  String get appInfoBatteryAllowBackgroundActivity;

  /// No description provided for @appInfoBatterySaverChooseNo.
  ///
  /// In en, this message translates to:
  /// **'App info > Battery saver: choose No restrictions'**
  String get appInfoBatterySaverChooseNo;

  /// No description provided for @appLaunchTurnOffManageAutomatically.
  ///
  /// In en, this message translates to:
  /// **'App launch: turn off Manage automatically for LinkUp'**
  String get appLaunchTurnOffManageAutomatically;

  /// No description provided for @appTooOldToAnswer.
  ///
  /// In en, this message translates to:
  /// **'app too old to answer'**
  String get appTooOldToAnswer;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get appVersion;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @approveAndGiveCode.
  ///
  /// In en, this message translates to:
  /// **'Approve and give code'**
  String get approveAndGiveCode;

  /// No description provided for @approveNewMembers.
  ///
  /// In en, this message translates to:
  /// **'Approve new members'**
  String get approveNewMembers;

  /// No description provided for @approved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approved;

  /// No description provided for @approvedEnterTheRecoveryCodeProvided.
  ///
  /// In en, this message translates to:
  /// **'Approved. Enter the recovery code provided by the administrator.'**
  String get approvedEnterTheRecoveryCodeProvided;

  /// No description provided for @approvedRecoveryFor.
  ///
  /// In en, this message translates to:
  /// **'{admin} approved recovery for {target}'**
  String approvedRecoveryFor(Object? admin, Object? target);

  /// No description provided for @appsBefore3054Can.
  ///
  /// In en, this message translates to:
  /// **'Apps before 3.0.54 can\'t read this rule. The server refuses them.'**
  String get appsBefore3054Can;

  /// No description provided for @apr.
  ///
  /// In en, this message translates to:
  /// **'Apr'**
  String get apr;

  /// No description provided for @areRequiredFillThemInBefore.
  ///
  /// In en, this message translates to:
  /// **'{and} are required — fill them in before saving.'**
  String areRequiredFillThemInBefore(Object? and);

  /// No description provided for @askAQuestion.
  ///
  /// In en, this message translates to:
  /// **'Ask a question'**
  String get askAQuestion;

  /// No description provided for @askPhones.
  ///
  /// In en, this message translates to:
  /// **'Ask phones'**
  String get askPhones;

  /// No description provided for @askPhonesForAChatOwner.
  ///
  /// In en, this message translates to:
  /// **'Ask phones for a chat · Owner only'**
  String get askPhonesForAChatOwner;

  /// No description provided for @askTheAdmin.
  ///
  /// In en, this message translates to:
  /// **'Ask the admin'**
  String get askTheAdmin;

  /// No description provided for @askTheAdminForTheCode.
  ///
  /// In en, this message translates to:
  /// **'Ask the admin for the code.'**
  String get askTheAdminForTheCode;

  /// No description provided for @askTheAdminToApproveIt.
  ///
  /// In en, this message translates to:
  /// **'Ask the admin to approve it'**
  String get askTheAdminToApproveIt;

  /// No description provided for @askThemToOpenTheLink.
  ///
  /// In en, this message translates to:
  /// **'Ask them to open the link again with the newest LinkUp.'**
  String get askThemToOpenTheLink;

  /// No description provided for @askToJoin.
  ///
  /// In en, this message translates to:
  /// **'Ask to join'**
  String get askToJoin;

  /// No description provided for @asked.
  ///
  /// In en, this message translates to:
  /// **'Asked {created_at} · {expires_at}'**
  String asked(Object? created_at, Object? expires_at);

  /// No description provided for @askedThePhoneForTheFull.
  ///
  /// In en, this message translates to:
  /// **'Asked the phone for the full file'**
  String get askedThePhoneForTheFull;

  /// No description provided for @atLeast8Characters.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get atLeast8Characters;

  /// No description provided for @attach.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get attach;

  /// No description provided for @auditLog.
  ///
  /// In en, this message translates to:
  /// **'Audit log'**
  String get auditLog;

  /// No description provided for @auditLog2.
  ///
  /// In en, this message translates to:
  /// **'Audit Log'**
  String get auditLog2;

  /// No description provided for @auditedEventsSessionsAndOutstandingRecovery.
  ///
  /// In en, this message translates to:
  /// **'Audited events, sessions and outstanding recovery work'**
  String get auditedEventsSessionsAndOutstandingRecovery;

  /// No description provided for @auditor.
  ///
  /// In en, this message translates to:
  /// **'Auditor'**
  String get auditor;

  /// No description provided for @aug.
  ///
  /// In en, this message translates to:
  /// **'Aug'**
  String get aug;

  /// No description provided for @authenticatedDeviceSessions.
  ///
  /// In en, this message translates to:
  /// **'Authenticated device sessions'**
  String get authenticatedDeviceSessions;

  /// No description provided for @authenticatedSessions.
  ///
  /// In en, this message translates to:
  /// **'Authenticated sessions'**
  String get authenticatedSessions;

  /// No description provided for @autoFixed.
  ///
  /// In en, this message translates to:
  /// **'Auto-fixed'**
  String get autoFixed;

  /// No description provided for @autoLaunchTurnLinkupOn.
  ///
  /// In en, this message translates to:
  /// **'Auto launch: turn LinkUp ON'**
  String get autoLaunchTurnLinkupOn;

  /// No description provided for @autoStartTurnLinkupOn.
  ///
  /// In en, this message translates to:
  /// **'Auto-start: turn LinkUp ON'**
  String get autoStartTurnLinkupOn;

  /// No description provided for @autostartTurnLinkupOn.
  ///
  /// In en, this message translates to:
  /// **'Autostart: turn LinkUp ON'**
  String get autostartTurnLinkupOn;

  /// No description provided for @available.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get available;

  /// No description provided for @avoidWiFiDirectAndMesh.
  ///
  /// In en, this message translates to:
  /// **'Avoid Wi-Fi Direct and mesh messaging. LinkUp uses the configured server connection when available; this does not guarantee that the server itself is on the public Internet.'**
  String get avoidWiFiDirectAndMesh;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @backToStep1.
  ///
  /// In en, this message translates to:
  /// **'←  Back to step 1'**
  String get backToStep1;

  /// No description provided for @backUpNow.
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get backUpNow;

  /// No description provided for @backgroundPowerUseAllowLinkup.
  ///
  /// In en, this message translates to:
  /// **'Background power use: allow LinkUp'**
  String get backgroundPowerUseAllowLinkup;

  /// No description provided for @backup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backup;

  /// No description provided for @backupAndRestore.
  ///
  /// In en, this message translates to:
  /// **'Backup and restore'**
  String get backupAndRestore;

  /// No description provided for @backupAndSafety.
  ///
  /// In en, this message translates to:
  /// **'Backup and safety'**
  String get backupAndSafety;

  /// No description provided for @backupCompleted.
  ///
  /// In en, this message translates to:
  /// **'Backup completed.'**
  String get backupCompleted;

  /// No description provided for @backupCouldNotBeCreated.
  ///
  /// In en, this message translates to:
  /// **'Backup could not be created.'**
  String get backupCouldNotBeCreated;

  /// No description provided for @backupMade.
  ///
  /// In en, this message translates to:
  /// **'Backup made.'**
  String get backupMade;

  /// No description provided for @backupPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Backup passphrase'**
  String get backupPassphrase;

  /// No description provided for @backupWrittenTo.
  ///
  /// In en, this message translates to:
  /// **'Backup written to {path}'**
  String backupWrittenTo(Object? path);

  /// No description provided for @batteryChooseUnrestricted.
  ///
  /// In en, this message translates to:
  /// **'Battery: choose Unrestricted'**
  String get batteryChooseUnrestricted;

  /// No description provided for @batteryLow10OrLess.
  ///
  /// In en, this message translates to:
  /// **'Battery low (10% or less)'**
  String get batteryLow10OrLess;

  /// No description provided for @batteryOptimizationIsAlreadyIgnored.
  ///
  /// In en, this message translates to:
  /// **'{lockedToast} Battery optimization is already ignored.'**
  String batteryOptimizationIsAlreadyIgnored(Object? lockedToast);

  /// No description provided for @batteryPermissionDialogsAreShownOnly.
  ///
  /// In en, this message translates to:
  /// **'Battery-permission dialogs are shown only when you tap a row. Nothing is enabled silently.'**
  String get batteryPermissionDialogsAreShownOnly;

  /// No description provided for @becomesTheNewOwner.
  ///
  /// In en, this message translates to:
  /// **' becomes the new owner.'**
  String get becomesTheNewOwner;

  /// No description provided for @below.
  ///
  /// In en, this message translates to:
  /// **' below.'**
  String get below;

  /// No description provided for @biggestFirstTapToOpenHold.
  ///
  /// In en, this message translates to:
  /// **'Biggest first. Tap to open, hold to pick.'**
  String get biggestFirstTapToOpenHold;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @block2.
  ///
  /// In en, this message translates to:
  /// **'Block {name}'**
  String block2(Object? name);

  /// No description provided for @block3.
  ///
  /// In en, this message translates to:
  /// **'Block {name}?'**
  String block3(Object? name);

  /// No description provided for @blockAUser.
  ///
  /// In en, this message translates to:
  /// **'Block a user'**
  String get blockAUser;

  /// No description provided for @blockFailed.
  ///
  /// In en, this message translates to:
  /// **'Block failed: {error}'**
  String blockFailed(Object? error);

  /// No description provided for @blockForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Block for everyone'**
  String get blockForEveryone;

  /// No description provided for @blockOrUnblockAUser.
  ///
  /// In en, this message translates to:
  /// **'Block or unblock a user'**
  String get blockOrUnblockAUser;

  /// No description provided for @blockSavedOnTheServer.
  ///
  /// In en, this message translates to:
  /// **'Block saved on the server'**
  String get blockSavedOnTheServer;

  /// No description provided for @blockSavedOnTheServer2.
  ///
  /// In en, this message translates to:
  /// **'{user} block saved on the server'**
  String blockSavedOnTheServer2(Object? user);

  /// No description provided for @blockUser.
  ///
  /// In en, this message translates to:
  /// **'Block user'**
  String get blockUser;

  /// No description provided for @blockUsersAllPhones.
  ///
  /// In en, this message translates to:
  /// **'Block users (all phones)'**
  String get blockUsersAllPhones;

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get blocked;

  /// No description provided for @blocked2.
  ///
  /// In en, this message translates to:
  /// **'Blocked {toLocal}'**
  String blocked2(Object? toLocal);

  /// No description provided for @blocked3.
  ///
  /// In en, this message translates to:
  /// **'blocked {when}'**
  String blocked3(Object? when);

  /// No description provided for @blocked4.
  ///
  /// In en, this message translates to:
  /// **'{name} blocked'**
  String blocked4(Object? name);

  /// No description provided for @blocked5.
  ///
  /// In en, this message translates to:
  /// **'{admin} blocked {target}'**
  String blocked5(Object? admin, Object? target);

  /// No description provided for @blocked6.
  ///
  /// In en, this message translates to:
  /// **'{label} · Blocked'**
  String blocked6(Object? label);

  /// No description provided for @blockedBy.
  ///
  /// In en, this message translates to:
  /// **'Blocked by {by} · {at}{phones}'**
  String blockedBy(Object? by, Object? at, Object? phones);

  /// No description provided for @blockedByAdmin.
  ///
  /// In en, this message translates to:
  /// **'Blocked by admin'**
  String get blockedByAdmin;

  /// No description provided for @blockedByAdminYouCanT.
  ///
  /// In en, this message translates to:
  /// **'Blocked by admin. You can\'t send.'**
  String get blockedByAdminYouCanT;

  /// No description provided for @blockedList.
  ///
  /// In en, this message translates to:
  /// **'Blocked list'**
  String get blockedList;

  /// No description provided for @blockedOn.
  ///
  /// In en, this message translates to:
  /// **'Blocked on {when}.'**
  String blockedOn(Object? when);

  /// No description provided for @blockedOnEveryLinkupPhoneIt.
  ///
  /// In en, this message translates to:
  /// **'{all} blocked · on every LinkUp phone it reaches'**
  String blockedOnEveryLinkupPhoneIt(Object? all);

  /// No description provided for @blockedOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Blocked on this phone'**
  String get blockedOnThisPhone;

  /// No description provided for @blockedOnThisPhone2.
  ///
  /// In en, this message translates to:
  /// **'{name} blocked on this phone.'**
  String blockedOnThisPhone2(Object? name);

  /// No description provided for @blockedPeople.
  ///
  /// In en, this message translates to:
  /// **'Blocked people'**
  String get blockedPeople;

  /// No description provided for @blockedRelaysOnly.
  ///
  /// In en, this message translates to:
  /// **'Blocked · relays only'**
  String get blockedRelaysOnly;

  /// No description provided for @blockedServerLater.
  ///
  /// In en, this message translates to:
  /// **'Blocked · server later'**
  String get blockedServerLater;

  /// No description provided for @blocks.
  ///
  /// In en, this message translates to:
  /// **'Blocks'**
  String get blocks;

  /// No description provided for @blueInTheChatOnlyWhen.
  ///
  /// In en, this message translates to:
  /// **'Blue ✓✓ in the chat only when all {total} have read it. People with read receipts off show under Delivered.'**
  String blueInTheChatOnlyWhen(Object? total);

  /// No description provided for @bluetoothNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth not allowed'**
  String get bluetoothNotAllowed;

  /// No description provided for @bluetoothOff.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth off'**
  String get bluetoothOff;

  /// No description provided for @bluetoothOn.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth on'**
  String get bluetoothOn;

  /// No description provided for @bridgeToWiFi.
  ///
  /// In en, this message translates to:
  /// **'Bridge to Wi-Fi'**
  String get bridgeToWiFi;

  /// No description provided for @build.
  ///
  /// In en, this message translates to:
  /// **'Build {build}'**
  String build(Object? build);

  /// No description provided for @build2.
  ///
  /// In en, this message translates to:
  /// **'build {build}'**
  String build2(Object? build);

  /// No description provided for @build3.
  ///
  /// In en, this message translates to:
  /// **'{version} (build {build})'**
  String build3(Object? version, Object? build);

  /// No description provided for @busy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get busy;

  /// No description provided for @call.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// No description provided for @callAlertsOffTapToTurn.
  ///
  /// In en, this message translates to:
  /// **'Call alerts off - tap to turn on'**
  String get callAlertsOffTapToTurn;

  /// No description provided for @callAlertsOn.
  ///
  /// In en, this message translates to:
  /// **'Call alerts on'**
  String get callAlertsOn;

  /// No description provided for @callAudio.
  ///
  /// In en, this message translates to:
  /// **'Call audio'**
  String get callAudio;

  /// No description provided for @callBack.
  ///
  /// In en, this message translates to:
  /// **'Call back'**
  String get callBack;

  /// No description provided for @callCanceled.
  ///
  /// In en, this message translates to:
  /// **'Call canceled'**
  String get callCanceled;

  /// No description provided for @callEnded.
  ///
  /// In en, this message translates to:
  /// **'Call ended'**
  String get callEnded;

  /// No description provided for @callEndedNoNearbyConnection.
  ///
  /// In en, this message translates to:
  /// **'Call ended: no nearby connection'**
  String get callEndedNoNearbyConnection;

  /// No description provided for @callFailed.
  ///
  /// In en, this message translates to:
  /// **'Call failed'**
  String get callFailed;

  /// No description provided for @callInProgress.
  ///
  /// In en, this message translates to:
  /// **'Call in progress'**
  String get callInProgress;

  /// No description provided for @callIsNoLongerAvailable.
  ///
  /// In en, this message translates to:
  /// **'Call is no longer available'**
  String get callIsNoLongerAvailable;

  /// No description provided for @callSessions.
  ///
  /// In en, this message translates to:
  /// **'Call sessions'**
  String get callSessions;

  /// No description provided for @calling.
  ///
  /// In en, this message translates to:
  /// **'Calling…'**
  String get calling;

  /// No description provided for @callingTapToReturn.
  ///
  /// In en, this message translates to:
  /// **'{name} · Calling… — Tap to return'**
  String callingTapToReturn(Object? name);

  /// No description provided for @calls.
  ///
  /// In en, this message translates to:
  /// **'{startedAt} · {count} calls'**
  String calls(Object? startedAt, Object? count);

  /// No description provided for @calls2.
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get calls2;

  /// No description provided for @callsPassedOnNow.
  ///
  /// In en, this message translates to:
  /// **'Calls passed on now'**
  String get callsPassedOnNow;

  /// No description provided for @callsRingButNoAcceptButton.
  ///
  /// In en, this message translates to:
  /// **'Calls ring, but no Accept button'**
  String get callsRingButNoAcceptButton;

  /// No description provided for @callsRingWithAcceptReject.
  ///
  /// In en, this message translates to:
  /// **'Calls ring with Accept / Reject'**
  String get callsRingWithAcceptReject;

  /// No description provided for @callsShowHereWithNamesAnd.
  ///
  /// In en, this message translates to:
  /// **'Calls show here with names and times.'**
  String get callsShowHereWithNamesAnd;

  /// No description provided for @callsToday.
  ///
  /// In en, this message translates to:
  /// **'Calls today'**
  String get callsToday;

  /// No description provided for @cameByLocalWiFi.
  ///
  /// In en, this message translates to:
  /// **'Came by Local Wi-Fi'**
  String get cameByLocalWiFi;

  /// No description provided for @cameByMeshThroughAFriend.
  ///
  /// In en, this message translates to:
  /// **'Came by Mesh (through a friend\'s phone)'**
  String get cameByMeshThroughAFriend;

  /// No description provided for @cameByWiFiDirect.
  ///
  /// In en, this message translates to:
  /// **'Came by Wi-Fi Direct'**
  String get cameByWiFiDirect;

  /// No description provided for @cameThroughTheServer.
  ///
  /// In en, this message translates to:
  /// **'Came through the server'**
  String get cameThroughTheServer;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @canAskAgainLater.
  ///
  /// In en, this message translates to:
  /// **'{they} can ask again later.'**
  String canAskAgainLater(Object? they);

  /// No description provided for @canHelpIfYouForgetYour.
  ///
  /// In en, this message translates to:
  /// **'Can help if you forget your password, lose a phone, or your Wi-Fi settings need fixing.'**
  String get canHelpIfYouForgetYour;

  /// No description provided for @canOnlyLook.
  ///
  /// In en, this message translates to:
  /// **'can only look'**
  String get canOnlyLook;

  /// No description provided for @canSendMessages.
  ///
  /// In en, this message translates to:
  /// **' can send messages.'**
  String get canSendMessages;

  /// No description provided for @canStillReadThemUnblockAnytime.
  ///
  /// In en, this message translates to:
  /// **'{first} can still read them. Unblock anytime'**
  String canStillReadThemUnblockAnytime(Object? first);

  /// No description provided for @canTJoinTheServerYet.
  ///
  /// In en, this message translates to:
  /// **'Can\'t join the server yet'**
  String get canTJoinTheServerYet;

  /// No description provided for @canTMessageOrCallYou.
  ///
  /// In en, this message translates to:
  /// **'{name} **can\'t message or call** you, and their adds are ignored.'**
  String canTMessageOrCallYou(Object? name);

  /// No description provided for @canTOpenTheLinkNow.
  ///
  /// In en, this message translates to:
  /// **'Can\'t open the link now. Check the internet and try again.'**
  String get canTOpenTheLinkNow;

  /// No description provided for @canTPlayThisVideo.
  ///
  /// In en, this message translates to:
  /// **'Can\'t play this video'**
  String get canTPlayThisVideo;

  /// No description provided for @canTSendOrGetThem.
  ///
  /// In en, this message translates to:
  /// **'Can\'t send or get them on any phone'**
  String get canTSendOrGetThem;

  /// No description provided for @canTSignInForNow.
  ///
  /// In en, this message translates to:
  /// **'Can’t sign in for now'**
  String get canTSignInForNow;

  /// No description provided for @canTSignInUntilYou.
  ///
  /// In en, this message translates to:
  /// **'{name} can’t sign in until you set Active again.'**
  String canTSignInUntilYou(Object? name);

  /// No description provided for @canUseLinkup.
  ///
  /// In en, this message translates to:
  /// **'Can use LinkUp'**
  String get canUseLinkup;

  /// No description provided for @canUseLinkupAgain.
  ///
  /// In en, this message translates to:
  /// **'{name} can use LinkUp again.'**
  String canUseLinkupAgain(Object? name);

  /// No description provided for @canUseLinkupAtOnce.
  ///
  /// In en, this message translates to:
  /// **'{first} can use LinkUp at once'**
  String canUseLinkupAtOnce(Object? first);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @cancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel action'**
  String get cancelAction;

  /// No description provided for @cancelDownload.
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get cancelDownload;

  /// No description provided for @cancelReply.
  ///
  /// In en, this message translates to:
  /// **'Cancel reply'**
  String get cancelReply;

  /// No description provided for @cancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get cancelRequest;

  /// No description provided for @cancelThis.
  ///
  /// In en, this message translates to:
  /// **'Cancel this {what}?'**
  String cancelThis(Object? what);

  /// No description provided for @cancelThisAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel this action?'**
  String get cancelThisAction;

  /// No description provided for @cancelThisRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel this request?'**
  String get cancelThisRequest;

  /// No description provided for @cancelTransfer.
  ///
  /// In en, this message translates to:
  /// **'Cancel transfer'**
  String get cancelTransfer;

  /// No description provided for @canceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get canceled;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @cancelled2.
  ///
  /// In en, this message translates to:
  /// **'Cancelled {finishedAt}'**
  String cancelled2(Object? finishedAt);

  /// No description provided for @carriedBy.
  ///
  /// In en, this message translates to:
  /// **'carried by {n}'**
  String carriedBy(Object? n);

  /// No description provided for @carriedByAPhone.
  ///
  /// In en, this message translates to:
  /// **'carried by a phone'**
  String get carriedByAPhone;

  /// No description provided for @changeKey.
  ///
  /// In en, this message translates to:
  /// **'Change key'**
  String get changeKey;

  /// No description provided for @changeProfilePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change profile photo'**
  String get changeProfilePhoto;

  /// No description provided for @changeSecurityKey.
  ///
  /// In en, this message translates to:
  /// **'Change security key?'**
  String get changeSecurityKey;

  /// No description provided for @changeTheRuleOnTheApp.
  ///
  /// In en, this message translates to:
  /// **'Change the rule on the App version page.'**
  String get changeTheRuleOnTheApp;

  /// No description provided for @changedAdminSettings.
  ///
  /// In en, this message translates to:
  /// **'{admin} changed admin settings'**
  String changedAdminSettings(Object? admin);

  /// No description provided for @changedTheGroup.
  ///
  /// In en, this message translates to:
  /// **'{actor} changed the group'**
  String changedTheGroup(Object? actor);

  /// No description provided for @changedTheGroupDescription.
  ///
  /// In en, this message translates to:
  /// **'{actor} changed the group description'**
  String changedTheGroupDescription(Object? actor);

  /// No description provided for @changedTheGroupNameTo.
  ///
  /// In en, this message translates to:
  /// **'{actor} changed the group name to \"{name}\"'**
  String changedTheGroupNameTo(Object? actor, Object? name);

  /// No description provided for @changedTheGroupSettings.
  ///
  /// In en, this message translates to:
  /// **'{actor} changed the group settings'**
  String changedTheGroupSettings(Object? actor);

  /// No description provided for @changedTheWiFiRuleOf.
  ///
  /// In en, this message translates to:
  /// **'{admin} changed the Wi-Fi rule of {target}'**
  String changedTheWiFiRuleOf(Object? admin, Object? target);

  /// No description provided for @changedThisGroupSPhoto.
  ///
  /// In en, this message translates to:
  /// **'{actor} changed this group\'s photo'**
  String changedThisGroupSPhoto(Object? actor);

  /// No description provided for @changedThisGroupSoAllMembers.
  ///
  /// In en, this message translates to:
  /// **'{actor} changed this group so all members can add members'**
  String changedThisGroupSoAllMembers(Object? actor);

  /// No description provided for @changedThisGroupSoAllMembers2.
  ///
  /// In en, this message translates to:
  /// **'{actor} changed this group so all members can edit the group info'**
  String changedThisGroupSoAllMembers2(Object? actor);

  /// No description provided for @changedThisGroupSoAllMembers3.
  ///
  /// In en, this message translates to:
  /// **'{actor} changed this group so all members can send messages'**
  String changedThisGroupSoAllMembers3(Object? actor);

  /// No description provided for @changedThisGroupSoOnlyAdmins.
  ///
  /// In en, this message translates to:
  /// **'{actor} changed this group so only admins can add members'**
  String changedThisGroupSoOnlyAdmins(Object? actor);

  /// No description provided for @changedThisGroupSoOnlyAdmins2.
  ///
  /// In en, this message translates to:
  /// **'{actor} changed this group so only admins can edit the group info'**
  String changedThisGroupSoOnlyAdmins2(Object? actor);

  /// No description provided for @changedThisGroupSoOnlyAdmins3.
  ///
  /// In en, this message translates to:
  /// **'{actor} changed this group so only admins can send messages'**
  String changedThisGroupSoOnlyAdmins3(Object? actor);

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @chatAndCallEvenWithoutInternet.
  ///
  /// In en, this message translates to:
  /// **'Chat and call, even without internet'**
  String get chatAndCallEvenWithoutInternet;

  /// No description provided for @chats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// No description provided for @chatsBiggestFirst.
  ///
  /// In en, this message translates to:
  /// **'Chats, biggest first'**
  String get chatsBiggestFirst;

  /// No description provided for @chatsCallsPeople.
  ///
  /// In en, this message translates to:
  /// **'Chats, calls, people'**
  String get chatsCallsPeople;

  /// No description provided for @checkAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get checkAgain;

  /// No description provided for @checkTheNewPasswordAndTry.
  ///
  /// In en, this message translates to:
  /// **'Check the new password and try again.'**
  String get checkTheNewPasswordAndTry;

  /// No description provided for @checkedByTheServerForEvery.
  ///
  /// In en, this message translates to:
  /// **'Checked by the server for every admin'**
  String get checkedByTheServerForEvery;

  /// No description provided for @checking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get checking;

  /// No description provided for @checkingAndroidPermission.
  ///
  /// In en, this message translates to:
  /// **'Checking Android permission…'**
  String get checkingAndroidPermission;

  /// No description provided for @checkingTheServer.
  ///
  /// In en, this message translates to:
  /// **'Checking the server…'**
  String get checkingTheServer;

  /// No description provided for @checksThatLinkupWorksWellCan.
  ///
  /// In en, this message translates to:
  /// **'Checks that LinkUp works well. Can only look, can not change your account.'**
  String get checksThatLinkupWorksWellCan;

  /// No description provided for @chooseAPasswordOfAtLeast.
  ///
  /// In en, this message translates to:
  /// **'Choose a password of at least 8 characters.'**
  String get chooseAPasswordOfAtLeast;

  /// No description provided for @chooseHowLinkupLooksOnThis.
  ///
  /// In en, this message translates to:
  /// **'Choose how LinkUp looks on this phone.'**
  String get chooseHowLinkupLooksOnThis;

  /// No description provided for @chooseHowMuchMessageDetailAppears.
  ///
  /// In en, this message translates to:
  /// **'Choose how much message detail appears when your phone is locked.'**
  String get chooseHowMuchMessageDetailAppears;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @clearCallsWithPeopleNearYou.
  ///
  /// In en, this message translates to:
  /// **'Clear calls with people near you'**
  String get clearCallsWithPeopleNearYou;

  /// No description provided for @clearChat.
  ///
  /// In en, this message translates to:
  /// **'Clear chat'**
  String get clearChat;

  /// No description provided for @clearChatWith.
  ///
  /// In en, this message translates to:
  /// **'Clear chat with {name}?'**
  String clearChatWith(Object? name);

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @closeDeleteThisCopy.
  ///
  /// In en, this message translates to:
  /// **'Close (delete this copy)'**
  String get closeDeleteThisCopy;

  /// No description provided for @closeOtherSharingAppsAndTry.
  ///
  /// In en, this message translates to:
  /// **'Close other sharing apps and try again.'**
  String get closeOtherSharingAppsAndTry;

  /// No description provided for @closeSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearch;

  /// No description provided for @closeVideo.
  ///
  /// In en, this message translates to:
  /// **'Close video'**
  String get closeVideo;

  /// No description provided for @codeChanged.
  ///
  /// In en, this message translates to:
  /// **'Code changed'**
  String get codeChanged;

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get codeCopied;

  /// No description provided for @collapseMenu.
  ///
  /// In en, this message translates to:
  /// **'Collapse menu'**
  String get collapseMenu;

  /// No description provided for @compareThisCodeWithTheOne.
  ///
  /// In en, this message translates to:
  /// **'Compare this code with the one on {v}\'s phone. If they are the same, nobody is in the middle of your chats and calls.'**
  String compareThisCodeWithTheOne(Object? v);

  /// No description provided for @completeRecovery.
  ///
  /// In en, this message translates to:
  /// **'Complete recovery'**
  String get completeRecovery;

  /// No description provided for @completeTransfer.
  ///
  /// In en, this message translates to:
  /// **'Complete transfer'**
  String get completeTransfer;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @completingSecureAccountRecovery.
  ///
  /// In en, this message translates to:
  /// **'Completing secure account recovery…'**
  String get completingSecureAccountRecovery;

  /// No description provided for @completingSecureDeviceTransfer.
  ///
  /// In en, this message translates to:
  /// **'Completing secure device transfer…'**
  String get completingSecureDeviceTransfer;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @confirmItSMe.
  ///
  /// In en, this message translates to:
  /// **'Confirm it\'s me'**
  String get confirmItSMe;

  /// No description provided for @confirmItSYouToKeep.
  ///
  /// In en, this message translates to:
  /// **'Confirm it\'s you to keep using LinkUp on this phone.'**
  String get confirmItSYouToKeep;

  /// No description provided for @confirmPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Confirm passphrase'**
  String get confirmPassphrase;

  /// No description provided for @confirmYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Confirm your account'**
  String get confirmYourAccount;

  /// No description provided for @connectToTheServerOnceTo.
  ///
  /// In en, this message translates to:
  /// **'Connect to the server once to turn on offline blocking'**
  String get connectToTheServerOnceTo;

  /// No description provided for @connectToTheServerOnceTo2.
  ///
  /// In en, this message translates to:
  /// **'Connect to the server once to turn on offline blocking.'**
  String get connectToTheServerOnceTo2;

  /// No description provided for @connectToTheServerToUse.
  ///
  /// In en, this message translates to:
  /// **'Connect to the server to use the old password.'**
  String get connectToTheServerToUse;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @connectedByMesh.
  ///
  /// In en, this message translates to:
  /// **'Connected by Mesh'**
  String get connectedByMesh;

  /// No description provided for @connectedByWiFi.
  ///
  /// In en, this message translates to:
  /// **'Connected by Wi-Fi'**
  String get connectedByWiFi;

  /// No description provided for @connectedByWiFiDirect.
  ///
  /// In en, this message translates to:
  /// **'Connected by Wi-Fi Direct'**
  String get connectedByWiFiDirect;

  /// No description provided for @connectedOnline.
  ///
  /// In en, this message translates to:
  /// **'Connected Online'**
  String get connectedOnline;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// No description provided for @connectingSecurely.
  ///
  /// In en, this message translates to:
  /// **'Connecting securely…'**
  String get connectingSecurely;

  /// No description provided for @connectingVideo.
  ///
  /// In en, this message translates to:
  /// **'Connecting video…'**
  String get connectingVideo;

  /// No description provided for @connection.
  ///
  /// In en, this message translates to:
  /// **'Connection: {label}'**
  String connection(Object? label);

  /// No description provided for @connectionQuality.
  ///
  /// In en, this message translates to:
  /// **'Connection quality'**
  String get connectionQuality;

  /// No description provided for @connectionStatus.
  ///
  /// In en, this message translates to:
  /// **'Connection status: {label}'**
  String connectionStatus(Object? label);

  /// No description provided for @connectionStatus2.
  ///
  /// In en, this message translates to:
  /// **'Connection status: {label}{detail}'**
  String connectionStatus2(Object? label, Object? detail);

  /// No description provided for @connectivity.
  ///
  /// In en, this message translates to:
  /// **'Connectivity'**
  String get connectivity;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contact;

  /// No description provided for @contactAdded.
  ///
  /// In en, this message translates to:
  /// **'Contact added'**
  String get contactAdded;

  /// No description provided for @contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// No description provided for @contacts2.
  ///
  /// In en, this message translates to:
  /// **'{all} contacts'**
  String contacts2(Object? all);

  /// No description provided for @contactsWithAnOlderLinkupWill.
  ///
  /// In en, this message translates to:
  /// **'Contacts with an older LinkUp will not connect nearby until they update. Messages through the internet still work.'**
  String get contactsWithAnOlderLinkupWill;

  /// No description provided for @continueRecording.
  ///
  /// In en, this message translates to:
  /// **'Continue recording'**
  String get continueRecording;

  /// No description provided for @continueText.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueText;

  /// No description provided for @conversationInfo.
  ///
  /// In en, this message translates to:
  /// **'Conversation info'**
  String get conversationInfo;

  /// No description provided for @conversations.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get conversations;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @copiedWhatsappIsNotOnThis.
  ///
  /// In en, this message translates to:
  /// **'Copied. WhatsApp is not on this phone.'**
  String get copiedWhatsappIsNotOnThis;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @copyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyText;

  /// No description provided for @couldNotAcceptTheNewCode.
  ///
  /// In en, this message translates to:
  /// **'Could not accept the new code'**
  String get couldNotAcceptTheNewCode;

  /// No description provided for @couldNotAddThisPersonTry.
  ///
  /// In en, this message translates to:
  /// **'Could not add this person. Try again.'**
  String get couldNotAddThisPersonTry;

  /// No description provided for @couldNotAddTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Could not add {r}. Try again.'**
  String couldNotAddTryAgain(Object? r);

  /// No description provided for @couldNotBlock.
  ///
  /// In en, this message translates to:
  /// **'Could not block {name}'**
  String couldNotBlock(Object? name);

  /// No description provided for @couldNotConnectToLinkupMake.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to LinkUp. Make sure the LinkUp server is available on your private network.'**
  String get couldNotConnectToLinkupMake;

  /// No description provided for @couldNotCreateYourQrCode.
  ///
  /// In en, this message translates to:
  /// **'Could not create your QR code. {error}'**
  String couldNotCreateYourQrCode(Object? error);

  /// No description provided for @couldNotForwardTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Could not forward. Try again.'**
  String get couldNotForwardTryAgain;

  /// No description provided for @couldNotGetItNow.
  ///
  /// In en, this message translates to:
  /// **'Could not get it now'**
  String get couldNotGetItNow;

  /// No description provided for @couldNotMakeANewCode.
  ///
  /// In en, this message translates to:
  /// **'Could not make a new code. Try again.'**
  String get couldNotMakeANewCode;

  /// No description provided for @couldNotOpenNotificationSettingsRight.
  ///
  /// In en, this message translates to:
  /// **'Could not open notification settings right now.'**
  String get couldNotOpenNotificationSettingsRight;

  /// No description provided for @couldNotOpenTheBatteryDialog.
  ///
  /// In en, this message translates to:
  /// **'Could not open the battery dialog right now — try again.'**
  String get couldNotOpenTheBatteryDialog;

  /// No description provided for @couldNotOpenTheCameraOr.
  ///
  /// In en, this message translates to:
  /// **'Could not open the camera or gallery.'**
  String get couldNotOpenTheCameraOr;

  /// No description provided for @couldNotOpenYourPhoneS.
  ///
  /// In en, this message translates to:
  /// **'Could not open your phone’s settings right now.'**
  String get couldNotOpenYourPhoneS;

  /// No description provided for @couldNotPrepareLogs.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare logs'**
  String get couldNotPrepareLogs;

  /// No description provided for @couldNotReachTheSenderTry.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the sender. Try again when nearby.'**
  String get couldNotReachTheSenderTry;

  /// No description provided for @couldNotReachTheServerTry.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Try again.'**
  String get couldNotReachTheServerTry;

  /// No description provided for @couldNotRefreshTheRequestThe.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh the request. The local network may be temporarily unavailable.'**
  String get couldNotRefreshTheRequestThe;

  /// No description provided for @couldNotRemove.
  ///
  /// In en, this message translates to:
  /// **'Could not remove {name}'**
  String couldNotRemove(Object? name);

  /// No description provided for @couldNotSave.
  ///
  /// In en, this message translates to:
  /// **'Could not save: {e}'**
  String couldNotSave(Object? e);

  /// No description provided for @couldNotSaveFreeSomeSpace.
  ///
  /// In en, this message translates to:
  /// **'Could not save. Free some space and try again.'**
  String get couldNotSaveFreeSomeSpace;

  /// No description provided for @couldNotSendTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Could not send. Try again'**
  String get couldNotSendTryAgain;

  /// No description provided for @couldNotShareLogs.
  ///
  /// In en, this message translates to:
  /// **'Could not share logs'**
  String get couldNotShareLogs;

  /// No description provided for @couldNotStartTryingAgainLater.
  ///
  /// In en, this message translates to:
  /// **'Could not start, trying again later'**
  String get couldNotStartTryingAgainLater;

  /// No description provided for @couldNotUnblock.
  ///
  /// In en, this message translates to:
  /// **'Could not unblock {label}'**
  String couldNotUnblock(Object? label);

  /// No description provided for @couldnTAskToJoinTry.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t ask to join. Try again.'**
  String get couldnTAskToJoinTry;

  /// No description provided for @couldnTBeAdded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t be added'**
  String get couldnTBeAdded;

  /// No description provided for @couldnTGetTheAddressBy.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get the address by itself'**
  String get couldnTGetTheAddressBy;

  /// No description provided for @couldnTLoadYourConversationsPlease.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your conversations. Please try again in a moment.'**
  String get couldnTLoadYourConversationsPlease;

  /// No description provided for @couldnTReachTheServerConversations.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the server. Conversations will appear when it\'s back.'**
  String get couldnTReachTheServerConversations;

  /// No description provided for @couldnTReachThemTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach them — try again'**
  String get couldnTReachThemTryAgain;

  /// No description provided for @couldnTReadTheLinkupApp.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the LinkUp app file'**
  String get couldnTReadTheLinkupApp;

  /// No description provided for @couldnTStartTheDownloadPage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the download page'**
  String get couldnTStartTheDownloadPage;

  /// No description provided for @couldnTSyncRightNowShowing.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sync right now — showing your saved conversations.'**
  String get couldnTSyncRightNowShowing;

  /// No description provided for @couldnTTurnOnWiFi.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t turn on Wi-Fi'**
  String get couldnTTurnOnWiFi;

  /// No description provided for @countUnknown.
  ///
  /// In en, this message translates to:
  /// **'count unknown'**
  String get countUnknown;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @createAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get createAnAccount;

  /// No description provided for @createBackup.
  ///
  /// In en, this message translates to:
  /// **'Create backup'**
  String get createBackup;

  /// No description provided for @createDatabaseBackup.
  ///
  /// In en, this message translates to:
  /// **'Create database backup'**
  String get createDatabaseBackup;

  /// No description provided for @createEncryptedKeyBackup.
  ///
  /// In en, this message translates to:
  /// **'Create encrypted key backup'**
  String get createEncryptedKeyBackup;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get createGroup;

  /// No description provided for @createUpdateEncryptedKeyBackup.
  ///
  /// In en, this message translates to:
  /// **'Create / update encrypted key backup'**
  String get createUpdateEncryptedKeyBackup;

  /// No description provided for @createYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get createYourAccount;

  /// No description provided for @createdBy.
  ///
  /// In en, this message translates to:
  /// **'Created by {creator}'**
  String createdBy(Object? creator);

  /// No description provided for @createdGroup.
  ///
  /// In en, this message translates to:
  /// **'{actor} created group \"{name}\"'**
  String createdGroup(Object? actor, Object? name);

  /// No description provided for @creatingYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Creating your account…'**
  String get creatingYourAccount;

  /// No description provided for @critical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get critical;

  /// No description provided for @criticalAlertIn24h.
  ///
  /// In en, this message translates to:
  /// **'{critical} critical alert{s} in 24h'**
  String criticalAlertIn24h(Object? critical, Object? s);

  /// No description provided for @crownShowsWhatTheyCanDo.
  ///
  /// In en, this message translates to:
  /// **'{role} crown. Shows what they can do'**
  String crownShowsWhatTheyCanDo(Object? role);

  /// No description provided for @currentIdentityKey.
  ///
  /// In en, this message translates to:
  /// **'Current identity key'**
  String get currentIdentityKey;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @darkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark theme'**
  String get darkTheme;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @dataBoundaries.
  ///
  /// In en, this message translates to:
  /// **'Data boundaries'**
  String get dataBoundaries;

  /// No description provided for @database.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get database;

  /// No description provided for @database2.
  ///
  /// In en, this message translates to:
  /// **'Database {num}'**
  String database2(Object? num);

  /// No description provided for @databaseBackup.
  ///
  /// In en, this message translates to:
  /// **'Database backup'**
  String get databaseBackup;

  /// No description provided for @dates.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get dates;

  /// No description provided for @days.
  ///
  /// In en, this message translates to:
  /// **'{d} days'**
  String days(Object? d);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days} days ago'**
  String daysAgo(Object? days);

  /// No description provided for @dec.
  ///
  /// In en, this message translates to:
  /// **'Dec'**
  String get dec;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @declined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get declined;

  /// No description provided for @defaultSameAsSAccount.
  ///
  /// In en, this message translates to:
  /// **'Default = same as {owner}’s account'**
  String defaultSameAsSAccount(Object? owner);

  /// No description provided for @defaultText.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultText;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @delete2.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{groupName}\"?'**
  String delete2(Object? groupName);

  /// No description provided for @delete3.
  ///
  /// In en, this message translates to:
  /// **'Delete {picked} {files} ({pickedBytes})'**
  String delete3(Object? picked, Object? files, Object? pickedBytes);

  /// No description provided for @delete4.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} {files}?'**
  String delete4(Object? count, Object? files);

  /// No description provided for @deleteChat.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get deleteChat;

  /// No description provided for @deleteChatCompletely.
  ///
  /// In en, this message translates to:
  /// **'Delete chat completely'**
  String get deleteChatCompletely;

  /// No description provided for @deleteChatWith.
  ///
  /// In en, this message translates to:
  /// **'Delete chat with {name}?'**
  String deleteChatWith(Object? name);

  /// No description provided for @deleteCompletely.
  ///
  /// In en, this message translates to:
  /// **'Delete completely'**
  String get deleteCompletely;

  /// No description provided for @deleteCompletely2.
  ///
  /// In en, this message translates to:
  /// **'Delete completely?'**
  String get deleteCompletely2;

  /// No description provided for @deleteFiles.
  ///
  /// In en, this message translates to:
  /// **'Delete files'**
  String get deleteFiles;

  /// No description provided for @deleteForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone'**
  String get deleteForEveryone;

  /// No description provided for @deleteForEveryoneRemovesItFrom.
  ///
  /// In en, this message translates to:
  /// **'\"Delete for everyone\" removes it from {who}{phone} too, even if {vIs} Offline now (it is removed when the phone gets the news). Only for your messages, up to 5 minutes old. A copy someone saved to the Gallery stays.'**
  String deleteForEveryoneRemovesItFrom(
      Object? who, Object? phone, Object? vIs);

  /// No description provided for @deleteForMe.
  ///
  /// In en, this message translates to:
  /// **'Delete for me'**
  String get deleteForMe;

  /// No description provided for @deleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroup;

  /// No description provided for @deleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete message?'**
  String get deleteMessage;

  /// No description provided for @deleteMessageCompletely.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} message{s} completely?'**
  String deleteMessageCompletely(Object? count, Object? s);

  /// No description provided for @deleteMessages.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} messages?'**
  String deleteMessages(Object? count);

  /// No description provided for @deleteMessagesCompletely.
  ///
  /// In en, this message translates to:
  /// **'Delete {sel} messages completely'**
  String deleteMessagesCompletely(Object? sel);

  /// No description provided for @deleteUnpublishedAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete unpublished account?'**
  String get deleteUnpublishedAccount;

  /// No description provided for @deleteVoiceNote.
  ///
  /// In en, this message translates to:
  /// **'Delete voice note'**
  String get deleteVoiceNote;

  /// No description provided for @deletedByUser.
  ///
  /// In en, this message translates to:
  /// **'Deleted by user'**
  String get deletedByUser;

  /// No description provided for @deletedByUser2.
  ///
  /// In en, this message translates to:
  /// **'Deleted by user · {t} {hm}'**
  String deletedByUser2(Object? t, Object? hm);

  /// No description provided for @deletedFromThisPhone.
  ///
  /// In en, this message translates to:
  /// **'deleted from this phone'**
  String get deletedFromThisPhone;

  /// No description provided for @deletedThisGroupSPhoto.
  ///
  /// In en, this message translates to:
  /// **'{actor} deleted this group\'s photo'**
  String deletedThisGroupSPhoto(Object? actor);

  /// No description provided for @delivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get delivered;

  /// No description provided for @deliveredTo.
  ///
  /// In en, this message translates to:
  /// **'Delivered to {delivered}'**
  String deliveredTo(Object? delivered);

  /// No description provided for @deliveredToOf.
  ///
  /// In en, this message translates to:
  /// **'Delivered to {delivered} of {total}'**
  String deliveredToOf(Object? delivered, Object? total);

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// No description provided for @developerAndCreatorOfLinkupBuilt.
  ///
  /// In en, this message translates to:
  /// **'Developer and creator of LinkUp. Built this app so you can chat and call, even without internet.'**
  String get developerAndCreatorOfLinkupBuilt;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @devicesSignedInToThisLinkup.
  ///
  /// In en, this message translates to:
  /// **'Devices signed in to this LinkUp account.'**
  String get devicesSignedInToThisLinkup;

  /// No description provided for @diagnosticCaptureMode.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic capture mode'**
  String get diagnosticCaptureMode;

  /// No description provided for @diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnostics;

  /// No description provided for @didNotWorkTryingAgainLater.
  ///
  /// In en, this message translates to:
  /// **'Did not work, trying again later'**
  String get didNotWorkTryingAgainLater;

  /// No description provided for @directLinks.
  ///
  /// In en, this message translates to:
  /// **'Direct links'**
  String get directLinks;

  /// No description provided for @directorySynchronization.
  ///
  /// In en, this message translates to:
  /// **'Directory synchronization'**
  String get directorySynchronization;

  /// No description provided for @directoryVisibility.
  ///
  /// In en, this message translates to:
  /// **'Directory visibility'**
  String get directoryVisibility;

  /// No description provided for @discoverableByName.
  ///
  /// In en, this message translates to:
  /// **'Discoverable by name'**
  String get discoverableByName;

  /// No description provided for @discoverableByPhone.
  ///
  /// In en, this message translates to:
  /// **'Discoverable by phone'**
  String get discoverableByPhone;

  /// No description provided for @diskFull.
  ///
  /// In en, this message translates to:
  /// **'Disk {disk}% full'**
  String diskFull(Object? disk);

  /// No description provided for @dismissAsAdmin.
  ///
  /// In en, this message translates to:
  /// **'Dismiss as admin'**
  String get dismissAsAdmin;

  /// No description provided for @dismissedAsGroupAdmin.
  ///
  /// In en, this message translates to:
  /// **'{actor} dismissed {targets} as group admin'**
  String dismissedAsGroupAdmin(Object? actor, Object? targets);

  /// No description provided for @dismissedYouAsGroupAdmin.
  ///
  /// In en, this message translates to:
  /// **'{actor} dismissed you as group admin'**
  String dismissedYouAsGroupAdmin(Object? actor);

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @docs.
  ///
  /// In en, this message translates to:
  /// **'Docs'**
  String get docs;

  /// No description provided for @document.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get document;

  /// No description provided for @documentReceived.
  ///
  /// In en, this message translates to:
  /// **'Document received'**
  String get documentReceived;

  /// No description provided for @documents.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documents;

  /// No description provided for @documentsReceived.
  ///
  /// In en, this message translates to:
  /// **'{n} documents received'**
  String documentsReceived(Object? n);

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done {done}'**
  String done(Object? done);

  /// No description provided for @done2.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done2;

  /// No description provided for @doneMb.
  ///
  /// In en, this message translates to:
  /// **'Done, {total} MB'**
  String doneMb(Object? total);

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @dragToMove.
  ///
  /// In en, this message translates to:
  /// **'Drag to move'**
  String get dragToMove;

  /// No description provided for @dragToScrollPinchToZoom.
  ///
  /// In en, this message translates to:
  /// **'Drag to scroll · pinch to zoom'**
  String get dragToScrollPinchToZoom;

  /// No description provided for @eachPhoneOnceByHowIt.
  ///
  /// In en, this message translates to:
  /// **'Each phone once, by how it is linked now'**
  String get eachPhoneOnceByHowIt;

  /// No description provided for @earlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get earlier;

  /// No description provided for @editGroup.
  ///
  /// In en, this message translates to:
  /// **'Edit group'**
  String get editGroup;

  /// No description provided for @editGroupInfo.
  ///
  /// In en, this message translates to:
  /// **'Edit group info'**
  String get editGroupInfo;

  /// No description provided for @effective.
  ///
  /// In en, this message translates to:
  /// **'Effective: {allowed}'**
  String effective(Object? allowed);

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @encryptedBackupOfYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup of your account'**
  String get encryptedBackupOfYourAccount;

  /// No description provided for @encryptedHistory.
  ///
  /// In en, this message translates to:
  /// **'Encrypted history'**
  String get encryptedHistory;

  /// No description provided for @encryptedIdentityBackupAvailable.
  ///
  /// In en, this message translates to:
  /// **'Encrypted identity backup available'**
  String get encryptedIdentityBackupAvailable;

  /// No description provided for @encryptedIdentityBackupSavedToThe.
  ///
  /// In en, this message translates to:
  /// **'Encrypted identity backup saved to the LinkUp server'**
  String get encryptedIdentityBackupSavedToThe;

  /// No description provided for @ended.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get ended;

  /// No description provided for @ending.
  ///
  /// In en, this message translates to:
  /// **'Ending…'**
  String get ending;

  /// No description provided for @endsInH.
  ///
  /// In en, this message translates to:
  /// **'ends in {left} h'**
  String endsInH(Object? left);

  /// No description provided for @endsInMin.
  ///
  /// In en, this message translates to:
  /// **'ends in {clamp} min'**
  String endsInMin(Object? clamp);

  /// No description provided for @enterThe12DigitCodeFrom.
  ///
  /// In en, this message translates to:
  /// **'Enter the 12-digit code from the admin.'**
  String get enterThe12DigitCodeFrom;

  /// No description provided for @enterTheCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get enterTheCode;

  /// No description provided for @enterTheOneTimeCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the one-time code'**
  String get enterTheOneTimeCode;

  /// No description provided for @enterThePasswordOf.
  ///
  /// In en, this message translates to:
  /// **'Enter the password of @{username}.'**
  String enterThePasswordOf(Object? username);

  /// No description provided for @enterTheRecoveryCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the recovery code.'**
  String get enterTheRecoveryCode;

  /// No description provided for @enterYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get enterYourPassword;

  /// No description provided for @enterYourRecoveryCodeLikeK7qm2.
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery code (like K7QM2-XPA9T-RC4WN-E8D3F).'**
  String get enterYourRecoveryCodeLikeK7qm2;

  /// No description provided for @enterYourUsername.
  ///
  /// In en, this message translates to:
  /// **'Enter your username.'**
  String get enterYourUsername;

  /// No description provided for @enterYourUsernameAndPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your username and password.'**
  String get enterYourUsernameAndPassword;

  /// No description provided for @enterYourUsernameToRequestAccount.
  ///
  /// In en, this message translates to:
  /// **'Enter your username to request account recovery.'**
  String get enterYourUsernameToRequestAccount;

  /// No description provided for @event.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get event;

  /// No description provided for @eventsInTheLast24Hours.
  ///
  /// In en, this message translates to:
  /// **'Events in the last 24 hours'**
  String get eventsInTheLast24Hours;

  /// No description provided for @everyPhoneAndWhoOwnsIt.
  ///
  /// In en, this message translates to:
  /// **'Every phone and who owns it'**
  String get everyPhoneAndWhoOwnsIt;

  /// No description provided for @everyone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get everyone;

  /// No description provided for @everyoneCanSend.
  ///
  /// In en, this message translates to:
  /// **'Everyone can send'**
  String get everyoneCanSend;

  /// No description provided for @everyoneInTheGroupSeesIt.
  ///
  /// In en, this message translates to:
  /// **'Everyone in the group sees it at the top of the chat. Only one message is pinned at a time; a new pin replaces the old one.'**
  String get everyoneInTheGroupSeesIt;

  /// No description provided for @everyoneNearbyIsAlreadyInYour.
  ///
  /// In en, this message translates to:
  /// **'Everyone nearby is already in your contacts'**
  String get everyoneNearbyIsAlreadyInYour;

  /// No description provided for @everyoneOnLinkupIsAlreadyIn.
  ///
  /// In en, this message translates to:
  /// **'Everyone on LinkUp is already in your contacts. To add someone new, search their name or use a QR code.'**
  String get everyoneOnLinkupIsAlreadyIn;

  /// No description provided for @everyonePicks.
  ///
  /// In en, this message translates to:
  /// **'Everyone picks '**
  String get everyonePicks;

  /// No description provided for @excellent.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get excellent;

  /// No description provided for @exit.
  ///
  /// In en, this message translates to:
  /// **'Exit \"{groupName}\"?'**
  String exit(Object? groupName);

  /// No description provided for @exitFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Exit full screen'**
  String get exitFullScreen;

  /// No description provided for @exitGroup.
  ///
  /// In en, this message translates to:
  /// **'Exit group'**
  String get exitGroup;

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @expiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in {remainingLabel}'**
  String expiresIn(Object? remainingLabel);

  /// No description provided for @expiresIn24Hours.
  ///
  /// In en, this message translates to:
  /// **'Expires in 24 hours'**
  String get expiresIn24Hours;

  /// No description provided for @expiresIn24Hours2.
  ///
  /// In en, this message translates to:
  /// **'Expires in 24 hours.'**
  String get expiresIn24Hours2;

  /// No description provided for @extraNearbySafety.
  ///
  /// In en, this message translates to:
  /// **'Extra nearby safety'**
  String get extraNearbySafety;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @failedLoginIn24h.
  ///
  /// In en, this message translates to:
  /// **'{failedLogins} failed login{s} in 24h'**
  String failedLoginIn24h(Object? failedLogins, Object? s);

  /// No description provided for @failedLogins24h.
  ///
  /// In en, this message translates to:
  /// **'Failed logins 24h'**
  String get failedLogins24h;

  /// No description provided for @fair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get fair;

  /// No description provided for @feb.
  ///
  /// In en, this message translates to:
  /// **'Feb'**
  String get feb;

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @fileContents.
  ///
  /// In en, this message translates to:
  /// **'File contents'**
  String get fileContents;

  /// No description provided for @fileInfo.
  ///
  /// In en, this message translates to:
  /// **'File info'**
  String get fileInfo;

  /// No description provided for @filePartsPassedOn.
  ///
  /// In en, this message translates to:
  /// **'File parts passed on'**
  String get filePartsPassedOn;

  /// No description provided for @fileRemovedAfter60DaysThumbnail.
  ///
  /// In en, this message translates to:
  /// **'File removed after 60 days · thumbnail only'**
  String get fileRemovedAfter60DaysThumbnail;

  /// No description provided for @fileTooBig.
  ///
  /// In en, this message translates to:
  /// **'File too big'**
  String get fileTooBig;

  /// No description provided for @fileTransfers.
  ///
  /// In en, this message translates to:
  /// **'File transfers'**
  String get fileTransfers;

  /// No description provided for @fileTransfers2.
  ///
  /// In en, this message translates to:
  /// **'File Transfers'**
  String get fileTransfers2;

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get files;

  /// No description provided for @filesPeopleSendShowHereWith.
  ///
  /// In en, this message translates to:
  /// **'Files people send show here with kind and size.'**
  String get filesPeopleSendShowHereWith;

  /// No description provided for @filesReceived.
  ///
  /// In en, this message translates to:
  /// **'{n} files received'**
  String filesReceived(Object? n);

  /// No description provided for @filesSentAndSpaceUsed.
  ///
  /// In en, this message translates to:
  /// **'Files sent and space used'**
  String get filesSentAndSpaceUsed;

  /// No description provided for @filesTooBig.
  ///
  /// In en, this message translates to:
  /// **'{count} files too big'**
  String filesTooBig(Object? count);

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @findANearbyPersonOrCreate.
  ///
  /// In en, this message translates to:
  /// **'Find a nearby person or create a group to start chatting.'**
  String get findANearbyPersonOrCreate;

  /// No description provided for @findAPerson.
  ///
  /// In en, this message translates to:
  /// **'Find a person'**
  String get findAPerson;

  /// No description provided for @findNearbyFriendsWhenClosed.
  ///
  /// In en, this message translates to:
  /// **'Find nearby friends when closed'**
  String get findNearbyFriendsWhenClosed;

  /// No description provided for @findNearbyFriendsWhenClosedTurn.
  ///
  /// In en, this message translates to:
  /// **'Find nearby friends when closed - Turn on'**
  String get findNearbyFriendsWhenClosedTurn;

  /// No description provided for @findPeopleNearby.
  ///
  /// In en, this message translates to:
  /// **'Find people nearby'**
  String get findPeopleNearby;

  /// No description provided for @findPeopleToAdd.
  ///
  /// In en, this message translates to:
  /// **'Find people to add'**
  String get findPeopleToAdd;

  /// No description provided for @findPhonesNearYou.
  ///
  /// In en, this message translates to:
  /// **'Find phones near you'**
  String get findPhonesNearYou;

  /// No description provided for @findServerNow.
  ///
  /// In en, this message translates to:
  /// **'Find server now'**
  String get findServerNow;

  /// No description provided for @findingTheMatchingLinkupServer.
  ///
  /// In en, this message translates to:
  /// **'Finding the matching LinkUp server…'**
  String get findingTheMatchingLinkupServer;

  /// No description provided for @firstOrLetThemScanThe.
  ///
  /// In en, this message translates to:
  /// **' first, or let them scan the group QR later.'**
  String get firstOrLetThemScanThe;

  /// No description provided for @firstPerson.
  ///
  /// In en, this message translates to:
  /// **'First person'**
  String get firstPerson;

  /// No description provided for @flashlight.
  ///
  /// In en, this message translates to:
  /// **'Flashlight'**
  String get flashlight;

  /// No description provided for @followAppTheme.
  ///
  /// In en, this message translates to:
  /// **'Follow app theme'**
  String get followAppTheme;

  /// No description provided for @followTheAccountOrPhoneSetting.
  ///
  /// In en, this message translates to:
  /// **'Follow the account or phone setting'**
  String get followTheAccountOrPhoneSetting;

  /// No description provided for @followThePhoneSLightOr.
  ///
  /// In en, this message translates to:
  /// **'Follow the phone’s light or dark mode.'**
  String get followThePhoneSLightOr;

  /// No description provided for @forEveryPhoneOfThisAccount.
  ///
  /// In en, this message translates to:
  /// **'For every phone of this account'**
  String get forEveryPhoneOfThisAccount;

  /// No description provided for @forEveryoneOnAllLinkupPhones.
  ///
  /// In en, this message translates to:
  /// **'For everyone, on all LinkUp phones'**
  String get forEveryoneOnAllLinkupPhones;

  /// No description provided for @forcedOff.
  ///
  /// In en, this message translates to:
  /// **'Forced OFF'**
  String get forcedOff;

  /// No description provided for @forcedOn.
  ///
  /// In en, this message translates to:
  /// **'Forced ON'**
  String get forcedOn;

  /// No description provided for @forgotItUseTheRecoveryCode.
  ///
  /// In en, this message translates to:
  /// **'Forgot it? Use the recovery code.'**
  String get forgotItUseTheRecoveryCode;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password'**
  String get forgotPassword;

  /// No description provided for @forgotPassword2.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword2;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @forwardTo.
  ///
  /// In en, this message translates to:
  /// **'Forward to'**
  String get forwardTo;

  /// No description provided for @forwarded.
  ///
  /// In en, this message translates to:
  /// **'Forwarded'**
  String get forwarded;

  /// No description provided for @foundSomeone.
  ///
  /// In en, this message translates to:
  /// **'Found someone!'**
  String get foundSomeone;

  /// No description provided for @freeUpSpaceAutomatically.
  ///
  /// In en, this message translates to:
  /// **'Free up space automatically'**
  String get freeUpSpaceAutomatically;

  /// No description provided for @freeUpSpaceAutomaticallyIsOff.
  ///
  /// In en, this message translates to:
  /// **'Free up space automatically is OFF. Nothing removed.'**
  String get freeUpSpaceAutomaticallyIsOff;

  /// No description provided for @fri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get fri;

  /// No description provided for @friendsOfFriendsScanToJoin.
  ///
  /// In en, this message translates to:
  /// **'Friends of friends scan to join'**
  String get friendsOfFriendsScanToJoin;

  /// No description provided for @friendsWithoutWiFiCanReach.
  ///
  /// In en, this message translates to:
  /// **'Friends without Wi-Fi can reach you'**
  String get friendsWithoutWiFiCanReach;

  /// No description provided for @fromEveryPhoneAlsoDeletedCopies.
  ///
  /// In en, this message translates to:
  /// **'From every phone, also deleted copies'**
  String get fromEveryPhoneAlsoDeletedCopies;

  /// No description provided for @fromEveryPhoneOfThisChat.
  ///
  /// In en, this message translates to:
  /// **'From every phone of this chat, also copies users deleted. This cannot be undone.'**
  String get fromEveryPhoneOfThisChat;

  /// No description provided for @fromPhoto.
  ///
  /// In en, this message translates to:
  /// **'From photo'**
  String get fromPhoto;

  /// No description provided for @fromSPhone.
  ///
  /// In en, this message translates to:
  /// **'{range} · from {from}\'s phone'**
  String fromSPhone(Object? range, Object? from);

  /// No description provided for @fullChat.
  ///
  /// In en, this message translates to:
  /// **'Full chat'**
  String get fullChat;

  /// No description provided for @fullMap.
  ///
  /// In en, this message translates to:
  /// **'Full map'**
  String get fullMap;

  /// No description provided for @fullScreen.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get fullScreen;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @gaveANewRecoveryCodeTo.
  ///
  /// In en, this message translates to:
  /// **'{admin} gave a new recovery code to {target}'**
  String gaveANewRecoveryCodeTo(Object? admin, Object? target);

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @generateANewQr.
  ///
  /// In en, this message translates to:
  /// **'Generate a new QR'**
  String get generateANewQr;

  /// No description provided for @getAOneTimeCode.
  ///
  /// In en, this message translates to:
  /// **'Get a one-time code'**
  String get getAOneTimeCode;

  /// No description provided for @getChat.
  ///
  /// In en, this message translates to:
  /// **'Get chat'**
  String get getChat;

  /// No description provided for @getFile.
  ///
  /// In en, this message translates to:
  /// **'Get file'**
  String get getFile;

  /// No description provided for @getFullPhoto.
  ///
  /// In en, this message translates to:
  /// **'Get full photo'**
  String get getFullPhoto;

  /// No description provided for @getFullVideo.
  ///
  /// In en, this message translates to:
  /// **'Get full video'**
  String get getFullVideo;

  /// No description provided for @getMessagesAndCallsWhenClosed.
  ///
  /// In en, this message translates to:
  /// **'Get messages and calls when closed'**
  String get getMessagesAndCallsWhenClosed;

  /// No description provided for @getsItWhenNearbyOrOnline.
  ///
  /// In en, this message translates to:
  /// **'gets it when Nearby or Online'**
  String get getsItWhenNearbyOrOnline;

  /// No description provided for @getsTheGroupWhenNearbyOr.
  ///
  /// In en, this message translates to:
  /// **'Gets the group when Nearby or Online'**
  String get getsTheGroupWhenNearbyOr;

  /// No description provided for @gettingIt.
  ///
  /// In en, this message translates to:
  /// **'Getting it…'**
  String get gettingIt;

  /// No description provided for @gettingItFromAnotherPhone.
  ///
  /// In en, this message translates to:
  /// **'Getting it from another phone'**
  String get gettingItFromAnotherPhone;

  /// No description provided for @gettingItFromTheServer.
  ///
  /// In en, this message translates to:
  /// **'Getting it from the server…'**
  String get gettingItFromTheServer;

  /// No description provided for @gettingTheDownloadAddress.
  ///
  /// In en, this message translates to:
  /// **'Getting the download address...'**
  String get gettingTheDownloadAddress;

  /// No description provided for @giveTheAppToANearby.
  ///
  /// In en, this message translates to:
  /// **'Give the app to a nearby phone · no internet'**
  String get giveTheAppToANearby;

  /// No description provided for @giveThemLinkupNoInternet.
  ///
  /// In en, this message translates to:
  /// **'Give them LinkUp · no internet'**
  String get giveThemLinkupNoInternet;

  /// No description provided for @goToPeople.
  ///
  /// In en, this message translates to:
  /// **'Go to People'**
  String get goToPeople;

  /// No description provided for @goesOutRightAway.
  ///
  /// In en, this message translates to:
  /// **'Goes out right away'**
  String get goesOutRightAway;

  /// No description provided for @goneFromEveryPhoneAndThe.
  ///
  /// In en, this message translates to:
  /// **'Gone from every phone and the server, also copies users deleted. Users see nothing.'**
  String get goneFromEveryPhoneAndThe;

  /// No description provided for @good.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get good;

  /// No description provided for @group.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get group;

  /// No description provided for @group2.
  ///
  /// In en, this message translates to:
  /// **'Group · {count} {members}'**
  String group2(Object? count, Object? members);

  /// No description provided for @groupChat.
  ///
  /// In en, this message translates to:
  /// **'Group chat'**
  String get groupChat;

  /// No description provided for @groupConversation.
  ///
  /// In en, this message translates to:
  /// **'Group conversation'**
  String get groupConversation;

  /// No description provided for @groupDetails.
  ///
  /// In en, this message translates to:
  /// **'Group details'**
  String get groupDetails;

  /// No description provided for @groupInfo.
  ///
  /// In en, this message translates to:
  /// **'Group info'**
  String get groupInfo;

  /// No description provided for @groupInvite.
  ///
  /// In en, this message translates to:
  /// **'Group invite'**
  String get groupInvite;

  /// No description provided for @groupInvite2.
  ///
  /// In en, this message translates to:
  /// **'Group invite · {members} {members2}'**
  String groupInvite2(Object? members, Object? members2);

  /// No description provided for @groupMember.
  ///
  /// In en, this message translates to:
  /// **'Group member'**
  String get groupMember;

  /// No description provided for @groupMembers.
  ///
  /// In en, this message translates to:
  /// **'Group · {members} members'**
  String groupMembers(Object? members);

  /// No description provided for @groupMembersFromSCode.
  ///
  /// In en, this message translates to:
  /// **'Group · {count} members · from {from}\'s code'**
  String groupMembersFromSCode(Object? count, Object? from);

  /// No description provided for @groupMessages.
  ///
  /// In en, this message translates to:
  /// **'Group messages'**
  String get groupMessages;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @groupPhoto.
  ///
  /// In en, this message translates to:
  /// **'Group photo'**
  String get groupPhoto;

  /// No description provided for @groupSettings.
  ///
  /// In en, this message translates to:
  /// **'Group settings'**
  String get groupSettings;

  /// No description provided for @groupsAreMadeFromYourFriends.
  ///
  /// In en, this message translates to:
  /// **'Groups are made from your friends. Add friends in '**
  String get groupsAreMadeFromYourFriends;

  /// No description provided for @halfCanBeReadNowThe.
  ///
  /// In en, this message translates to:
  /// **'Half can be read now · the rest is on the way'**
  String get halfCanBeReadNowThe;

  /// No description provided for @hasAnOldLinkup.
  ///
  /// In en, this message translates to:
  /// **'{name} has an old LinkUp'**
  String hasAnOldLinkup(Object? name);

  /// No description provided for @haveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Have an account?'**
  String get haveAnAccount;

  /// No description provided for @healthy.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get healthy;

  /// No description provided for @helpsRunLinkup.
  ///
  /// In en, this message translates to:
  /// **'Helps run LinkUp.'**
  String get helpsRunLinkup;

  /// No description provided for @hidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get hidden;

  /// No description provided for @hideForToday.
  ///
  /// In en, this message translates to:
  /// **'Hide for today'**
  String get hideForToday;

  /// No description provided for @hideMap.
  ///
  /// In en, this message translates to:
  /// **'Hide map'**
  String get hideMap;

  /// No description provided for @hideMessageTextOnTheLock.
  ///
  /// In en, this message translates to:
  /// **'Hide message text on the lock screen'**
  String get hideMessageTextOnTheLock;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @hideSensitiveContent.
  ///
  /// In en, this message translates to:
  /// **'Hide sensitive content'**
  String get hideSensitiveContent;

  /// No description provided for @hideText.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hideText;

  /// No description provided for @historicalIdentityKeys.
  ///
  /// In en, this message translates to:
  /// **'Historical identity keys'**
  String get historicalIdentityKeys;

  /// No description provided for @holdToRecordReleaseToSend.
  ///
  /// In en, this message translates to:
  /// **'Hold to record, release to send'**
  String get holdToRecordReleaseToSend;

  /// No description provided for @holdToRecordVoiceNote.
  ///
  /// In en, this message translates to:
  /// **'Hold to record voice note'**
  String get holdToRecordVoiceNote;

  /// No description provided for @host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @hotspot.
  ///
  /// In en, this message translates to:
  /// **'Hotspot'**
  String get hotspot;

  /// No description provided for @hours.
  ///
  /// In en, this message translates to:
  /// **'{d} hours'**
  String hours(Object? d);

  /// No description provided for @howOftenAdminPagesUpdate.
  ///
  /// In en, this message translates to:
  /// **'How often admin pages update'**
  String get howOftenAdminPagesUpdate;

  /// No description provided for @howOtherPeopleSeeYou.
  ///
  /// In en, this message translates to:
  /// **'How other people see you'**
  String get howOtherPeopleSeeYou;

  /// No description provided for @howPhonesAreLinked.
  ///
  /// In en, this message translates to:
  /// **'How phones are linked'**
  String get howPhonesAreLinked;

  /// No description provided for @iAlreadyHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get iAlreadyHaveAnAccount;

  /// No description provided for @iDonTHaveIt.
  ///
  /// In en, this message translates to:
  /// **'I don\'t have it'**
  String get iDonTHaveIt;

  /// No description provided for @iSavedIt.
  ///
  /// In en, this message translates to:
  /// **'I saved it'**
  String get iSavedIt;

  /// No description provided for @identity.
  ///
  /// In en, this message translates to:
  /// **'{platform} • {status}\n{lastSeenAt}\nIdentity: {unverified}{identityFingerprint}'**
  String identity(Object? platform, Object? status, Object? lastSeenAt,
      Object? unverified, Object? identityFingerprint);

  /// No description provided for @identityChanged.
  ///
  /// In en, this message translates to:
  /// **'Identity changed'**
  String get identityChanged;

  /// No description provided for @identityChangedOrRevokedVerifyThis.
  ///
  /// In en, this message translates to:
  /// **'Identity changed or revoked — verify this user again'**
  String get identityChangedOrRevokedVerifyThis;

  /// No description provided for @identityKeyHistory.
  ///
  /// In en, this message translates to:
  /// **'Identity key history'**
  String get identityKeyHistory;

  /// No description provided for @identityKeyRotatedToVersion.
  ///
  /// In en, this message translates to:
  /// **'Identity key rotated to version {currentVersion}.'**
  String identityKeyRotatedToVersion(Object? currentVersion);

  /// No description provided for @identityKeysAreManagedLocallyAnd.
  ///
  /// In en, this message translates to:
  /// **'Identity keys are managed locally and are not shown in your public profile.'**
  String get identityKeysAreManagedLocallyAnd;

  /// No description provided for @identitySigning.
  ///
  /// In en, this message translates to:
  /// **'Identity & signing'**
  String get identitySigning;

  /// No description provided for @ifOffYouCanTSee.
  ///
  /// In en, this message translates to:
  /// **'If off, you can\'t see when others read your messages, and they can\'t see when you read theirs.'**
  String get ifOffYouCanTSee;

  /// No description provided for @ifTheNewPhoneSaysThis.
  ///
  /// In en, this message translates to:
  /// **'If the new phone says \"This Wi-Fi has no internet. Stay connected?\" tap Yes / Stay.'**
  String get ifTheNewPhoneSaysThis;

  /// No description provided for @ifYouLoseThisPhoneIt.
  ///
  /// In en, this message translates to:
  /// **'If you lose this phone, it is the only way back into @{user}.'**
  String ifYouLoseThisPhoneIt(Object? user);

  /// No description provided for @ifYouUnblockCanMessageAnd.
  ///
  /// In en, this message translates to:
  /// **'If you unblock, {label} can message and call you again.'**
  String ifYouUnblockCanMessageAnd(Object? label);

  /// No description provided for @ignore.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get ignore;

  /// No description provided for @ignoreBatteryOptimization.
  ///
  /// In en, this message translates to:
  /// **'Ignore battery optimization'**
  String get ignoreBatteryOptimization;

  /// No description provided for @imageReceived.
  ///
  /// In en, this message translates to:
  /// **'Image received'**
  String get imageReceived;

  /// No description provided for @imagesReceived.
  ///
  /// In en, this message translates to:
  /// **'{n} images received'**
  String imagesReceived(Object? n);

  /// No description provided for @inBothChatsTheMessageBox.
  ///
  /// In en, this message translates to:
  /// **'In both chats the message box is replaced by a short text, so **{name} can see** they can\'t message you.'**
  String inBothChatsTheMessageBox(Object? name);

  /// No description provided for @inLinkup.
  ///
  /// In en, this message translates to:
  /// **'In LinkUp: {token}'**
  String inLinkup(Object? token);

  /// No description provided for @inYourContacts.
  ///
  /// In en, this message translates to:
  /// **'In your contacts'**
  String get inYourContacts;

  /// No description provided for @includesTheGroupQrCode.
  ///
  /// In en, this message translates to:
  /// **'Includes the group QR code'**
  String get includesTheGroupQrCode;

  /// No description provided for @incoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get incoming;

  /// No description provided for @incomingCall.
  ///
  /// In en, this message translates to:
  /// **'Incoming call'**
  String get incomingCall;

  /// No description provided for @info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get info;

  /// No description provided for @inheritPlatformState.
  ///
  /// In en, this message translates to:
  /// **'Inherit / platform state'**
  String get inheritPlatformState;

  /// No description provided for @install.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// No description provided for @internet.
  ///
  /// In en, this message translates to:
  /// **'Internet'**
  String get internet;

  /// No description provided for @internetServerOnly.
  ///
  /// In en, this message translates to:
  /// **'Internet / server only'**
  String get internetServerOnly;

  /// No description provided for @inviteAFriendNearby.
  ///
  /// In en, this message translates to:
  /// **'Invite a friend nearby'**
  String get inviteAFriendNearby;

  /// No description provided for @inviteLinkFrom.
  ///
  /// In en, this message translates to:
  /// **'invite link from {invitedBy}'**
  String inviteLinkFrom(Object? invitedBy);

  /// No description provided for @inviteWithLink.
  ///
  /// In en, this message translates to:
  /// **'Invite with link'**
  String get inviteWithLink;

  /// No description provided for @inviteWithQr.
  ///
  /// In en, this message translates to:
  /// **'Invite with QR'**
  String get inviteWithQr;

  /// No description provided for @isBlocked.
  ///
  /// In en, this message translates to:
  /// **'{label} is blocked'**
  String isBlocked(Object? label);

  /// No description provided for @isBlockedByAdmin.
  ///
  /// In en, this message translates to:
  /// **'{name} is blocked by admin'**
  String isBlockedByAdmin(Object? name);

  /// No description provided for @isBlockedForEveryone.
  ///
  /// In en, this message translates to:
  /// **'{target} is blocked for everyone.'**
  String isBlockedForEveryone(Object? target);

  /// No description provided for @isInYourFriends.
  ///
  /// In en, this message translates to:
  /// **'{name} is in your friends.'**
  String isInYourFriends(Object? name);

  /// No description provided for @isNotInYourFriends.
  ///
  /// In en, this message translates to:
  /// **'{name} is not in your friends.'**
  String isNotInYourFriends(Object? name);

  /// No description provided for @isNotInYourFriendsMember.
  ///
  /// In en, this message translates to:
  /// **'{name} is not in your friends. {via} (member) is his friend.'**
  String isNotInYourFriendsMember(Object? name, Object? via);

  /// No description provided for @isNotInYourFriendsMembers.
  ///
  /// In en, this message translates to:
  /// **'{name} is not in your friends. {list} (members) are his friends.'**
  String isNotInYourFriendsMembers(Object? name, Object? list);

  /// No description provided for @isNotOnTheServerYet.
  ///
  /// In en, this message translates to:
  /// **'{notOnServerName} is not on the server yet. It goes when {notOnServerName2} is nearby or joins the server.'**
  String isNotOnTheServerYet(Object? notOnServerName, Object? notOnServerName2);

  /// No description provided for @isNowTheGroupOwner.
  ///
  /// In en, this message translates to:
  /// **'{owner} is now the group owner'**
  String isNowTheGroupOwner(Object? owner);

  /// No description provided for @isRemovedFromYourContacts.
  ///
  /// In en, this message translates to:
  /// **'{name} is **removed from your contacts**.'**
  String isRemovedFromYourContacts(Object? name);

  /// No description provided for @isRequiredFillItInBefore.
  ///
  /// In en, this message translates to:
  /// **'{missing} is required — fill it in before saving.'**
  String isRequiredFillItInBefore(Object? missing);

  /// No description provided for @isSignedOutOn.
  ///
  /// In en, this message translates to:
  /// **'{name} is signed out on {phone}.'**
  String isSignedOutOn(Object? name, Object? phone);

  /// No description provided for @isTheServerHealthy.
  ///
  /// In en, this message translates to:
  /// **'Is the server healthy'**
  String get isTheServerHealthy;

  /// No description provided for @isTyping.
  ///
  /// In en, this message translates to:
  /// **'{clean} is typing…'**
  String isTyping(Object? clean);

  /// No description provided for @isUnblockedForEveryone.
  ///
  /// In en, this message translates to:
  /// **'{target} is unblocked for everyone.'**
  String isUnblockedForEveryone(Object? target);

  /// No description provided for @isVerified.
  ///
  /// In en, this message translates to:
  /// **'{v} is verified'**
  String isVerified(Object? v);

  /// No description provided for @itGoesToEveryPhoneNearby.
  ///
  /// In en, this message translates to:
  /// **'It goes to every phone nearby, and to the server when online.'**
  String get itGoesToEveryPhoneNearby;

  /// No description provided for @itGoesToHerPhoneBy.
  ///
  /// In en, this message translates to:
  /// **'It goes to her phone by card, over any link. Pending until it is done.'**
  String get itGoesToHerPhoneBy;

  /// No description provided for @itIsRemovedOnlyFromYour.
  ///
  /// In en, this message translates to:
  /// **'It is removed only from your phone. The group still has it.'**
  String get itIsRemovedOnlyFromYour;

  /// No description provided for @itIsRemovedOnlyFromYour2.
  ///
  /// In en, this message translates to:
  /// **'It is removed only from your phone. {peerName} still has it.'**
  String itIsRemovedOnlyFromYour2(Object? peerName);

  /// No description provided for @itIsSignedOutAndMust.
  ///
  /// In en, this message translates to:
  /// **'It is signed out and must sign in again.'**
  String get itIsSignedOutAndMust;

  /// No description provided for @itMustSignInAgain.
  ///
  /// In en, this message translates to:
  /// **'It must sign in again.'**
  String get itMustSignInAgain;

  /// No description provided for @itSyncsWhenTheServerAnswers.
  ///
  /// In en, this message translates to:
  /// **'It syncs when the server answers. Your local key above is fine.'**
  String get itSyncsWhenTheServerAnswers;

  /// No description provided for @itWasInstalledInPartsFor.
  ///
  /// In en, this message translates to:
  /// **'It was installed in parts (for example from a store). Ask a friend who installed the LinkUp file to share it.'**
  String get itWasInstalledInPartsFor;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'{files} items'**
  String items(Object? files);

  /// No description provided for @jan.
  ///
  /// In en, this message translates to:
  /// **'Jan'**
  String get jan;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// No description provided for @joinFullNearbyGroupsAsA.
  ///
  /// In en, this message translates to:
  /// **'Join full nearby groups as a Wi-Fi user and join a LinkUp hotspot. {linkStatusText}'**
  String joinFullNearbyGroupsAsA(Object? linkStatusText);

  /// No description provided for @joinGroup.
  ///
  /// In en, this message translates to:
  /// **'Join group'**
  String get joinGroup;

  /// No description provided for @joinGroupWithQr.
  ///
  /// In en, this message translates to:
  /// **'Join group with QR'**
  String get joinGroupWithQr;

  /// No description provided for @joinMyGroup.
  ///
  /// In en, this message translates to:
  /// **'JOIN MY GROUP'**
  String get joinMyGroup;

  /// No description provided for @joinMyLinkupGroup.
  ///
  /// In en, this message translates to:
  /// **'Join my LinkUp group \"{groupName}\":'**
  String joinMyLinkupGroup(Object? groupName);

  /// No description provided for @joinWiFi.
  ///
  /// In en, this message translates to:
  /// **'Join Wi-Fi'**
  String get joinWiFi;

  /// No description provided for @joinedALinkupHotspot.
  ///
  /// In en, this message translates to:
  /// **'Joined a LinkUp hotspot'**
  String get joinedALinkupHotspot;

  /// No description provided for @joinedFromOffline.
  ///
  /// In en, this message translates to:
  /// **'Joined from offline · {joined_offline_at}'**
  String joinedFromOffline(Object? joined_offline_at);

  /// No description provided for @joinedFromOffline2.
  ///
  /// In en, this message translates to:
  /// **'{u} · Joined from offline'**
  String joinedFromOffline2(Object? u);

  /// No description provided for @joinedUsingThisGroupSInvite.
  ///
  /// In en, this message translates to:
  /// **'{actor} joined using this group\'s invite link'**
  String joinedUsingThisGroupSInvite(Object? actor);

  /// No description provided for @joining.
  ///
  /// In en, this message translates to:
  /// **'Joining…'**
  String get joining;

  /// No description provided for @joiningALinkupHotspot.
  ///
  /// In en, this message translates to:
  /// **'Joining a LinkUp hotspot…'**
  String get joiningALinkupHotspot;

  /// No description provided for @joiningAnotherGroup.
  ///
  /// In en, this message translates to:
  /// **'Joining another group…'**
  String get joiningAnotherGroup;

  /// No description provided for @jul.
  ///
  /// In en, this message translates to:
  /// **'Jul'**
  String get jul;

  /// No description provided for @jumpToLatest.
  ///
  /// In en, this message translates to:
  /// **'Jump to latest'**
  String get jumpToLatest;

  /// No description provided for @jun.
  ///
  /// In en, this message translates to:
  /// **'Jun'**
  String get jun;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @k7qm2Xpa9tRc4wnE8d3f.
  ///
  /// In en, this message translates to:
  /// **'K7QM2-XPA9T-RC4WN-E8D3F'**
  String get k7qm2Xpa9tRc4wnE8d3f;

  /// No description provided for @keepItPrivateItLetsYou.
  ///
  /// In en, this message translates to:
  /// **'Keep it private. It lets you set a new password.'**
  String get keepItPrivateItLetsYou;

  /// No description provided for @keepKeepRunningInBackgroundOn.
  ///
  /// In en, this message translates to:
  /// **'Keep \"Keep running in background\" on (above)'**
  String get keepKeepRunningInBackgroundOn;

  /// No description provided for @keepLinkupRunning.
  ///
  /// In en, this message translates to:
  /// **'Keep LinkUp running'**
  String get keepLinkupRunning;

  /// No description provided for @keepRunningInBackground.
  ///
  /// In en, this message translates to:
  /// **'Keep running in background'**
  String get keepRunningInBackground;

  /// No description provided for @keepTheNewPhoneConnectedTo.
  ///
  /// In en, this message translates to:
  /// **'Keep the new phone connected to the private LinkUp network while waiting for approval.'**
  String get keepTheNewPhoneConnectedTo;

  /// No description provided for @keepThisPrivate.
  ///
  /// In en, this message translates to:
  /// **'Keep this private'**
  String get keepThisPrivate;

  /// No description provided for @keepWiFiOnOnBoth.
  ///
  /// In en, this message translates to:
  /// **'Keep Wi-Fi on, on both phones'**
  String get keepWiFiOnOnBoth;

  /// No description provided for @keepsLinkupSafeCanHelpYou.
  ///
  /// In en, this message translates to:
  /// **'Keeps LinkUp safe. Can help you get back in if you forget your password.'**
  String get keepsLinkupSafeCanHelpYou;

  /// No description provided for @keyRotationChangesTheDevicePublic.
  ///
  /// In en, this message translates to:
  /// **'Key rotation changes the device public identity used for future encrypted traffic. Previous private key versions stay only on this device and are never uploaded to the server. A new phone therefore needs a future encrypted key-migration/backup mechanism to recover historical ciphertext created for an older device identity.'**
  String get keyRotationChangesTheDevicePublic;

  /// No description provided for @lanAvailable.
  ///
  /// In en, this message translates to:
  /// **'LAN available'**
  String get lanAvailable;

  /// No description provided for @lanServerConnected.
  ///
  /// In en, this message translates to:
  /// **'LAN / Server connected'**
  String get lanServerConnected;

  /// No description provided for @last.
  ///
  /// In en, this message translates to:
  /// **'Last: {whenSub216}{bytes}'**
  String last(Object? whenSub216, Object? bytes);

  /// No description provided for @last1Hour.
  ///
  /// In en, this message translates to:
  /// **'Last 1 hour'**
  String get last1Hour;

  /// No description provided for @last30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get last30Days;

  /// No description provided for @last7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get last7Days;

  /// No description provided for @lastCleanUp.
  ///
  /// In en, this message translates to:
  /// **'Last clean-up: {dayText}, {time} · {what}'**
  String lastCleanUp(Object? dayText, Object? time, Object? what);

  /// No description provided for @lastPolicyUpdate.
  ///
  /// In en, this message translates to:
  /// **'Last policy update: {updated_at}'**
  String lastPolicyUpdate(Object? updated_at);

  /// No description provided for @lastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen'**
  String get lastSeen;

  /// No description provided for @lastSeen2.
  ///
  /// In en, this message translates to:
  /// **'Last seen {value}'**
  String lastSeen2(Object? value);

  /// No description provided for @lastUpdate.
  ///
  /// In en, this message translates to:
  /// **'Last update'**
  String get lastUpdate;

  /// No description provided for @lastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated {hour}:{padLeft}'**
  String lastUpdated(Object? hour, Object? padLeft);

  /// No description provided for @lastWeek.
  ///
  /// In en, this message translates to:
  /// **'last week'**
  String get lastWeek;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @left.
  ///
  /// In en, this message translates to:
  /// **'{actor} left'**
  String left(Object? actor);

  /// No description provided for @letAFriendScanYou.
  ///
  /// In en, this message translates to:
  /// **'Let a friend scan you'**
  String get letAFriendScanYou;

  /// No description provided for @levelTapYourPhotoInSettings.
  ///
  /// In en, this message translates to:
  /// **'Level: {role} · Tap your photo in Settings to switch.'**
  String levelTapYourPhotoInSettings(Object? role);

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @lightTheme.
  ///
  /// In en, this message translates to:
  /// **'Light theme'**
  String get lightTheme;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get linkCopied;

  /// No description provided for @linkFullGroups.
  ///
  /// In en, this message translates to:
  /// **'Link full groups'**
  String get linkFullGroups;

  /// No description provided for @linkFullGroups2.
  ///
  /// In en, this message translates to:
  /// **'Link full groups?'**
  String get linkFullGroups2;

  /// No description provided for @linkNow.
  ///
  /// In en, this message translates to:
  /// **'Link now'**
  String get linkNow;

  /// No description provided for @linkPaths.
  ///
  /// In en, this message translates to:
  /// **'Link paths'**
  String get linkPaths;

  /// No description provided for @linkedGroupHotspotTest.
  ///
  /// In en, this message translates to:
  /// **'Linked group / hotspot (test)'**
  String get linkedGroupHotspotTest;

  /// No description provided for @linkedToAnotherGroup.
  ///
  /// In en, this message translates to:
  /// **'Linked to another group'**
  String get linkedToAnotherGroup;

  /// No description provided for @linksWithCheckedId.
  ///
  /// In en, this message translates to:
  /// **'Links with checked id'**
  String get linksWithCheckedId;

  /// No description provided for @linkup.
  ///
  /// In en, this message translates to:
  /// **'LinkUp {version}  ·  {sizeLabel}'**
  String linkup(Object? version, Object? sizeLabel);

  /// No description provided for @linkupAccount.
  ///
  /// In en, this message translates to:
  /// **'LinkUp account'**
  String get linkupAccount;

  /// No description provided for @linkupCallAndRoutingTransportIs.
  ///
  /// In en, this message translates to:
  /// **'LinkUp call and routing transport is local-only: LAN, Wi-Fi Direct and multi-hop mesh.'**
  String get linkupCallAndRoutingTransportIs;

  /// No description provided for @linkupConnected.
  ///
  /// In en, this message translates to:
  /// **'LinkUp connected'**
  String get linkupConnected;

  /// No description provided for @linkupCouldNotInitializeSafelyClose.
  ///
  /// In en, this message translates to:
  /// **'LinkUp could not initialize safely. Close and reopen the app.'**
  String get linkupCouldNotInitializeSafelyClose;

  /// No description provided for @linkupCouldNotStart.
  ///
  /// In en, this message translates to:
  /// **'LinkUp could not start'**
  String get linkupCouldNotStart;

  /// No description provided for @linkupCouldnTTurnOnIts.
  ///
  /// In en, this message translates to:
  /// **'LinkUp couldn\'t turn on its own Wi-Fi. If your friend is on the same Wi-Fi as you, they can scan this:'**
  String get linkupCouldnTTurnOnIts;

  /// No description provided for @linkupIsDownloaded.
  ///
  /// In en, this message translates to:
  /// **'LinkUp{version} is downloaded'**
  String linkupIsDownloaded(Object? version);

  /// No description provided for @linkupKeepsNotificationContentSeparateFrom.
  ///
  /// In en, this message translates to:
  /// **'LinkUp keeps notification content separate from your chat content.'**
  String get linkupKeepsNotificationContentSeparateFrom;

  /// No description provided for @linkupLogo.
  ///
  /// In en, this message translates to:
  /// **'LinkUp logo'**
  String get linkupLogo;

  /// No description provided for @linkupNeedsTheNearbyDevicesPermission.
  ///
  /// In en, this message translates to:
  /// **'LinkUp needs the \"Nearby devices\" permission to turn on its Wi-Fi. Allow it in LinkUp\'s app settings.'**
  String get linkupNeedsTheNearbyDevicesPermission;

  /// No description provided for @linkupNeedsThisToStayOn.
  ///
  /// In en, this message translates to:
  /// **'LinkUp needs this to stay on — messages and calls must keep arriving in the background.'**
  String get linkupNeedsThisToStayOn;

  /// No description provided for @linkupNeedsYourOkOnce.
  ///
  /// In en, this message translates to:
  /// **'LinkUp needs your OK once'**
  String get linkupNeedsYourOkOnce;

  /// No description provided for @linkupNotification.
  ///
  /// In en, this message translates to:
  /// **'LinkUp notification'**
  String get linkupNotification;

  /// No description provided for @linkupOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'LinkUp on this phone'**
  String get linkupOnThisPhone;

  /// No description provided for @linkupPhone.
  ///
  /// In en, this message translates to:
  /// **'LinkUp phone'**
  String get linkupPhone;

  /// No description provided for @linkupServerIdentityChangedConnectionWas.
  ///
  /// In en, this message translates to:
  /// **'LinkUp server identity changed. Connection was blocked for safety.'**
  String get linkupServerIdentityChangedConnectionWas;

  /// No description provided for @linkupTriesAgainLaterByItself.
  ///
  /// In en, this message translates to:
  /// **'LinkUp tries again later by itself.'**
  String get linkupTriesAgainLaterByItself;

  /// No description provided for @linkupUpdatedTo.
  ///
  /// In en, this message translates to:
  /// **'LinkUp updated to {kAppVersion}'**
  String linkupUpdatedTo(Object? kAppVersion);

  /// No description provided for @linkupUses.
  ///
  /// In en, this message translates to:
  /// **'LinkUp uses {bytes}'**
  String linkupUses(Object? bytes);

  /// No description provided for @linkupVideoCall.
  ///
  /// In en, this message translates to:
  /// **'LinkUp video call'**
  String get linkupVideoCall;

  /// No description provided for @linkupVoiceCall.
  ///
  /// In en, this message translates to:
  /// **'LinkUp voice call'**
  String get linkupVoiceCall;

  /// No description provided for @linkupWiFiIsOff.
  ///
  /// In en, this message translates to:
  /// **'LinkUp Wi-Fi is off.'**
  String get linkupWiFiIsOff;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get live;

  /// No description provided for @liveNetwork.
  ///
  /// In en, this message translates to:
  /// **'Live network'**
  String get liveNetwork;

  /// No description provided for @liveOffline.
  ///
  /// In en, this message translates to:
  /// **'{live} live · {offline} offline'**
  String liveOffline(Object? live, Object? offline);

  /// No description provided for @livePlatformTotalsWithTheActivity.
  ///
  /// In en, this message translates to:
  /// **'Live platform totals with the activity recorded in the selected window'**
  String get livePlatformTotalsWithTheActivity;

  /// No description provided for @liveSubsystemHealth.
  ///
  /// In en, this message translates to:
  /// **'Live subsystem health'**
  String get liveSubsystemHealth;

  /// No description provided for @liveSubsystemReadings.
  ///
  /// In en, this message translates to:
  /// **'Live subsystem readings'**
  String get liveSubsystemReadings;

  /// No description provided for @llgq1.
  ///
  /// In en, this message translates to:
  /// **'llgq1:…'**
  String get llgq1;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @loadingGroupMessages.
  ///
  /// In en, this message translates to:
  /// **'Loading group messages…'**
  String get loadingGroupMessages;

  /// No description provided for @loadingMembers.
  ///
  /// In en, this message translates to:
  /// **'Loading members…'**
  String get loadingMembers;

  /// No description provided for @loadingMessages.
  ///
  /// In en, this message translates to:
  /// **'Loading messages…'**
  String get loadingMessages;

  /// No description provided for @loadingYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Loading your account…'**
  String get loadingYourAccount;

  /// No description provided for @loadingYourConversations.
  ///
  /// In en, this message translates to:
  /// **'Loading your conversations…'**
  String get loadingYourConversations;

  /// No description provided for @localCallingServiceIsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Local calling service is unavailable'**
  String get localCallingServiceIsUnavailable;

  /// No description provided for @localCallingServiceUnavailableReconnectAnd.
  ///
  /// In en, this message translates to:
  /// **'Local calling service unavailable — reconnect and try again'**
  String get localCallingServiceUnavailableReconnectAnd;

  /// No description provided for @localIpv4.
  ///
  /// In en, this message translates to:
  /// **'Local IPv4'**
  String get localIpv4;

  /// No description provided for @localNetworkAvailable.
  ///
  /// In en, this message translates to:
  /// **'Local network available'**
  String get localNetworkAvailable;

  /// No description provided for @localPlatformState.
  ///
  /// In en, this message translates to:
  /// **'local platform state'**
  String get localPlatformState;

  /// No description provided for @localWiFi.
  ///
  /// In en, this message translates to:
  /// **'Local Wi-Fi'**
  String get localWiFi;

  /// No description provided for @localWiFiOnly.
  ///
  /// In en, this message translates to:
  /// **'Local Wi-Fi only'**
  String get localWiFiOnly;

  /// No description provided for @lockAppInRecents.
  ///
  /// In en, this message translates to:
  /// **'Lock app in recents'**
  String get lockAppInRecents;

  /// No description provided for @lockLinkupInRecents.
  ///
  /// In en, this message translates to:
  /// **'Lock LinkUp in Recents'**
  String get lockLinkupInRecents;

  /// No description provided for @lockScreenCallsOffTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Lock-screen calls off - turn on'**
  String get lockScreenCallsOffTurnOn;

  /// No description provided for @lockScreenPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Lock-screen privacy'**
  String get lockScreenPrivacy;

  /// No description provided for @locked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get locked;

  /// No description provided for @lockedUsers.
  ///
  /// In en, this message translates to:
  /// **'Locked users'**
  String get lockedUsers;

  /// No description provided for @logIn.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get logIn;

  /// No description provided for @logInToYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Log in to your account'**
  String get logInToYourAccount;

  /// No description provided for @longPressForMessageActions.
  ///
  /// In en, this message translates to:
  /// **'Long press for message actions'**
  String get longPressForMessageActions;

  /// No description provided for @lookingForPhonesNearYou.
  ///
  /// In en, this message translates to:
  /// **'Looking for phones near you'**
  String get lookingForPhonesNearYou;

  /// No description provided for @lowestVersionAllowed.
  ///
  /// In en, this message translates to:
  /// **'Lowest version allowed'**
  String get lowestVersionAllowed;

  /// No description provided for @made.
  ///
  /// In en, this message translates to:
  /// **'Made {now}'**
  String made(Object? now);

  /// No description provided for @madeABackup.
  ///
  /// In en, this message translates to:
  /// **'{admin} made a backup'**
  String madeABackup(Object? admin);

  /// No description provided for @madeAGroupAdmin.
  ///
  /// In en, this message translates to:
  /// **'{actor} made {targets} a group admin'**
  String madeAGroupAdmin(Object? actor, Object? targets);

  /// No description provided for @madeAnAdmin.
  ///
  /// In en, this message translates to:
  /// **'{admin} made {target} an admin{detail}'**
  String madeAnAdmin(Object? admin, Object? target, Object? detail);

  /// No description provided for @madeYouAGroupAdmin.
  ///
  /// In en, this message translates to:
  /// **'{actor} made you a group admin'**
  String madeYouAGroupAdmin(Object? actor);

  /// No description provided for @makeANewCode.
  ///
  /// In en, this message translates to:
  /// **'Make a new code'**
  String get makeANewCode;

  /// No description provided for @makeANewCode2.
  ///
  /// In en, this message translates to:
  /// **'Make a new code?'**
  String get makeANewCode2;

  /// No description provided for @makeARecoveryCode.
  ///
  /// In en, this message translates to:
  /// **'Make a recovery code'**
  String get makeARecoveryCode;

  /// No description provided for @makeGroupAdmin.
  ///
  /// In en, this message translates to:
  /// **'Make group admin'**
  String get makeGroupAdmin;

  /// No description provided for @makeMyCode.
  ///
  /// In en, this message translates to:
  /// **'Make my code'**
  String get makeMyCode;

  /// No description provided for @makeNewCode.
  ///
  /// In en, this message translates to:
  /// **'Make new code'**
  String get makeNewCode;

  /// No description provided for @makePrivate.
  ///
  /// In en, this message translates to:
  /// **'Make private'**
  String get makePrivate;

  /// No description provided for @makeYourProfilePrivate.
  ///
  /// In en, this message translates to:
  /// **'Make your profile private?'**
  String get makeYourProfilePrivate;

  /// No description provided for @makingAGroupNeedsOnlineFor.
  ///
  /// In en, this message translates to:
  /// **'Making a group needs Online for now. Try again when Online.'**
  String get makingAGroupNeedsOnlineFor;

  /// No description provided for @manageDevices.
  ///
  /// In en, this message translates to:
  /// **'Manage devices'**
  String get manageDevices;

  /// No description provided for @manageSoundsVibrationAndImportanceIn.
  ///
  /// In en, this message translates to:
  /// **'Manage sounds, vibration and importance in Android settings.'**
  String get manageSoundsVibrationAndImportanceIn;

  /// No description provided for @manageUsers.
  ///
  /// In en, this message translates to:
  /// **'Manage users'**
  String get manageUsers;

  /// No description provided for @mar.
  ///
  /// In en, this message translates to:
  /// **'Mar'**
  String get mar;

  /// No description provided for @markAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markAsRead;

  /// No description provided for @markAsVerified.
  ///
  /// In en, this message translates to:
  /// **'Mark as verified'**
  String get markAsVerified;

  /// No description provided for @match.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get match;

  /// No description provided for @may.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get may;

  /// No description provided for @mayChangeIfTaken.
  ///
  /// In en, this message translates to:
  /// **'@{username} (may change if taken)'**
  String mayChangeIfTaken(Object? username);

  /// No description provided for @media.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get media;

  /// No description provided for @mediaLinksAndDocs.
  ///
  /// In en, this message translates to:
  /// **'Media, links and docs'**
  String get mediaLinksAndDocs;

  /// No description provided for @mediaLinksAndDocs2.
  ///
  /// In en, this message translates to:
  /// **'Media, links and docs · {files}'**
  String mediaLinksAndDocs2(Object? files);

  /// No description provided for @member.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get member;

  /// No description provided for @member2.
  ///
  /// In en, this message translates to:
  /// **'{members} member{s}'**
  String member2(Object? members, Object? s);

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @members2.
  ///
  /// In en, this message translates to:
  /// **'{people} members'**
  String members2(Object? people);

  /// No description provided for @membersSeeLeft.
  ///
  /// In en, this message translates to:
  /// **'Members see \"{me} left\".'**
  String membersSeeLeft(Object? me);

  /// No description provided for @memory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memory;

  /// No description provided for @mesh.
  ///
  /// In en, this message translates to:
  /// **'Mesh'**
  String get mesh;

  /// No description provided for @meshCall.
  ///
  /// In en, this message translates to:
  /// **'Mesh call'**
  String get meshCall;

  /// No description provided for @meshCapable.
  ///
  /// In en, this message translates to:
  /// **'Mesh capable'**
  String get meshCapable;

  /// No description provided for @meshLinks.
  ///
  /// In en, this message translates to:
  /// **'Mesh links'**
  String get meshLinks;

  /// No description provided for @meshOnly.
  ///
  /// In en, this message translates to:
  /// **'Mesh only'**
  String get meshOnly;

  /// No description provided for @meshPeers.
  ///
  /// In en, this message translates to:
  /// **'Mesh peers'**
  String get meshPeers;

  /// No description provided for @meshQueuedPackets.
  ///
  /// In en, this message translates to:
  /// **'Mesh queued packets'**
  String get meshQueuedPackets;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @message2.
  ///
  /// In en, this message translates to:
  /// **'Message {name}'**
  String message2(Object? name);

  /// No description provided for @messageActivity.
  ///
  /// In en, this message translates to:
  /// **'Message activity'**
  String get messageActivity;

  /// No description provided for @messageAndCallAlertsAreEnabled.
  ///
  /// In en, this message translates to:
  /// **'Message and call alerts are enabled'**
  String get messageAndCallAlertsAreEnabled;

  /// No description provided for @messageCopied.
  ///
  /// In en, this message translates to:
  /// **'Message copied'**
  String get messageCopied;

  /// No description provided for @messageGroup.
  ///
  /// In en, this message translates to:
  /// **'Message group'**
  String get messageGroup;

  /// No description provided for @messageInfo.
  ///
  /// In en, this message translates to:
  /// **'Message info'**
  String get messageInfo;

  /// No description provided for @messageNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Message not available'**
  String get messageNotAvailable;

  /// No description provided for @messageNotFound.
  ///
  /// In en, this message translates to:
  /// **'Message not found'**
  String get messageNotFound;

  /// No description provided for @messageNotSent.
  ///
  /// In en, this message translates to:
  /// **'Message not sent'**
  String get messageNotSent;

  /// No description provided for @messageNotSentTapToResend.
  ///
  /// In en, this message translates to:
  /// **'Message not sent. Tap to resend or delete'**
  String get messageNotSentTapToResend;

  /// No description provided for @messageOneFriend.
  ///
  /// In en, this message translates to:
  /// **'Message one friend'**
  String get messageOneFriend;

  /// No description provided for @messageText.
  ///
  /// In en, this message translates to:
  /// **'Message text'**
  String get messageText;

  /// No description provided for @messageWithAttachment.
  ///
  /// In en, this message translates to:
  /// **'Message with attachment'**
  String get messageWithAttachment;

  /// No description provided for @messages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messages;

  /// No description provided for @messages2.
  ///
  /// In en, this message translates to:
  /// **'Messages · {hits}'**
  String messages2(Object? hits);

  /// No description provided for @messages3.
  ///
  /// In en, this message translates to:
  /// **'{count} messages'**
  String messages3(Object? count);

  /// No description provided for @messagesAcceptedByTheServerPer.
  ///
  /// In en, this message translates to:
  /// **'Messages accepted by the server per bucket'**
  String get messagesAcceptedByTheServerPer;

  /// No description provided for @messagesAndCallsGetWrongTimes.
  ///
  /// In en, this message translates to:
  /// **'Messages and calls get wrong times. On the server PC: Settings > Time > Set time automatically > Sync now.'**
  String get messagesAndCallsGetWrongTimes;

  /// No description provided for @messagesAndCallsWorkAgain.
  ///
  /// In en, this message translates to:
  /// **'Messages and calls work again'**
  String get messagesAndCallsWorkAgain;

  /// No description provided for @messagesAreSealedForGroupMembers.
  ///
  /// In en, this message translates to:
  /// **'Messages are sealed for group members only'**
  String get messagesAreSealedForGroupMembers;

  /// No description provided for @messagesArriveWhenTheAppIs.
  ///
  /// In en, this message translates to:
  /// **'Messages arrive when the app is closed'**
  String get messagesArriveWhenTheAppIs;

  /// No description provided for @messagesCopied.
  ///
  /// In en, this message translates to:
  /// **'{withText} messages copied'**
  String messagesCopied(Object? withText);

  /// No description provided for @messagesGroupsAndCalls.
  ///
  /// In en, this message translates to:
  /// **'Messages, groups and calls'**
  String get messagesGroupsAndCalls;

  /// No description provided for @messagesPhotosVideos.
  ///
  /// In en, this message translates to:
  /// **'Messages, photos, videos'**
  String get messagesPhotosVideos;

  /// No description provided for @messagesToday.
  ///
  /// In en, this message translates to:
  /// **'Messages today'**
  String get messagesToday;

  /// No description provided for @messagesWaitUntilItRunsAgain.
  ///
  /// In en, this message translates to:
  /// **'Messages wait until it runs again'**
  String get messagesWaitUntilItRunsAgain;

  /// No description provided for @microphonePermissionNeededAllowItThen.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission needed — allow it, then answer again'**
  String get microphonePermissionNeededAllowItThen;

  /// No description provided for @min.
  ///
  /// In en, this message translates to:
  /// **'{left} min'**
  String min(Object? left);

  /// No description provided for @minAgo.
  ///
  /// In en, this message translates to:
  /// **'{diff} min ago'**
  String minAgo(Object? diff);

  /// No description provided for @minVersion.
  ///
  /// In en, this message translates to:
  /// **'Min. version'**
  String get minVersion;

  /// No description provided for @miniPlayer.
  ///
  /// In en, this message translates to:
  /// **'Mini player'**
  String get miniPlayer;

  /// No description provided for @minimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimize;

  /// No description provided for @minimumVersion.
  ///
  /// In en, this message translates to:
  /// **'Minimum version'**
  String get minimumVersion;

  /// No description provided for @missed.
  ///
  /// In en, this message translates to:
  /// **'{missed} missed'**
  String missed(Object? missed);

  /// No description provided for @missed2.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get missed2;

  /// No description provided for @missedCall.
  ///
  /// In en, this message translates to:
  /// **'Missed call'**
  String get missedCall;

  /// No description provided for @missedVoiceCall.
  ///
  /// In en, this message translates to:
  /// **'Missed voice call'**
  String get missedVoiceCall;

  /// No description provided for @moAgo.
  ///
  /// In en, this message translates to:
  /// **'{floor}mo ago'**
  String moAgo(Object? floor);

  /// No description provided for @mon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get mon;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'+{files} more'**
  String more(Object? files);

  /// No description provided for @more2.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more2;

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @moveThisAccountToAnotherPhone.
  ///
  /// In en, this message translates to:
  /// **'Move this account to another phone'**
  String get moveThisAccountToAnotherPhone;

  /// No description provided for @moveThisAccountToAnotherPhone2.
  ///
  /// In en, this message translates to:
  /// **'Move this account to another phone with a one-time QR transfer.'**
  String get moveThisAccountToAnotherPhone2;

  /// No description provided for @moveThisLinkupAccountToAnother.
  ///
  /// In en, this message translates to:
  /// **'Move this LinkUp account to another phone.'**
  String get moveThisLinkupAccountToAnother;

  /// No description provided for @moveToANewPhone.
  ///
  /// In en, this message translates to:
  /// **'Move to a new phone'**
  String get moveToANewPhone;

  /// No description provided for @movedToANewPhone.
  ///
  /// In en, this message translates to:
  /// **'Moved to a new phone'**
  String get movedToANewPhone;

  /// No description provided for @msDelay.
  ///
  /// In en, this message translates to:
  /// **'{rttMs} ms delay'**
  String msDelay(Object? rttMs);

  /// No description provided for @msJitter.
  ///
  /// In en, this message translates to:
  /// **'{jitterMs} ms jitter'**
  String msJitter(Object? jitterMs);

  /// No description provided for @mustSignInAgain.
  ///
  /// In en, this message translates to:
  /// **'{name} must sign in again'**
  String mustSignInAgain(Object? name);

  /// No description provided for @mustSignInAgainOnEvery.
  ///
  /// In en, this message translates to:
  /// **'{name} must sign in again on every phone.'**
  String mustSignInAgainOnEvery(Object? name);

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @muteNotifications.
  ///
  /// In en, this message translates to:
  /// **'Mute notifications'**
  String get muteNotifications;

  /// No description provided for @myAndroidPhone.
  ///
  /// In en, this message translates to:
  /// **'My Android Phone'**
  String get myAndroidPhone;

  /// No description provided for @myLinks.
  ///
  /// In en, this message translates to:
  /// **'My links'**
  String get myLinks;

  /// No description provided for @myLinkupAccount.
  ///
  /// In en, this message translates to:
  /// **'My LinkUp account'**
  String get myLinkupAccount;

  /// No description provided for @myLinkupRecoveryCodeKeepIt.
  ///
  /// In en, this message translates to:
  /// **'My LinkUp recovery code (@{who}): {code} - keep it private.'**
  String myLinkupRecoveryCodeKeepIt(Object? who, Object? code);

  /// No description provided for @myLinkupRecoveryCodeKeepIt2.
  ///
  /// In en, this message translates to:
  /// **'My LinkUp recovery code: {code} - keep it private.'**
  String myLinkupRecoveryCodeKeepIt2(Object? code);

  /// No description provided for @myPhones.
  ///
  /// In en, this message translates to:
  /// **'My phones'**
  String get myPhones;

  /// No description provided for @myQrCode.
  ///
  /// In en, this message translates to:
  /// **'My QR code'**
  String get myQrCode;

  /// No description provided for @nameAndPasswordInYourPhone.
  ///
  /// In en, this message translates to:
  /// **'Name and password: in your phone\'s hotspot settings'**
  String get nameAndPasswordInYourPhone;

  /// No description provided for @nameAndPhoto.
  ///
  /// In en, this message translates to:
  /// **'Name and photo'**
  String get nameAndPhoto;

  /// No description provided for @nameOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Name on this phone'**
  String get nameOnThisPhone;

  /// No description provided for @namePhotoAndDescription.
  ///
  /// In en, this message translates to:
  /// **'Name, photo and description'**
  String get namePhotoAndDescription;

  /// No description provided for @nearYou.
  ///
  /// In en, this message translates to:
  /// **'Near you'**
  String get nearYou;

  /// No description provided for @nearby.
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get nearby;

  /// No description provided for @nearbyChatsWithOtherLinkupPhones.
  ///
  /// In en, this message translates to:
  /// **'Nearby chats with other LinkUp phones may pause for a moment if your phone can\'t do both. They come back by themselves when you stop sharing.'**
  String get nearbyChatsWithOtherLinkupPhones;

  /// No description provided for @nearbyDirectLink.
  ///
  /// In en, this message translates to:
  /// **'Nearby - direct link'**
  String get nearbyDirectLink;

  /// No description provided for @nearbyGroupsCanHaveUpTo.
  ///
  /// In en, this message translates to:
  /// **'Nearby groups can have up to 32 people.'**
  String get nearbyGroupsCanHaveUpTo;

  /// No description provided for @nearbyLinkupUser.
  ///
  /// In en, this message translates to:
  /// **'Nearby LinkUp user'**
  String get nearbyLinkupUser;

  /// No description provided for @nearbyMesh.
  ///
  /// In en, this message translates to:
  /// **'Nearby · Mesh'**
  String get nearbyMesh;

  /// No description provided for @nearbyMeshVia.
  ///
  /// In en, this message translates to:
  /// **'Nearby · Mesh, via {phonesBetween} {phones}'**
  String nearbyMeshVia(Object? phonesBetween, Object? phones);

  /// No description provided for @nearbyNow.
  ///
  /// In en, this message translates to:
  /// **'Nearby now'**
  String get nearbyNow;

  /// No description provided for @nearbyNow2.
  ///
  /// In en, this message translates to:
  /// **'nearby now'**
  String get nearbyNow2;

  /// No description provided for @nearbyNowAFewSeconds.
  ///
  /// In en, this message translates to:
  /// **'Nearby now · a few seconds'**
  String get nearbyNowAFewSeconds;

  /// No description provided for @nearbyNowAdding.
  ///
  /// In en, this message translates to:
  /// **'Nearby now · adding…'**
  String get nearbyNowAdding;

  /// No description provided for @nearbyOnlineOrOffline.
  ///
  /// In en, this message translates to:
  /// **'Nearby, Online or Offline'**
  String get nearbyOnlineOrOffline;

  /// No description provided for @nearbyPhonesNowServerWhenOnline.
  ///
  /// In en, this message translates to:
  /// **'Nearby phones now, server when online'**
  String get nearbyPhonesNowServerWhenOnline;

  /// No description provided for @nearbyPhonesSeen.
  ///
  /// In en, this message translates to:
  /// **'Nearby phones seen'**
  String get nearbyPhonesSeen;

  /// No description provided for @nearbyTestsTestersOnly.
  ///
  /// In en, this message translates to:
  /// **'Nearby tests (testers only)'**
  String get nearbyTestsTestersOnly;

  /// No description provided for @nearbyWhileClosedBatteryLow.
  ///
  /// In en, this message translates to:
  /// **'Nearby while closed: Battery low'**
  String get nearbyWhileClosedBatteryLow;

  /// No description provided for @nearbyWhileClosedNeedsLocation.
  ///
  /// In en, this message translates to:
  /// **'Nearby while closed: Needs location'**
  String get nearbyWhileClosedNeedsLocation;

  /// No description provided for @nearbyWhileClosedNeedsPermission.
  ///
  /// In en, this message translates to:
  /// **'Nearby while closed: Needs permission'**
  String get nearbyWhileClosedNeedsPermission;

  /// No description provided for @nearbyWhileClosedOffByAdmin.
  ///
  /// In en, this message translates to:
  /// **'Nearby while closed: Off by admin'**
  String get nearbyWhileClosedOffByAdmin;

  /// No description provided for @nearbyWhileClosedOn.
  ///
  /// In en, this message translates to:
  /// **'Nearby while closed: On'**
  String get nearbyWhileClosedOn;

  /// No description provided for @nearbyWiFi.
  ///
  /// In en, this message translates to:
  /// **'Nearby · Wi-Fi'**
  String get nearbyWiFi;

  /// No description provided for @nearbyWiFiDirect.
  ///
  /// In en, this message translates to:
  /// **'Nearby · Wi-Fi Direct'**
  String get nearbyWiFiDirect;

  /// No description provided for @needsALook.
  ///
  /// In en, this message translates to:
  /// **'Needs a look'**
  String get needsALook;

  /// No description provided for @needsAndroid10OrNewer.
  ///
  /// In en, this message translates to:
  /// **'Needs Android 10 or newer'**
  String get needsAndroid10OrNewer;

  /// No description provided for @needsTheServer.
  ///
  /// In en, this message translates to:
  /// **'Needs the server'**
  String get needsTheServer;

  /// No description provided for @needsTheServer2.
  ///
  /// In en, this message translates to:
  /// **'Needs the server.'**
  String get needsTheServer2;

  /// No description provided for @needsTheServerItOpensBy.
  ///
  /// In en, this message translates to:
  /// **'Needs the server. It opens by itself when the server is back.'**
  String get needsTheServerItOpensBy;

  /// No description provided for @network.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get network;

  /// No description provided for @networkDetails.
  ///
  /// In en, this message translates to:
  /// **'Network details'**
  String get networkDetails;

  /// No description provided for @networkMesh.
  ///
  /// In en, this message translates to:
  /// **'Network & mesh'**
  String get networkMesh;

  /// No description provided for @networkMesh2.
  ///
  /// In en, this message translates to:
  /// **'Network & Mesh'**
  String get networkMesh2;

  /// No description provided for @neverSeen.
  ///
  /// In en, this message translates to:
  /// **'Never seen'**
  String get neverSeen;

  /// No description provided for @neverShareItLinkupAndThe.
  ///
  /// In en, this message translates to:
  /// **'Never share it. LinkUp and the admin never ask for it.'**
  String get neverShareItLinkupAndThe;

  /// No description provided for @neverShown.
  ///
  /// In en, this message translates to:
  /// **'Never shown'**
  String get neverShown;

  /// No description provided for @neverShownToAdmins.
  ///
  /// In en, this message translates to:
  /// **'Never shown to admins'**
  String get neverShownToAdmins;

  /// No description provided for @newCall.
  ///
  /// In en, this message translates to:
  /// **'New call'**
  String get newCall;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @newCode.
  ///
  /// In en, this message translates to:
  /// **'New code'**
  String get newCode;

  /// No description provided for @newConversation.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get newConversation;

  /// No description provided for @newDeviceName.
  ///
  /// In en, this message translates to:
  /// **'New device name'**
  String get newDeviceName;

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// No description provided for @newHere.
  ///
  /// In en, this message translates to:
  /// **'New here?'**
  String get newHere;

  /// No description provided for @newLinkMadeTheOldOne.
  ///
  /// In en, this message translates to:
  /// **'New link made. The old one stops working.'**
  String get newLinkMadeTheOldOne;

  /// No description provided for @newLinkupFoundNearby.
  ///
  /// In en, this message translates to:
  /// **'New LinkUp found nearby'**
  String get newLinkupFoundNearby;

  /// No description provided for @newLinkupOnTheServer.
  ///
  /// In en, this message translates to:
  /// **'New LinkUp on the server'**
  String get newLinkupOnTheServer;

  /// No description provided for @newMessage.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get newMessage;

  /// No description provided for @newMessageFrom.
  ///
  /// In en, this message translates to:
  /// **'New message from {displayName}'**
  String newMessageFrom(Object? displayName);

  /// No description provided for @newMessages.
  ///
  /// In en, this message translates to:
  /// **'New messages'**
  String get newMessages;

  /// No description provided for @newMessages2.
  ///
  /// In en, this message translates to:
  /// **'{unreadCount} new messages'**
  String newMessages2(Object? unreadCount);

  /// No description provided for @newMessages3.
  ///
  /// In en, this message translates to:
  /// **'{displayName} • {unreadCount} new messages'**
  String newMessages3(Object? displayName, Object? unreadCount);

  /// No description provided for @newNotification.
  ///
  /// In en, this message translates to:
  /// **'New notification'**
  String get newNotification;

  /// No description provided for @newOwnerOfThisPhoneAsk.
  ///
  /// In en, this message translates to:
  /// **'New owner of this phone? Ask the admin.'**
  String get newOwnerOfThisPhoneAsk;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @newPasswordAgain.
  ///
  /// In en, this message translates to:
  /// **'New password again'**
  String get newPasswordAgain;

  /// No description provided for @newPhone.
  ///
  /// In en, this message translates to:
  /// **'New phone: {named}'**
  String newPhone(Object? named);

  /// No description provided for @newPhone2.
  ///
  /// In en, this message translates to:
  /// **'New phone: {named} · {created_at}'**
  String newPhone2(Object? named, Object? created_at);

  /// No description provided for @newPoll.
  ///
  /// In en, this message translates to:
  /// **'New poll'**
  String get newPoll;

  /// No description provided for @newRecoveryCode.
  ///
  /// In en, this message translates to:
  /// **'New recovery code'**
  String get newRecoveryCode;

  /// No description provided for @newRequest.
  ///
  /// In en, this message translates to:
  /// **'New request'**
  String get newRequest;

  /// No description provided for @newSecurityCodeAccepted.
  ///
  /// In en, this message translates to:
  /// **'New security code accepted'**
  String get newSecurityCodeAccepted;

  /// No description provided for @newSecurityKey.
  ///
  /// In en, this message translates to:
  /// **'New security key'**
  String get newSecurityKey;

  /// No description provided for @newText.
  ///
  /// In en, this message translates to:
  /// **'{unreadCount} new {messages}'**
  String newText(Object? unreadCount, Object? messages);

  /// No description provided for @newer.
  ///
  /// In en, this message translates to:
  /// **'Newer'**
  String get newer;

  /// No description provided for @newestFirstMergedAcrossUsersDevices.
  ///
  /// In en, this message translates to:
  /// **'Newest first, merged across users, devices, files, calls and audit sources'**
  String get newestFirstMergedAcrossUsersDevices;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @nextDownload.
  ///
  /// In en, this message translates to:
  /// **'Next: Download  →'**
  String get nextDownload;

  /// No description provided for @nextPhone.
  ///
  /// In en, this message translates to:
  /// **'Next phone'**
  String get nextPhone;

  /// No description provided for @noAccountWithThisUsername.
  ///
  /// In en, this message translates to:
  /// **'No account with this username.'**
  String get noAccountWithThisUsername;

  /// No description provided for @noActivityRecorded.
  ///
  /// In en, this message translates to:
  /// **'No activity recorded'**
  String get noActivityRecorded;

  /// No description provided for @noAddressAtAllYourFriend.
  ///
  /// In en, this message translates to:
  /// **'No address at all? Your friend joins the Wi-Fi (step 1), opens its Wi-Fi details, and types the \"Gateway\" address in Chrome with :8080'**
  String get noAddressAtAllYourFriend;

  /// No description provided for @noAnswer.
  ///
  /// In en, this message translates to:
  /// **'No answer'**
  String get noAnswer;

  /// No description provided for @noBackupYet.
  ///
  /// In en, this message translates to:
  /// **'No backup yet'**
  String get noBackupYet;

  /// No description provided for @noCallsYet.
  ///
  /// In en, this message translates to:
  /// **'No calls yet'**
  String get noCallsYet;

  /// No description provided for @noChatsFound.
  ///
  /// In en, this message translates to:
  /// **'No chats found'**
  String get noChatsFound;

  /// No description provided for @noChatsYet.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get noChatsYet;

  /// No description provided for @noConnectionCheckYourNetworkAnd.
  ///
  /// In en, this message translates to:
  /// **'No connection. Check your network and try again.'**
  String get noConnectionCheckYourNetworkAnd;

  /// No description provided for @noContactsYet.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet'**
  String get noContactsYet;

  /// No description provided for @noConversationsYet.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get noConversationsYet;

  /// No description provided for @noCriticalSecurityAlertsIn24h.
  ///
  /// In en, this message translates to:
  /// **'No critical security alerts in 24h'**
  String get noCriticalSecurityAlertsIn24h;

  /// No description provided for @noData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get noData;

  /// No description provided for @noDataForThisPeriod.
  ///
  /// In en, this message translates to:
  /// **'No data for this period'**
  String get noDataForThisPeriod;

  /// No description provided for @noDownloadsFor10Minutes.
  ///
  /// In en, this message translates to:
  /// **'No downloads for 10 minutes.'**
  String get noDownloadsFor10Minutes;

  /// No description provided for @noEncryptedIdentityBackupOnThe.
  ///
  /// In en, this message translates to:
  /// **'No encrypted identity backup on the server'**
  String get noEncryptedIdentityBackupOnThe;

  /// No description provided for @noFilesYet.
  ///
  /// In en, this message translates to:
  /// **'No files yet'**
  String get noFilesYet;

  /// No description provided for @noFriendFound.
  ///
  /// In en, this message translates to:
  /// **'No friend found'**
  String get noFriendFound;

  /// No description provided for @noFriendSPhoneCouldCheck.
  ///
  /// In en, this message translates to:
  /// **'No friend\'s phone could check the code yet. Come near a friend\'s phone, or connect to the server.'**
  String get noFriendSPhoneCouldCheck;

  /// No description provided for @noFriendsYet.
  ///
  /// In en, this message translates to:
  /// **'No friends yet'**
  String get noFriendsYet;

  /// No description provided for @noHealthReadings.
  ///
  /// In en, this message translates to:
  /// **'No health readings'**
  String get noHealthReadings;

  /// No description provided for @noInternetNoSimNeeded.
  ///
  /// In en, this message translates to:
  /// **'•  No internet, no SIM needed'**
  String get noInternetNoSimNeeded;

  /// No description provided for @noLink.
  ///
  /// In en, this message translates to:
  /// **'No link'**
  String get noLink;

  /// No description provided for @noLinkupServerWasFoundEnter.
  ///
  /// In en, this message translates to:
  /// **'No LinkUp server was found. Enter the server address and try again.'**
  String get noLinkupServerWasFoundEnter;

  /// No description provided for @noMessageHereYouCanOnly.
  ///
  /// In en, this message translates to:
  /// **'No \"Message\" here: you can only chat 1:1 with friends. In the group you can still talk.'**
  String get noMessageHereYouCanOnly;

  /// No description provided for @noMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages'**
  String get noMessages;

  /// No description provided for @noMessagesFound.
  ///
  /// In en, this message translates to:
  /// **'No messages found'**
  String get noMessagesFound;

  /// No description provided for @noMessagesInTheseDates.
  ///
  /// In en, this message translates to:
  /// **'No messages in these dates.'**
  String get noMessagesInTheseDates;

  /// No description provided for @noMessagesInThisChat.
  ///
  /// In en, this message translates to:
  /// **'No messages in this chat'**
  String get noMessagesInThisChat;

  /// No description provided for @noMessagesOrCalls.
  ///
  /// In en, this message translates to:
  /// **'No messages or calls'**
  String get noMessagesOrCalls;

  /// No description provided for @noMessagesWereExchangedInThis.
  ///
  /// In en, this message translates to:
  /// **'No messages were exchanged in this window.'**
  String get noMessagesWereExchangedInThis;

  /// No description provided for @noMessagesYetToday.
  ///
  /// In en, this message translates to:
  /// **'No messages yet today'**
  String get noMessagesYetToday;

  /// No description provided for @noMinimum.
  ///
  /// In en, this message translates to:
  /// **'No minimum'**
  String get noMinimum;

  /// No description provided for @noModuleMatchesThatTermGlobal.
  ///
  /// In en, this message translates to:
  /// **'No module matches that term. Global entity search across users, devices and transfers is available inside each module.'**
  String get noModuleMatchesThatTermGlobal;

  /// No description provided for @noNearbyPhoneCouldShareIt.
  ///
  /// In en, this message translates to:
  /// **'No nearby phone could share it'**
  String get noNearbyPhoneCouldShareIt;

  /// No description provided for @noNewSignIn.
  ///
  /// In en, this message translates to:
  /// **'No new sign-in'**
  String get noNewSignIn;

  /// No description provided for @noOneCalled.
  ///
  /// In en, this message translates to:
  /// **'No one called '**
  String get noOneCalled;

  /// No description provided for @noOneCalledOnTheMap.
  ///
  /// In en, this message translates to:
  /// **'No one called \"{q}\" on the map'**
  String noOneCalledOnTheMap(Object? q);

  /// No description provided for @noOneFound.
  ///
  /// In en, this message translates to:
  /// **'No one found'**
  String get noOneFound;

  /// No description provided for @noOneIsAsking.
  ///
  /// In en, this message translates to:
  /// **'No one is asking'**
  String get noOneIsAsking;

  /// No description provided for @noOneIsBlockedByAdmin.
  ///
  /// In en, this message translates to:
  /// **'No one is blocked by admin'**
  String get noOneIsBlockedByAdmin;

  /// No description provided for @noOneNearbyRightNow.
  ///
  /// In en, this message translates to:
  /// **'No one nearby right now'**
  String get noOneNearbyRightNow;

  /// No description provided for @noOneOnlineRightNow.
  ///
  /// In en, this message translates to:
  /// **'No one online right now'**
  String get noOneOnlineRightNow;

  /// No description provided for @noOneTimeCodeWasReturned.
  ///
  /// In en, this message translates to:
  /// **'No one-time code was returned.'**
  String get noOneTimeCodeWasReturned;

  /// No description provided for @noOneToShowYetSearch.
  ///
  /// In en, this message translates to:
  /// **'No one to show yet. Search a name or scan a QR code.'**
  String get noOneToShowYetSearch;

  /// No description provided for @noOperationalEventsHaveBeenRecorded.
  ///
  /// In en, this message translates to:
  /// **'No operational events have been recorded on this server yet.'**
  String get noOperationalEventsHaveBeenRecorded;

  /// No description provided for @noOtherPhonesLinked.
  ///
  /// In en, this message translates to:
  /// **'No other phones linked'**
  String get noOtherPhonesLinked;

  /// No description provided for @noOtherRegisteredDevicesAreAvailable.
  ///
  /// In en, this message translates to:
  /// **'No other registered devices are available.'**
  String get noOtherRegisteredDevicesAreAvailable;

  /// No description provided for @noOwner.
  ///
  /// In en, this message translates to:
  /// **'No owner'**
  String get noOwner;

  /// No description provided for @noPendingRecoveryRequest.
  ///
  /// In en, this message translates to:
  /// **'No pending recovery request'**
  String get noPendingRecoveryRequest;

  /// No description provided for @noPeopleFound.
  ///
  /// In en, this message translates to:
  /// **'No people found'**
  String get noPeopleFound;

  /// No description provided for @noPhone.
  ///
  /// In en, this message translates to:
  /// **'no phone'**
  String get noPhone;

  /// No description provided for @noPhoneReachedYet.
  ///
  /// In en, this message translates to:
  /// **'{since} · no phone reached yet'**
  String noPhoneReachedYet(Object? since);

  /// No description provided for @noPhonesFound.
  ///
  /// In en, this message translates to:
  /// **'No phones found'**
  String get noPhonesFound;

  /// No description provided for @noPhonesOnline.
  ///
  /// In en, this message translates to:
  /// **'No phones online'**
  String get noPhonesOnline;

  /// No description provided for @noQrCodeFoundInThis.
  ///
  /// In en, this message translates to:
  /// **'No QR code found in this picture'**
  String get noQrCodeFoundInThis;

  /// No description provided for @noRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'No recent activity'**
  String get noRecentActivity;

  /// No description provided for @noRecords.
  ///
  /// In en, this message translates to:
  /// **'No records'**
  String get noRecords;

  /// No description provided for @noRequests.
  ///
  /// In en, this message translates to:
  /// **'No requests'**
  String get noRequests;

  /// No description provided for @noResponseTrafficRecordedYet.
  ///
  /// In en, this message translates to:
  /// **'No response traffic recorded yet.'**
  String get noResponseTrafficRecordedYet;

  /// No description provided for @noResultsFor.
  ///
  /// In en, this message translates to:
  /// **'No results for \'{q}\''**
  String noResultsFor(Object? q);

  /// No description provided for @noRoutesYet.
  ///
  /// In en, this message translates to:
  /// **'No routes yet.'**
  String get noRoutesYet;

  /// No description provided for @noRule.
  ///
  /// In en, this message translates to:
  /// **'no rule'**
  String get noRule;

  /// No description provided for @noServerAFriendSPhone.
  ///
  /// In en, this message translates to:
  /// **'No server · a friend\'s phone nearby checks it'**
  String get noServerAFriendSPhone;

  /// No description provided for @noServerRequestsGoByWi.
  ///
  /// In en, this message translates to:
  /// **'No server · requests go by Wi-Fi Direct / mesh'**
  String get noServerRequestsGoByWi;

  /// No description provided for @noServerRightNow.
  ///
  /// In en, this message translates to:
  /// **'No server right now'**
  String get noServerRightNow;

  /// No description provided for @noServerSearchingNearbyPhones.
  ///
  /// In en, this message translates to:
  /// **'No server - searching nearby phones'**
  String get noServerSearchingNearbyPhones;

  /// No description provided for @noServerShowingPeopleSeenNearby.
  ///
  /// In en, this message translates to:
  /// **'No server · showing people seen nearby'**
  String get noServerShowingPeopleSeenNearby;

  /// No description provided for @noServerSideKeyHistoryYet.
  ///
  /// In en, this message translates to:
  /// **'No server-side key history yet.'**
  String get noServerSideKeyHistoryYet;

  /// No description provided for @noWarnings.
  ///
  /// In en, this message translates to:
  /// **'No warnings'**
  String get noWarnings;

  /// No description provided for @noWayToReachRightNow.
  ///
  /// In en, this message translates to:
  /// **'No way to reach right now. Messages wait and go when a way opens.'**
  String get noWayToReachRightNow;

  /// No description provided for @nobody.
  ///
  /// In en, this message translates to:
  /// **'Nobody'**
  String get nobody;

  /// No description provided for @nobodyCanFindYouByName.
  ///
  /// In en, this message translates to:
  /// **'**Nobody can find you** by name search, and no phone shows you to others.'**
  String get nobodyCanFindYouByName;

  /// No description provided for @nobodyCanFindYouByName2.
  ///
  /// In en, this message translates to:
  /// **'Nobody can find you by name search. Only friends get your phone number.'**
  String get nobodyCanFindYouByName2;

  /// No description provided for @nobodyIsBlockedHere.
  ///
  /// In en, this message translates to:
  /// **'Nobody is blocked here'**
  String get nobodyIsBlockedHere;

  /// No description provided for @nobodyKnownOnThisPhoneYet.
  ///
  /// In en, this message translates to:
  /// **'Nobody known on this phone yet.'**
  String get nobodyKnownOnThisPhoneYet;

  /// No description provided for @nobodySignedIn.
  ///
  /// In en, this message translates to:
  /// **'Nobody signed in'**
  String get nobodySignedIn;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @noneYetWaiting.
  ///
  /// In en, this message translates to:
  /// **'None yet. Waiting…'**
  String get noneYetWaiting;

  /// No description provided for @notAddedYetTheyNeedTo.
  ///
  /// In en, this message translates to:
  /// **'Not added yet: {join}. They need to open LinkUp Online once.'**
  String notAddedYetTheyNeedTo(Object? join);

  /// No description provided for @notApproved.
  ///
  /// In en, this message translates to:
  /// **'Not approved'**
  String get notApproved;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get notAvailable;

  /// No description provided for @notAvailableOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Not available on this device.'**
  String get notAvailableOnThisDevice;

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// No description provided for @notDownloadedYet.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded yet'**
  String get notDownloadedYet;

  /// No description provided for @notFoundItMayHaveBeen.
  ///
  /// In en, this message translates to:
  /// **'Not found. It may have been removed or renamed.'**
  String get notFoundItMayHaveBeen;

  /// No description provided for @notFoundTryAgainWhenYou.
  ///
  /// In en, this message translates to:
  /// **'Not found. Try again when you\'re online or near friends.'**
  String get notFoundTryAgainWhenYou;

  /// No description provided for @notHereAskThemToOpen.
  ///
  /// In en, this message translates to:
  /// **'Not here? Ask them to open '**
  String get notHereAskThemToOpen;

  /// No description provided for @notHereAskThemToOpen2.
  ///
  /// In en, this message translates to:
  /// **'Not here? Ask them to open My QR code, then tap Scan QR code below.'**
  String get notHereAskThemToOpen2;

  /// No description provided for @notInAGroup.
  ///
  /// In en, this message translates to:
  /// **'Not in a group'**
  String get notInAGroup;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @notOnServer.
  ///
  /// In en, this message translates to:
  /// **'{local} not on server'**
  String notOnServer(Object? local);

  /// No description provided for @notOnServer2.
  ///
  /// In en, this message translates to:
  /// **'Not on server'**
  String get notOnServer2;

  /// No description provided for @notOnServerYet.
  ///
  /// In en, this message translates to:
  /// **'Not on server yet'**
  String get notOnServerYet;

  /// No description provided for @notReachedIn7DaysTap.
  ///
  /// In en, this message translates to:
  /// **'Not reached in 7 days · tap to try again'**
  String get notReachedIn7DaysTap;

  /// No description provided for @notReachedIn7DaysTap2.
  ///
  /// In en, this message translates to:
  /// **'Not reached in 7 days. Tap Try again to send the group to {name} again.'**
  String notReachedIn7DaysTap2(Object? name);

  /// No description provided for @notSaved.
  ///
  /// In en, this message translates to:
  /// **'Not saved'**
  String get notSaved;

  /// No description provided for @notSeenFor30Days.
  ///
  /// In en, this message translates to:
  /// **'Not seen for 30+ days'**
  String get notSeenFor30Days;

  /// No description provided for @notSentTapToRetry.
  ///
  /// In en, this message translates to:
  /// **'Not sent - tap to retry'**
  String get notSentTapToRetry;

  /// No description provided for @notSentYet.
  ///
  /// In en, this message translates to:
  /// **'Not sent yet'**
  String get notSentYet;

  /// No description provided for @notVerified.
  ///
  /// In en, this message translates to:
  /// **'Not verified'**
  String get notVerified;

  /// No description provided for @notVotedYet.
  ///
  /// In en, this message translates to:
  /// **'Not voted yet'**
  String get notVotedYet;

  /// No description provided for @notYourFriendInThisGroup.
  ///
  /// In en, this message translates to:
  /// **'Not your friend · in this group'**
  String get notYourFriendInThisGroup;

  /// No description provided for @nothingDoneYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing done yet'**
  String get nothingDoneYet;

  /// No description provided for @nothingNeedsALookRightNow.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs a look right now.'**
  String get nothingNeedsALookRightNow;

  /// No description provided for @nothingPending.
  ///
  /// In en, this message translates to:
  /// **'Nothing pending'**
  String get nothingPending;

  /// No description provided for @nothingRecordedForThisPeriod.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded for this period.'**
  String get nothingRecordedForThisPeriod;

  /// No description provided for @nothingRemoved.
  ///
  /// In en, this message translates to:
  /// **'nothing removed'**
  String get nothingRemoved;

  /// No description provided for @nothingToReport.
  ///
  /// In en, this message translates to:
  /// **'Nothing to report'**
  String get nothingToReport;

  /// No description provided for @nothingYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get nothingYet;

  /// No description provided for @notificationChannels.
  ///
  /// In en, this message translates to:
  /// **'Notification channels'**
  String get notificationChannels;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @notificationsAllowLinkupTurnOnBanners.
  ///
  /// In en, this message translates to:
  /// **'Notifications: allow LinkUp, turn on Banners, Lock screen and Full-screen'**
  String get notificationsAllowLinkupTurnOnBanners;

  /// No description provided for @notificationsAreDisabledInAndroidSettings.
  ///
  /// In en, this message translates to:
  /// **'Notifications are disabled in Android settings'**
  String get notificationsAreDisabledInAndroidSettings;

  /// No description provided for @notificationsOffTapToAllow.
  ///
  /// In en, this message translates to:
  /// **'Notifications off - tap to allow'**
  String get notificationsOffTapToAllow;

  /// No description provided for @notificationsOn.
  ///
  /// In en, this message translates to:
  /// **'Notifications on'**
  String get notificationsOn;

  /// No description provided for @nov.
  ///
  /// In en, this message translates to:
  /// **'Nov'**
  String get nov;

  /// No description provided for @now.
  ///
  /// In en, this message translates to:
  /// **'Now: {rule}'**
  String now(Object? rule);

  /// No description provided for @oct.
  ///
  /// In en, this message translates to:
  /// **'Oct'**
  String get oct;

  /// No description provided for @ofAdded.
  ///
  /// In en, this message translates to:
  /// **'{added} of {invites} added'**
  String ofAdded(Object? added, Object? invites);

  /// No description provided for @ofParts.
  ///
  /// In en, this message translates to:
  /// **'{parts} of {vOf} parts'**
  String ofParts(Object? parts, Object? vOf);

  /// No description provided for @ofPartsTheRestIsOn.
  ///
  /// In en, this message translates to:
  /// **'{parts} of {vOf} parts · the rest is on the way'**
  String ofPartsTheRestIsOn(Object? parts, Object? vOf);

  /// No description provided for @ofPhones.
  ///
  /// In en, this message translates to:
  /// **'{done} of {need} phones'**
  String ofPhones(Object? done, Object? need);

  /// No description provided for @ofRegistered.
  ///
  /// In en, this message translates to:
  /// **'of {num} registered'**
  String ofRegistered(Object? num);

  /// No description provided for @ofVoted.
  ///
  /// In en, this message translates to:
  /// **'{voters} of {members} voted'**
  String ofVoted(Object? voters, Object? members);

  /// No description provided for @ofVoted2.
  ///
  /// In en, this message translates to:
  /// **'{question} · {voters} of {members} voted'**
  String ofVoted2(Object? question, Object? voters, Object? members);

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @offAccountClosed.
  ///
  /// In en, this message translates to:
  /// **'Off (account closed)'**
  String get offAccountClosed;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @offlineAccount.
  ///
  /// In en, this message translates to:
  /// **'Offline account'**
  String get offlineAccount;

  /// No description provided for @offlineAccountNotOnServerYet.
  ///
  /// In en, this message translates to:
  /// **'Offline account · not on server yet'**
  String get offlineAccountNotOnServerYet;

  /// No description provided for @offlineAccountsNotSeenFor30.
  ///
  /// In en, this message translates to:
  /// **'Offline accounts not seen for 30 days'**
  String get offlineAccountsNotSeenFor30;

  /// No description provided for @offlineBlockingIsNotReadyYet.
  ///
  /// In en, this message translates to:
  /// **'Offline blocking is not ready yet.'**
  String get offlineBlockingIsNotReadyYet;

  /// No description provided for @offlineBlockingIsReady.
  ///
  /// In en, this message translates to:
  /// **'Offline blocking is ready'**
  String get offlineBlockingIsReady;

  /// No description provided for @offlineIdle.
  ///
  /// In en, this message translates to:
  /// **'Offline / idle'**
  String get offlineIdle;

  /// No description provided for @offlineToolsOnlyBlockAppVersion.
  ///
  /// In en, this message translates to:
  /// **'{level} · Offline tools only · block, app version'**
  String offlineToolsOnlyBlockAppVersion(Object? level);

  /// No description provided for @offlineToolsStillWorkLockedOnes.
  ///
  /// In en, this message translates to:
  /// **'Offline tools still work. Locked ones open by themselves.'**
  String get offlineToolsStillWorkLockedOnes;

  /// No description provided for @offlineWorksOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Offline · works on this phone'**
  String get offlineWorksOnThisPhone;

  /// No description provided for @oldAccount.
  ///
  /// In en, this message translates to:
  /// **'old account'**
  String get oldAccount;

  /// No description provided for @oldApp.
  ///
  /// In en, this message translates to:
  /// **'Old app'**
  String get oldApp;

  /// No description provided for @oldAppRule.
  ///
  /// In en, this message translates to:
  /// **'Old app rule'**
  String get oldAppRule;

  /// No description provided for @oldChatsStay.
  ///
  /// In en, this message translates to:
  /// **'Old chats stay'**
  String get oldChatsStay;

  /// No description provided for @oldLinkup.
  ///
  /// In en, this message translates to:
  /// **'Old LinkUp'**
  String get oldLinkup;

  /// No description provided for @oldMessagesStayOnYourPhone.
  ///
  /// In en, this message translates to:
  /// **'Old messages stay on your phone (read only). You can delete the group later.'**
  String get oldMessagesStayOnYourPhone;

  /// No description provided for @oldVersionUpdateToCall.
  ///
  /// In en, this message translates to:
  /// **'Old version. Update to call.'**
  String get oldVersionUpdateToCall;

  /// No description provided for @oldVersionUpdateToSend.
  ///
  /// In en, this message translates to:
  /// **'Old version. Update to send.'**
  String get oldVersionUpdateToSend;

  /// No description provided for @older.
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get older;

  /// No description provided for @olderApps.
  ///
  /// In en, this message translates to:
  /// **'Older apps'**
  String get olderApps;

  /// No description provided for @olderAppsCanOnlyReadChats.
  ///
  /// In en, this message translates to:
  /// **'Older apps can only read chats from now. They see an Update button.'**
  String get olderAppsCanOnlyReadChats;

  /// No description provided for @olderAppsSeeAYellowUpdate.
  ///
  /// In en, this message translates to:
  /// **'Older apps see a yellow \"Update\" banner. They keep working.'**
  String get olderAppsSeeAYellowUpdate;

  /// No description provided for @olderAppsSeeUpdateNeededIn.
  ///
  /// In en, this message translates to:
  /// **'Older apps see \"Update needed in {days} days\". After that they can only read chats.'**
  String olderAppsSeeUpdateNeededIn(Object? days);

  /// No description provided for @olderVersionsStopped.
  ///
  /// In en, this message translates to:
  /// **'{v} · older versions stopped'**
  String olderVersionsStopped(Object? v);

  /// No description provided for @onAnOldApp.
  ///
  /// In en, this message translates to:
  /// **'{phone} on an old app'**
  String onAnOldApp(Object? phone);

  /// No description provided for @onCharger.
  ///
  /// In en, this message translates to:
  /// **'On charger'**
  String get onCharger;

  /// No description provided for @onEveryPhone.
  ///
  /// In en, this message translates to:
  /// **'{adminBlocked} · on every phone'**
  String onEveryPhone(Object? adminBlocked);

  /// No description provided for @onEveryPhoneTheUnblockReaches.
  ///
  /// In en, this message translates to:
  /// **'On every phone the unblock reaches'**
  String get onEveryPhoneTheUnblockReaches;

  /// No description provided for @onLinkup.
  ///
  /// In en, this message translates to:
  /// **' on LinkUp'**
  String get onLinkup;

  /// No description provided for @onNearbyLinkupPhonesCanJoin.
  ///
  /// In en, this message translates to:
  /// **'On — nearby LinkUp phones can join'**
  String get onNearbyLinkupPhonesCanJoin;

  /// No description provided for @onServer.
  ///
  /// In en, this message translates to:
  /// **'On server'**
  String get onServer;

  /// No description provided for @onTheNewPhone.
  ///
  /// In en, this message translates to:
  /// **'On the new phone:'**
  String get onTheNewPhone;

  /// No description provided for @onTheNewPhoneChooseTransfer.
  ///
  /// In en, this message translates to:
  /// **'On the new phone, choose “Transfer account from old phone” and scan this QR code. Keep both phones on the same trusted LinkUp network.'**
  String get onTheNewPhoneChooseTransfer;

  /// No description provided for @onTheServer.
  ///
  /// In en, this message translates to:
  /// **'On the server'**
  String get onTheServer;

  /// No description provided for @onTheWebOrInThe.
  ///
  /// In en, this message translates to:
  /// **'On the web or in the app'**
  String get onTheWebOrInThe;

  /// No description provided for @onThisPhoneAndroidNeedsLocation.
  ///
  /// In en, this message translates to:
  /// **'On this phone Android needs Location on to start a LinkUp Wi-Fi. Nothing is tracked.'**
  String get onThisPhoneAndroidNeedsLocation;

  /// No description provided for @onWaitingForAFullGroup.
  ///
  /// In en, this message translates to:
  /// **'On — waiting for a full group or a hotspot nearby'**
  String get onWaitingForAFullGroup;

  /// No description provided for @oneAnswerEachAVoteCan.
  ///
  /// In en, this message translates to:
  /// **'One answer each. A vote can be changed for 3 minutes, then it\'s final.'**
  String get oneAnswerEachAVoteCan;

  /// No description provided for @oneRunAsIfFilesWere.
  ///
  /// In en, this message translates to:
  /// **'One run as if files were 11 days old'**
  String get oneRunAsIfFilesWere;

  /// No description provided for @oneTimeCodeFor.
  ///
  /// In en, this message translates to:
  /// **'One-time code for {them}'**
  String oneTimeCodeFor(Object? them);

  /// No description provided for @oneTimeCodeFromTheAdmin.
  ///
  /// In en, this message translates to:
  /// **'One-time code from the admin'**
  String get oneTimeCodeFromTheAdmin;

  /// No description provided for @oneTimeOnly.
  ///
  /// In en, this message translates to:
  /// **'One time only\n'**
  String get oneTimeOnly;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @online2.
  ///
  /// In en, this message translates to:
  /// **'{online} online'**
  String online2(Object? online);

  /// No description provided for @online3.
  ///
  /// In en, this message translates to:
  /// **'{phone} · {online} online'**
  String online3(Object? phone, Object? online);

  /// No description provided for @onlineCall.
  ///
  /// In en, this message translates to:
  /// **'Online call'**
  String get onlineCall;

  /// No description provided for @onlineDevices.
  ///
  /// In en, this message translates to:
  /// **'Online devices'**
  String get onlineDevices;

  /// No description provided for @onlineNow.
  ///
  /// In en, this message translates to:
  /// **'Online now'**
  String get onlineNow;

  /// No description provided for @onlineViaServer.
  ///
  /// In en, this message translates to:
  /// **'Online - via server'**
  String get onlineViaServer;

  /// No description provided for @only.
  ///
  /// In en, this message translates to:
  /// **'Only '**
  String get only;

  /// No description provided for @onlyActionsYourAdminRolePermits.
  ///
  /// In en, this message translates to:
  /// **'Only actions your admin role permits'**
  String get onlyActionsYourAdminRolePermits;

  /// No description provided for @onlyAdmins.
  ///
  /// In en, this message translates to:
  /// **'Only admins'**
  String get onlyAdmins;

  /// No description provided for @onlyAdminsAddPeople.
  ///
  /// In en, this message translates to:
  /// **'Only admins add people'**
  String get onlyAdminsAddPeople;

  /// No description provided for @onlyAdminsAnnouncementGroup.
  ///
  /// In en, this message translates to:
  /// **'Only admins = announcement group'**
  String get onlyAdminsAnnouncementGroup;

  /// No description provided for @onlyAdminsCanChangeTheGroup.
  ///
  /// In en, this message translates to:
  /// **'Only admins can change the group photo.'**
  String get onlyAdminsCanChangeTheGroup;

  /// No description provided for @onlyAdminsCanDoThis.
  ///
  /// In en, this message translates to:
  /// **'Only admins can do this.'**
  String get onlyAdminsCanDoThis;

  /// No description provided for @onlyAdminsCanPinMessages.
  ///
  /// In en, this message translates to:
  /// **'Only admins can pin messages'**
  String get onlyAdminsCanPinMessages;

  /// No description provided for @onlyAdminsCanSeeAndChange.
  ///
  /// In en, this message translates to:
  /// **'Only admins can see and change these.'**
  String get onlyAdminsCanSeeAndChange;

  /// No description provided for @onlyAdminsCanSendMessages.
  ///
  /// In en, this message translates to:
  /// **'Only admins can send messages.'**
  String get onlyAdminsCanSendMessages;

  /// No description provided for @onlyAdminsSend.
  ///
  /// In en, this message translates to:
  /// **'Only admins send'**
  String get onlyAdminsSend;

  /// No description provided for @onlyContactsTheAppCanConfirm.
  ///
  /// In en, this message translates to:
  /// **'Only contacts the app can confirm'**
  String get onlyContactsTheAppCanConfirm;

  /// No description provided for @onlyForThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Only for this phone?'**
  String get onlyForThisPhone;

  /// No description provided for @onlyKindAndSizeNobodyCan.
  ///
  /// In en, this message translates to:
  /// **'Only kind and size. Nobody can open the files.'**
  String get onlyKindAndSizeNobodyCan;

  /// No description provided for @onlyNamesAndTimesNobodyCan.
  ///
  /// In en, this message translates to:
  /// **'Only names and times. Nobody can hear calls.'**
  String get onlyNamesAndTimesNobodyCan;

  /// No description provided for @onlyPeopleThisPhoneHasSeen.
  ///
  /// In en, this message translates to:
  /// **'Only people this phone has seen are listed. Others can be blocked from the web panel.'**
  String get onlyPeopleThisPhoneHasSeen;

  /// No description provided for @onlyTheOwnerAdminCanBlock.
  ///
  /// In en, this message translates to:
  /// **'Only the owner admin can block users'**
  String get onlyTheOwnerAdminCanBlock;

  /// No description provided for @onlyTheOwnerCanChangeThis.
  ///
  /// In en, this message translates to:
  /// **'Only the Owner can change this.'**
  String get onlyTheOwnerCanChangeThis;

  /// No description provided for @onlyThisPhoneOnlineOrOffline.
  ///
  /// In en, this message translates to:
  /// **'Only this phone, online or offline'**
  String get onlyThisPhoneOnlineOrOffline;

  /// No description provided for @onlyYouCanChangeThisTurn.
  ///
  /// In en, this message translates to:
  /// **'Only you can change this. Turn it off any time.'**
  String get onlyYouCanChangeThisTurn;

  /// No description provided for @onlyYouShouldSeeYourRecovery.
  ///
  /// In en, this message translates to:
  /// **'Only you should see your recovery code.'**
  String get onlyYouShouldSeeYourRecovery;

  /// No description provided for @onlyYouWillSeeThisName.
  ///
  /// In en, this message translates to:
  /// **'Only you will see this name'**
  String get onlyYouWillSeeThisName;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @openAppVersion.
  ///
  /// In en, this message translates to:
  /// **'Open App version'**
  String get openAppVersion;

  /// No description provided for @openAuditLog.
  ///
  /// In en, this message translates to:
  /// **'Open audit log'**
  String get openAuditLog;

  /// No description provided for @openGroup.
  ///
  /// In en, this message translates to:
  /// **'Open group'**
  String get openGroup;

  /// No description provided for @openHotspotSettings.
  ///
  /// In en, this message translates to:
  /// **'Open hotspot settings'**
  String get openHotspotSettings;

  /// No description provided for @openLinkup.
  ///
  /// In en, this message translates to:
  /// **'Open LinkUp'**
  String get openLinkup;

  /// No description provided for @openLinkupNearAMember.
  ///
  /// In en, this message translates to:
  /// **'Open LinkUp near a member'**
  String get openLinkupNearAMember;

  /// No description provided for @openNavigation.
  ///
  /// In en, this message translates to:
  /// **'Open navigation'**
  String get openNavigation;

  /// No description provided for @openNetworkTopology.
  ///
  /// In en, this message translates to:
  /// **'Open Network Topology'**
  String get openNetworkTopology;

  /// No description provided for @openRecentsTapTheLinkupIcon.
  ///
  /// In en, this message translates to:
  /// **'Open Recents, tap the LinkUp icon, choose Lock'**
  String get openRecentsTapTheLinkupIcon;

  /// No description provided for @openRecovery.
  ///
  /// In en, this message translates to:
  /// **'Open Recovery'**
  String get openRecovery;

  /// No description provided for @openSecurity.
  ///
  /// In en, this message translates to:
  /// **'Open Security'**
  String get openSecurity;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @openThisPersonFromPeopleTo.
  ///
  /// In en, this message translates to:
  /// **'Open this person from People to block them.'**
  String get openThisPersonFromPeopleTo;

  /// No description provided for @openThisScreenAgainWhenYou.
  ///
  /// In en, this message translates to:
  /// **'Open this screen again when you are back online.'**
  String get openThisScreenAgainWhenYou;

  /// No description provided for @openedChat.
  ///
  /// In en, this message translates to:
  /// **'{admin} opened chat {pair}'**
  String openedChat(Object? admin, Object? pair);

  /// No description provided for @openedTheGroupInviteLinkAdd.
  ///
  /// In en, this message translates to:
  /// **'{name} opened the group invite link. Add only people you know.'**
  String openedTheGroupInviteLinkAdd(Object? name);

  /// No description provided for @openedTheInviteLink.
  ///
  /// In en, this message translates to:
  /// **'opened the invite link'**
  String get openedTheInviteLink;

  /// No description provided for @opensWhatsappChooseMessageYourself.
  ///
  /// In en, this message translates to:
  /// **'Opens WhatsApp · choose \"Message yourself\"'**
  String get opensWhatsappChooseMessageYourself;

  /// No description provided for @operationalMetadataFromTheLinkupServer.
  ///
  /// In en, this message translates to:
  /// **'Operational metadata from the LinkUp server.'**
  String get operationalMetadataFromTheLinkupServer;

  /// No description provided for @operationalMetadataOnlyPasswordsPrivateKeys.
  ///
  /// In en, this message translates to:
  /// **'Operational metadata only. Passwords, private keys, message bodies, call audio and decrypted media are never exposed to this dashboard.'**
  String get operationalMetadataOnlyPasswordsPrivateKeys;

  /// No description provided for @operations.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get operations;

  /// No description provided for @operatorText.
  ///
  /// In en, this message translates to:
  /// **'Operator'**
  String get operatorText;

  /// No description provided for @option.
  ///
  /// In en, this message translates to:
  /// **'Option {i}'**
  String option(Object? i);

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @orScanWithTheCameraApp.
  ///
  /// In en, this message translates to:
  /// **'(or scan with the camera app)'**
  String get orScanWithTheCameraApp;

  /// No description provided for @orType.
  ///
  /// In en, this message translates to:
  /// **'or type:'**
  String get orType;

  /// No description provided for @orTypeIt.
  ///
  /// In en, this message translates to:
  /// **'Or type it'**
  String get orTypeIt;

  /// No description provided for @orWaitUntilAMemberIs.
  ///
  /// In en, this message translates to:
  /// **', or wait until a member is Online once.'**
  String get orWaitUntilAMemberIs;

  /// No description provided for @otherBrandTapToPick.
  ///
  /// In en, this message translates to:
  /// **'Other brand? Tap to pick'**
  String get otherBrandTapToPick;

  /// No description provided for @otherLinkupPhones.
  ///
  /// In en, this message translates to:
  /// **'{n} other LinkUp phones'**
  String otherLinkupPhones(Object? n);

  /// No description provided for @otherLinkupPhonesJoinThisOne.
  ///
  /// In en, this message translates to:
  /// **'Other LinkUp phones join this one. No internet is shared. {hotspotStatusText}'**
  String otherLinkupPhonesJoinThisOne(Object? hotspotStatusText);

  /// No description provided for @otherPhonesPixelMotorolaNokia.
  ///
  /// In en, this message translates to:
  /// **'Other phones (Pixel, Motorola, Nokia...)'**
  String get otherPhonesPixelMotorolaNokia;

  /// No description provided for @outgoing.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get outgoing;

  /// No description provided for @outsideTheDatesPhoneClock.
  ///
  /// In en, this message translates to:
  /// **'Outside the dates (phone clock)'**
  String get outsideTheDatesPhoneClock;

  /// No description provided for @overTheInternetThroughTheLinkup.
  ///
  /// In en, this message translates to:
  /// **'Over the internet, through the LinkUp server.'**
  String get overTheInternetThroughTheLinkup;

  /// No description provided for @overall.
  ///
  /// In en, this message translates to:
  /// **'Overall: {label}'**
  String overall(Object? label);

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @owner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get owner;

  /// No description provided for @ownerCanRead.
  ///
  /// In en, this message translates to:
  /// **'Owner can read'**
  String get ownerCanRead;

  /// No description provided for @ownerCanReadEveryOpenIs.
  ///
  /// In en, this message translates to:
  /// **'Owner can read; every open is saved'**
  String get ownerCanReadEveryOpenIs;

  /// No description provided for @ownerOnly.
  ///
  /// In en, this message translates to:
  /// **'Owner only'**
  String get ownerOnly;

  /// No description provided for @packetLoss.
  ///
  /// In en, this message translates to:
  /// **'{toStringAsFixed}% packet loss'**
  String packetLoss(Object? toStringAsFixed);

  /// No description provided for @packetsPassedOn.
  ///
  /// In en, this message translates to:
  /// **'Packets passed on'**
  String get packetsPassedOn;

  /// No description provided for @pairingCode.
  ///
  /// In en, this message translates to:
  /// **'Pairing code'**
  String get pairingCode;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get passwordChanged;

  /// No description provided for @passwordCopied.
  ///
  /// In en, this message translates to:
  /// **'Password copied'**
  String get passwordCopied;

  /// No description provided for @passwordHasACharacterThatIs.
  ///
  /// In en, this message translates to:
  /// **'Password has a character that is not allowed.'**
  String get passwordHasACharacterThatIs;

  /// No description provided for @passwordIsTooLong.
  ///
  /// In en, this message translates to:
  /// **'Password is too long.'**
  String get passwordIsTooLong;

  /// No description provided for @passwordMustBeAtLeast8.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters.'**
  String get passwordMustBeAtLeast8;

  /// No description provided for @passwordOf.
  ///
  /// In en, this message translates to:
  /// **'Password of @{username}'**
  String passwordOf(Object? username);

  /// No description provided for @passwords.
  ///
  /// In en, this message translates to:
  /// **'Passwords'**
  String get passwords;

  /// No description provided for @pasteCode.
  ///
  /// In en, this message translates to:
  /// **'Paste code'**
  String get pasteCode;

  /// No description provided for @pasteContactCode.
  ///
  /// In en, this message translates to:
  /// **'Paste contact code'**
  String get pasteContactCode;

  /// No description provided for @pasteGroupCode.
  ///
  /// In en, this message translates to:
  /// **'Paste group code'**
  String get pasteGroupCode;

  /// No description provided for @pasteItInAnyApp.
  ///
  /// In en, this message translates to:
  /// **'Paste it in any app'**
  String get pasteItInAnyApp;

  /// No description provided for @pasteTheSharedCodeTextHere.
  ///
  /// In en, this message translates to:
  /// **'Paste the shared code text here'**
  String get pasteTheSharedCodeTextHere;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @pending2.
  ///
  /// In en, this message translates to:
  /// **'Pending {pending}'**
  String pending2(Object? pending);

  /// No description provided for @pendingRecoveries.
  ///
  /// In en, this message translates to:
  /// **'Pending recoveries'**
  String get pendingRecoveries;

  /// No description provided for @pendingUntilEachPhoneDoesIt.
  ///
  /// In en, this message translates to:
  /// **'Pending until each phone does it'**
  String get pendingUntilEachPhoneDoesIt;

  /// No description provided for @pendingUntilEachPhoneDoesIt2.
  ///
  /// In en, this message translates to:
  /// **'{pendingCount} pending · until each phone does it'**
  String pendingUntilEachPhoneDoesIt2(Object? pendingCount);

  /// No description provided for @people.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get people;

  /// No description provided for @people2.
  ///
  /// In en, this message translates to:
  /// **'{n} people'**
  String people2(Object? n);

  /// No description provided for @peopleAreTyping.
  ///
  /// In en, this message translates to:
  /// **'{clean} people are typing…'**
  String peopleAreTyping(Object? clean);

  /// No description provided for @peopleMovingToANewPhone.
  ///
  /// In en, this message translates to:
  /// **'People moving to a new phone'**
  String get peopleMovingToANewPhone;

  /// No description provided for @peopleNearYouMustAskFirst.
  ///
  /// In en, this message translates to:
  /// **'People near you must **ask first**, and you accept or decline. A **QR code** still adds at once.'**
  String get peopleNearYouMustAskFirst;

  /// No description provided for @peopleNearby.
  ///
  /// In en, this message translates to:
  /// **'People nearby'**
  String get peopleNearby;

  /// No description provided for @peopleNearbyPhonesKnow.
  ///
  /// In en, this message translates to:
  /// **'People nearby phones know'**
  String get peopleNearbyPhonesKnow;

  /// No description provided for @peopleSignedIn.
  ///
  /// In en, this message translates to:
  /// **'People signed in'**
  String get peopleSignedIn;

  /// No description provided for @peopleWhoAlreadyHaveYouKeep.
  ///
  /// In en, this message translates to:
  /// **'People who already have you **keep you**. They see a \"Private\" label next to your name.'**
  String get peopleWhoAlreadyHaveYouKeep;

  /// No description provided for @peopleWithAnAccount.
  ///
  /// In en, this message translates to:
  /// **'People with an account'**
  String get peopleWithAnAccount;

  /// No description provided for @peopleYouBlockHereAreStopped.
  ///
  /// In en, this message translates to:
  /// **'People you block here are stopped on every phone.'**
  String get peopleYouBlockHereAreStopped;

  /// No description provided for @peopleYouCanAdd.
  ///
  /// In en, this message translates to:
  /// **'People you can add'**
  String get peopleYouCanAdd;

  /// No description provided for @percentagesAreLiveReadingsTheTick.
  ///
  /// In en, this message translates to:
  /// **'Percentages are live readings; the tick marks the alert threshold'**
  String get percentagesAreLiveReadingsTheTick;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @phone2.
  ///
  /// In en, this message translates to:
  /// **'Phone {number}'**
  String phone2(Object? number);

  /// No description provided for @phoneFullFree.
  ///
  /// In en, this message translates to:
  /// **'Phone: {usedPercent}% full · {free} free'**
  String phoneFullFree(Object? usedPercent, Object? free);

  /// No description provided for @phoneMasterPowerSavingLetLinkup.
  ///
  /// In en, this message translates to:
  /// **'Phone Master > Power saving: let LinkUp run in background'**
  String get phoneMasterPowerSavingLetLinkup;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @phoneNumberVisibility.
  ///
  /// In en, this message translates to:
  /// **'Phone number visibility'**
  String get phoneNumberVisibility;

  /// No description provided for @phoneRemoved.
  ///
  /// In en, this message translates to:
  /// **'Phone removed'**
  String get phoneRemoved;

  /// No description provided for @phoneToPhoneNoRouterNeeded.
  ///
  /// In en, this message translates to:
  /// **'Phone to phone, no router needed. Messages and calls go straight between your phones.'**
  String get phoneToPhoneNoRouterNeeded;

  /// No description provided for @phones.
  ///
  /// In en, this message translates to:
  /// **'Phones'**
  String get phones;

  /// No description provided for @phones2.
  ///
  /// In en, this message translates to:
  /// **'{carriers} phones'**
  String phones2(Object? carriers);

  /// No description provided for @phonesAroundYouWithLinkup.
  ///
  /// In en, this message translates to:
  /// **'Phones around you with LinkUp'**
  String get phonesAroundYouWithLinkup;

  /// No description provided for @phonesConfirmed.
  ///
  /// In en, this message translates to:
  /// **'{since} · phones confirmed'**
  String phonesConfirmed(Object? since);

  /// No description provided for @phonesGettingLinkup.
  ///
  /// In en, this message translates to:
  /// **'Phones getting LinkUp'**
  String get phonesGettingLinkup;

  /// No description provided for @phonesLinkedThisWay.
  ///
  /// In en, this message translates to:
  /// **'Phones linked this way'**
  String get phonesLinkedThisWay;

  /// No description provided for @phonesLive.
  ///
  /// In en, this message translates to:
  /// **'Phones live'**
  String get phonesLive;

  /// No description provided for @phonesNear.
  ///
  /// In en, this message translates to:
  /// **'Phones near'**
  String get phonesNear;

  /// No description provided for @phonesRightNow.
  ///
  /// In en, this message translates to:
  /// **'Phones right now'**
  String get phonesRightNow;

  /// No description provided for @phonesSeenNearbyThatThisAffects.
  ///
  /// In en, this message translates to:
  /// **'Phones seen nearby that this affects: {affects}.'**
  String phonesSeenNearbyThatThisAffects(Object? affects);

  /// No description provided for @phonesShowHereWhenTheyAre.
  ///
  /// In en, this message translates to:
  /// **'Phones show here when they are linked.'**
  String get phonesShowHereWhenTheyAre;

  /// No description provided for @phonesThatGotTheRule.
  ///
  /// In en, this message translates to:
  /// **'phones that got the rule'**
  String get phonesThatGotTheRule;

  /// No description provided for @phonesThatHavenTAnsweredYet.
  ///
  /// In en, this message translates to:
  /// **'Phones that haven\'t answered yet won\'t answer.'**
  String get phonesThatHavenTAnsweredYet;

  /// No description provided for @phonesThatHavenTDoneIt.
  ///
  /// In en, this message translates to:
  /// **'Phones that haven\'t done it yet won\'t do it. Phones that did it stay as they are.'**
  String get phonesThatHavenTDoneIt;

  /// No description provided for @phonesWiFiRulesRecovery.
  ///
  /// In en, this message translates to:
  /// **'phones, Wi-Fi rules, recovery'**
  String get phonesWiFiRulesRecovery;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @pick.
  ///
  /// In en, this message translates to:
  /// **'Pick'**
  String get pick;

  /// No description provided for @pickAUsernameYourFriendsKnow.
  ///
  /// In en, this message translates to:
  /// **'Pick a username your friends know'**
  String get pickAUsernameYourFriendsKnow;

  /// No description provided for @pickAsManyChatsAsYou.
  ///
  /// In en, this message translates to:
  /// **'Pick as many chats as you want. Photos and videos are sent again as new files.'**
  String get pickAsManyChatsAsYou;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// No description provided for @pinForHowLong.
  ///
  /// In en, this message translates to:
  /// **'Pin for how long?'**
  String get pinForHowLong;

  /// No description provided for @pinnedAMessage.
  ///
  /// In en, this message translates to:
  /// **'{actor} pinned a message'**
  String pinnedAMessage(Object? actor);

  /// No description provided for @pinnedMessage.
  ///
  /// In en, this message translates to:
  /// **'Pinned message'**
  String get pinnedMessage;

  /// No description provided for @platform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get platform;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @played.
  ///
  /// In en, this message translates to:
  /// **'Played'**
  String get played;

  /// No description provided for @playingInMiniPlayer.
  ///
  /// In en, this message translates to:
  /// **'Playing in mini player'**
  String get playingInMiniPlayer;

  /// No description provided for @pleaseWaitAFewSeconds.
  ///
  /// In en, this message translates to:
  /// **'Please wait a few seconds'**
  String get pleaseWaitAFewSeconds;

  /// No description provided for @pointAtThisCode.
  ///
  /// In en, this message translates to:
  /// **'Point at this code'**
  String get pointAtThisCode;

  /// No description provided for @pointAtThisCodeOrPick.
  ///
  /// In en, this message translates to:
  /// **'Point at this code, or pick this picture'**
  String get pointAtThisCodeOrPick;

  /// No description provided for @pointAtYourFriendSQr.
  ///
  /// In en, this message translates to:
  /// **'Point at your friend\'s QR code'**
  String get pointAtYourFriendSQr;

  /// No description provided for @poll.
  ///
  /// In en, this message translates to:
  /// **'📊 Poll: {question}'**
  String poll(Object? question);

  /// No description provided for @pollChooseOne.
  ///
  /// In en, this message translates to:
  /// **'POLL · CHOOSE ONE'**
  String get pollChooseOne;

  /// No description provided for @pollChooseOneOrMore.
  ///
  /// In en, this message translates to:
  /// **'POLL · CHOOSE ONE OR MORE'**
  String get pollChooseOneOrMore;

  /// No description provided for @poor.
  ///
  /// In en, this message translates to:
  /// **'Poor'**
  String get poor;

  /// No description provided for @preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get preparing;

  /// No description provided for @preparingLogs.
  ///
  /// In en, this message translates to:
  /// **'Preparing logs...'**
  String get preparingLogs;

  /// No description provided for @pressBackAgainToExit.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get pressBackAgainToExit;

  /// No description provided for @pretendOldBuild.
  ///
  /// In en, this message translates to:
  /// **'Pretend old build'**
  String get pretendOldBuild;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @privacyAccess.
  ///
  /// In en, this message translates to:
  /// **'Privacy & access'**
  String get privacyAccess;

  /// No description provided for @privacyAccess2.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Access'**
  String get privacyAccess2;

  /// No description provided for @privacyBoundary.
  ///
  /// In en, this message translates to:
  /// **'Privacy boundary'**
  String get privacyBoundary;

  /// No description provided for @privacySecurity.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Security'**
  String get privacySecurity;

  /// No description provided for @privacySettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Privacy settings saved'**
  String get privacySettingsSaved;

  /// No description provided for @private.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get private;

  /// No description provided for @privateAndSecure.
  ///
  /// In en, this message translates to:
  /// **'Private and secure'**
  String get privateAndSecure;

  /// No description provided for @privateChat.
  ///
  /// In en, this message translates to:
  /// **'Private chat'**
  String get privateChat;

  /// No description provided for @privateKeys.
  ///
  /// In en, this message translates to:
  /// **'Private keys'**
  String get privateKeys;

  /// No description provided for @privateProfile.
  ///
  /// In en, this message translates to:
  /// **'Private profile'**
  String get privateProfile;

  /// No description provided for @privateThingsStayPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private things stay private'**
  String get privateThingsStayPrivate;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @profileInformation.
  ///
  /// In en, this message translates to:
  /// **'Profile information'**
  String get profileInformation;

  /// No description provided for @profilePhoto.
  ///
  /// In en, this message translates to:
  /// **'Profile photo'**
  String get profilePhoto;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved'**
  String get profileSaved;

  /// No description provided for @protectYourAccountWhenThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Protect your account when this phone is lost.'**
  String get protectYourAccountWhenThisPhone;

  /// No description provided for @publicKey.
  ///
  /// In en, this message translates to:
  /// **'Public key: {currentPublicKey}'**
  String publicKey(Object? currentPublicKey);

  /// No description provided for @publicKeyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Public key unavailable'**
  String get publicKeyUnavailable;

  /// No description provided for @qrImportFailed.
  ///
  /// In en, this message translates to:
  /// **'QR import failed ({stage}): {e}'**
  String qrImportFailed(Object? stage, Object? e);

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get quickActions;

  /// No description provided for @reached.
  ///
  /// In en, this message translates to:
  /// **'Reached {done}'**
  String reached(Object? done);

  /// No description provided for @reachedPhone.
  ///
  /// In en, this message translates to:
  /// **'Reached {reached} phone{s}'**
  String reachedPhone(Object? reached, Object? s);

  /// No description provided for @reachedThePhoneItMustReach.
  ///
  /// In en, this message translates to:
  /// **'Reached the phone - it must reach the server once'**
  String get reachedThePhoneItMustReach;

  /// No description provided for @reachedThePhoneItMustReach2.
  ///
  /// In en, this message translates to:
  /// **'reached the phone · it must reach the server once'**
  String get reachedThePhoneItMustReach2;

  /// No description provided for @react.
  ///
  /// In en, this message translates to:
  /// **'React {emoji}'**
  String react(Object? emoji);

  /// No description provided for @reactions.
  ///
  /// In en, this message translates to:
  /// **'Reactions'**
  String get reactions;

  /// No description provided for @read.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get read;

  /// No description provided for @readByOf.
  ///
  /// In en, this message translates to:
  /// **'Read by {read} of {total}'**
  String readByOf(Object? read, Object? total);

  /// No description provided for @readChatsOnlyUpdateToSend.
  ///
  /// In en, this message translates to:
  /// **'Read chats only. Update to send and call.'**
  String get readChatsOnlyUpdateToSend;

  /// No description provided for @readOnlyAtOnce.
  ///
  /// In en, this message translates to:
  /// **'Read only at once'**
  String get readOnlyAtOnce;

  /// No description provided for @readReceipts.
  ///
  /// In en, this message translates to:
  /// **'Read receipts'**
  String get readReceipts;

  /// No description provided for @readReceiptsAreOffTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Read receipts are off. Turn on in Settings › Privacy.'**
  String get readReceiptsAreOffTurnOn;

  /// No description provided for @ready.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get ready;

  /// No description provided for @readyToSend.
  ///
  /// In en, this message translates to:
  /// **'Ready to send'**
  String get readyToSend;

  /// No description provided for @readyToUpdate.
  ///
  /// In en, this message translates to:
  /// **'Ready to update'**
  String get readyToUpdate;

  /// No description provided for @reason.
  ///
  /// In en, this message translates to:
  /// **'Reason: {rejectedReason}'**
  String reason(Object? rejectedReason);

  /// No description provided for @reasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get reasonOptional;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get recentActivity;

  /// No description provided for @recentChats.
  ///
  /// In en, this message translates to:
  /// **'RECENT CHATS'**
  String get recentChats;

  /// No description provided for @recentSecurityEvents.
  ///
  /// In en, this message translates to:
  /// **'RECENT SECURITY EVENTS'**
  String get recentSecurityEvents;

  /// No description provided for @recentsLockLinkupTapItsIcon.
  ///
  /// In en, this message translates to:
  /// **'Recents: lock LinkUp (tap its icon, choose Lock)'**
  String get recentsLockLinkupTapItsIcon;

  /// No description provided for @recommendedMessagesArriveInstantly.
  ///
  /// In en, this message translates to:
  /// **'Recommended — messages arrive instantly'**
  String get recommendedMessagesArriveInstantly;

  /// No description provided for @recommendedWhenReplacingTheOldPhone.
  ///
  /// In en, this message translates to:
  /// **'Recommended when replacing the old phone.'**
  String get recommendedWhenReplacingTheOldPhone;

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get reconnecting;

  /// No description provided for @reconnecting2.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get reconnecting2;

  /// No description provided for @recoverYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Recover your account'**
  String get recoverYourAccount;

  /// No description provided for @recovery.
  ///
  /// In en, this message translates to:
  /// **'Recovery {v}'**
  String recovery(Object? v);

  /// No description provided for @recovery2.
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get recovery2;

  /// No description provided for @recoveryApproved.
  ///
  /// In en, this message translates to:
  /// **'Recovery approved'**
  String get recoveryApproved;

  /// No description provided for @recoveryAsked.
  ///
  /// In en, this message translates to:
  /// **'Recovery asked'**
  String get recoveryAsked;

  /// No description provided for @recoveryAttempts.
  ///
  /// In en, this message translates to:
  /// **'{recoveryAttempts} recovery attempts'**
  String recoveryAttempts(Object? recoveryAttempts);

  /// No description provided for @recoveryCanLook.
  ///
  /// In en, this message translates to:
  /// **'recovery, can look'**
  String get recoveryCanLook;

  /// No description provided for @recoveryCode.
  ///
  /// In en, this message translates to:
  /// **'RECOVERY CODE'**
  String get recoveryCode;

  /// No description provided for @recoveryCode2.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get recoveryCode2;

  /// No description provided for @recoveryCodeSaved.
  ///
  /// In en, this message translates to:
  /// **'Recovery code saved'**
  String get recoveryCodeSaved;

  /// No description provided for @recoveryCodeTurnedOff.
  ///
  /// In en, this message translates to:
  /// **'Recovery code turned off'**
  String get recoveryCodeTurnedOff;

  /// No description provided for @recoveryCompleted.
  ///
  /// In en, this message translates to:
  /// **'Recovery completed'**
  String get recoveryCompleted;

  /// No description provided for @recoveryCompleted2.
  ///
  /// In en, this message translates to:
  /// **'Recovery completed.'**
  String get recoveryCompleted2;

  /// No description provided for @recoveryCredentialExpires.
  ///
  /// In en, this message translates to:
  /// **'Recovery credential expires'**
  String get recoveryCredentialExpires;

  /// No description provided for @recoveryExpired.
  ///
  /// In en, this message translates to:
  /// **'Recovery expired'**
  String get recoveryExpired;

  /// No description provided for @recoveryFinished.
  ///
  /// In en, this message translates to:
  /// **'Recovery finished'**
  String get recoveryFinished;

  /// No description provided for @recoveryNewCode.
  ///
  /// In en, this message translates to:
  /// **'Recovery new code'**
  String get recoveryNewCode;

  /// No description provided for @recoveryQueue.
  ///
  /// In en, this message translates to:
  /// **'Recovery queue'**
  String get recoveryQueue;

  /// No description provided for @recoveryRejected.
  ///
  /// In en, this message translates to:
  /// **'Recovery rejected'**
  String get recoveryRejected;

  /// No description provided for @recoveryStatus.
  ///
  /// In en, this message translates to:
  /// **'Recovery status'**
  String get recoveryStatus;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @refreshData.
  ///
  /// In en, this message translates to:
  /// **'Refresh data'**
  String get refreshData;

  /// No description provided for @refreshEvery.
  ///
  /// In en, this message translates to:
  /// **'Refresh every'**
  String get refreshEvery;

  /// No description provided for @refreshNow.
  ///
  /// In en, this message translates to:
  /// **'Refresh now'**
  String get refreshNow;

  /// No description provided for @refreshTimeAlertsBackup.
  ///
  /// In en, this message translates to:
  /// **'Refresh time, alerts, backup'**
  String get refreshTimeAlertsBackup;

  /// No description provided for @refreshUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Refresh unavailable'**
  String get refreshUnavailable;

  /// No description provided for @registered.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get registered;

  /// No description provided for @registeredDevices.
  ///
  /// In en, this message translates to:
  /// **'Registered devices'**
  String get registeredDevices;

  /// No description provided for @registeredHardware.
  ///
  /// In en, this message translates to:
  /// **'Registered hardware'**
  String get registeredHardware;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @rejectThisRequest.
  ///
  /// In en, this message translates to:
  /// **'Reject this request?'**
  String get rejectThisRequest;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @rejectedRecoveryFor.
  ///
  /// In en, this message translates to:
  /// **'{admin} rejected recovery for {target}'**
  String rejectedRecoveryFor(Object? admin, Object? target);

  /// No description provided for @relayLinksNotContacts.
  ///
  /// In en, this message translates to:
  /// **'Relay links (not contacts)'**
  String get relayLinksNotContacts;

  /// No description provided for @relaysForOthers.
  ///
  /// In en, this message translates to:
  /// **'relays for others'**
  String get relaysForOthers;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @removeContact.
  ///
  /// In en, this message translates to:
  /// **'Remove contact'**
  String get removeContact;

  /// No description provided for @removeFrom.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from \"{groupName}\"?'**
  String removeFrom(Object? name, Object? groupName);

  /// No description provided for @removeFromGroup.
  ///
  /// In en, this message translates to:
  /// **'Remove from group'**
  String get removeFromGroup;

  /// No description provided for @removeFromThisGroup.
  ///
  /// In en, this message translates to:
  /// **'Remove {label} from this group?'**
  String removeFromThisGroup(Object? label);

  /// No description provided for @removeFromYourContacts.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from your contacts?'**
  String removeFromYourContacts(Object? name);

  /// No description provided for @removeMember.
  ///
  /// In en, this message translates to:
  /// **'Remove member'**
  String get removeMember;

  /// No description provided for @removeMember2.
  ///
  /// In en, this message translates to:
  /// **'Remove member?'**
  String get removeMember2;

  /// No description provided for @removeOption.
  ///
  /// In en, this message translates to:
  /// **'Remove option'**
  String get removeOption;

  /// No description provided for @removePhone.
  ///
  /// In en, this message translates to:
  /// **'Remove phone'**
  String get removePhone;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get removePhoto;

  /// No description provided for @removeRule.
  ///
  /// In en, this message translates to:
  /// **'Remove rule'**
  String get removeRule;

  /// No description provided for @removeThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Remove this phone?'**
  String get removeThisPhone;

  /// No description provided for @removeVerifiedMark.
  ///
  /// In en, this message translates to:
  /// **'Remove verified mark'**
  String get removeVerifiedMark;

  /// No description provided for @removeYour.
  ///
  /// In en, this message translates to:
  /// **'Remove your {emoji}'**
  String removeYour(Object? emoji);

  /// No description provided for @removed.
  ///
  /// In en, this message translates to:
  /// **'{name} removed'**
  String removed(Object? name);

  /// No description provided for @removed2.
  ///
  /// In en, this message translates to:
  /// **'{label} removed.'**
  String removed2(Object? label);

  /// No description provided for @removed3.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get removed3;

  /// No description provided for @removed4.
  ///
  /// In en, this message translates to:
  /// **'{actor} removed {targets}'**
  String removed4(Object? actor, Object? targets);

  /// No description provided for @removedAdminFrom.
  ///
  /// In en, this message translates to:
  /// **'{admin} removed admin from {target}'**
  String removedAdminFrom(Object? admin, Object? target);

  /// No description provided for @removedToSaveSpace.
  ///
  /// In en, this message translates to:
  /// **'Removed to save space'**
  String get removedToSaveSpace;

  /// No description provided for @removedToSaveSpaceAskTo.
  ///
  /// In en, this message translates to:
  /// **'Removed to save space. Ask {sender} to send it again.'**
  String removedToSaveSpaceAskTo(Object? sender);

  /// No description provided for @removesPhotosVideosAndDocumentsAs.
  ///
  /// In en, this message translates to:
  /// **'Removes photos, videos and documents as if they were 11 days old and the phone 80% full. Voice notes and unsent media stay. The messages stay with a small picture.'**
  String get removesPhotosVideosAndDocumentsAs;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @renamePhone.
  ///
  /// In en, this message translates to:
  /// **'Rename phone'**
  String get renamePhone;

  /// No description provided for @renamed.
  ///
  /// In en, this message translates to:
  /// **'{admin} renamed {target}'**
  String renamed(Object? admin, Object? target);

  /// No description provided for @replaced.
  ///
  /// In en, this message translates to:
  /// **'Replaced'**
  String get replaced;

  /// No description provided for @replacedByANewerAction.
  ///
  /// In en, this message translates to:
  /// **'Replaced by a newer action'**
  String get replacedByANewerAction;

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @request.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get request;

  /// No description provided for @requestDeclined.
  ///
  /// In en, this message translates to:
  /// **'Request declined'**
  String get requestDeclined;

  /// No description provided for @requestSent.
  ///
  /// In en, this message translates to:
  /// **'Request sent'**
  String get requestSent;

  /// No description provided for @requestSentByTheServer.
  ///
  /// In en, this message translates to:
  /// **'Request sent by the server'**
  String get requestSentByTheServer;

  /// No description provided for @requestSentNeedsToAccept.
  ///
  /// In en, this message translates to:
  /// **'Request sent. {who} needs to accept.'**
  String requestSentNeedsToAccept(Object? who);

  /// No description provided for @requestSentToNearbyPhones.
  ///
  /// In en, this message translates to:
  /// **'Request sent to nearby phones'**
  String get requestSentToNearbyPhones;

  /// No description provided for @requestStatus.
  ///
  /// In en, this message translates to:
  /// **'Request: {substring}…\nStatus: {status}'**
  String requestStatus(Object? substring, Object? status);

  /// No description provided for @requestSubmittedAskTheLinkupAdministrator.
  ///
  /// In en, this message translates to:
  /// **'Request submitted. Ask the LinkUp administrator to approve it and provide the recovery code.'**
  String get requestSubmittedAskTheLinkupAdministrator;

  /// No description provided for @requested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get requested;

  /// No description provided for @requested2.
  ///
  /// In en, this message translates to:
  /// **'Requested ✓'**
  String get requested2;

  /// No description provided for @requests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requests;

  /// No description provided for @requests2.
  ///
  /// In en, this message translates to:
  /// **'Requests {requests}'**
  String requests2(Object? requests);

  /// No description provided for @requestsToJoin.
  ///
  /// In en, this message translates to:
  /// **'{n} requests to join'**
  String requestsToJoin(Object? n);

  /// No description provided for @requestsWaitHereUntilAPhone.
  ///
  /// In en, this message translates to:
  /// **'Requests wait here until a phone answers. There is no time limit.'**
  String get requestsWaitHereUntilAPhone;

  /// No description provided for @requiredText.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredText;

  /// No description provided for @requiresTheRuntimeMetricsSampler.
  ///
  /// In en, this message translates to:
  /// **'Requires the runtime metrics sampler'**
  String get requiresTheRuntimeMetricsSampler;

  /// No description provided for @resend.
  ///
  /// In en, this message translates to:
  /// **'Resend'**
  String get resend;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @resetCode.
  ///
  /// In en, this message translates to:
  /// **'Reset code'**
  String get resetCode;

  /// No description provided for @resetLink.
  ///
  /// In en, this message translates to:
  /// **'Reset link'**
  String get resetLink;

  /// No description provided for @resetLink2.
  ///
  /// In en, this message translates to:
  /// **'Reset link?'**
  String get resetLink2;

  /// No description provided for @resetSetup.
  ///
  /// In en, this message translates to:
  /// **'Reset setup'**
  String get resetSetup;

  /// No description provided for @resetSetup2.
  ///
  /// In en, this message translates to:
  /// **'Reset setup?'**
  String get resetSetup2;

  /// No description provided for @resetYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get resetYourPassword;

  /// No description provided for @responseBytesServedPerBucket.
  ///
  /// In en, this message translates to:
  /// **'Response bytes served per bucket'**
  String get responseBytesServedPerBucket;

  /// No description provided for @restoreAccountData.
  ///
  /// In en, this message translates to:
  /// **'Restore account data'**
  String get restoreAccountData;

  /// No description provided for @restoreAccountDataEncryptedKeys.
  ///
  /// In en, this message translates to:
  /// **'Restore account data + encrypted keys'**
  String get restoreAccountDataEncryptedKeys;

  /// No description provided for @restoreEncryptedIdentityBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore encrypted identity backup'**
  String get restoreEncryptedIdentityBackup;

  /// No description provided for @restoreEncryptedIdentityKeys.
  ///
  /// In en, this message translates to:
  /// **'Restore encrypted identity keys?'**
  String get restoreEncryptedIdentityKeys;

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed'**
  String get restoreFailed;

  /// No description provided for @restoreKeys.
  ///
  /// In en, this message translates to:
  /// **'Restore keys'**
  String get restoreKeys;

  /// No description provided for @restoringYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Restoring your account'**
  String get restoringYourAccount;

  /// No description provided for @results.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get results;

  /// No description provided for @resultsFor.
  ///
  /// In en, this message translates to:
  /// **'Results for \"{searchQuery}\"'**
  String resultsFor(Object? searchQuery);

  /// No description provided for @resumingYourRecoveryRequest.
  ///
  /// In en, this message translates to:
  /// **'Resuming your recovery request…'**
  String get resumingYourRecoveryRequest;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @returnText.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get returnText;

  /// No description provided for @reviewReports.
  ///
  /// In en, this message translates to:
  /// **'Review reports'**
  String get reviewReports;

  /// No description provided for @revokeOldPhoneAfterTransfer.
  ///
  /// In en, this message translates to:
  /// **'Revoke old phone after transfer'**
  String get revokeOldPhoneAfterTransfer;

  /// No description provided for @revoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get revoked;

  /// No description provided for @revokedDevices.
  ///
  /// In en, this message translates to:
  /// **'Revoked devices'**
  String get revokedDevices;

  /// No description provided for @rightsCheckedByTheServer.
  ///
  /// In en, this message translates to:
  /// **'Rights checked by the server'**
  String get rightsCheckedByTheServer;

  /// No description provided for @ringing.
  ///
  /// In en, this message translates to:
  /// **'Ringing…'**
  String get ringing;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @rollupsComputedFromPlatformTablesAnd.
  ///
  /// In en, this message translates to:
  /// **'Rollups computed from platform tables and the runtime sampler'**
  String get rollupsComputedFromPlatformTablesAnd;

  /// No description provided for @rotateIdentityKey.
  ///
  /// In en, this message translates to:
  /// **'Rotate identity key'**
  String get rotateIdentityKey;

  /// No description provided for @rotating.
  ///
  /// In en, this message translates to:
  /// **'Rotating…'**
  String get rotating;

  /// No description provided for @routerEchoWiFiDirectAnd.
  ///
  /// In en, this message translates to:
  /// **'Router echo, Wi-Fi Direct and mesh checks'**
  String get routerEchoWiFiDirectAnd;

  /// No description provided for @routes.
  ///
  /// In en, this message translates to:
  /// **'Routes ({routes})'**
  String routes(Object? routes);

  /// No description provided for @ruleRemovedForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Rule removed for everyone.'**
  String get ruleRemovedForEveryone;

  /// No description provided for @runTest.
  ///
  /// In en, this message translates to:
  /// **'Run test'**
  String get runTest;

  /// No description provided for @runningFor.
  ///
  /// In en, this message translates to:
  /// **'Running for'**
  String get runningFor;

  /// No description provided for @runningNow.
  ///
  /// In en, this message translates to:
  /// **'Running now'**
  String get runningNow;

  /// No description provided for @sAccountIsClosedCanT.
  ///
  /// In en, this message translates to:
  /// **'{name}’s account is closed. {name2} can’t sign in.'**
  String sAccountIsClosedCanT(Object? name, Object? name2);

  /// No description provided for @sPhoneHasNotGotThe.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s phone has not got the group yet. It is added by itself when {name2} is Nearby (Wi-Fi Direct or mesh) or Online.'**
  String sPhoneHasNotGotThe(Object? name, Object? name2);

  /// No description provided for @sSecurityCodeChanged.
  ///
  /// In en, this message translates to:
  /// **'{v}\'s security code changed'**
  String sSecurityCodeChanged(Object? v);

  /// No description provided for @sSecurityCodeChangedTapTo.
  ///
  /// In en, this message translates to:
  /// **'{device}\'s security code changed. Tap to check.'**
  String sSecurityCodeChangedTapTo(Object? device);

  /// No description provided for @sSecurityCodeChangedTapTo2.
  ///
  /// In en, this message translates to:
  /// **'{device}\'s security code changed. Tap to learn more.'**
  String sSecurityCodeChangedTapTo2(Object? device);

  /// No description provided for @sSecurityCodeIsNotReady.
  ///
  /// In en, this message translates to:
  /// **'{v}\'s security code is not ready yet. It shows after you have chatted once nearby or over the server.'**
  String sSecurityCodeIsNotReady(Object? v);

  /// No description provided for @safety.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get safety;

  /// No description provided for @sajjad.
  ///
  /// In en, this message translates to:
  /// **'Sajjad'**
  String get sajjad;

  /// No description provided for @sameWiFi.
  ///
  /// In en, this message translates to:
  /// **'same Wi-Fi'**
  String get sameWiFi;

  /// No description provided for @sat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get sat;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @saveContactAs.
  ///
  /// In en, this message translates to:
  /// **'Save contact as'**
  String get saveContactAs;

  /// No description provided for @saveForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Save for everyone'**
  String get saveForEveryone;

  /// No description provided for @saveItNowTheOldOne.
  ///
  /// In en, this message translates to:
  /// **'Save it now. The old one no longer works.'**
  String get saveItNowTheOldOne;

  /// No description provided for @saveOnWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'Save on WhatsApp'**
  String get saveOnWhatsapp;

  /// No description provided for @saveRule.
  ///
  /// In en, this message translates to:
  /// **'Save rule'**
  String get saveRule;

  /// No description provided for @saveStaysOffUntilTheNumber.
  ///
  /// In en, this message translates to:
  /// **'{phoneHint256}. Save stays off until the number is right.'**
  String saveStaysOffUntilTheNumber(Object? phoneHint256);

  /// No description provided for @saveToPhone.
  ///
  /// In en, this message translates to:
  /// **'Save to phone'**
  String get saveToPhone;

  /// No description provided for @saveYourNewRecoveryCodeNow.
  ///
  /// In en, this message translates to:
  /// **'Save your new recovery code now.'**
  String get saveYourNewRecoveryCodeNow;

  /// No description provided for @saveYourRecoveryCode.
  ///
  /// In en, this message translates to:
  /// **'Save your recovery code'**
  String get saveYourRecoveryCode;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @saved2.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get saved2;

  /// No description provided for @saved3.
  ///
  /// In en, this message translates to:
  /// **'{size} · Saved'**
  String saved3(Object? size);

  /// No description provided for @savedItIsSpreadingToNearby.
  ///
  /// In en, this message translates to:
  /// **'Saved. It is spreading to nearby phones.'**
  String get savedItIsSpreadingToNearby;

  /// No description provided for @savedLocallyWillSyncWhenAvailable.
  ///
  /// In en, this message translates to:
  /// **'Saved locally; will sync when available'**
  String get savedLocallyWillSyncWhenAvailable;

  /// No description provided for @savedOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone'**
  String get savedOnThisPhone;

  /// No description provided for @savedToDownloadLinkup.
  ///
  /// In en, this message translates to:
  /// **'Saved to Download › LinkUp'**
  String get savedToDownloadLinkup;

  /// No description provided for @savedToGalleryLinkup.
  ///
  /// In en, this message translates to:
  /// **'Saved to Gallery › LinkUp'**
  String get savedToGalleryLinkup;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @savingPhoto.
  ///
  /// In en, this message translates to:
  /// **'Saving photo…'**
  String get savingPhoto;

  /// No description provided for @scanAGroupCode.
  ///
  /// In en, this message translates to:
  /// **'Scan a group code'**
  String get scanAGroupCode;

  /// No description provided for @scanInstead.
  ///
  /// In en, this message translates to:
  /// **'Scan instead'**
  String get scanInstead;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQrCode;

  /// No description provided for @scanSCode.
  ///
  /// In en, this message translates to:
  /// **'Scan {v}\'s code'**
  String scanSCode(Object? v);

  /// No description provided for @scanSecurityCode.
  ///
  /// In en, this message translates to:
  /// **'Scan security code'**
  String get scanSecurityCode;

  /// No description provided for @scanTheQrShownOnYour.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR shown on your old phone.'**
  String get scanTheQrShownOnYour;

  /// No description provided for @scanWithTheCameraAppNot.
  ///
  /// In en, this message translates to:
  /// **'Scan with the camera app,\nnot the Wi-Fi scanner'**
  String get scanWithTheCameraAppNot;

  /// No description provided for @scannedTheGroupQr.
  ///
  /// In en, this message translates to:
  /// **'scanned the group QR'**
  String get scannedTheGroupQr;

  /// No description provided for @scannedTheQr.
  ///
  /// In en, this message translates to:
  /// **'scanned the QR'**
  String get scannedTheQr;

  /// No description provided for @screenStaysOnWhileSharing.
  ///
  /// In en, this message translates to:
  /// **'Screen stays on while sharing'**
  String get screenStaysOnWhileSharing;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @search2.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get search2;

  /// No description provided for @searchChatsAndMessages.
  ///
  /// In en, this message translates to:
  /// **'Search chats and messages'**
  String get searchChatsAndMessages;

  /// No description provided for @searchFriends.
  ///
  /// In en, this message translates to:
  /// **'Search friends'**
  String get searchFriends;

  /// No description provided for @searchMessages.
  ///
  /// In en, this message translates to:
  /// **'Search messages'**
  String get searchMessages;

  /// No description provided for @searchModules.
  ///
  /// In en, this message translates to:
  /// **'Search modules…'**
  String get searchModules;

  /// No description provided for @searchName.
  ///
  /// In en, this message translates to:
  /// **'Search name'**
  String get searchName;

  /// No description provided for @searchNameOrId.
  ///
  /// In en, this message translates to:
  /// **'Search name or id'**
  String get searchNameOrId;

  /// No description provided for @searchNameOrUsername.
  ///
  /// In en, this message translates to:
  /// **'Search name or @username'**
  String get searchNameOrUsername;

  /// No description provided for @searchPeople.
  ///
  /// In en, this message translates to:
  /// **'Search people'**
  String get searchPeople;

  /// No description provided for @searchPhoneOrNextHop.
  ///
  /// In en, this message translates to:
  /// **'Search phone or next hop'**
  String get searchPhoneOrNextHop;

  /// No description provided for @searchPhoneOrOwner.
  ///
  /// In en, this message translates to:
  /// **'Search phone or owner'**
  String get searchPhoneOrOwner;

  /// No description provided for @searchUsersDevices.
  ///
  /// In en, this message translates to:
  /// **'Search users, devices…'**
  String get searchUsersDevices;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching'**
  String get searching;

  /// No description provided for @searchingForConnection.
  ///
  /// In en, this message translates to:
  /// **'Searching for connection'**
  String get searchingForConnection;

  /// No description provided for @secondPerson.
  ///
  /// In en, this message translates to:
  /// **'Second person'**
  String get secondPerson;

  /// No description provided for @secureLocalFirstMessaging.
  ///
  /// In en, this message translates to:
  /// **'Secure, local-first messaging'**
  String get secureLocalFirstMessaging;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @securityAlerts.
  ///
  /// In en, this message translates to:
  /// **'Security alerts'**
  String get securityAlerts;

  /// No description provided for @securityAndOperationalEventsAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Security and operational events appear here as the server records them.'**
  String get securityAndOperationalEventsAppearHere;

  /// No description provided for @securityCenter.
  ///
  /// In en, this message translates to:
  /// **'Security center'**
  String get securityCenter;

  /// No description provided for @securityCenter2.
  ///
  /// In en, this message translates to:
  /// **'Security Center'**
  String get securityCenter2;

  /// No description provided for @securityCode.
  ///
  /// In en, this message translates to:
  /// **'Security code'**
  String get securityCode;

  /// No description provided for @securityCodeChanged.
  ///
  /// In en, this message translates to:
  /// **'Security code changed'**
  String get securityCodeChanged;

  /// No description provided for @securityEvent.
  ///
  /// In en, this message translates to:
  /// **'Security event'**
  String get securityEvent;

  /// No description provided for @securityKey.
  ///
  /// In en, this message translates to:
  /// **'Security key'**
  String get securityKey;

  /// No description provided for @securityOverview.
  ///
  /// In en, this message translates to:
  /// **'Security overview'**
  String get securityOverview;

  /// No description provided for @securityWarning.
  ///
  /// In en, this message translates to:
  /// **'security warning'**
  String get securityWarning;

  /// No description provided for @seeAndRemovePhonesSignedIn.
  ///
  /// In en, this message translates to:
  /// **'See and remove phones signed in'**
  String get seeAndRemovePhonesSignedIn;

  /// No description provided for @seeAndUnblockPeopleYouBlocked.
  ///
  /// In en, this message translates to:
  /// **'See and unblock people you blocked'**
  String get seeAndUnblockPeopleYouBlocked;

  /// No description provided for @seen.
  ///
  /// In en, this message translates to:
  /// **'Seen'**
  String get seen;

  /// No description provided for @seen2.
  ///
  /// In en, this message translates to:
  /// **'seen {a}'**
  String seen2(Object? a);

  /// No description provided for @seenBefore.
  ///
  /// In en, this message translates to:
  /// **'Seen before'**
  String get seenBefore;

  /// No description provided for @seenDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'seen {d} days ago'**
  String seenDaysAgo(Object? d);

  /// No description provided for @seenHAgo.
  ///
  /// In en, this message translates to:
  /// **'seen {d} h ago'**
  String seenHAgo(Object? d);

  /// No description provided for @seenJustNow.
  ///
  /// In en, this message translates to:
  /// **'seen just now'**
  String get seenJustNow;

  /// No description provided for @seenMinAgo.
  ///
  /// In en, this message translates to:
  /// **'Seen {s} min ago'**
  String seenMinAgo(Object? s);

  /// No description provided for @seenMinAgo2.
  ///
  /// In en, this message translates to:
  /// **'seen {d} min ago'**
  String seenMinAgo2(Object? d);

  /// No description provided for @seenNearby.
  ///
  /// In en, this message translates to:
  /// **'Seen nearby: {join}'**
  String seenNearby(Object? join);

  /// No description provided for @seenNearbyNoneYet.
  ///
  /// In en, this message translates to:
  /// **'Seen nearby: none yet'**
  String get seenNearbyNoneYet;

  /// No description provided for @seenSAgo.
  ///
  /// In en, this message translates to:
  /// **'Seen {s} s ago'**
  String seenSAgo(Object? s);

  /// No description provided for @seenYesterday.
  ///
  /// In en, this message translates to:
  /// **'seen yesterday'**
  String get seenYesterday;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @selectedUpTo.
  ///
  /// In en, this message translates to:
  /// **'{picked} selected · up to {kNewGroupMax}'**
  String selectedUpTo(Object? picked, Object? kNewGroupMax);

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @sendAMessageOrShareA.
  ///
  /// In en, this message translates to:
  /// **'Send a message or share a file with everyone in this group.'**
  String get sendAMessageOrShareA;

  /// No description provided for @sendAMessagePhotoOrFile.
  ///
  /// In en, this message translates to:
  /// **'Send a message, photo or file to begin chatting privately.'**
  String get sendAMessagePhotoOrFile;

  /// No description provided for @sendARequest.
  ///
  /// In en, this message translates to:
  /// **'Send a request'**
  String get sendARequest;

  /// No description provided for @sendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get sendMessage;

  /// No description provided for @sendMessages.
  ///
  /// In en, this message translates to:
  /// **'Send messages'**
  String get sendMessages;

  /// No description provided for @sendPoll.
  ///
  /// In en, this message translates to:
  /// **'Send poll'**
  String get sendPoll;

  /// No description provided for @sendRequest.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get sendRequest;

  /// No description provided for @sendThePictureToAFriend.
  ///
  /// In en, this message translates to:
  /// **'Send the picture to a friend'**
  String get sendThePictureToAFriend;

  /// No description provided for @sendVoiceNote.
  ///
  /// In en, this message translates to:
  /// **'Send voice note'**
  String get sendVoiceNote;

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sending;

  /// No description provided for @sendingTheGroupToAgain.
  ///
  /// In en, this message translates to:
  /// **'Sending the group to {name} again'**
  String sendingTheGroupToAgain(Object? name);

  /// No description provided for @sendsAFriendRequest.
  ///
  /// In en, this message translates to:
  /// **'Sends a friend request'**
  String get sendsAFriendRequest;

  /// No description provided for @sendsAfterTheCall.
  ///
  /// In en, this message translates to:
  /// **'Sends after the call'**
  String get sendsAfterTheCall;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @sent2.
  ///
  /// In en, this message translates to:
  /// **'Sent {sentAgo}'**
  String sent2(Object? sentAgo);

  /// No description provided for @sentAsOneMessage.
  ///
  /// In en, this message translates to:
  /// **'{summary}\nSent as one message'**
  String sentAsOneMessage(Object? summary);

  /// No description provided for @sentByWiFiDirectPasses.
  ///
  /// In en, this message translates to:
  /// **'Sent by Wi-Fi Direct · passes phone to phone\nNo time limit · goes to the server log later'**
  String get sentByWiFiDirectPasses;

  /// No description provided for @sentOnlyWhenAllMembersGot.
  ///
  /// In en, this message translates to:
  /// **'✓ = sent. ✓✓ only when all members got it.'**
  String get sentOnlyWhenAllMembersGot;

  /// No description provided for @sentTo.
  ///
  /// In en, this message translates to:
  /// **'Sent to {picks}'**
  String sentTo(Object? picks);

  /// No description provided for @sentToAllPhonesPendingUntil.
  ///
  /// In en, this message translates to:
  /// **'Sent to all phones · Pending until it is done'**
  String get sentToAllPhonesPendingUntil;

  /// No description provided for @sentToChats.
  ///
  /// In en, this message translates to:
  /// **'Sent to {chats} chats'**
  String sentToChats(Object? chats);

  /// No description provided for @sentToTheAdmin.
  ///
  /// In en, this message translates to:
  /// **'Sent to the admin'**
  String get sentToTheAdmin;

  /// No description provided for @sep.
  ///
  /// In en, this message translates to:
  /// **'Sep'**
  String get sep;

  /// No description provided for @serious.
  ///
  /// In en, this message translates to:
  /// **'Serious'**
  String get serious;

  /// No description provided for @server.
  ///
  /// In en, this message translates to:
  /// **'Server: {waiting}'**
  String server(Object? waiting);

  /// No description provided for @server2.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get server2;

  /// No description provided for @serverAddressOptionalFallback.
  ///
  /// In en, this message translates to:
  /// **'Server address (optional fallback)'**
  String get serverAddressOptionalFallback;

  /// No description provided for @serverConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Server configuration'**
  String get serverConfiguration;

  /// No description provided for @serverConnected.
  ///
  /// In en, this message translates to:
  /// **'Server connected'**
  String get serverConnected;

  /// No description provided for @serverConnectedRequestsGoByThe.
  ///
  /// In en, this message translates to:
  /// **'Server connected · requests go by the server'**
  String get serverConnectedRequestsGoByThe;

  /// No description provided for @serverDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Server disconnected'**
  String get serverDisconnected;

  /// No description provided for @serverError.
  ///
  /// In en, this message translates to:
  /// **'Server error ({statusCode})'**
  String serverError(Object? statusCode);

  /// No description provided for @serverHealth.
  ///
  /// In en, this message translates to:
  /// **'Server health'**
  String get serverHealth;

  /// No description provided for @serverHealthDetailsAreOffOn.
  ///
  /// In en, this message translates to:
  /// **'Server health details are off on this server.'**
  String get serverHealthDetailsAreOffOn;

  /// No description provided for @serverHistoryNotReachableRightNow.
  ///
  /// In en, this message translates to:
  /// **'Server history not reachable right now.'**
  String get serverHistoryNotReachableRightNow;

  /// No description provided for @serverIsBackToolsUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Server is back. Tools unlocked.'**
  String get serverIsBackToolsUnlocked;

  /// No description provided for @serverLinks.
  ///
  /// In en, this message translates to:
  /// **'Server links'**
  String get serverLinks;

  /// No description provided for @serverLost.
  ///
  /// In en, this message translates to:
  /// **'Server lost'**
  String get serverLost;

  /// No description provided for @serverOffYourLinksOnly.
  ///
  /// In en, this message translates to:
  /// **'Server off - your links only'**
  String get serverOffYourLinksOnly;

  /// No description provided for @serverOffGroupPhones324.
  ///
  /// In en, this message translates to:
  /// **'Server off - this group\'s phones are not known yet.'**
  String get serverOffGroupPhones324;

  /// No description provided for @serverOffPersonPhone324.
  ///
  /// In en, this message translates to:
  /// **'Server off - this person\'s phone is not known yet.'**
  String get serverOffPersonPhone324;

  /// No description provided for @serverPcClockIsH.
  ///
  /// In en, this message translates to:
  /// **'Server PC clock is {h} h {fast}'**
  String serverPcClockIsH(Object? h, Object? fast);

  /// No description provided for @serverTraffic.
  ///
  /// In en, this message translates to:
  /// **'Server traffic'**
  String get serverTraffic;

  /// No description provided for @sessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get sessions;

  /// No description provided for @setMinimumVersion.
  ///
  /// In en, this message translates to:
  /// **'{admin} set minimum version {detail}'**
  String setMinimumVersion(Object? admin, Object? detail);

  /// No description provided for @setNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Set new password'**
  String get setNewPassword;

  /// No description provided for @setOnceCannotBeChanged.
  ///
  /// In en, this message translates to:
  /// **'Set once — cannot be changed'**
  String get setOnceCannotBeChanged;

  /// No description provided for @setText.
  ///
  /// In en, this message translates to:
  /// **'Set {label}'**
  String setText(Object? label);

  /// No description provided for @setTo.
  ///
  /// In en, this message translates to:
  /// **'Set {name} to {label}?'**
  String setTo(Object? name, Object? label);

  /// No description provided for @setTo2.
  ///
  /// In en, this message translates to:
  /// **'{admin} set {target} to {detail}'**
  String setTo2(Object? admin, Object? target, Object? detail);

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsBatteryBackgroundUsageLimitsLinkup.
  ///
  /// In en, this message translates to:
  /// **'Settings > Battery > Background usage limits: LinkUp must not be in Sleeping or Deep sleeping apps'**
  String get settingsBatteryBackgroundUsageLimitsLinkup;

  /// No description provided for @settingsWiFiTapTheQr.
  ///
  /// In en, this message translates to:
  /// **'Settings → Wi-Fi → tap the QR icon and scan this code.'**
  String get settingsWiFiTapTheQr;

  /// No description provided for @sha256Created.
  ///
  /// In en, this message translates to:
  /// **'SHA-256 {publicKey}\nCreated {createdAt}{retiredAt}'**
  String sha256Created(Object? publicKey, Object? createdAt, Object? retiredAt);

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @shareAHotspot.
  ///
  /// In en, this message translates to:
  /// **'Share a hotspot?'**
  String get shareAHotspot;

  /// No description provided for @shareALinkupHotspot.
  ///
  /// In en, this message translates to:
  /// **'Share a LinkUp hotspot'**
  String get shareALinkupHotspot;

  /// No description provided for @shareAgain.
  ///
  /// In en, this message translates to:
  /// **'Share again'**
  String get shareAgain;

  /// No description provided for @shareAnyway.
  ///
  /// In en, this message translates to:
  /// **'Share anyway'**
  String get shareAnyway;

  /// No description provided for @shareCode.
  ///
  /// In en, this message translates to:
  /// **'Share code'**
  String get shareCode;

  /// No description provided for @shareLink.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get shareLink;

  /// No description provided for @shareLinkup.
  ///
  /// In en, this message translates to:
  /// **'Share LinkUp'**
  String get shareLinkup;

  /// No description provided for @shareMyQr.
  ///
  /// In en, this message translates to:
  /// **'Share my QR'**
  String get shareMyQr;

  /// No description provided for @shareYourLinkupIdentityWithAnother.
  ///
  /// In en, this message translates to:
  /// **'Share your LinkUp identity with another phone.'**
  String get shareYourLinkupIdentityWithAnother;

  /// No description provided for @shareYourSignedPublicProfileThrough.
  ///
  /// In en, this message translates to:
  /// **'Share your signed public profile through LinkUp'**
  String get shareYourSignedPublicProfileThrough;

  /// No description provided for @sharingAHotspotTest.
  ///
  /// In en, this message translates to:
  /// **'Sharing a hotspot (test)'**
  String get sharingAHotspotTest;

  /// No description provided for @sharingStopped.
  ///
  /// In en, this message translates to:
  /// **'Sharing stopped'**
  String get sharingStopped;

  /// No description provided for @sharingStopsByItselfAfter10.
  ///
  /// In en, this message translates to:
  /// **'Sharing stops by itself after 10 minutes with no download, or when you leave this screen.'**
  String get sharingStopsByItselfAfter10;

  /// No description provided for @sharingUsesALotOfBattery.
  ///
  /// In en, this message translates to:
  /// **'Sharing uses a lot of battery. Plug in the charger first.'**
  String get sharingUsesALotOfBattery;

  /// No description provided for @shortRouteList.
  ///
  /// In en, this message translates to:
  /// **'Short route list'**
  String get shortRouteList;

  /// No description provided for @showAGenericLinkupNotification.
  ///
  /// In en, this message translates to:
  /// **'Show a generic LinkUp notification'**
  String get showAGenericLinkupNotification;

  /// No description provided for @showFullContent.
  ///
  /// In en, this message translates to:
  /// **'Show full content'**
  String get showFullContent;

  /// No description provided for @showHidden.
  ///
  /// In en, this message translates to:
  /// **'Show hidden ({count})'**
  String showHidden(Object? count);

  /// No description provided for @showMoreLeft.
  ///
  /// In en, this message translates to:
  /// **'Show {next} more  ({left} left)'**
  String showMoreLeft(Object? next, Object? left);

  /// No description provided for @showMyCode.
  ///
  /// In en, this message translates to:
  /// **'Show my code'**
  String get showMyCode;

  /// No description provided for @showMyLinksMap.
  ///
  /// In en, this message translates to:
  /// **'Show My links map'**
  String get showMyLinksMap;

  /// No description provided for @showMyQrCode.
  ///
  /// In en, this message translates to:
  /// **'Show my QR code'**
  String get showMyQrCode;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @showSenderAndMessagePreview.
  ///
  /// In en, this message translates to:
  /// **'Show sender and message preview'**
  String get showSenderAndMessagePreview;

  /// No description provided for @showSenderOnly.
  ///
  /// In en, this message translates to:
  /// **'Show sender only'**
  String get showSenderOnly;

  /// No description provided for @showText.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showText;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signInAgain.
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get signInAgain;

  /// No description provided for @signInToTheServerTo.
  ///
  /// In en, this message translates to:
  /// **'Sign in to the server to open group links.'**
  String get signInToTheServerTo;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signOut2.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get signOut2;

  /// No description provided for @signOutAllPhones.
  ///
  /// In en, this message translates to:
  /// **'Sign out all phones'**
  String get signOutAllPhones;

  /// No description provided for @signOutAllPhones2.
  ///
  /// In en, this message translates to:
  /// **'Sign out all phones?'**
  String get signOutAllPhones2;

  /// No description provided for @signOutThisAdmin.
  ///
  /// In en, this message translates to:
  /// **'Sign out this admin?'**
  String get signOutThisAdmin;

  /// No description provided for @signOutThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Sign out this phone?'**
  String get signOutThisPhone;

  /// No description provided for @signedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get signedIn;

  /// No description provided for @signedIn2.
  ///
  /// In en, this message translates to:
  /// **'{admin} signed in'**
  String signedIn2(Object? admin);

  /// No description provided for @signedOut.
  ///
  /// In en, this message translates to:
  /// **'{admin} signed out'**
  String signedOut(Object? admin);

  /// No description provided for @signedOut2.
  ///
  /// In en, this message translates to:
  /// **'{admin} signed out {target}'**
  String signedOut2(Object? admin, Object? target);

  /// No description provided for @signedOutByAdmin.
  ///
  /// In en, this message translates to:
  /// **'Signed out by admin'**
  String get signedOutByAdmin;

  /// No description provided for @signedOutByAdminYourChats.
  ///
  /// In en, this message translates to:
  /// **'Signed out by admin. Your chats are still here. Log in again when the server is on.'**
  String get signedOutByAdminYourChats;

  /// No description provided for @signedOutFromTheServerNearby.
  ///
  /// In en, this message translates to:
  /// **'Signed out from the server. Nearby chats still work. Sign in again to use the server.'**
  String get signedOutFromTheServerNearby;

  /// No description provided for @signingYouIn.
  ///
  /// In en, this message translates to:
  /// **'Signing you in…'**
  String get signingYouIn;

  /// No description provided for @since.
  ///
  /// In en, this message translates to:
  /// **'since {madeAt}'**
  String since(Object? madeAt);

  /// No description provided for @since2.
  ///
  /// In en, this message translates to:
  /// **'{s} · since {created_at}'**
  String since2(Object? s, Object? created_at);

  /// No description provided for @sinceEnds.
  ///
  /// In en, this message translates to:
  /// **'Since {created_at} · ends {expires_at}'**
  String sinceEnds(Object? created_at, Object? expires_at);

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @slideToCancel.
  ///
  /// In en, this message translates to:
  /// **'Slide to cancel'**
  String get slideToCancel;

  /// No description provided for @small.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get small;

  /// No description provided for @smallMap.
  ///
  /// In en, this message translates to:
  /// **'Small map'**
  String get smallMap;

  /// No description provided for @someDataCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Some data could not load'**
  String get someDataCouldNotLoad;

  /// No description provided for @someOldPicturesWereLeftOut.
  ///
  /// In en, this message translates to:
  /// **'Some old pictures were left out to keep the copy small.'**
  String get someOldPicturesWereLeftOut;

  /// No description provided for @someone.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get someone;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @somethingWentWrongPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get somethingWentWrongPleaseTryAgain;

  /// No description provided for @somethingWentWrongTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get somethingWentWrongTryAgain;

  /// No description provided for @speakerOff.
  ///
  /// In en, this message translates to:
  /// **'Speaker off'**
  String get speakerOff;

  /// No description provided for @speakerOn.
  ///
  /// In en, this message translates to:
  /// **'Speaker on'**
  String get speakerOn;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @startAgain.
  ///
  /// In en, this message translates to:
  /// **'Start again'**
  String get startAgain;

  /// No description provided for @startAgainOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Start again on this phone'**
  String get startAgainOnThisPhone;

  /// No description provided for @startOver.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get startOver;

  /// No description provided for @startRecoveryFromTheLinkupWelcome.
  ///
  /// In en, this message translates to:
  /// **'Start recovery from the LinkUp welcome screen to create a new request.'**
  String get startRecoveryFromTheLinkupWelcome;

  /// No description provided for @startTheConversation.
  ///
  /// In en, this message translates to:
  /// **'Start the conversation'**
  String get startTheConversation;

  /// No description provided for @startTheGroupConversation.
  ///
  /// In en, this message translates to:
  /// **'Start the group conversation'**
  String get startTheGroupConversation;

  /// No description provided for @started.
  ///
  /// In en, this message translates to:
  /// **'{num} started {windowLabel}'**
  String started(Object? num, Object? windowLabel);

  /// No description provided for @startedByItselfYouCanKeep.
  ///
  /// In en, this message translates to:
  /// **'Started by itself. You can keep using LinkUp.'**
  String get startedByItselfYouCanKeep;

  /// No description provided for @starting.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get starting;

  /// No description provided for @starting2.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get starting2;

  /// No description provided for @startingCamera.
  ///
  /// In en, this message translates to:
  /// **'Starting camera…'**
  String get startingCamera;

  /// No description provided for @startingRestore.
  ///
  /// In en, this message translates to:
  /// **'Starting restore…'**
  String get startingRestore;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @statusUnknownStale.
  ///
  /// In en, this message translates to:
  /// **'Status unknown / stale'**
  String get statusUnknownStale;

  /// No description provided for @stayReachableEvenWhenTheApp.
  ///
  /// In en, this message translates to:
  /// **'Stay reachable even when the app is closed'**
  String get stayReachableEvenWhenTheApp;

  /// No description provided for @staysYourFriendANewMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} stays your friend. A new message from them starts a new chat.'**
  String staysYourFriendANewMessage(Object? name);

  /// No description provided for @stillHas.
  ///
  /// In en, this message translates to:
  /// **'still has'**
  String get stillHas;

  /// No description provided for @stillHasCopyPhotosYouSaved.
  ///
  /// In en, this message translates to:
  /// **'{peerName} still has {their} copy. Photos you saved to your Gallery stay.'**
  String stillHasCopyPhotosYouSaved(Object? peerName, Object? their);

  /// No description provided for @stillHave.
  ///
  /// In en, this message translates to:
  /// **'still have'**
  String get stillHave;

  /// No description provided for @stillHelpsTheMesh.
  ///
  /// In en, this message translates to:
  /// **'Still helps the mesh'**
  String get stillHelpsTheMesh;

  /// No description provided for @stillReceivingOverWiFiIt.
  ///
  /// In en, this message translates to:
  /// **'Still receiving over Wi-Fi. It will appear by itself.'**
  String get stillReceivingOverWiFiIt;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @stopAfterDay.
  ///
  /// In en, this message translates to:
  /// **'Stop after {days} day{s}'**
  String stopAfterDay(Object? days, Object? s);

  /// No description provided for @stopInDay.
  ///
  /// In en, this message translates to:
  /// **'{v} · stop in {days} day{s}'**
  String stopInDay(Object? v, Object? days, Object? s);

  /// No description provided for @stopNow.
  ///
  /// In en, this message translates to:
  /// **'Stop now'**
  String get stopNow;

  /// No description provided for @stopSharing.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get stopSharing;

  /// No description provided for @stopVersionsBelow.
  ///
  /// In en, this message translates to:
  /// **'Stop versions below {v}?'**
  String stopVersionsBelow(Object? v);

  /// No description provided for @stopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get stopped;

  /// No description provided for @stoppedByAdmin.
  ///
  /// In en, this message translates to:
  /// **'Stopped by admin'**
  String get stoppedByAdmin;

  /// No description provided for @stoppedByAdminUpdateToSend.
  ///
  /// In en, this message translates to:
  /// **'Stopped by admin. Update to send and call.'**
  String get stoppedByAdminUpdateToSend;

  /// No description provided for @stoppedByYourPhone.
  ///
  /// In en, this message translates to:
  /// **'Stopped by your phone'**
  String get stoppedByYourPhone;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @storageUsed.
  ///
  /// In en, this message translates to:
  /// **'Storage used'**
  String get storageUsed;

  /// No description provided for @strong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get strong;

  /// No description provided for @subsystemStateReportedByTheServer.
  ///
  /// In en, this message translates to:
  /// **'Subsystem state reported by the server'**
  String get subsystemStateReportedByTheServer;

  /// No description provided for @sun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get sun;

  /// No description provided for @suspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get suspended;

  /// No description provided for @swipeUpToAnswer.
  ///
  /// In en, this message translates to:
  /// **'Swipe up to answer'**
  String get swipeUpToAnswer;

  /// No description provided for @switchAccount.
  ///
  /// In en, this message translates to:
  /// **'Switch account'**
  String get switchAccount;

  /// No description provided for @switchToDarkTheme.
  ///
  /// In en, this message translates to:
  /// **'Switch to dark theme'**
  String get switchToDarkTheme;

  /// No description provided for @switchToLightTheme.
  ///
  /// In en, this message translates to:
  /// **'Switch to light theme'**
  String get switchToLightTheme;

  /// No description provided for @switchToVideoCall.
  ///
  /// In en, this message translates to:
  /// **'Switch to video call?'**
  String get switchToVideoCall;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @systemHealth.
  ///
  /// In en, this message translates to:
  /// **'System health'**
  String get systemHealth;

  /// No description provided for @t1AppInfoBatteryChooseUnrestricted.
  ///
  /// In en, this message translates to:
  /// **'1. App info > Battery: choose Unrestricted'**
  String get t1AppInfoBatteryChooseUnrestricted;

  /// No description provided for @t1Day.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get t1Day;

  /// No description provided for @t1Message.
  ///
  /// In en, this message translates to:
  /// **'1 message'**
  String get t1Message;

  /// No description provided for @t1Min.
  ///
  /// In en, this message translates to:
  /// **'1 min'**
  String get t1Min;

  /// No description provided for @t1OpenLinkupOnTheOther.
  ///
  /// In en, this message translates to:
  /// **'1. Open LinkUp on the other phone\n2. Tap Scan QR code and point at this\n3. You are added instantly'**
  String get t1OpenLinkupOnTheOther;

  /// No description provided for @t1OpenTheRecentsRecentApps.
  ///
  /// In en, this message translates to:
  /// **'1. Open the Recents (recent apps) screen.\n2. Tap the LinkUp app icon at the top of its card.\n3. Choose “Lock”. A padlock stays on the card — the system won’t swipe the app away in “clear all”.'**
  String get t1OpenTheRecentsRecentApps;

  /// No description provided for @t1OtherLinkupPhone.
  ///
  /// In en, this message translates to:
  /// **'1 other LinkUp phone'**
  String get t1OtherLinkupPhone;

  /// No description provided for @t1Person.
  ///
  /// In en, this message translates to:
  /// **'1 person'**
  String get t1Person;

  /// No description provided for @t1Phone.
  ///
  /// In en, this message translates to:
  /// **'1 phone'**
  String get t1Phone;

  /// No description provided for @t1RequestToJoin.
  ///
  /// In en, this message translates to:
  /// **'1 request to join'**
  String get t1RequestToJoin;

  /// No description provided for @t1UnreadMessage.
  ///
  /// In en, this message translates to:
  /// **'1 unread message'**
  String get t1UnreadMessage;

  /// No description provided for @t1Week.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get t1Week;

  /// No description provided for @t24Hours.
  ///
  /// In en, this message translates to:
  /// **'24 hours'**
  String get t24Hours;

  /// No description provided for @t2PowerManagerPowerManagementFor.
  ///
  /// In en, this message translates to:
  /// **'2. Power manager > Power management for apps > LinkUp: turn OFF screen-lock cleaning'**
  String get t2PowerManagerPowerManagementFor;

  /// No description provided for @t30Days.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get t30Days;

  /// No description provided for @t7Days.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get t7Days;

  /// No description provided for @t8Hours.
  ///
  /// In en, this message translates to:
  /// **'8 hours'**
  String get t8Hours;

  /// No description provided for @takesASecond.
  ///
  /// In en, this message translates to:
  /// **'Takes a second'**
  String get takesASecond;

  /// No description provided for @tapAPersonToSeeMore.
  ///
  /// In en, this message translates to:
  /// **'Tap a person to see more.'**
  String get tapAPersonToSeeMore;

  /// No description provided for @tapAddFriendNextToThe.
  ///
  /// In en, this message translates to:
  /// **'Tap Add friend next to the phone you want to add.'**
  String get tapAddFriendNextToThe;

  /// No description provided for @tapAnOptionInTheChat.
  ///
  /// In en, this message translates to:
  /// **'Tap an option in the chat to vote; tap it again to take your vote back. Works Nearby and Online.'**
  String get tapAnOptionInTheChat;

  /// No description provided for @tapJoinGroupWithQr.
  ///
  /// In en, this message translates to:
  /// **'Tap Join group with QR'**
  String get tapJoinGroupWithQr;

  /// No description provided for @tapOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Tap Open settings'**
  String get tapOpenSettings;

  /// No description provided for @tapPhotoToAddOne.
  ///
  /// In en, this message translates to:
  /// **'Tap photo to add one'**
  String get tapPhotoToAddOne;

  /// No description provided for @tapPhotoToChange.
  ///
  /// In en, this message translates to:
  /// **'Tap photo to change'**
  String get tapPhotoToChange;

  /// No description provided for @tapScanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Tap Scan QR code'**
  String get tapScanQrCode;

  /// No description provided for @tapTheCameraToChooseA.
  ///
  /// In en, this message translates to:
  /// **'Tap the camera to choose a photo'**
  String get tapTheCameraToChooseA;

  /// No description provided for @tapTheOneYourFriendCan.
  ///
  /// In en, this message translates to:
  /// **'Tap the one your friend can open:'**
  String get tapTheOneYourFriendCan;

  /// No description provided for @tapToCallBack.
  ///
  /// In en, this message translates to:
  /// **'Tap to call back'**
  String get tapToCallBack;

  /// No description provided for @tapToCancel.
  ///
  /// In en, this message translates to:
  /// **'Tap to cancel'**
  String get tapToCancel;

  /// No description provided for @tapToDownload.
  ///
  /// In en, this message translates to:
  /// **'Tap to download'**
  String get tapToDownload;

  /// No description provided for @tapToEditNameAndPhoto.
  ///
  /// In en, this message translates to:
  /// **'Tap to edit name and photo'**
  String get tapToEditNameAndPhoto;

  /// No description provided for @tapToRemove.
  ///
  /// In en, this message translates to:
  /// **'Tap to remove'**
  String get tapToRemove;

  /// No description provided for @tapToReturn.
  ///
  /// In en, this message translates to:
  /// **'{name} · {answered} — Tap to return'**
  String tapToReturn(Object? name, Object? answered);

  /// No description provided for @tapYourPhotoInSettingsTo.
  ///
  /// In en, this message translates to:
  /// **'Tap your photo in Settings to switch.'**
  String get tapYourPhotoInSettingsTo;

  /// No description provided for @testCleanUpNow.
  ///
  /// In en, this message translates to:
  /// **'Test clean-up now'**
  String get testCleanUpNow;

  /// No description provided for @testCleanUpNow2.
  ///
  /// In en, this message translates to:
  /// **'Test clean-up now?'**
  String get testCleanUpNow2;

  /// No description provided for @testCleanUpRemoved.
  ///
  /// In en, this message translates to:
  /// **'Test clean-up: {removed} {files} removed'**
  String testCleanUpRemoved(Object? removed, Object? files);

  /// No description provided for @testers.
  ///
  /// In en, this message translates to:
  /// **'Testers'**
  String get testers;

  /// No description provided for @thatActionIsNotAllowedOn.
  ///
  /// In en, this message translates to:
  /// **'That action is not allowed on this account.'**
  String get thatActionIsNotAllowedOn;

  /// No description provided for @thatAlreadyExistsTryADifferent.
  ///
  /// In en, this message translates to:
  /// **'That already exists. Try a different name.'**
  String get thatAlreadyExistsTryADifferent;

  /// No description provided for @thatCodeIsNotRight.
  ///
  /// In en, this message translates to:
  /// **'That code is not right.'**
  String get thatCodeIsNotRight;

  /// No description provided for @thatFileIsTooLargeTo.
  ///
  /// In en, this message translates to:
  /// **'That file is too large to send.'**
  String get thatFileIsTooLargeTo;

  /// No description provided for @thatPasswordIsNotRight.
  ///
  /// In en, this message translates to:
  /// **'That password is not right.'**
  String get thatPasswordIsNotRight;

  /// No description provided for @thatTookTooLongPleaseTry.
  ///
  /// In en, this message translates to:
  /// **'That took too long. Please try again.'**
  String get thatTookTooLongPleaseTry;

  /// No description provided for @thatUsernameAndPasswordDoNot.
  ///
  /// In en, this message translates to:
  /// **'That username and password do not match.'**
  String get thatUsernameAndPasswordDoNot;

  /// No description provided for @theAccountHistoryCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The account history could not be restored ({error}). You can retry now — the app will NOT pretend the account is empty.'**
  String theAccountHistoryCouldNotBe(Object? error);

  /// No description provided for @theAdminApprovedIt.
  ///
  /// In en, this message translates to:
  /// **'The admin approved it'**
  String get theAdminApprovedIt;

  /// No description provided for @theAdminApprovesIt.
  ///
  /// In en, this message translates to:
  /// **'The admin approves it'**
  String get theAdminApprovesIt;

  /// No description provided for @theAdminDidNotApproveIt.
  ///
  /// In en, this message translates to:
  /// **'The admin did not approve it.{rejectedReason}'**
  String theAdminDidNotApproveIt(Object? rejectedReason);

  /// No description provided for @theAdminGivesItToYou.
  ///
  /// In en, this message translates to:
  /// **'The admin gives it to you in person'**
  String get theAdminGivesItToYou;

  /// No description provided for @theAdminHasNotApprovedIt.
  ///
  /// In en, this message translates to:
  /// **'The admin has not approved it yet.'**
  String get theAdminHasNotApprovedIt;

  /// No description provided for @theAdministratorApprovedThisDeviceRecovery.
  ///
  /// In en, this message translates to:
  /// **'The administrator approved this device recovery request.'**
  String get theAdministratorApprovedThisDeviceRecovery;

  /// No description provided for @theAdministratorRejectedThisRecoveryRequest.
  ///
  /// In en, this message translates to:
  /// **'The administrator rejected this recovery request.'**
  String get theAdministratorRejectedThisRecoveryRequest;

  /// No description provided for @theAdministratorRejectedThisRequest.
  ///
  /// In en, this message translates to:
  /// **'The administrator rejected this request.'**
  String get theAdministratorRejectedThisRequest;

  /// No description provided for @theChatAndAllItsMessages.
  ///
  /// In en, this message translates to:
  /// **'The chat and all its messages, photos and files are '**
  String get theChatAndAllItsMessages;

  /// No description provided for @theChatStaysInYourChats.
  ///
  /// In en, this message translates to:
  /// **'The chat stays in your Chats list, empty.'**
  String get theChatStaysInYourChats;

  /// No description provided for @theCodeIsWrongOrToo.
  ///
  /// In en, this message translates to:
  /// **'The code is wrong or too old. Ask the admin for a new code.'**
  String get theCodeIsWrongOrToo;

  /// No description provided for @theCodesDonTMatchAsk.
  ///
  /// In en, this message translates to:
  /// **'The codes don\'t match. Ask {v} to open this screen again.'**
  String theCodesDonTMatchAsk(Object? v);

  /// No description provided for @theDeletedFromThisPhone.
  ///
  /// In en, this message translates to:
  /// **'The {files} {are} deleted from this phone ({bytes}).'**
  String theDeletedFromThisPhone(Object? files, Object? are, Object? bytes);

  /// No description provided for @theGroup.
  ///
  /// In en, this message translates to:
  /// **'the group'**
  String get theGroup;

  /// No description provided for @theGroupPhotoCanBeSet.
  ///
  /// In en, this message translates to:
  /// **'The group photo can be set when Online.'**
  String get theGroupPhotoCanBeSet;

  /// No description provided for @theLinkWasLostLookingFor.
  ///
  /// In en, this message translates to:
  /// **'The link was lost. Looking for a way again.'**
  String get theLinkWasLostLookingFor;

  /// No description provided for @theMessagesStayInTheChat.
  ///
  /// In en, this message translates to:
  /// **'The messages stay in the chat with a small picture and \"Removed to save space\".'**
  String get theMessagesStayInTheChat;

  /// No description provided for @theOldCodeStopsWorking.
  ///
  /// In en, this message translates to:
  /// **'The old code stops working'**
  String get theOldCodeStopsWorking;

  /// No description provided for @theOldLinkStopsWorking.
  ///
  /// In en, this message translates to:
  /// **'The old link stops working'**
  String get theOldLinkStopsWorking;

  /// No description provided for @theOldLinkStopsWorkingPeople.
  ///
  /// In en, this message translates to:
  /// **'The old link stops working. People who have it can\'t use it to join.'**
  String get theOldLinkStopsWorkingPeople;

  /// No description provided for @theOtherItemsWereForwarded.
  ///
  /// In en, this message translates to:
  /// **'{first} The other items were forwarded.'**
  String theOtherItemsWereForwarded(Object? first);

  /// No description provided for @theOtherMembers.
  ///
  /// In en, this message translates to:
  /// **'The other members '**
  String get theOtherMembers;

  /// No description provided for @thePhoneCarriesOthersLockedMessages.
  ///
  /// In en, this message translates to:
  /// **'The phone carries others\' locked messages'**
  String get thePhoneCarriesOthersLockedMessages;

  /// No description provided for @thePhoneDecides.
  ///
  /// In en, this message translates to:
  /// **'The phone decides'**
  String get thePhoneDecides;

  /// No description provided for @theQrBelongsToADifferent.
  ///
  /// In en, this message translates to:
  /// **'The QR belongs to a different or unavailable LinkUp server.'**
  String get theQrBelongsToADifferent;

  /// No description provided for @theQrShowsHereByItself.
  ///
  /// In en, this message translates to:
  /// **'The QR shows here by itself.\n(up to 10 seconds)'**
  String get theQrShowsHereByItself;

  /// No description provided for @theRequestOrItsRecoveryCredential.
  ///
  /// In en, this message translates to:
  /// **'The request or its recovery credential is no longer valid.'**
  String get theRequestOrItsRecoveryCredential;

  /// No description provided for @theRestIsOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'the rest is on the way'**
  String get theRestIsOnTheWay;

  /// No description provided for @theServerDidNotReturnSubsystem.
  ///
  /// In en, this message translates to:
  /// **'The server did not return subsystem readings for this request.'**
  String get theServerDidNotReturnSubsystem;

  /// No description provided for @theServerDidNotTakeIt.
  ///
  /// In en, this message translates to:
  /// **'The server did not take it (your recovery code was changed). Use Forgot password again when online.'**
  String get theServerDidNotTakeIt;

  /// No description provided for @theServerIsHavingTroublePlease.
  ///
  /// In en, this message translates to:
  /// **'The server is having trouble. Please try again in a moment.'**
  String get theServerIsHavingTroublePlease;

  /// No description provided for @theServerIsUnreachableCheckThat.
  ///
  /// In en, this message translates to:
  /// **'The server is unreachable. Check that it is running and that this phone is on the same network.'**
  String get theServerIsUnreachableCheckThat;

  /// No description provided for @theServerNeedsAPairingCode.
  ///
  /// In en, this message translates to:
  /// **'The server needs a pairing code'**
  String get theServerNeedsAPairingCode;

  /// No description provided for @theServerReturnedAReplyThe.
  ///
  /// In en, this message translates to:
  /// **'The server returned a reply the app could not understand.'**
  String get theServerReturnedAReplyThe;

  /// No description provided for @theServerReturnedNoActivityBuckets.
  ///
  /// In en, this message translates to:
  /// **'The server returned no activity buckets for the selected range.'**
  String get theServerReturnedNoActivityBuckets;

  /// No description provided for @theServerSignedThisPhoneOut.
  ///
  /// In en, this message translates to:
  /// **'The server signed this phone out. Type your password to sign in again. Your chats stay on this phone.'**
  String get theServerSignedThisPhoneOut;

  /// No description provided for @theServerStoresOnlyAnEncrypted.
  ///
  /// In en, this message translates to:
  /// **'The server stores only an encrypted backup envelope. The backup passphrase stays on your device.'**
  String get theServerStoresOnlyAnEncrypted;

  /// No description provided for @theServerTookTooLongTo.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to respond. It will keep retrying automatically.'**
  String get theServerTookTooLongTo;

  /// No description provided for @theTwoPasswordsAreNotThe.
  ///
  /// In en, this message translates to:
  /// **'The two passwords are not the same.'**
  String get theTwoPasswordsAreNotThe;

  /// No description provided for @theirCopyPhotosYouSavedTo.
  ///
  /// In en, this message translates to:
  /// **' their copy. Photos you saved to your Gallery stay.'**
  String get theirCopyPhotosYouSavedTo;

  /// No description provided for @theirPhoneIsNotKnownYet.
  ///
  /// In en, this message translates to:
  /// **'Their phone is not known yet. Ask them to open LinkUp near you, then try again.'**
  String get theirPhoneIsNotKnownYet;

  /// No description provided for @theirPhonesSendTheseMessagesAlso.
  ///
  /// In en, this message translates to:
  /// **'Their phones send these messages (also ones they deleted). They see nothing.'**
  String get theirPhonesSendTheseMessagesAlso;

  /// No description provided for @thenTap.
  ///
  /// In en, this message translates to:
  /// **', then tap '**
  String get thenTap;

  /// No description provided for @theseFilesAreBiggerThan50.
  ///
  /// In en, this message translates to:
  /// **'These files are bigger than 50 MB and can\'t be forwarded.'**
  String get theseFilesAreBiggerThan50;

  /// No description provided for @theseFilesAreBiggerThan502.
  ///
  /// In en, this message translates to:
  /// **'These files are bigger than 50 MB, so they were not added.'**
  String get theseFilesAreBiggerThan502;

  /// No description provided for @theseTwoAccountsAreOnThe.
  ///
  /// In en, this message translates to:
  /// **'These two accounts are on the same phone.'**
  String get theseTwoAccountsAreOnThe;

  /// No description provided for @they.
  ///
  /// In en, this message translates to:
  /// **'They'**
  String get they;

  /// No description provided for @theyAreAddedWhenNearbyOr.
  ///
  /// In en, this message translates to:
  /// **'They are added when Nearby or Online'**
  String get theyAreAddedWhenNearbyOr;

  /// No description provided for @theyCanNoLongerMessageOr.
  ///
  /// In en, this message translates to:
  /// **'They can no longer message or pair with this phone — online or offline. This applies right away on this phone.'**
  String get theyCanNoLongerMessageOr;

  /// No description provided for @theyCanTMessageOrCall.
  ///
  /// In en, this message translates to:
  /// **'They can\'t message or call you.'**
  String get theyCanTMessageOrCall;

  /// No description provided for @thisAccountHasAnEncryptedBackup.
  ///
  /// In en, this message translates to:
  /// **'This account has an encrypted backup of its identity keys. Enter the backup passphrase to also restore message decryption keys, or skip it.'**
  String get thisAccountHasAnEncryptedBackup;

  /// No description provided for @thisAccountHasNoRecoveryCode.
  ///
  /// In en, this message translates to:
  /// **'This account has no recovery code on this phone yet.'**
  String get thisAccountHasNoRecoveryCode;

  /// No description provided for @thisAccountIsNotActiveAsk.
  ///
  /// In en, this message translates to:
  /// **'This account is not active. Ask the admin.'**
  String get thisAccountIsNotActiveAsk;

  /// No description provided for @thisAdminSessionEndsNow.
  ///
  /// In en, this message translates to:
  /// **'This admin session ends now.'**
  String get thisAdminSessionEndsNow;

  /// No description provided for @thisCopyOfLinkupCanT.
  ///
  /// In en, this message translates to:
  /// **'This copy of LinkUp can\'t be shared'**
  String get thisCopyOfLinkupCanT;

  /// No description provided for @thisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get thisDevice;

  /// No description provided for @thisFileIsBiggerThan50.
  ///
  /// In en, this message translates to:
  /// **'This file is bigger than 50 MB and can\'t be forwarded.'**
  String get thisFileIsBiggerThan50;

  /// No description provided for @thisFileIsBiggerThan502.
  ///
  /// In en, this message translates to:
  /// **'This file is bigger than 50 MB, so it was not added.'**
  String get thisFileIsBiggerThan502;

  /// No description provided for @thisFileIsNoLongerOn.
  ///
  /// In en, this message translates to:
  /// **'This file is no longer on your phone'**
  String get thisFileIsNoLongerOn;

  /// No description provided for @thisFileIsNoLongerOn2.
  ///
  /// In en, this message translates to:
  /// **'This file is no longer on your phone.'**
  String get thisFileIsNoLongerOn2;

  /// No description provided for @thisGroupCodeHasExpiredAsk.
  ///
  /// In en, this message translates to:
  /// **'This group code has expired. Ask for a new one.'**
  String get thisGroupCodeHasExpiredAsk;

  /// No description provided for @thisGroupIsFull100People.
  ///
  /// In en, this message translates to:
  /// **'This group is full (100 people).'**
  String get thisGroupIsFull100People;

  /// No description provided for @thisGroupWorksOnlyNearbyIt.
  ///
  /// In en, this message translates to:
  /// **'This group works only Nearby (it is not on the server yet), so a link can\'t work. Use '**
  String get thisGroupWorksOnlyNearbyIt;

  /// No description provided for @thisHappensByItself.
  ///
  /// In en, this message translates to:
  /// **'This happens by itself.'**
  String get thisHappensByItself;

  /// No description provided for @thisHappensWhenReinstallsLinkupOr.
  ///
  /// In en, this message translates to:
  /// **'This happens when {v} reinstalls LinkUp or uses a new phone. Until you accept, the old code is kept. If you are not sure, ask {v2} first.'**
  String thisHappensWhenReinstallsLinkupOr(Object? v, Object? v2);

  /// No description provided for @thisInviteLinkDoesnTWork.
  ///
  /// In en, this message translates to:
  /// **'This invite link doesn\'t work any more.'**
  String get thisInviteLinkDoesnTWork;

  /// No description provided for @thisInviteLinkDoesnTWork2.
  ///
  /// In en, this message translates to:
  /// **'This invite link doesn\'t work any more. Ask for a new one.'**
  String get thisInviteLinkDoesnTWork2;

  /// No description provided for @thisIsNotALinkupGroup.
  ///
  /// In en, this message translates to:
  /// **'This is not a LinkUp group code.'**
  String get thisIsNotALinkupGroup;

  /// No description provided for @thisIsYou.
  ///
  /// In en, this message translates to:
  /// **'This is you'**
  String get thisIsYou;

  /// No description provided for @thisLinkupVersionIsStoppedBy.
  ///
  /// In en, this message translates to:
  /// **'This LinkUp version is stopped by admin'**
  String get thisLinkupVersionIsStoppedBy;

  /// No description provided for @thisMessageCannotBeResent.
  ///
  /// In en, this message translates to:
  /// **'This message cannot be resent'**
  String get thisMessageCannotBeResent;

  /// No description provided for @thisNearbyPhoneCannotBeConnected.
  ///
  /// In en, this message translates to:
  /// **'This nearby phone cannot be connected right now.'**
  String get thisNearbyPhoneCannotBeConnected;

  /// No description provided for @thisNeedsTheServerTryAgain.
  ///
  /// In en, this message translates to:
  /// **'This needs the server. Try again when the server is back.'**
  String get thisNeedsTheServerTryAgain;

  /// No description provided for @thisOne.
  ///
  /// In en, this message translates to:
  /// **'This one'**
  String get thisOne;

  /// No description provided for @thisPageChecksTheLocalServer.
  ///
  /// In en, this message translates to:
  /// **'This page checks the local server every few seconds.'**
  String get thisPageChecksTheLocalServer;

  /// No description provided for @thisPageIsLockedItOpens.
  ///
  /// In en, this message translates to:
  /// **'This page is locked. It opens again by itself when the server is back.'**
  String get thisPageIsLockedItOpens;

  /// No description provided for @thisPerson.
  ///
  /// In en, this message translates to:
  /// **'This person'**
  String get thisPerson;

  /// No description provided for @thisPersonCouldNotBeFound.
  ///
  /// In en, this message translates to:
  /// **'This person could not be found now. Try again near them or scan their QR code.'**
  String get thisPersonCouldNotBeFound;

  /// No description provided for @thisPersonIsNotCurrentlyAvailable.
  ///
  /// In en, this message translates to:
  /// **'This person is not currently available.'**
  String get thisPersonIsNotCurrentlyAvailable;

  /// No description provided for @thisPhone.
  ///
  /// In en, this message translates to:
  /// **'This phone'**
  String get thisPhone;

  /// No description provided for @thisPhone2.
  ///
  /// In en, this message translates to:
  /// **'this phone'**
  String get thisPhone2;

  /// No description provided for @thisPhoneAlreadyHasAnAccount.
  ///
  /// In en, this message translates to:
  /// **'This phone already has an account'**
  String get thisPhoneAlreadyHasAnAccount;

  /// No description provided for @thisPhoneBlocksHotspotsMadeBy.
  ///
  /// In en, this message translates to:
  /// **'This phone blocks hotspots made by apps.'**
  String get thisPhoneBlocksHotspotsMadeBy;

  /// No description provided for @thisPhoneCanSignInOffline.
  ///
  /// In en, this message translates to:
  /// **'This phone can sign in offline only with the last account used on it.'**
  String get thisPhoneCanSignInOffline;

  /// No description provided for @thisPhoneCannotReachThatPhone.
  ///
  /// In en, this message translates to:
  /// **'This phone cannot reach that phone directly.'**
  String get thisPhoneCannotReachThatPhone;

  /// No description provided for @thisPhoneDoesnTAllowIt.
  ///
  /// In en, this message translates to:
  /// **'This phone doesn\'t allow it'**
  String get thisPhoneDoesnTAllowIt;

  /// No description provided for @thisPhoneHasNoCopyOf.
  ///
  /// In en, this message translates to:
  /// **'This phone has no copy of your password. Log in again on this phone, then try.'**
  String get thisPhoneHasNoCopyOf;

  /// No description provided for @thisPhoneHasNoSavedSign.
  ///
  /// In en, this message translates to:
  /// **'This phone has no saved sign-in yet. Turn the server on and sign in once.'**
  String get thisPhoneHasNoSavedSign;

  /// No description provided for @thisPhoneIsAlreadyLinkedTo.
  ///
  /// In en, this message translates to:
  /// **'This phone is already linked to {who} on the server. Ask the admin to remove this phone on the web (Devices), then tap Try again.'**
  String thisPhoneIsAlreadyLinkedTo(Object? who);

  /// No description provided for @thisPhoneIsNotPairedWith.
  ///
  /// In en, this message translates to:
  /// **'This phone is not paired with the server yet. Ask the admin for the pairing code.'**
  String get thisPhoneIsNotPairedWith;

  /// No description provided for @thisPhoneJoinedYourAccount.
  ///
  /// In en, this message translates to:
  /// **'This phone joined your account @{name}. {tail}'**
  String thisPhoneJoinedYourAccount(Object? name, Object? tail);

  /// No description provided for @thisPhoneLinkupBuild.
  ///
  /// In en, this message translates to:
  /// **'This phone: LinkUp {kAppVersion} (build {kAppBuild})'**
  String thisPhoneLinkupBuild(Object? kAppVersion, Object? kAppBuild);

  /// No description provided for @thisPhoneLinkupBuild2.
  ///
  /// In en, this message translates to:
  /// **'This phone: LinkUp {kAppVersion} (build {kAppBuild}){sent}'**
  String thisPhoneLinkupBuild2(
      Object? kAppVersion, Object? kAppBuild, Object? sent);

  /// No description provided for @thisPhoneNearbyNetwork.
  ///
  /// In en, this message translates to:
  /// **'This phone — nearby network'**
  String get thisPhoneNearbyNetwork;

  /// No description provided for @thisPhoneReportsOneBuildLower.
  ///
  /// In en, this message translates to:
  /// **'This phone reports one build lower'**
  String get thisPhoneReportsOneBuildLower;

  /// No description provided for @thisPhoneStillHasAskThe.
  ///
  /// In en, this message translates to:
  /// **'This phone still has @{username}. Ask the admin.'**
  String thisPhoneStillHasAskThe(Object? username);

  /// No description provided for @thisPhoneWasRemovedByAdmin.
  ///
  /// In en, this message translates to:
  /// **'This phone was removed by admin. Your chats are still here. Log in again when the server is on.'**
  String get thisPhoneWasRemovedByAdmin;

  /// No description provided for @thisPhotoIsNoLongerOn.
  ///
  /// In en, this message translates to:
  /// **'This photo is no longer on your phone.'**
  String get thisPhotoIsNoLongerOn;

  /// No description provided for @thisPhotoIsTooBigTry.
  ///
  /// In en, this message translates to:
  /// **'This photo is too big. Try another one.'**
  String get thisPhotoIsTooBigTry;

  /// No description provided for @thisQrContainsAOneTime.
  ///
  /// In en, this message translates to:
  /// **'This QR contains a one-time transfer credential. Anyone who can scan it may transfer the account, so keep this screen private.'**
  String get thisQrContainsAOneTime;

  /// No description provided for @thisRecoveryRequestHasAlreadyBeen.
  ///
  /// In en, this message translates to:
  /// **'This recovery request has already been completed.'**
  String get thisRecoveryRequestHasAlreadyBeen;

  /// No description provided for @thisRecoveryRequestHasExpiredStart.
  ///
  /// In en, this message translates to:
  /// **'This recovery request has expired. Start a new request.'**
  String get thisRecoveryRequestHasExpiredStart;

  /// No description provided for @thisReturnsTheAppToIts.
  ///
  /// In en, this message translates to:
  /// **'This returns the app to its setup state. Existing local data may be removed.'**
  String get thisReturnsTheAppToIts;

  /// No description provided for @thisServerBuildDoesNotExpose.
  ///
  /// In en, this message translates to:
  /// **'This server build does not expose the runtime sampler.'**
  String get thisServerBuildDoesNotExpose;

  /// No description provided for @thisTransferQrHasExpiredGenerate.
  ///
  /// In en, this message translates to:
  /// **'This transfer QR has expired. Generate a new QR on the old phone.'**
  String get thisTransferQrHasExpiredGenerate;

  /// No description provided for @thisUserIdentityIsNotTrusted.
  ///
  /// In en, this message translates to:
  /// **'This user identity is not trusted for local calling'**
  String get thisUserIdentityIsNotTrusted;

  /// No description provided for @thisUserIsBlocked.
  ///
  /// In en, this message translates to:
  /// **'This user is blocked'**
  String get thisUserIsBlocked;

  /// No description provided for @thisUsesMoreBatterySomePhones.
  ///
  /// In en, this message translates to:
  /// **'This uses more battery. Some phones cannot run it while on Wi-Fi. Only LinkUp phones with \"Link full groups\" on will join it.'**
  String get thisUsesMoreBatterySomePhones;

  /// No description provided for @thisVideoIsNoLongerOn.
  ///
  /// In en, this message translates to:
  /// **'This video is no longer on your phone.'**
  String get thisVideoIsNoLongerOn;

  /// No description provided for @thisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get thisWeek;

  /// No description provided for @thisWeekWaiting.
  ///
  /// In en, this message translates to:
  /// **'{file} this week · {waiting} waiting'**
  String thisWeekWaiting(Object? file, Object? waiting);

  /// No description provided for @thisWiFiBlocksPhonesFrom.
  ///
  /// In en, this message translates to:
  /// **'This Wi-Fi blocks phones from seeing each other'**
  String get thisWiFiBlocksPhonesFrom;

  /// No description provided for @through.
  ///
  /// In en, this message translates to:
  /// **'through {other}'**
  String through(Object? other);

  /// No description provided for @through2.
  ///
  /// In en, this message translates to:
  /// **'{link}, through {other}'**
  String through2(Object? link, Object? other);

  /// No description provided for @thu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get thu;

  /// No description provided for @toStopSomeoneOnEveryPhone.
  ///
  /// In en, this message translates to:
  /// **'To stop someone on every phone, use Blocked by admin.'**
  String get toStopSomeoneOnEveryPhone;

  /// No description provided for @toTheServer.
  ///
  /// In en, this message translates to:
  /// **'to the server'**
  String get toTheServer;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @today2.
  ///
  /// In en, this message translates to:
  /// **'today {t}'**
  String today2(Object? t);

  /// No description provided for @todayAtAGlance.
  ///
  /// In en, this message translates to:
  /// **'Today at a glance'**
  String get todayAtAGlance;

  /// No description provided for @toggleFlash.
  ///
  /// In en, this message translates to:
  /// **'Toggle flash'**
  String get toggleFlash;

  /// No description provided for @tooLateToDeleteForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Too late to delete for everyone'**
  String get tooLateToDeleteForEveryone;

  /// No description provided for @tooManyAttemptsPleaseWaitA.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a moment and try again.'**
  String get tooManyAttemptsPleaseWaitA;

  /// No description provided for @tooManyTriesTryAgainIn.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Try again in 1 minute.'**
  String get tooManyTriesTryAgainIn;

  /// No description provided for @topologyAndTransports.
  ///
  /// In en, this message translates to:
  /// **'Topology and transports'**
  String get topologyAndTransports;

  /// No description provided for @totalUsers.
  ///
  /// In en, this message translates to:
  /// **'Total users'**
  String get totalUsers;

  /// No description provided for @trafficMetricsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Traffic metrics unavailable'**
  String get trafficMetricsUnavailable;

  /// No description provided for @transferAccount.
  ///
  /// In en, this message translates to:
  /// **'Transfer account'**
  String get transferAccount;

  /// No description provided for @transferAccountToThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Transfer account to this phone'**
  String get transferAccountToThisPhone;

  /// No description provided for @transferNeedsTheServer.
  ///
  /// In en, this message translates to:
  /// **'Transfer needs the server'**
  String get transferNeedsTheServer;

  /// No description provided for @transferRequestDetected.
  ///
  /// In en, this message translates to:
  /// **'Transfer request detected'**
  String get transferRequestDetected;

  /// No description provided for @transferring.
  ///
  /// In en, this message translates to:
  /// **'Transferring'**
  String get transferring;

  /// No description provided for @transferring2.
  ///
  /// In en, this message translates to:
  /// **'Transferring {text}'**
  String transferring2(Object? text);

  /// No description provided for @transfersAndQuota.
  ///
  /// In en, this message translates to:
  /// **'Transfers and quota'**
  String get transfersAndQuota;

  /// No description provided for @transport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get transport;

  /// No description provided for @transportStateReportedByConnectedDevices.
  ///
  /// In en, this message translates to:
  /// **'Transport state reported by connected devices'**
  String get transportStateReportedByConnectedDevices;

  /// No description provided for @trustCompliance.
  ///
  /// In en, this message translates to:
  /// **'Trust & Compliance'**
  String get trustCompliance;

  /// No description provided for @tryADifferentWordOrPhrase.
  ///
  /// In en, this message translates to:
  /// **'Try a different word or phrase.'**
  String get tryADifferentWordOrPhrase;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @tryAgainInAMoment.
  ///
  /// In en, this message translates to:
  /// **'Try again in a moment.'**
  String get tryAgainInAMoment;

  /// No description provided for @tryAnotherName.
  ///
  /// In en, this message translates to:
  /// **'Try another name.'**
  String get tryAnotherName;

  /// No description provided for @tryAnotherNameOrFilter.
  ///
  /// In en, this message translates to:
  /// **'Try another name or filter.'**
  String get tryAnotherNameOrFilter;

  /// No description provided for @tryAnotherNameOrUsername.
  ///
  /// In en, this message translates to:
  /// **'Try another name or username.'**
  String get tryAnotherNameOrUsername;

  /// No description provided for @tryLinkupWiFiAgain.
  ///
  /// In en, this message translates to:
  /// **'Try LinkUp Wi-Fi again'**
  String get tryLinkupWiFiAgain;

  /// No description provided for @tryingAgain.
  ///
  /// In en, this message translates to:
  /// **'Trying again…'**
  String get tryingAgain;

  /// No description provided for @tue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get tue;

  /// No description provided for @turnCameraOff.
  ///
  /// In en, this message translates to:
  /// **'Turn camera off'**
  String get turnCameraOff;

  /// No description provided for @turnCameraOn.
  ///
  /// In en, this message translates to:
  /// **'Turn camera on'**
  String get turnCameraOn;

  /// No description provided for @turnItOnToFindPhones.
  ///
  /// In en, this message translates to:
  /// **'Turn it on to find phones near you'**
  String get turnItOnToFindPhones;

  /// No description provided for @turnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get turnOn;

  /// No description provided for @turnOnAutoLaunchSecondaryLaunch.
  ///
  /// In en, this message translates to:
  /// **'Turn ON Auto-launch, Secondary launch and Run in background'**
  String get turnOnAutoLaunchSecondaryLaunch;

  /// No description provided for @turnOnExtraNearbySafety.
  ///
  /// In en, this message translates to:
  /// **'Turn on extra nearby safety?'**
  String get turnOnExtraNearbySafety;

  /// No description provided for @turnOnLocation.
  ///
  /// In en, this message translates to:
  /// **'Turn on Location'**
  String get turnOnLocation;

  /// No description provided for @turnOnWiFi.
  ///
  /// In en, this message translates to:
  /// **'Turn on Wi-Fi'**
  String get turnOnWiFi;

  /// No description provided for @turnOnWiFiToReach.
  ///
  /// In en, this message translates to:
  /// **'Turn on Wi-Fi to reach people nearby.'**
  String get turnOnWiFiToReach;

  /// No description provided for @turnYourHotspotOffAndTry.
  ///
  /// In en, this message translates to:
  /// **'Turn your hotspot off and try again, or let your friend join your hotspot.'**
  String get turnYourHotspotOffAndTry;

  /// No description provided for @turnedOnTheirCameraAcceptTo.
  ///
  /// In en, this message translates to:
  /// **'{name} turned on their camera. Accept to switch this call to video.'**
  String turnedOnTheirCameraAcceptTo(Object? name);

  /// No description provided for @turningOnLinkupWiFi.
  ///
  /// In en, this message translates to:
  /// **'Turning on LinkUp Wi-Fi…'**
  String get turningOnLinkupWiFi;

  /// No description provided for @typeANameOrAWord.
  ///
  /// In en, this message translates to:
  /// **'Type a name or a word'**
  String get typeANameOrAWord;

  /// No description provided for @typeANameToContinue.
  ///
  /// In en, this message translates to:
  /// **'Type a name to continue'**
  String get typeANameToContinue;

  /// No description provided for @typeTheOneTimeCode.
  ///
  /// In en, this message translates to:
  /// **'Type the one-time code'**
  String get typeTheOneTimeCode;

  /// No description provided for @typeYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Type your password.'**
  String get typeYourPassword;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// No description provided for @unblock2.
  ///
  /// In en, this message translates to:
  /// **'Unblock {name}'**
  String unblock2(Object? name);

  /// No description provided for @unblock3.
  ///
  /// In en, this message translates to:
  /// **'Unblock {target}?'**
  String unblock3(Object? target);

  /// No description provided for @unblockAndAddBack.
  ///
  /// In en, this message translates to:
  /// **'Unblock and add back'**
  String get unblockAndAddBack;

  /// No description provided for @unblockForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Unblock for everyone'**
  String get unblockForEveryone;

  /// No description provided for @unblockOnly.
  ///
  /// In en, this message translates to:
  /// **'Unblock only'**
  String get unblockOnly;

  /// No description provided for @unblocked.
  ///
  /// In en, this message translates to:
  /// **'{label} unblocked'**
  String unblocked(Object? label);

  /// No description provided for @unblocked2.
  ///
  /// In en, this message translates to:
  /// **'{admin} unblocked {target}'**
  String unblocked2(Object? admin, Object? target);

  /// No description provided for @unblockedAndAddedBack.
  ///
  /// In en, this message translates to:
  /// **'{label} unblocked and added back'**
  String unblockedAndAddedBack(Object? label);

  /// No description provided for @unblockedOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'{r} unblocked on this phone.'**
  String unblockedOnThisPhone(Object? r);

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @unknownRole.
  ///
  /// In en, this message translates to:
  /// **'Unknown role'**
  String get unknownRole;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @unmuteNotifications.
  ///
  /// In en, this message translates to:
  /// **'Unmute notifications'**
  String get unmuteNotifications;

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @unreadMessages.
  ///
  /// In en, this message translates to:
  /// **'{count} unread messages'**
  String unreadMessages(Object? count);

  /// No description provided for @unsupported.
  ///
  /// In en, this message translates to:
  /// **'Unsupported'**
  String get unsupported;

  /// No description provided for @until.
  ///
  /// In en, this message translates to:
  /// **'Until {day} {month}, {hh}:{mm} {ampm}'**
  String until(
      Object? day, Object? month, Object? hh, Object? mm, Object? ampm);

  /// No description provided for @unverified.
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get unverified;

  /// No description provided for @upTo32PeopleNearby100.
  ///
  /// In en, this message translates to:
  /// **'Up to 32 people Nearby, 100 Online'**
  String get upTo32PeopleNearby100;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @updateLinkupSoon.
  ///
  /// In en, this message translates to:
  /// **'Update LinkUp soon'**
  String get updateLinkupSoon;

  /// No description provided for @updateNeededInAfterThatThis.
  ///
  /// In en, this message translates to:
  /// **'Update needed in {d}. After that this version can only read chats.'**
  String updateNeededInAfterThatThis(Object? d);

  /// No description provided for @updated.
  ///
  /// In en, this message translates to:
  /// **'Updated {cryptoBackupUpdatedAt}'**
  String updated(Object? cryptoBackupUpdatedAt);

  /// No description provided for @updated2.
  ///
  /// In en, this message translates to:
  /// **'Updated {generatedAt}{s}'**
  String updated2(Object? generatedAt, Object? s);

  /// No description provided for @uploadSizePerPhoneTlsSet.
  ///
  /// In en, this message translates to:
  /// **'Upload size {maxFile} · {quota} per phone · TLS {off}. Set on the server, can’t be changed here.'**
  String uploadSizePerPhoneTlsSet(Object? maxFile, Object? quota, Object? off);

  /// No description provided for @use03xxXxxxxxxOr923xx.
  ///
  /// In en, this message translates to:
  /// **'Use 03xx xxxxxxx or +92 3xx xxxxxxx'**
  String get use03xxXxxxxxxOr923xx;

  /// No description provided for @useAtLeast10CharactersThis.
  ///
  /// In en, this message translates to:
  /// **'Use at least 10 characters. This passphrase is never sent to the server.'**
  String get useAtLeast10CharactersThis;

  /// No description provided for @useBlockedOnThisPhoneIt.
  ///
  /// In en, this message translates to:
  /// **'Use \"Blocked on this phone\". It does not reach other phones.'**
  String get useBlockedOnThisPhoneIt;

  /// No description provided for @useItInLinkupLoginForgot.
  ///
  /// In en, this message translates to:
  /// **'Use it in LinkUp: Login > Forgot password'**
  String get useItInLinkupLoginForgot;

  /// No description provided for @useItOnForgotPasswordIf.
  ///
  /// In en, this message translates to:
  /// **'Use it on Forgot password if this phone is lost. Works offline.'**
  String get useItOnForgotPasswordIf;

  /// No description provided for @useNewRequestToAskThe.
  ///
  /// In en, this message translates to:
  /// **'Use New request to ask the phones of 2 people or a group.'**
  String get useNewRequestToAskThe;

  /// No description provided for @useOldPassword.
  ///
  /// In en, this message translates to:
  /// **'Use old password'**
  String get useOldPassword;

  /// No description provided for @useRecoveryCode.
  ///
  /// In en, this message translates to:
  /// **'Use recovery code'**
  String get useRecoveryCode;

  /// No description provided for @useTheUsername.
  ///
  /// In en, this message translates to:
  /// **'Use the username @{username}.'**
  String useTheUsername(Object? username);

  /// No description provided for @used.
  ///
  /// In en, this message translates to:
  /// **'{used} used'**
  String used(Object? used);

  /// No description provided for @usedByAnotherAccountSavedOn.
  ///
  /// In en, this message translates to:
  /// **'Used by another account. Saved on this phone only.'**
  String get usedByAnotherAccountSavedOn;

  /// No description provided for @usedLinkupOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'@{username} · used LinkUp on this phone'**
  String usedLinkupOnThisPhone(Object? username);

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @usernameMustBe332Characters.
  ///
  /// In en, this message translates to:
  /// **'Username must be 3–32 characters and use letters, numbers, dot, dash, or underscore.'**
  String get usernameMustBe332Characters;

  /// No description provided for @usernameOrRecoveryCodeIsWrong.
  ///
  /// In en, this message translates to:
  /// **'Username or recovery code is wrong.'**
  String get usernameOrRecoveryCodeIsWrong;

  /// No description provided for @users.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get users;

  /// No description provided for @usersBlockedServer.
  ///
  /// In en, this message translates to:
  /// **'{all} users · {blockedCount} blocked · server {offline}'**
  String usersBlockedServer(Object? all, Object? blockedCount, Object? offline);

  /// No description provided for @usesTheCodeSavedOnThis.
  ///
  /// In en, this message translates to:
  /// **'Uses the code saved on this phone. The new password goes to the server when it is back.'**
  String get usesTheCodeSavedOnThis;

  /// No description provided for @usingNearbyGroupsInstead.
  ///
  /// In en, this message translates to:
  /// **'Using nearby groups instead.'**
  String get usingNearbyGroupsInstead;

  /// No description provided for @verboseLogsForSupportCapturesTurns.
  ///
  /// In en, this message translates to:
  /// **'Verbose logs for support captures. Turns off when the app restarts.'**
  String get verboseLogsForSupportCapturesTurns;

  /// No description provided for @verified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verified;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version {currentVersion}'**
  String version(Object? currentVersion);

  /// No description provided for @version2.
  ///
  /// In en, this message translates to:
  /// **'Version {keyVersion}{retired}'**
  String version2(Object? keyVersion, Object? retired);

  /// No description provided for @versionNewer.
  ///
  /// In en, this message translates to:
  /// **'Version newer'**
  String get versionNewer;

  /// No description provided for @veryOldAppsBefore30.
  ///
  /// In en, this message translates to:
  /// **'Very old apps (before 3.0.54) are stopped too.'**
  String get veryOldAppsBefore30;

  /// No description provided for @via.
  ///
  /// In en, this message translates to:
  /// **'via {nextHop}{state}'**
  String via(Object? nextHop, Object? state);

  /// No description provided for @viaMesh.
  ///
  /// In en, this message translates to:
  /// **'via mesh'**
  String get viaMesh;

  /// No description provided for @viaServer.
  ///
  /// In en, this message translates to:
  /// **'via server'**
  String get viaServer;

  /// No description provided for @viaWiFi.
  ///
  /// In en, this message translates to:
  /// **'via Wi-Fi'**
  String get viaWiFi;

  /// No description provided for @viaWiFiDirect.
  ///
  /// In en, this message translates to:
  /// **'via Wi-Fi Direct'**
  String get viaWiFiDirect;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @videoDbgRx.
  ///
  /// In en, this message translates to:
  /// **'video dbg · {cfg} · rx:{videoRxFrames} · {drops}'**
  String videoDbgRx(Object? cfg, Object? videoRxFrames, Object? drops);

  /// No description provided for @videoReceived.
  ///
  /// In en, this message translates to:
  /// **'Video received'**
  String get videoReceived;

  /// No description provided for @videos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videos;

  /// No description provided for @videosReceived.
  ///
  /// In en, this message translates to:
  /// **'{n} videos received'**
  String videosReceived(Object? n);

  /// No description provided for @viewAsUser.
  ///
  /// In en, this message translates to:
  /// **'View as User'**
  String get viewAsUser;

  /// No description provided for @viewAuditLog.
  ///
  /// In en, this message translates to:
  /// **'View Audit Log'**
  String get viewAuditLog;

  /// No description provided for @viewNetwork.
  ///
  /// In en, this message translates to:
  /// **'View network'**
  String get viewNetwork;

  /// No description provided for @viewProfile.
  ///
  /// In en, this message translates to:
  /// **'View profile'**
  String get viewProfile;

  /// No description provided for @viewSecurityCenter.
  ///
  /// In en, this message translates to:
  /// **'View Security Center'**
  String get viewSecurityCenter;

  /// No description provided for @viewVotes.
  ///
  /// In en, this message translates to:
  /// **'View votes'**
  String get viewVotes;

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// No description provided for @voice2.
  ///
  /// In en, this message translates to:
  /// **'Voice · {started_at}'**
  String voice2(Object? started_at);

  /// No description provided for @voice3.
  ///
  /// In en, this message translates to:
  /// **'Voice · {secs} · {started_at}'**
  String voice3(Object? secs, Object? started_at);

  /// No description provided for @voiceCall.
  ///
  /// In en, this message translates to:
  /// **'Voice call'**
  String get voiceCall;

  /// No description provided for @voiceCalls.
  ///
  /// In en, this message translates to:
  /// **'Voice calls'**
  String get voiceCalls;

  /// No description provided for @voiceFramesPassedOn.
  ///
  /// In en, this message translates to:
  /// **'Voice frames passed on'**
  String get voiceFramesPassedOn;

  /// No description provided for @voiceMessage.
  ///
  /// In en, this message translates to:
  /// **'voice message'**
  String get voiceMessage;

  /// No description provided for @voiceMessage2.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get voiceMessage2;

  /// No description provided for @voiceMessageReceived.
  ///
  /// In en, this message translates to:
  /// **'Voice message received'**
  String get voiceMessageReceived;

  /// No description provided for @voiceMessagesReceived.
  ///
  /// In en, this message translates to:
  /// **'{n} voice messages received'**
  String voiceMessagesReceived(Object? n);

  /// No description provided for @voiceNote.
  ///
  /// In en, this message translates to:
  /// **'Voice note'**
  String get voiceNote;

  /// No description provided for @votes.
  ///
  /// In en, this message translates to:
  /// **'Votes'**
  String get votes;

  /// No description provided for @votesCanTBeChangedAfter.
  ///
  /// In en, this message translates to:
  /// **'Votes can\'t be changed after 3 minutes'**
  String get votesCanTBeChangedAfter;

  /// No description provided for @waiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get waiting;

  /// No description provided for @waiting2.
  ///
  /// In en, this message translates to:
  /// **'{waiting} waiting'**
  String waiting2(Object? waiting);

  /// No description provided for @waitingCarriedByThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Waiting · carried by this phone'**
  String get waitingCarriedByThisPhone;

  /// No description provided for @waitingFor.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {name}'**
  String waitingFor(Object? name);

  /// No description provided for @waitingForARoute.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a route'**
  String get waitingForARoute;

  /// No description provided for @waitingForAdministratorApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for administrator approval…'**
  String get waitingForAdministratorApproval;

  /// No description provided for @waitingForApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get waitingForApproval;

  /// No description provided for @waitingForSender.
  ///
  /// In en, this message translates to:
  /// **'Waiting for sender'**
  String get waitingForSender;

  /// No description provided for @waitingForTheAdmin.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the admin'**
  String get waitingForTheAdmin;

  /// No description provided for @waitingForThePhone.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the phone'**
  String get waitingForThePhone;

  /// No description provided for @waitingForTheServer.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the server'**
  String get waitingForTheServer;

  /// No description provided for @waitingForTheServerToBe.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the server to be updated.'**
  String get waitingForTheServerToBe;

  /// No description provided for @waitingForThisMessage.
  ///
  /// In en, this message translates to:
  /// **'🔒 Waiting for this message'**
  String get waitingForThisMessage;

  /// No description provided for @waitingForThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Waiting for this phone…'**
  String get waitingForThisPhone;

  /// No description provided for @waitingForToConnect.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {shown} to connect…'**
  String waitingForToConnect(Object? shown);

  /// No description provided for @waitingGetsItWhenTheyAre.
  ///
  /// In en, this message translates to:
  /// **'Waiting. {peerName} gets it when they are Nearby or Online.'**
  String waitingGetsItWhenTheyAre(Object? peerName);

  /// No description provided for @waitingNotNearOrOnlineYet.
  ///
  /// In en, this message translates to:
  /// **'Waiting · not near or online yet'**
  String get waitingNotNearOrOnlineYet;

  /// No description provided for @waitingSendsWhenYourFriendIs.
  ///
  /// In en, this message translates to:
  /// **'Waiting. Sends when your friend is online'**
  String get waitingSendsWhenYourFriendIs;

  /// No description provided for @waitingToJoinTheServer.
  ///
  /// In en, this message translates to:
  /// **'Waiting to join the server'**
  String get waitingToJoinTheServer;

  /// No description provided for @wantsToAddYou.
  ///
  /// In en, this message translates to:
  /// **'{username}wants to add you · {now}'**
  String wantsToAddYou(Object? username, Object? now);

  /// No description provided for @warnOnly.
  ///
  /// In en, this message translates to:
  /// **'Warn only'**
  String get warnOnly;

  /// No description provided for @warnOnly2.
  ///
  /// In en, this message translates to:
  /// **'{v} · warn only'**
  String warnOnly2(Object? v);

  /// No description provided for @warnVersionsBelow.
  ///
  /// In en, this message translates to:
  /// **'Warn versions below {v}?'**
  String warnVersionsBelow(Object? v);

  /// No description provided for @warning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get warning;

  /// No description provided for @warningFirstThenReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Warning first, then read only'**
  String get warningFirstThenReadOnly;

  /// No description provided for @warningsLikeWrongPasswords.
  ///
  /// In en, this message translates to:
  /// **'Warnings like wrong passwords'**
  String get warningsLikeWrongPasswords;

  /// No description provided for @wasStoppedNoRight.
  ///
  /// In en, this message translates to:
  /// **'{admin} was stopped (no right)'**
  String wasStoppedNoRight(Object? admin);

  /// No description provided for @wasTakenSoYouAre.
  ///
  /// In en, this message translates to:
  /// **'@{was} was taken, so you are @{name}. {tail}'**
  String wasTakenSoYouAre(Object? was, Object? name, Object? tail);

  /// No description provided for @weak.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get weak;

  /// No description provided for @webPanel.
  ///
  /// In en, this message translates to:
  /// **'web panel'**
  String get webPanel;

  /// No description provided for @wed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get wed;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @whatAdminsCanNeverSee.
  ///
  /// In en, this message translates to:
  /// **'What admins can never see'**
  String get whatAdminsCanNeverSee;

  /// No description provided for @whatAdminsDid.
  ///
  /// In en, this message translates to:
  /// **'What admins did'**
  String get whatAdminsDid;

  /// No description provided for @whatAdminsDoShowsHere.
  ///
  /// In en, this message translates to:
  /// **'What admins do shows here.'**
  String get whatAdminsDoShowsHere;

  /// No description provided for @whatIsRestored.
  ///
  /// In en, this message translates to:
  /// **'What is restored?'**
  String get whatIsRestored;

  /// No description provided for @whatYourFriendNeeds.
  ///
  /// In en, this message translates to:
  /// **'What your friend needs'**
  String get whatYourFriendNeeds;

  /// No description provided for @whatsappSmsEmail.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp, SMS, email…'**
  String get whatsappSmsEmail;

  /// No description provided for @whenSomeoneMovesToANew.
  ///
  /// In en, this message translates to:
  /// **'When someone moves to a new phone and asks for help, it shows here.'**
  String get whenSomeoneMovesToANew;

  /// No description provided for @whenThePhoneIsMoreThan.
  ///
  /// In en, this message translates to:
  /// **'When the phone is more than 70% full, remove photos, videos and documents not opened for 10 days. Voice notes stay.'**
  String get whenThePhoneIsMoreThan;

  /// No description provided for @whenThisIsOffLinkupCan.
  ///
  /// In en, this message translates to:
  /// **'When this is off, LinkUp can use the available local Wi-Fi, Wi-Fi Direct and mesh paths automatically.'**
  String get whenThisIsOffLinkupCan;

  /// No description provided for @whoCalledWhom.
  ///
  /// In en, this message translates to:
  /// **'Who called whom'**
  String get whoCalledWhom;

  /// No description provided for @whoIsLinkedToWhomLive.
  ///
  /// In en, this message translates to:
  /// **'Who is linked to whom, live'**
  String get whoIsLinkedToWhomLive;

  /// No description provided for @whoIsSignedInOnWhich.
  ///
  /// In en, this message translates to:
  /// **'Who is signed in, on which phone'**
  String get whoIsSignedInOnWhich;

  /// No description provided for @wholeMap.
  ///
  /// In en, this message translates to:
  /// **'Whole map'**
  String get wholeMap;

  /// No description provided for @wiFiCall.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi call'**
  String get wiFiCall;

  /// No description provided for @wiFiDirect.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi Direct'**
  String get wiFiDirect;

  /// No description provided for @wiFiDirectCall.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi Direct call'**
  String get wiFiDirectCall;

  /// No description provided for @wiFiDirectLinks.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi Direct links'**
  String get wiFiDirectLinks;

  /// No description provided for @wiFiDirectOff.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi Direct off'**
  String get wiFiDirectOff;

  /// No description provided for @wiFiDirectOn.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi Direct on'**
  String get wiFiDirectOn;

  /// No description provided for @wiFiDirectOnly.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi Direct only'**
  String get wiFiDirectOnly;

  /// No description provided for @wiFiDirectPeers.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi Direct peers'**
  String get wiFiDirectPeers;

  /// No description provided for @wiFiIsOff.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi is off'**
  String get wiFiIsOff;

  /// No description provided for @wiFiIsOffOrAndroid.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi is off or Android said no.'**
  String get wiFiIsOffOrAndroid;

  /// No description provided for @wiFiLinks.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi links'**
  String get wiFiLinks;

  /// No description provided for @wiFiName.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi name'**
  String get wiFiName;

  /// No description provided for @wiFiNameCopied.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi name copied'**
  String get wiFiNameCopied;

  /// No description provided for @wiFiOff.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi off'**
  String get wiFiOff;

  /// No description provided for @wiFiOffUsingWiFi.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi off - using Wi-Fi Direct'**
  String get wiFiOffUsingWiFi;

  /// No description provided for @wiFiRadioPolicy.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi radio policy'**
  String get wiFiRadioPolicy;

  /// No description provided for @wiFiRule.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi rule'**
  String get wiFiRule;

  /// No description provided for @wiFiRule2.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi rule: {detail}'**
  String wiFiRule2(Object? detail);

  /// No description provided for @wiFiRuleFor.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi rule for {name}'**
  String wiFiRuleFor(Object? name);

  /// No description provided for @wiFiRuleOpenAPerson.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi rule: open a person in Users or a phone in Devices.'**
  String get wiFiRuleOpenAPerson;

  /// No description provided for @wiFiStaysOff.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi stays off'**
  String get wiFiStaysOff;

  /// No description provided for @wiFiStaysOn.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi stays on'**
  String get wiFiStaysOn;

  /// No description provided for @wiFiStopped.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi stopped'**
  String get wiFiStopped;

  /// No description provided for @willBeSignedOutAndBlocked.
  ///
  /// In en, this message translates to:
  /// **'“{device}” will be signed out and blocked from this account. You can add it again later through the normal login flow.'**
  String willBeSignedOutAndBlocked(Object? device);

  /// No description provided for @willSeeRemovedYouTheyKeep.
  ///
  /// In en, this message translates to:
  /// **'{name} will see \"{me} removed you\". They keep the old messages but get no new ones.'**
  String willSeeRemovedYouTheyKeep(Object? name, Object? me);

  /// No description provided for @withText.
  ///
  /// In en, this message translates to:
  /// **'with {other}'**
  String withText(Object? other);

  /// No description provided for @withoutTheServerThisWorksOnly.
  ///
  /// In en, this message translates to:
  /// **'Without the server this works only for the last account on this phone.'**
  String get withoutTheServerThisWorksOnly;

  /// No description provided for @workingNow.
  ///
  /// In en, this message translates to:
  /// **'Working now'**
  String get workingNow;

  /// No description provided for @worksWithoutTheServerToo.
  ///
  /// In en, this message translates to:
  /// **'Works without the server too.'**
  String get worksWithoutTheServerToo;

  /// No description provided for @wrongPassword.
  ///
  /// In en, this message translates to:
  /// **'{g} wrong password{s}'**
  String wrongPassword(Object? g, Object? s);

  /// No description provided for @wrongPasswordTries.
  ///
  /// In en, this message translates to:
  /// **'Wrong password tries'**
  String get wrongPasswordTries;

  /// No description provided for @wrongPasswordTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Wrong password. Try again.'**
  String get wrongPasswordTryAgain;

  /// No description provided for @wrongPasswordYourCodeStaysHidden.
  ///
  /// In en, this message translates to:
  /// **'Wrong password. Your code stays hidden.'**
  String get wrongPasswordYourCodeStaysHidden;

  /// No description provided for @wrongPasswordsAndOtherWarningsShow.
  ///
  /// In en, this message translates to:
  /// **'Wrong passwords and other warnings show here.'**
  String get wrongPasswordsAndOtherWarningsShow;

  /// No description provided for @yellowBannerKeepsWorking.
  ///
  /// In en, this message translates to:
  /// **'Yellow banner, keeps working'**
  String get yellowBannerKeepsWorking;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @yesterday2.
  ///
  /// In en, this message translates to:
  /// **'Yesterday {t}'**
  String yesterday2(Object? t);

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You: '**
  String get you;

  /// No description provided for @you2.
  ///
  /// In en, this message translates to:
  /// **'You: {text}'**
  String you2(Object? text);

  /// No description provided for @you3.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you3;

  /// No description provided for @youAdded.
  ///
  /// In en, this message translates to:
  /// **'You added {targets}'**
  String youAdded(Object? targets);

  /// No description provided for @youAlreadyHaveThisChatTheir.
  ///
  /// In en, this message translates to:
  /// **'You already have this chat. Their phone adds the messages they deleted.'**
  String get youAlreadyHaveThisChatTheir;

  /// No description provided for @youAreNoLongerAnAdmin.
  ///
  /// In en, this message translates to:
  /// **'You are no longer an admin'**
  String get youAreNoLongerAnAdmin;

  /// No description provided for @youAreNowAnAdmin.
  ///
  /// In en, this message translates to:
  /// **'You are now an admin 👑'**
  String get youAreNowAnAdmin;

  /// No description provided for @youAreNowTheGroupOwner.
  ///
  /// In en, this message translates to:
  /// **'You are now the group owner'**
  String get youAreNowTheGroupOwner;

  /// No description provided for @youAreOnTheSameWi.
  ///
  /// In en, this message translates to:
  /// **'You are on the same Wi-Fi router. Messages and calls go straight between your phones.'**
  String get youAreOnTheSameWi;

  /// No description provided for @youAreOnTheServerNow.
  ///
  /// In en, this message translates to:
  /// **'You are @{name} on the server now. {tail}'**
  String youAreOnTheServerNow(Object? name, Object? tail);

  /// No description provided for @youAreTheOwner.
  ///
  /// In en, this message translates to:
  /// **'You are the owner: '**
  String get youAreTheOwner;

  /// No description provided for @youBlocked.
  ///
  /// In en, this message translates to:
  /// **'You blocked {device}'**
  String youBlocked(Object? device);

  /// No description provided for @youBlocked2.
  ///
  /// In en, this message translates to:
  /// **'You blocked {device} · {at}'**
  String youBlocked2(Object? device, Object? at);

  /// No description provided for @youBlocked3.
  ///
  /// In en, this message translates to:
  /// **'You blocked {device}.'**
  String youBlocked3(Object? device);

  /// No description provided for @youBlockedOnTheyCanT.
  ///
  /// In en, this message translates to:
  /// **'You blocked {name} on {when}. They can\'t message or call you.'**
  String youBlockedOnTheyCanT(Object? name, Object? when);

  /// No description provided for @youBlockedTheyCanTMessage.
  ///
  /// In en, this message translates to:
  /// **'You blocked {name}. They can\'t message or call you.'**
  String youBlockedTheyCanTMessage(Object? name);

  /// No description provided for @youBlockedThisPersonUnblockThem.
  ///
  /// In en, this message translates to:
  /// **'You blocked this person. Unblock them first.'**
  String get youBlockedThisPersonUnblockThem;

  /// No description provided for @youCanAddThemAgainLater.
  ///
  /// In en, this message translates to:
  /// **'You can add them again later.'**
  String get youCanAddThemAgainLater;

  /// No description provided for @youCanAddUpToPeople.
  ///
  /// In en, this message translates to:
  /// **'You can add up to {kNewGroupMax} people'**
  String youCanAddUpToPeople(Object? kNewGroupMax);

  /// No description provided for @youCanChangeYourVoteFor.
  ///
  /// In en, this message translates to:
  /// **'You can change your vote for {left}'**
  String youCanChangeYourVoteFor(Object? left);

  /// No description provided for @youCanMessageAndCallAfter.
  ///
  /// In en, this message translates to:
  /// **'You can message and call after they update.'**
  String get youCanMessageAndCallAfter;

  /// No description provided for @youCanOnlyAddYourFriends.
  ///
  /// In en, this message translates to:
  /// **'You can only add your friends.'**
  String get youCanOnlyAddYourFriends;

  /// No description provided for @youCanOnlyLook.
  ///
  /// In en, this message translates to:
  /// **'You can only look.'**
  String get youCanOnlyLook;

  /// No description provided for @youCanReadChatsButCan.
  ///
  /// In en, this message translates to:
  /// **'You can read chats but can\'t send.'**
  String get youCanReadChatsButCan;

  /// No description provided for @youCanReadOldChatsBut.
  ///
  /// In en, this message translates to:
  /// **'You can read old chats but can\'t send or call.'**
  String get youCanReadOldChatsBut;

  /// No description provided for @youCanReadOldChatsUpdate.
  ///
  /// In en, this message translates to:
  /// **'You can read old chats. Update to send and call{newer}.'**
  String youCanReadOldChatsUpdate(Object? newer);

  /// No description provided for @youCanSendMessagesAndCall.
  ///
  /// In en, this message translates to:
  /// **'You can send messages and call again.'**
  String get youCanSendMessagesAndCall;

  /// No description provided for @youCanTAddYourself.
  ///
  /// In en, this message translates to:
  /// **'You can\'t add yourself.'**
  String get youCanTAddYourself;

  /// No description provided for @youCanTJoinThisGroup.
  ///
  /// In en, this message translates to:
  /// **'You can\'t join this group.'**
  String get youCanTJoinThisGroup;

  /// No description provided for @youCanTMessage.
  ///
  /// In en, this message translates to:
  /// **'You can\'t message {device}.'**
  String youCanTMessage(Object? device);

  /// No description provided for @youCanTMessageOrCall.
  ///
  /// In en, this message translates to:
  /// **'You can\'t message or call {name}.'**
  String youCanTMessageOrCall(Object? name);

  /// No description provided for @youCanUnblockThemAnyTime.
  ///
  /// In en, this message translates to:
  /// **'You can unblock them any time.'**
  String get youCanUnblockThemAnyTime;

  /// No description provided for @youCanWriteNowTheyGet.
  ///
  /// In en, this message translates to:
  /// **'You can write now. They get your messages right after they join.'**
  String get youCanWriteNowTheyGet;

  /// No description provided for @youCreatedGroup.
  ///
  /// In en, this message translates to:
  /// **'You created group \"{name}\"'**
  String youCreatedGroup(Object? name);

  /// No description provided for @youCreatedThisGroup.
  ///
  /// In en, this message translates to:
  /// **'You created this group'**
  String get youCreatedThisGroup;

  /// No description provided for @youHaveNotSavedItYet.
  ///
  /// In en, this message translates to:
  /// **'You have not saved it yet. Keep it safe in case this phone is lost.'**
  String get youHaveNotSavedItYet;

  /// No description provided for @youHavenTBlockedAnyone.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t blocked anyone.'**
  String get youHavenTBlockedAnyone;

  /// No description provided for @youJoinedUsingThisGroupS.
  ///
  /// In en, this message translates to:
  /// **'You joined using this group\'s invite link'**
  String get youJoinedUsingThisGroupS;

  /// No description provided for @youLeft.
  ///
  /// In en, this message translates to:
  /// **'You left'**
  String get youLeft;

  /// No description provided for @youReAgain.
  ///
  /// In en, this message translates to:
  /// **'You\'re @{username} again'**
  String youReAgain(Object? username);

  /// No description provided for @youReAlreadyInThisGroup.
  ///
  /// In en, this message translates to:
  /// **'You\'re already in this group.'**
  String get youReAlreadyInThisGroup;

  /// No description provided for @youReNoLongerAParticipant.
  ///
  /// In en, this message translates to:
  /// **'You\'re no longer a participant in this group.'**
  String get youReNoLongerAParticipant;

  /// No description provided for @youReOnTheServerNow.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the server now'**
  String get youReOnTheServerNow;

  /// No description provided for @youReSignedIn.
  ///
  /// In en, this message translates to:
  /// **'You\'re signed in'**
  String get youReSignedIn;

  /// No description provided for @youStillGetMessagesAMention.
  ///
  /// In en, this message translates to:
  /// **'You still get messages. A mention of you (@) still notifies you.'**
  String get youStillGetMessagesAMention;

  /// No description provided for @youVeAddedEveryone.
  ///
  /// In en, this message translates to:
  /// **'You\'ve added everyone'**
  String get youVeAddedEveryone;

  /// No description provided for @yourAccountExistsOnlyOnThis.
  ///
  /// In en, this message translates to:
  /// **'Your account exists ONLY on this phone and has never reached the server. Resetting deletes it permanently — chats, and its recovery code, will be unrecoverable.'**
  String get yourAccountExistsOnlyOnThis;

  /// No description provided for @yourAccountIsActiveAgain.
  ///
  /// In en, this message translates to:
  /// **'Your account is active again'**
  String get yourAccountIsActiveAgain;

  /// No description provided for @yourAccountIsBlockedByAdmin.
  ///
  /// In en, this message translates to:
  /// **'Your account is blocked by admin'**
  String get yourAccountIsBlockedByAdmin;

  /// No description provided for @yourAccountIsBlockedByAdmin2.
  ///
  /// In en, this message translates to:
  /// **'Your account is blocked by admin. You can read old chats but can\'t send or call.'**
  String get yourAccountIsBlockedByAdmin2;

  /// No description provided for @yourAccountIsOnTheServer.
  ///
  /// In en, this message translates to:
  /// **'Your account is on the server now. {tail}'**
  String yourAccountIsOnTheServer(Object? tail);

  /// No description provided for @yourAccountSSecretLock.
  ///
  /// In en, this message translates to:
  /// **'Your account\'s secret lock'**
  String get yourAccountSSecretLock;

  /// No description provided for @yourAccountWasSentWithYou.
  ///
  /// In en, this message translates to:
  /// **'Your account was sent with {via}. You join the server when a phone with internet passes it on.'**
  String yourAccountWasSentWithYou(Object? via);

  /// No description provided for @yourAccountYourChats.
  ///
  /// In en, this message translates to:
  /// **'Your account, your chats'**
  String get yourAccountYourChats;

  /// No description provided for @yourAdminLevelIsNow.
  ///
  /// In en, this message translates to:
  /// **'Your admin level is now {role}'**
  String yourAdminLevelIsNow(Object? role);

  /// No description provided for @yourAndroidNeedsLocationAllThe.
  ///
  /// In en, this message translates to:
  /// **'Your Android needs Location \"All the time\" for this. LinkUp never saves where you are.'**
  String get yourAndroidNeedsLocationAllThe;

  /// No description provided for @yourCameraPreviewTapToFlip.
  ///
  /// In en, this message translates to:
  /// **'Your camera preview. Tap to flip camera, drag to move.'**
  String get yourCameraPreviewTapToFlip;

  /// No description provided for @yourChatWithThemStays.
  ///
  /// In en, this message translates to:
  /// **'Your chat with them **stays**.'**
  String get yourChatWithThemStays;

  /// No description provided for @yourChatsAndAccountStayOn.
  ///
  /// In en, this message translates to:
  /// **'Your chats and account stay on this phone.'**
  String get yourChatsAndAccountStayOn;

  /// No description provided for @yourChatsAndAccountStayOn2.
  ///
  /// In en, this message translates to:
  /// **'Your chats and account stay on this phone. Log back in with your password or recovery code whenever you are ready.'**
  String get yourChatsAndAccountStayOn2;

  /// No description provided for @yourChatsStayOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Your chats stay on this phone.'**
  String get yourChatsStayOnThisPhone;

  /// No description provided for @yourChatsWithSFriendsGo.
  ///
  /// In en, this message translates to:
  /// **'Your chats with {shownName}\'s friends go on. The new account on this phone is removed.'**
  String yourChatsWithSFriendsGo(Object? shownName);

  /// No description provided for @yourContact.
  ///
  /// In en, this message translates to:
  /// **'Your contact'**
  String get yourContact;

  /// No description provided for @yourContacts.
  ///
  /// In en, this message translates to:
  /// **'Your contacts'**
  String get yourContacts;

  /// No description provided for @yourConversationsAndContactsAreRestored.
  ///
  /// In en, this message translates to:
  /// **'Your conversations and contacts are restored.'**
  String get yourConversationsAndContactsAreRestored;

  /// No description provided for @yourFriendWillJoinThisWi.
  ///
  /// In en, this message translates to:
  /// **'Your friend will join this Wi-Fi to download the app. No internet used.'**
  String get yourFriendWillJoinThisWi;

  /// No description provided for @yourFriends.
  ///
  /// In en, this message translates to:
  /// **'Your friends'**
  String get yourFriends;

  /// No description provided for @yourLinkupIsOld.
  ///
  /// In en, this message translates to:
  /// **'Your LinkUp is old'**
  String get yourLinkupIsOld;

  /// No description provided for @yourMessagesHopThroughSThey.
  ///
  /// In en, this message translates to:
  /// **'Your messages hop through {phones} ({who}\'s). They stay locked; {who2} can\'t read them. Calls may be a bit slower.'**
  String yourMessagesHopThroughSThey(Object? phones, Object? who, Object? who2);

  /// No description provided for @yourMessagesHopThroughTheyStay.
  ///
  /// In en, this message translates to:
  /// **'Your messages hop through {phones}. They stay locked; nobody in between can read them. Calls may be a bit slower.'**
  String yourMessagesHopThroughTheyStay(Object? phones);

  /// No description provided for @yourNewPasswordIsOnlyOn.
  ///
  /// In en, this message translates to:
  /// **'Your new password is only on this phone'**
  String get yourNewPasswordIsOnlyOn;

  /// No description provided for @yourNewPasswordWorksOnThis.
  ///
  /// In en, this message translates to:
  /// **'Your new password works on this phone now. It goes to the server when the server is back, then you get a new recovery code.'**
  String get yourNewPasswordWorksOnThis;

  /// No description provided for @yourOldCodeNoLongerWorks.
  ///
  /// In en, this message translates to:
  /// **'Your old code no longer works.'**
  String get yourOldCodeNoLongerWorks;

  /// No description provided for @yourOldCodeStopsWorking.
  ///
  /// In en, this message translates to:
  /// **'Your old code stops working.'**
  String get yourOldCodeStopsWorking;

  /// No description provided for @yourOldMessagesStayOnThis.
  ///
  /// In en, this message translates to:
  /// **'Your old messages stay on this phone'**
  String get yourOldMessagesStayOnThis;

  /// No description provided for @yourOtherPhonesStaySignedIn.
  ///
  /// In en, this message translates to:
  /// **'Your other phones stay signed in. You get a new recovery code after this.'**
  String get yourOtherPhonesStaySignedIn;

  /// No description provided for @yourPhone.
  ///
  /// In en, this message translates to:
  /// **'YOUR PHONE'**
  String get yourPhone;

  /// No description provided for @yourPhone2.
  ///
  /// In en, this message translates to:
  /// **'Your phone: {title}'**
  String yourPhone2(Object? title);

  /// No description provided for @yourPhoneHotspotIsAlreadyOn.
  ///
  /// In en, this message translates to:
  /// **'Your phone hotspot is already on, so LinkUp can\'t start its own Wi-Fi. Ask your friend to join your hotspot, then scan:'**
  String get yourPhoneHotspotIsAlreadyOn;

  /// No description provided for @yourPhoneHotspotIsOn.
  ///
  /// In en, this message translates to:
  /// **'Your phone hotspot is on'**
  String get yourPhoneHotspotIsOn;

  /// No description provided for @yourPhoneNumberStaysOnThis.
  ///
  /// In en, this message translates to:
  /// **'Your phone number stays on this phone only.'**
  String get yourPhoneNumberStaysOnThis;

  /// No description provided for @yourPhoneNumberWasNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Your phone number was not saved: {reason}'**
  String yourPhoneNumberWasNotSaved(Object? reason);

  /// No description provided for @yourProfile.
  ///
  /// In en, this message translates to:
  /// **'Your profile'**
  String get yourProfile;

  /// No description provided for @yourProfileChangeWasNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Your profile change was not saved: {reason}'**
  String yourProfileChangeWasNotSaved(Object? reason);

  /// No description provided for @yourProfileIsNotReadyYet.
  ///
  /// In en, this message translates to:
  /// **'Your profile is not ready yet.'**
  String get yourProfileIsNotReadyYet;

  /// No description provided for @yourProfileIsPrivate.
  ///
  /// In en, this message translates to:
  /// **'Your profile is private'**
  String get yourProfileIsPrivate;

  /// No description provided for @yourProfileIsPublicAgain.
  ///
  /// In en, this message translates to:
  /// **'Your profile is public again'**
  String get yourProfileIsPublicAgain;

  /// No description provided for @yourRecentLinkupCallsWillAppear.
  ///
  /// In en, this message translates to:
  /// **'Your recent LinkUp calls will appear here.'**
  String get yourRecentLinkupCallsWillAppear;

  /// No description provided for @yourRecoveryCode.
  ///
  /// In en, this message translates to:
  /// **'Your recovery code'**
  String get yourRecoveryCode;

  /// No description provided for @yourRecoveryCodeChanged.
  ///
  /// In en, this message translates to:
  /// **'Your recovery code changed'**
  String get yourRecoveryCodeChanged;

  /// No description provided for @yourSavedProfileIsShown.
  ///
  /// In en, this message translates to:
  /// **'Your saved profile is shown. {error}'**
  String yourSavedProfileIsShown(Object? error);

  /// No description provided for @yourSessionHasExpiredPleaseLog.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please log in again.'**
  String get yourSessionHasExpiredPleaseLog;

  /// No description provided for @yourUniqueUsername.
  ///
  /// In en, this message translates to:
  /// **'Your unique username'**
  String get yourUniqueUsername;

  /// No description provided for @yourVoteIsFinal.
  ///
  /// In en, this message translates to:
  /// **'Your vote is final'**
  String get yourVoteIsFinal;

  /// No description provided for @yourWayBackInIfThis.
  ///
  /// In en, this message translates to:
  /// **'Your way back in if this phone is lost'**
  String get yourWayBackInIfThis;

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomIn;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOut;

  /// No description provided for @youObject304.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get youObject304;

  /// No description provided for @language304.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language304;

  /// No description provided for @phoneLanguage304.
  ///
  /// In en, this message translates to:
  /// **'Phone language'**
  String get phoneLanguage304;

  /// No description provided for @phoneLanguageHint304.
  ///
  /// In en, this message translates to:
  /// **'Urdu when the phone is set to Urdu, English otherwise'**
  String get phoneLanguageHint304;

  /// No description provided for @chooseLanguage304.
  ///
  /// In en, this message translates to:
  /// **'Choose the language of LinkUp on this phone.'**
  String get chooseLanguage304;

  /// No description provided for @no304.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no304;

  /// No description provided for @groupCountOf304.
  ///
  /// In en, this message translates to:
  /// **'{v0} · {v1} of {v2}'**
  String groupCountOf304(Object? v0, Object? v1, Object? v2);

  /// No description provided for @mbOf304.
  ///
  /// In en, this message translates to:
  /// **'{v0} of {v1} MB'**
  String mbOf304(Object? v0, Object? v1);

  /// No description provided for @wiFiOn304.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi on'**
  String get wiFiOn304;

  /// No description provided for @yourFriend304.
  ///
  /// In en, this message translates to:
  /// **'Your friend'**
  String get yourFriend304;

  /// No description provided for @reasonSuffix304.
  ///
  /// In en, this message translates to:
  /// **' Reason: {v0}'**
  String reasonSuffix304(Object? v0);

  /// No description provided for @todayAt304.
  ///
  /// In en, this message translates to:
  /// **'Today, {v0}'**
  String todayAt304(Object? v0);

  /// No description provided for @yesterdayAt304.
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {v0}'**
  String yesterdayAt304(Object? v0);

  /// No description provided for @cantAddYetOnline304.
  ///
  /// In en, this message translates to:
  /// **'{v0} can\'t be added yet. They need to open LinkUp Online once.'**
  String cantAddYetOnline304(Object? v0);

  /// No description provided for @cantAddYetNearby304.
  ///
  /// In en, this message translates to:
  /// **'{v0} can\'t be added yet. They need to be Online or Nearby with you once.'**
  String cantAddYetNearby304(Object? v0);

  /// No description provided for @madeOnAdminPhone304.
  ///
  /// In en, this message translates to:
  /// **'This request was made on the admin phone. The answer opens there.'**
  String get madeOnAdminPhone304;

  /// No description provided for @waitingForPhoneOfChat304.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a phone of this chat. There is no time limit.'**
  String get waitingForPhoneOfChat304;

  /// No description provided for @adminsLower304.
  ///
  /// In en, this message translates to:
  /// **'admins'**
  String get adminsLower304;

  /// No description provided for @oneLower304.
  ///
  /// In en, this message translates to:
  /// **'one'**
  String get oneLower304;

  /// No description provided for @possPhone304.
  ///
  /// In en, this message translates to:
  /// **'\'s phone'**
  String get possPhone304;

  /// No description provided for @someoneIs304.
  ///
  /// In en, this message translates to:
  /// **'someone is'**
  String get someoneIs304;

  /// No description provided for @heIs304.
  ///
  /// In en, this message translates to:
  /// **'he is'**
  String get heIs304;

  /// No description provided for @byWho304.
  ///
  /// In en, this message translates to:
  /// **'By {v0}'**
  String byWho304(Object? v0);

  /// No description provided for @fileWord304.
  ///
  /// In en, this message translates to:
  /// **'file'**
  String get fileWord304;

  /// No description provided for @filesWord304.
  ///
  /// In en, this message translates to:
  /// **'files'**
  String get filesWord304;

  /// No description provided for @slow304.
  ///
  /// In en, this message translates to:
  /// **'slow'**
  String get slow304;

  /// No description provided for @fast304.
  ///
  /// In en, this message translates to:
  /// **'fast'**
  String get fast304;

  /// No description provided for @todayLower304.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get todayLower304;

  /// No description provided for @yesterdayLower304.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get yesterdayLower304;

  /// No description provided for @isBlockedByAdminYouCanEn304.
  ///
  /// In en, this message translates to:
  /// **'{v0} is blocked by admin. You can\'t message or call {v1}.'**
  String isBlockedByAdminYouCanEn304(Object? v0, Object? v1);

  /// No description provided for @hasAnOldLinkupTheyNeedEn304.
  ///
  /// In en, this message translates to:
  /// **'{v0} has an old LinkUp. They need to update.'**
  String hasAnOldLinkupTheyNeedEn304(Object? v0);

  /// No description provided for @replyPhotoEn304.
  ///
  /// In en, this message translates to:
  /// **'📷 Photo'**
  String get replyPhotoEn304;

  /// No description provided for @replyVideoEn304.
  ///
  /// In en, this message translates to:
  /// **'🎥 Video'**
  String get replyVideoEn304;

  /// No description provided for @replyVoiceEn304.
  ///
  /// In en, this message translates to:
  /// **'🎤 Voice message'**
  String get replyVoiceEn304;

  /// No description provided for @replyDocumentEn304.
  ///
  /// In en, this message translates to:
  /// **'📄 Document'**
  String get replyDocumentEn304;

  /// No description provided for @serverAddressIsNotConfiguredEn304.
  ///
  /// In en, this message translates to:
  /// **'Server address is not configured.'**
  String get serverAddressIsNotConfiguredEn304;

  /// No description provided for @noAccountMadeOfflineToSendEn304.
  ///
  /// In en, this message translates to:
  /// **'No account made offline to send.'**
  String get noAccountMadeOfflineToSendEn304;

  /// No description provided for @selectedImageNoLongerExistsEn304.
  ///
  /// In en, this message translates to:
  /// **'Selected image no longer exists'**
  String get selectedImageNoLongerExistsEn304;

  /// No description provided for @serverReturnedNoRecoveryCodeEn304.
  ///
  /// In en, this message translates to:
  /// **'Server returned no recovery code'**
  String get serverReturnedNoRecoveryCodeEn304;

  /// No description provided for @adminIsNotOnForThisEn304.
  ///
  /// In en, this message translates to:
  /// **'Admin is not on for this phone.'**
  String get adminIsNotOnForThisEn304;

  /// No description provided for @yourAdminRoleCanTDoEn304.
  ///
  /// In en, this message translates to:
  /// **'Your admin role can\'t do this.'**
  String get yourAdminRoleCanTDoEn304;

  /// No description provided for @youCanTDoThisOnEn304.
  ///
  /// In en, this message translates to:
  /// **'You can\'t do this on your own account.'**
  String get youCanTDoThisOnEn304;

  /// No description provided for @connectToTheServerOnceToEn304.
  ///
  /// In en, this message translates to:
  /// **'Connect to the server once to turn on offline admin actions.'**
  String get connectToTheServerOnceToEn304;

  /// No description provided for @finishOrCancelSomeActionsFirstEn304.
  ///
  /// In en, this message translates to:
  /// **'Finish or cancel some actions first'**
  String get finishOrCancelSomeActionsFirstEn304;

  /// No description provided for @thisPhoneDoesnTKnowSEn304.
  ///
  /// In en, this message translates to:
  /// **'This phone doesn\'t know {v0}\'s phone yet. Connect to the server.'**
  String thisPhoneDoesnTKnowSEn304(Object? v0);

  /// No description provided for @thisActionIsTooBigToEn304.
  ///
  /// In en, this message translates to:
  /// **'This action is too big to send.'**
  String get thisActionIsTooBigToEn304;

  /// No description provided for @thisActionIsNotPendingEn304.
  ///
  /// In en, this message translates to:
  /// **'This action is not pending.'**
  String get thisActionIsNotPendingEn304;

  /// No description provided for @thisActionIsNotOnThisEn304.
  ///
  /// In en, this message translates to:
  /// **'This action is not on this phone.'**
  String get thisActionIsNotOnThisEn304;

  /// No description provided for @theseTwoAccountsAreOnTheEn304.
  ///
  /// In en, this message translates to:
  /// **'These two accounts are on the same phone - there is no chat between them.'**
  String get theseTwoAccountsAreOnTheEn304;

  /// No description provided for @adminActionsAreNotReadyEn304.
  ///
  /// In en, this message translates to:
  /// **'Admin actions are not ready.'**
  String get adminActionsAreNotReadyEn304;

  /// No description provided for @thisPhoneDoesnTKnowTheirEn304.
  ///
  /// In en, this message translates to:
  /// **'This phone doesn\'t know their phones yet.'**
  String get thisPhoneDoesnTKnowTheirEn304;

  /// No description provided for @openTheChatAgainFirstEn304.
  ///
  /// In en, this message translates to:
  /// **'Open the chat again first.'**
  String get openTheChatAgainFirstEn304;

  /// No description provided for @youCanTBlockYourOwnEn304.
  ///
  /// In en, this message translates to:
  /// **'You can\'t block your own account.'**
  String get youCanTBlockYourOwnEn304;

  /// No description provided for @pickThisPhoneSVersionOrEn304.
  ///
  /// In en, this message translates to:
  /// **'Pick this phone\'s version or a lower one.'**
  String get pickThisPhoneSVersionOrEn304;

  /// No description provided for @connectToTheServerOnceToEn3042.
  ///
  /// In en, this message translates to:
  /// **'Connect to the server once to turn on offline admin.'**
  String get connectToTheServerOnceToEn3042;

  /// No description provided for @onlyTheOwnerAdminCanSetEn304.
  ///
  /// In en, this message translates to:
  /// **'Only the owner admin can set the minimum version.'**
  String get onlyTheOwnerAdminCanSetEn304;

  /// No description provided for @noLinkupServerIsAvailableOnEn304.
  ///
  /// In en, this message translates to:
  /// **'No LinkUp server is available on the local network.'**
  String get noLinkupServerIsAvailableOnEn304;

  /// No description provided for @chooseAUsernameBetween3AndEn304.
  ///
  /// In en, this message translates to:
  /// **'Choose a username between 3 and 32 characters.'**
  String get chooseAUsernameBetween3AndEn304;

  /// No description provided for @linkupServerCouldNotBeVerifiedEn304.
  ///
  /// In en, this message translates to:
  /// **'LinkUp server could not be verified.'**
  String get linkupServerCouldNotBeVerifiedEn304;

  /// No description provided for @linkupServerIdentityChangedEn304.
  ///
  /// In en, this message translates to:
  /// **'LinkUp server identity changed.'**
  String get linkupServerIdentityChangedEn304;

  /// No description provided for @userNotFoundOrUnavailableEn304.
  ///
  /// In en, this message translates to:
  /// **'User not found or unavailable'**
  String get userNotFoundOrUnavailableEn304;

  /// No description provided for @contactHasNoActiveDeviceEn304.
  ///
  /// In en, this message translates to:
  /// **'Contact has no active device'**
  String get contactHasNoActiveDeviceEn304;

  /// No description provided for @pairAnswerWasNotSentCheckEn304.
  ///
  /// In en, this message translates to:
  /// **'Pair answer was not sent — check the connection and ask them to pair again.'**
  String get pairAnswerWasNotSentCheckEn304;

  /// No description provided for @thisRequestHasExpiredEn304.
  ///
  /// In en, this message translates to:
  /// **'This request has expired.'**
  String get thisRequestHasExpiredEn304;

  /// No description provided for @thisRequestCouldNotBeCheckedEn304.
  ///
  /// In en, this message translates to:
  /// **'This request could not be checked.'**
  String get thisRequestCouldNotBeCheckedEn304;

  /// No description provided for @deviceIdentityIsNotReadyYetEn304.
  ///
  /// In en, this message translates to:
  /// **'Device identity is not ready yet'**
  String get deviceIdentityIsNotReadyYetEn304;

  /// No description provided for @finishSettingUpYourProfileBeforeEn304.
  ///
  /// In en, this message translates to:
  /// **'Finish setting up your profile before pairing'**
  String get finishSettingUpYourProfileBeforeEn304;

  /// No description provided for @identityKeysAreNotReadyOnEn304.
  ///
  /// In en, this message translates to:
  /// **'Identity keys are not ready on this phone — restart the app once and try again.'**
  String get identityKeysAreNotReadyOnEn304;

  /// No description provided for @couldNotSignYourIdentityForEn304.
  ///
  /// In en, this message translates to:
  /// **'Could not sign your identity for pairing.'**
  String get couldNotSignYourIdentityForEn304;

  /// No description provided for @thisContactIsUnavailableOrBlockedEn304.
  ///
  /// In en, this message translates to:
  /// **'This contact is unavailable or blocked'**
  String get thisContactIsUnavailableOrBlockedEn304;

  /// No description provided for @selectedFileIsNoLongerAvailableEn304.
  ///
  /// In en, this message translates to:
  /// **'Selected file is no longer available'**
  String get selectedFileIsNoLongerAvailableEn304;

  /// No description provided for @wiFiDirectTransportIsUnavailableEn304.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi Direct transport is unavailable'**
  String get wiFiDirectTransportIsUnavailableEn304;

  /// No description provided for @downloadFailedEn304.
  ///
  /// In en, this message translates to:
  /// **'Download failed ({v0})'**
  String downloadFailedEn304(Object? v0);

  /// No description provided for @noLocalLanWiFiDirectEn304.
  ///
  /// In en, this message translates to:
  /// **'No local LAN, Wi-Fi Direct, or mesh route is available'**
  String get noLocalLanWiFiDirectEn304;

  /// No description provided for @messageBodyIsTooLargeEn304.
  ///
  /// In en, this message translates to:
  /// **'Message body is too large'**
  String get messageBodyIsTooLargeEn304;

  /// No description provided for @groupNotFoundEn304.
  ///
  /// In en, this message translates to:
  /// **'Group not found'**
  String get groupNotFoundEn304;

  /// No description provided for @messageBodyMustBe16kbOrEn304.
  ///
  /// In en, this message translates to:
  /// **'Message body must be 16KB or less'**
  String get messageBodyMustBe16kbOrEn304;

  /// No description provided for @messageOrAttachmentRequiredEn304.
  ///
  /// In en, this message translates to:
  /// **'Message or attachment required'**
  String get messageOrAttachmentRequiredEn304;

  /// No description provided for @voiceRecordingCouldNotStartEn304.
  ///
  /// In en, this message translates to:
  /// **'Voice recording could not start'**
  String get voiceRecordingCouldNotStartEn304;

  /// No description provided for @voiceRecordingCouldNotBeSavedEn304.
  ///
  /// In en, this message translates to:
  /// **'Voice recording could not be saved'**
  String get voiceRecordingCouldNotBeSavedEn304;

  /// No description provided for @voiceNoteCouldNotBeSavedEn304.
  ///
  /// In en, this message translates to:
  /// **'Voice note could not be saved'**
  String get voiceNoteCouldNotBeSavedEn304;

  /// No description provided for @backupPassphraseMustBeAtLeastEn304.
  ///
  /// In en, this message translates to:
  /// **'Backup passphrase must be at least 10 characters'**
  String get backupPassphraseMustBeAtLeastEn304;

  /// No description provided for @noEncryptedIdentityBackupIsAvailableEn304.
  ///
  /// In en, this message translates to:
  /// **'No encrypted identity backup is available'**
  String get noEncryptedIdentityBackupIsAvailableEn304;

  /// No description provided for @encryptedBackupBelongsToADifferentEn304.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup belongs to a different account'**
  String get encryptedBackupBelongsToADifferentEn304;

  /// No description provided for @thisDeviceIsNotLinkedToEn304.
  ///
  /// In en, this message translates to:
  /// **'This device is not linked to a LinkUp account'**
  String get thisDeviceIsNotLinkedToEn304;

  /// No description provided for @fileTransferCancelledEn304.
  ///
  /// In en, this message translates to:
  /// **'File transfer cancelled'**
  String get fileTransferCancelledEn304;

  /// No description provided for @fileUploadFailedEn304.
  ///
  /// In en, this message translates to:
  /// **'File upload failed ({v0})'**
  String fileUploadFailedEn304(Object? v0);

  /// No description provided for @invalidAdminServerResponseEn304.
  ///
  /// In en, this message translates to:
  /// **'Invalid admin server response.'**
  String get invalidAdminServerResponseEn304;

  /// No description provided for @adminRequestFailedEn304.
  ///
  /// In en, this message translates to:
  /// **'Admin request failed ({v0}).'**
  String adminRequestFailedEn304(Object? v0);

  /// No description provided for @inProgress307.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get inProgress307;

  /// No description provided for @finished307.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get finished307;

  /// No description provided for @seeAll307.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll307;

  /// No description provided for @readyToReadSection307.
  ///
  /// In en, this message translates to:
  /// **'Ready to read'**
  String get readyToReadSection307;

  /// No description provided for @allChats307.
  ///
  /// In en, this message translates to:
  /// **'All chats'**
  String get allChats307;

  /// No description provided for @noServer307.
  ///
  /// In en, this message translates to:
  /// **'No server'**
  String get noServer307;

  /// No description provided for @stepSent307.
  ///
  /// In en, this message translates to:
  /// **'{hl} to {n} phones'**
  String stepSent307(Object? hl, Object? n);

  /// No description provided for @stepPhones307.
  ///
  /// In en, this message translates to:
  /// **'{hl} phones'**
  String stepPhones307(Object? hl);

  /// No description provided for @stepParts307.
  ///
  /// In en, this message translates to:
  /// **'{hl} parts'**
  String stepParts307(Object? hl);

  /// No description provided for @xOfY307.
  ///
  /// In en, this message translates to:
  /// **'{a} of {b}'**
  String xOfY307(Object? a, Object? b);

  /// No description provided for @stepReady307.
  ///
  /// In en, this message translates to:
  /// **'{hl} to read'**
  String stepReady307(Object? hl);

  /// No description provided for @sentWord307.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sentWord307;

  /// No description provided for @waitingForTheirPhones307.
  ///
  /// In en, this message translates to:
  /// **'Waiting for their phones'**
  String get waitingForTheirPhones307;

  /// No description provided for @lookingForTheChat307.
  ///
  /// In en, this message translates to:
  /// **'Looking for the chat'**
  String get lookingForTheChat307;

  /// No description provided for @answerComingFrom307.
  ///
  /// In en, this message translates to:
  /// **'Answer coming from {name}\'s phone'**
  String answerComingFrom307(Object? name);

  /// No description provided for @answerComing307.
  ///
  /// In en, this message translates to:
  /// **'Answer coming'**
  String get answerComing307;

  /// No description provided for @tapToOpenParts307.
  ///
  /// In en, this message translates to:
  /// **'Tap to open · {n} parts'**
  String tapToOpenParts307(Object? n);

  /// No description provided for @noPhoneHasThisChat307.
  ///
  /// In en, this message translates to:
  /// **'No phone has this chat'**
  String get noPhoneHasThisChat307;

  /// No description provided for @chatReady307.
  ///
  /// In en, this message translates to:
  /// **'Chat ready'**
  String get chatReady307;

  /// No description provided for @openChat307.
  ///
  /// In en, this message translates to:
  /// **'Open chat'**
  String get openChat307;

  /// No description provided for @chatRequestsSummary307.
  ///
  /// In en, this message translates to:
  /// **'{n} chat requests · {r} ready'**
  String chatRequestsSummary307(Object? n, Object? r);

  /// No description provided for @chatRequestsChannel307.
  ///
  /// In en, this message translates to:
  /// **'LinkUp chat requests'**
  String get chatRequestsChannel307;

  /// No description provided for @everything307.
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get everything307;

  /// No description provided for @lastWeek307.
  ///
  /// In en, this message translates to:
  /// **'Last week'**
  String get lastWeek307;

  /// No description provided for @lastMonth307.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get lastMonth307;

  /// No description provided for @pickARange307.
  ///
  /// In en, this message translates to:
  /// **'Pick a range'**
  String get pickARange307;

  /// No description provided for @messagesAt307.
  ///
  /// In en, this message translates to:
  /// **'{n} messages · {when}'**
  String messagesAt307(Object? n, Object? when);

  /// No description provided for @searchPeopleOrGroups307.
  ///
  /// In en, this message translates to:
  /// **'Search people or groups'**
  String get searchPeopleOrGroups307;

  /// No description provided for @requestCancelled307.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled'**
  String get requestCancelled307;

  /// No description provided for @phonesNotAnswered307.
  ///
  /// In en, this message translates to:
  /// **'Phones that haven\'t answered yet'**
  String get phonesNotAnswered307;

  /// No description provided for @fromPhone307.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s phone'**
  String fromPhone307(Object? name);

  /// No description provided for @noServerTip307.
  ///
  /// In en, this message translates to:
  /// **'No server · requests go to nearby phones'**
  String get noServerTip307;

  /// No description provided for @onePart313.
  ///
  /// In en, this message translates to:
  /// **'1 part'**
  String get onePart313;

  /// No description provided for @tapToOpenOnePart313.
  ///
  /// In en, this message translates to:
  /// **'Tap to open · 1 part'**
  String get tapToOpenOnePart313;

  /// No description provided for @getChatsBack313.
  ///
  /// In en, this message translates to:
  /// **'Get chats back from friends'**
  String get getChatsBack313;

  /// No description provided for @getChatsBackSub313.
  ///
  /// In en, this message translates to:
  /// **'Messages and voice notes from friends\' phones'**
  String get getChatsBackSub313;

  /// No description provided for @waitingFriendsNearby313.
  ///
  /// In en, this message translates to:
  /// **'Waiting for friends nearby'**
  String get waitingFriendsNearby313;

  /// No description provided for @askingFriend313.
  ///
  /// In en, this message translates to:
  /// **'Asking {name}…'**
  String askingFriend313(Object? name);

  /// No description provided for @gettingFrom313.
  ///
  /// In en, this message translates to:
  /// **'Getting from {name}… {got} of {total}'**
  String gettingFrom313(Object? name, Object? got, Object? total);

  /// No description provided for @restoreDone313.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get restoreDone313;

  /// No description provided for @noFriendsNearby313.
  ///
  /// In en, this message translates to:
  /// **'No friends nearby now · open LinkUp near a friend'**
  String get noFriendsNearby313;

  /// No description provided for @gotMessagesBack313.
  ///
  /// In en, this message translates to:
  /// **'Got {count} messages back from {name}'**
  String gotMessagesBack313(Object? count, Object? name);

  /// No description provided for @gotOneMessageBack313.
  ///
  /// In en, this message translates to:
  /// **'Got 1 message back from {name}'**
  String gotOneMessageBack313(Object? name);

  /// No description provided for @aFriend313.
  ///
  /// In en, this message translates to:
  /// **'a friend'**
  String get aFriend313;

  /// No description provided for @ownChat314.
  ///
  /// In en, this message translates to:
  /// **'You are in this chat. It\'s already on your phone.'**
  String get ownChat314;

  /// No description provided for @alreadyAskedText314.
  ///
  /// In en, this message translates to:
  /// **'This chat already has an open request. Open it or cancel it first.'**
  String get alreadyAskedText314;

  /// No description provided for @alreadyAsked314.
  ///
  /// In en, this message translates to:
  /// **'Already asked'**
  String get alreadyAsked314;

  /// No description provided for @openIt314.
  ///
  /// In en, this message translates to:
  /// **'Open it'**
  String get openIt314;

  /// No description provided for @noOtherGroups314.
  ///
  /// In en, this message translates to:
  /// **'No other groups yet'**
  String get noOtherGroups314;

  /// No description provided for @membersCount314.
  ///
  /// In en, this message translates to:
  /// **'{count} members'**
  String membersCount314(Object? count);

  /// No description provided for @nearbyMembers314.
  ///
  /// In en, this message translates to:
  /// **'Nearby · {count} members'**
  String nearbyMembers314(Object? count);

  /// No description provided for @onYourPhone314.
  ///
  /// In en, this message translates to:
  /// **'On your phone'**
  String get onYourPhone314;

  /// No description provided for @phoneAnswered317.
  ///
  /// In en, this message translates to:
  /// **'{hl} answered'**
  String phoneAnswered317(Object? hl);

  /// No description provided for @namesPhone317.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s phone'**
  String namesPhone317(Object? name);

  /// No description provided for @thePhone317.
  ///
  /// In en, this message translates to:
  /// **'The phone'**
  String get thePhone317;

  /// No description provided for @chatOnTheWay317.
  ///
  /// In en, this message translates to:
  /// **'The chat is on the way'**
  String get chatOnTheWay317;

  /// No description provided for @fileOnTheWay317.
  ///
  /// In en, this message translates to:
  /// **'The file is on the way'**
  String get fileOnTheWay317;

  /// No description provided for @answered317.
  ///
  /// In en, this message translates to:
  /// **'Answered'**
  String get answered317;

  /// No description provided for @deletedAt317.
  ///
  /// In en, this message translates to:
  /// **'Deleted {when}'**
  String deletedAt317(Object? when);

  /// No description provided for @nextInLineFrom317.
  ///
  /// In en, this message translates to:
  /// **'Next in line from {name}\'s phone'**
  String nextInLineFrom317(Object? name);

  /// No description provided for @nextInLine317.
  ///
  /// In en, this message translates to:
  /// **'Next in line'**
  String get nextInLine317;

  /// No description provided for @comingFrom317.
  ///
  /// In en, this message translates to:
  /// **'Coming from {name}\'s phone'**
  String comingFrom317(Object? name);

  /// No description provided for @coming317.
  ///
  /// In en, this message translates to:
  /// **'Coming'**
  String get coming317;

  /// No description provided for @notOnPhoneAnyMore317.
  ///
  /// In en, this message translates to:
  /// **'Not on {name}\'s phone any more'**
  String notOnPhoneAnyMore317(Object? name);

  /// No description provided for @notOnThePhoneAnyMore317.
  ///
  /// In en, this message translates to:
  /// **'Not on the phone any more'**
  String get notOnThePhoneAnyMore317;

  /// No description provided for @tooBigToBring317.
  ///
  /// In en, this message translates to:
  /// **'Too big to bring (over 50 MB)'**
  String get tooBigToBring317;

  /// No description provided for @photoSize317.
  ///
  /// In en, this message translates to:
  /// **'Photo · {size}'**
  String photoSize317(Object? size);

  /// No description provided for @videoSize317.
  ///
  /// In en, this message translates to:
  /// **'Video · {size}'**
  String videoSize317(Object? size);

  /// No description provided for @fileSize317.
  ///
  /// In en, this message translates to:
  /// **'File · {size}'**
  String fileSize317(Object? size);

  /// No description provided for @filesStopped317.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get filesStopped317;

  /// No description provided for @allFilesHere317.
  ///
  /// In en, this message translates to:
  /// **'All files here'**
  String get allFilesHere317;

  /// No description provided for @filesOf317.
  ///
  /// In en, this message translates to:
  /// **'{a} of {b} files'**
  String filesOf317(Object? a, Object? b);

  /// No description provided for @mbOf317.
  ///
  /// In en, this message translates to:
  /// **'{a} of {b}'**
  String mbOf317(Object? a, Object? b);

  /// No description provided for @fromPhone317.
  ///
  /// In en, this message translates to:
  /// **'from {name}\'s phone'**
  String fromPhone317(Object? name);

  /// No description provided for @viaName317.
  ///
  /// In en, this message translates to:
  /// **'via {name}'**
  String viaName317(Object? name);

  /// No description provided for @filesWaiting317.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a phone to bring them'**
  String get filesWaiting317;

  /// No description provided for @filesHereGone317.
  ///
  /// In en, this message translates to:
  /// **'{a} files here · {b} not on the phone any more'**
  String filesHereGone317(Object? a, Object? b);

  /// No description provided for @filesHere317.
  ///
  /// In en, this message translates to:
  /// **'{a} files here'**
  String filesHere317(Object? a);

  /// No description provided for @stopFiles317.
  ///
  /// In en, this message translates to:
  /// **'Stop files'**
  String get stopFiles317;

  /// No description provided for @openChat317.
  ///
  /// In en, this message translates to:
  /// **'Open chat'**
  String get openChat317;

  /// No description provided for @filesComingTitle317.
  ///
  /// In en, this message translates to:
  /// **'Files coming'**
  String get filesComingTitle317;

  /// No description provided for @filesWaitTitle317.
  ///
  /// In en, this message translates to:
  /// **'Files waiting'**
  String get filesWaitTitle317;

  /// No description provided for @filesDoneTitle317.
  ///
  /// In en, this message translates to:
  /// **'Files here'**
  String get filesDoneTitle317;

  /// No description provided for @filesShort317.
  ///
  /// In en, this message translates to:
  /// **'Files {a}/{b}'**
  String filesShort317(Object? a, Object? b);

  /// No description provided for @chatReadyFilesComing317.
  ///
  /// In en, this message translates to:
  /// **'Chat ready · files coming'**
  String get chatReadyFilesComing317;

  /// No description provided for @chatReadyWaiting317.
  ///
  /// In en, this message translates to:
  /// **'Chat ready · waiting for the next trip'**
  String get chatReadyWaiting317;

  /// No description provided for @chatReadyAllHere317.
  ///
  /// In en, this message translates to:
  /// **'Chat ready · all files here'**
  String get chatReadyAllHere317;

  /// No description provided for @lastPartsAgo317.
  ///
  /// In en, this message translates to:
  /// **'last parts {n} min ago'**
  String lastPartsAgo317(Object? n);

  /// No description provided for @filesGoneCount317.
  ///
  /// In en, this message translates to:
  /// **'{n} not on the phone any more'**
  String filesGoneCount317(Object? n);

  /// No description provided for @filesDoneShort317.
  ///
  /// In en, this message translates to:
  /// **'Files ✓'**
  String get filesDoneShort317;

  /// No description provided for @upToDate318.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get upToDate318;

  /// No description provided for @noNewSince318.
  ///
  /// In en, this message translates to:
  /// **'No new messages since {when}'**
  String noNewSince318(Object? when);

  /// No description provided for @upToDateNoNew318.
  ///
  /// In en, this message translates to:
  /// **'Up to date · no new messages'**
  String get upToDateNoNew318;

  /// No description provided for @stepReadyNew318.
  ///
  /// In en, this message translates to:
  /// **'{hl} · {n} new'**
  String stepReadyNew318(Object? hl, Object? n);

  /// No description provided for @nNew318.
  ///
  /// In en, this message translates to:
  /// **'{n} new'**
  String nNew318(Object? n);

  /// No description provided for @addedToCopy318.
  ///
  /// In en, this message translates to:
  /// **'Tap to open · added to your copy'**
  String get addedToCopy318;

  /// No description provided for @chatReadyNew318.
  ///
  /// In en, this message translates to:
  /// **'Chat ready · {n} new'**
  String chatReadyNew318(Object? n);

  /// No description provided for @newSince318.
  ///
  /// In en, this message translates to:
  /// **'New messages since {when}'**
  String newSince318(Object? when);

  /// No description provided for @askingNew318.
  ///
  /// In en, this message translates to:
  /// **'Asking for new messages'**
  String get askingNew318;

  /// No description provided for @newOnly318.
  ///
  /// In en, this message translates to:
  /// **'New only'**
  String get newOnly318;

  /// No description provided for @keptDays318.
  ///
  /// In en, this message translates to:
  /// **'Kept · 7 days'**
  String get keptDays318;

  /// No description provided for @getChatNewOnly318.
  ///
  /// In en, this message translates to:
  /// **'Get chat · new only'**
  String get getChatNewOnly318;

  /// No description provided for @yourCopy318.
  ///
  /// In en, this message translates to:
  /// **'Your copy:'**
  String get yourCopy318;

  /// No description provided for @copyLine318.
  ///
  /// In en, this message translates to:
  /// **'{range} · got {got} · kept until {until}'**
  String copyLine318(Object? range, Object? got, Object? until);

  /// No description provided for @fullChatLower318.
  ///
  /// In en, this message translates to:
  /// **'full chat'**
  String get fullChatLower318;

  /// No description provided for @alreadyHere318.
  ///
  /// In en, this message translates to:
  /// **'Already here · {range}'**
  String alreadyHere318(Object? range);

  /// No description provided for @gotFrom318.
  ///
  /// In en, this message translates to:
  /// **'Got {got} from {name}\'s phone · kept until {until}'**
  String gotFrom318(Object? got, Object? name, Object? until);

  /// No description provided for @gotKept318.
  ///
  /// In en, this message translates to:
  /// **'Got {got} · kept until {until}'**
  String gotKept318(Object? got, Object? until);

  /// No description provided for @insideTitle318.
  ///
  /// In en, this message translates to:
  /// **'Already here · {range} is inside your {copy}'**
  String insideTitle318(Object? range, Object? copy);

  /// No description provided for @insideSub318.
  ///
  /// In en, this message translates to:
  /// **'Got {got} · opens at once, nothing is sent'**
  String insideSub318(Object? got);

  /// No description provided for @getNewOnly318.
  ///
  /// In en, this message translates to:
  /// **'Get new messages only'**
  String get getNewOnly318;

  /// No description provided for @noCardNoPhone318.
  ///
  /// In en, this message translates to:
  /// **'No card, no phone is asked.'**
  String get noCardNoPhone318;

  /// No description provided for @getAllAgain318.
  ///
  /// In en, this message translates to:
  /// **'Get all again'**
  String get getAllAgain318;

  /// No description provided for @getAllAgainSub318.
  ///
  /// In en, this message translates to:
  /// **'The whole range comes again from their phones. Slower, uses more battery.'**
  String get getAllAgainSub318;

  /// No description provided for @viewerKept318.
  ///
  /// In en, this message translates to:
  /// **'{range} · got {got}'**
  String viewerKept318(Object? range, Object? got);

  /// No description provided for @plusNew318.
  ///
  /// In en, this message translates to:
  /// **'+{n} new {when}'**
  String plusNew318(Object? n, Object? when);

  /// No description provided for @more318.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more318;

  /// No description provided for @findAChat320.
  ///
  /// In en, this message translates to:
  /// **'Find a chat'**
  String get findAChat320;

  /// No description provided for @filterAll320.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll320;

  /// No description provided for @filterComing320.
  ///
  /// In en, this message translates to:
  /// **'Coming'**
  String get filterComing320;

  /// No description provided for @filterKept320.
  ///
  /// In en, this message translates to:
  /// **'Kept'**
  String get filterKept320;

  /// No description provided for @now320.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get now320;

  /// No description provided for @nothingHere320.
  ///
  /// In en, this message translates to:
  /// **'Nothing here'**
  String get nothingHere320;

  /// No description provided for @comingFrom320.
  ///
  /// In en, this message translates to:
  /// **'Coming · {name}\'s phone'**
  String comingFrom320(Object? name);

  /// No description provided for @coming320.
  ///
  /// In en, this message translates to:
  /// **'Coming'**
  String get coming320;

  /// No description provided for @waitingForAPhone320.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a phone'**
  String get waitingForAPhone320;

  /// No description provided for @ageMin320.
  ///
  /// In en, this message translates to:
  /// **'{n} min'**
  String ageMin320(Object? n);

  /// No description provided for @ageH320.
  ///
  /// In en, this message translates to:
  /// **'{n} h'**
  String ageH320(Object? n);

  /// No description provided for @ageD320.
  ///
  /// In en, this message translates to:
  /// **'{n} d'**
  String ageD320(Object? n);

  /// No description provided for @keptUntil320.
  ///
  /// In en, this message translates to:
  /// **'Kept until {day}'**
  String keptUntil320(Object? day);

  /// No description provided for @cancelledOn320.
  ///
  /// In en, this message translates to:
  /// **'Cancelled · {day}'**
  String cancelledOn320(Object? day);

  /// No description provided for @new320.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get new320;

  /// No description provided for @waitingFor1Phone320.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {a}\'s phone'**
  String waitingFor1Phone320(Object? a);

  /// No description provided for @waitingFor2Phones320.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {a}\'s or {b}\'s phone'**
  String waitingFor2Phones320(Object? a, Object? b);

  /// No description provided for @waitingForGroup320.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a phone in {group}'**
  String waitingForGroup320(Object? group);

  /// No description provided for @comesByItself320.
  ///
  /// In en, this message translates to:
  /// **'The chat comes by itself as soon as one of their phones is online or near you. There\'s no time limit.'**
  String get comesByItself320;

  /// No description provided for @youWord320.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get youWord320;

  /// No description provided for @askedWord320.
  ///
  /// In en, this message translates to:
  /// **'Asked'**
  String get askedWord320;

  /// No description provided for @sentToWord320.
  ///
  /// In en, this message translates to:
  /// **'Sent to'**
  String get sentToWord320;

  /// No description provided for @nPhones320.
  ///
  /// In en, this message translates to:
  /// **'{n} phones'**
  String nPhones320(Object? n);

  /// No description provided for @onePhone320.
  ///
  /// In en, this message translates to:
  /// **'1 phone'**
  String get onePhone320;

  /// No description provided for @comingParts320.
  ///
  /// In en, this message translates to:
  /// **'Coming · {parts} of {total} parts'**
  String comingParts320(Object? parts, Object? total);

  /// No description provided for @aboutMin320.
  ///
  /// In en, this message translates to:
  /// **'about {n} min'**
  String aboutMin320(Object? n);

  /// No description provided for @underMin320.
  ///
  /// In en, this message translates to:
  /// **'less than a minute'**
  String get underMin320;

  /// No description provided for @moreOnTheWay320.
  ///
  /// In en, this message translates to:
  /// **'More messages on the way…'**
  String get moreOnTheWay320;

  /// No description provided for @keptOnPhoneUntil320.
  ///
  /// In en, this message translates to:
  /// **'Kept on this phone until {day}'**
  String keptOnPhoneUntil320(Object? day);

  /// No description provided for @comingByItself320.
  ///
  /// In en, this message translates to:
  /// **'Coming by itself'**
  String get comingByItself320;

  /// No description provided for @allHere320.
  ///
  /// In en, this message translates to:
  /// **'All here · {n} parts'**
  String allHere320(Object? n);

  /// No description provided for @loginL01_321.
  ///
  /// In en, this message translates to:
  /// **'No LinkUp server answered on this Wi-Fi. Check that the server PC is on and this phone is on the same Wi-Fi.'**
  String get loginL01_321;

  /// No description provided for @loginL02a_321.
  ///
  /// In en, this message translates to:
  /// **'This phone can\'t reach the server PC ({address}) on this Wi-Fi. Turn Wi-Fi off and on, then try again.'**
  String loginL02a_321(Object? address);

  /// No description provided for @loginL02b_321.
  ///
  /// In en, this message translates to:
  /// **'The server PC is not answering. Try again.'**
  String get loginL02b_321;

  /// No description provided for @loginL02c_321.
  ///
  /// In en, this message translates to:
  /// **'The server program is not running on {address}.'**
  String loginL02c_321(Object? address);

  /// No description provided for @loginL03_321.
  ///
  /// In en, this message translates to:
  /// **'Wrong username or password.'**
  String get loginL03_321;

  /// No description provided for @loginL04_321.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong tries. This account is locked for a few minutes.'**
  String get loginL04_321;

  /// No description provided for @loginL05_321.
  ///
  /// In en, this message translates to:
  /// **'Too many tries from this phone. Wait 1 minute.'**
  String get loginL05_321;

  /// No description provided for @loginL06_321.
  ///
  /// In en, this message translates to:
  /// **'This server is not the one this phone knows. Ask the admin.'**
  String get loginL06_321;

  /// No description provided for @loginL07_321.
  ///
  /// In en, this message translates to:
  /// **'This phone must be paired by the admin first.'**
  String get loginL07_321;

  /// No description provided for @loginL08_321.
  ///
  /// In en, this message translates to:
  /// **'This phone was removed by the admin.'**
  String get loginL08_321;

  /// No description provided for @loginL09_321.
  ///
  /// In en, this message translates to:
  /// **'This account is turned off. Ask the admin.'**
  String get loginL09_321;

  /// No description provided for @loginL10_321.
  ///
  /// In en, this message translates to:
  /// **'Update LinkUp to sign in (version {version} or newer).'**
  String loginL10_321(Object? version);

  /// No description provided for @loginL11_321.
  ///
  /// In en, this message translates to:
  /// **'The server had a problem (code {status}). Try again; if it repeats, share logs.'**
  String loginL11_321(Object? status);

  /// No description provided for @loginL12_321.
  ///
  /// In en, this message translates to:
  /// **'The server was found but did not finish signing in. Try again.'**
  String get loginL12_321;

  /// No description provided for @loginL13_321.
  ///
  /// In en, this message translates to:
  /// **'Signed in on this phone only - server not answering ({reason}). It connects by itself later.'**
  String loginL13_321(Object? reason);

  /// No description provided for @loginCode321.
  ///
  /// In en, this message translates to:
  /// **'Code {code} · {address}'**
  String loginCode321(Object? code, Object? address);

  /// No description provided for @loginCodeOnly321.
  ///
  /// In en, this message translates to:
  /// **'Code {code}'**
  String loginCodeOnly321(Object? code);

  /// No description provided for @offlineNoCopy321.
  ///
  /// In en, this message translates to:
  /// **'This phone has no saved sign-in to open offline.'**
  String get offlineNoCopy321;

  /// No description provided for @offlineOtherUser321.
  ///
  /// In en, this message translates to:
  /// **'Offline, this phone opens only the last account used on it.'**
  String get offlineOtherUser321;

  /// No description provided for @offlineBadPassword321.
  ///
  /// In en, this message translates to:
  /// **'Offline, the username and password do not match the copy saved on this phone.'**
  String get offlineBadPassword321;

  /// No description provided for @loginStepSearch321.
  ///
  /// In en, this message translates to:
  /// **'Looking for the server…'**
  String get loginStepSearch321;

  /// No description provided for @loginStepFound321.
  ///
  /// In en, this message translates to:
  /// **'Server found · {address} · signing in…'**
  String loginStepFound321(Object? address);

  /// No description provided for @messagesHere321.
  ///
  /// In en, this message translates to:
  /// **'Messages here · {here} of {total} files coming'**
  String messagesHere321(Object? here, Object? total);

  /// No description provided for @filesNotAvailable321.
  ///
  /// In en, this message translates to:
  /// **'{n} files not available'**
  String filesNotAvailable321(Object? n);

  /// No description provided for @fileNotAvailable321.
  ///
  /// In en, this message translates to:
  /// **'1 file not available'**
  String get fileNotAvailable321;

  /// No description provided for @filesHere321.
  ///
  /// In en, this message translates to:
  /// **'{count} files here'**
  String filesHere321(Object? count);

  /// No description provided for @comingCount321.
  ///
  /// In en, this message translates to:
  /// **'Coming · {count} parts'**
  String comingCount321(Object? count);

  /// No description provided for @countOf321.
  ///
  /// In en, this message translates to:
  /// **'{a} of {b}'**
  String countOf321(Object? a, Object? b);

  /// No description provided for @readWhatIsHere321.
  ///
  /// In en, this message translates to:
  /// **'read what is here already'**
  String get readWhatIsHere321;

  /// No description provided for @nFilesSize321.
  ///
  /// In en, this message translates to:
  /// **'{n} files · {size}'**
  String nFilesSize321(Object? n, Object? size);

  /// No description provided for @partsCount321.
  ///
  /// In en, this message translates to:
  /// **'{a} / {b} parts'**
  String partsCount321(Object? a, Object? b);

  /// No description provided for @comesByItself321.
  ///
  /// In en, this message translates to:
  /// **'comes by itself'**
  String get comesByItself321;

  /// No description provided for @keptHereUntil321.
  ///
  /// In en, this message translates to:
  /// **'Kept here until {day}'**
  String keptHereUntil321(Object? day);

  /// No description provided for @voiceComing321.
  ///
  /// In en, this message translates to:
  /// **'Coming · {a} / {b}'**
  String voiceComing321(Object? a, Object? b);

  /// No description provided for @waitingShort321.
  ///
  /// In en, this message translates to:
  /// **'waiting'**
  String get waitingShort321;

  /// No description provided for @nChats321.
  ///
  /// In en, this message translates to:
  /// **'{n} chats'**
  String nChats321(Object? n);

  /// No description provided for @whatComes324.
  ///
  /// In en, this message translates to:
  /// **'What comes'**
  String get whatComes324;

  /// No description provided for @text324.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get text324;

  /// No description provided for @voiceNotes324.
  ///
  /// In en, this message translates to:
  /// **'Voice notes'**
  String get voiceNotes324;

  /// No description provided for @photos324.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos324;

  /// No description provided for @videos324.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videos324;

  /// No description provided for @videosComeAsAThumbnailOnly324.
  ///
  /// In en, this message translates to:
  /// **'Videos come as a thumbnail only'**
  String get videosComeAsAThumbnailOnly324;

  /// No description provided for @sizesAppearWhenThePhoneAnswers324.
  ///
  /// In en, this message translates to:
  /// **'Sizes appear when the phone answers'**
  String get sizesAppearWhenThePhoneAnswers324;

  /// No description provided for @askedAgo324.
  ///
  /// In en, this message translates to:
  /// **'asked {ago}'**
  String askedAgo324(String ago);

  /// No description provided for @anHourAgo324.
  ///
  /// In en, this message translates to:
  /// **'1 hour ago'**
  String get anHourAgo324;

  /// No description provided for @hoursAgo324.
  ///
  /// In en, this message translates to:
  /// **'{n} hours ago'**
  String hoursAgo324(int n);

  /// No description provided for @aDayAgo324.
  ///
  /// In en, this message translates to:
  /// **'1 day ago'**
  String get aDayAgo324;

  /// No description provided for @daysAgo324.
  ///
  /// In en, this message translates to:
  /// **'{n} days ago'**
  String daysAgo324(int n);

  /// No description provided for @stillComing324.
  ///
  /// In en, this message translates to:
  /// **'still coming'**
  String get stillComing324;

  /// No description provided for @holdingTheLine324.
  ///
  /// In en, this message translates to:
  /// **'Holding the line — Stop it if you don\'t need it'**
  String get holdingTheLine324;

  /// No description provided for @installing324.
  ///
  /// In en, this message translates to:
  /// **'Installing…'**
  String get installing324;

  /// No description provided for @couldNotGetItNow324.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t get it now'**
  String get couldNotGetItNow324;

  /// No description provided for @tryAgain324.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain324;

  /// No description provided for @dismiss324.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss324;

  /// No description provided for @youCanLeaveThisScreen324.
  ///
  /// In en, this message translates to:
  /// **'You can leave this screen'**
  String get youCanLeaveThisScreen324;

  /// No description provided for @gettingUpdatePct324.
  ///
  /// In en, this message translates to:
  /// **'Getting the update · {pct}%'**
  String gettingUpdatePct324(String pct);

  /// No description provided for @theUpdateIsHere324.
  ///
  /// In en, this message translates to:
  /// **'The update is here'**
  String get theUpdateIsHere324;

  /// No description provided for @nRequests324.
  ///
  /// In en, this message translates to:
  /// **'{n} requests'**
  String nRequests324(int n);

  /// No description provided for @filesTakeTurns324.
  ///
  /// In en, this message translates to:
  /// **'Files take turns, 2 at a time'**
  String get filesTakeTurns324;

  /// No description provided for @getPhotos324.
  ///
  /// In en, this message translates to:
  /// **'Get photos'**
  String get getPhotos324;

  /// No description provided for @videosNotAsked324.
  ///
  /// In en, this message translates to:
  /// **'videos not asked'**
  String get videosNotAsked324;

  /// No description provided for @waiting325.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get waiting325;

  /// No description provided for @askedAgo325.
  ///
  /// In en, this message translates to:
  /// **'asked {when}'**
  String askedAgo325(Object? when);

  /// No description provided for @goesWhenNear325.
  ///
  /// In en, this message translates to:
  /// **'goes the moment their phone is near'**
  String get goesWhenNear325;

  /// No description provided for @askForFile326.
  ///
  /// In en, this message translates to:
  /// **'Send this file?'**
  String get askForFile326;

  /// No description provided for @send326.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send326;

  /// No description provided for @wifiOnly326.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi only'**
  String get wifiOnly326;

  /// No description provided for @refuse326.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get refuse326;

  /// No description provided for @evidence329.
  ///
  /// In en, this message translates to:
  /// **'Export evidence'**
  String get evidence329;

  /// No description provided for @evidenceWhat329Short.
  ///
  /// In en, this message translates to:
  /// **'What this phone did, in a file'**
  String get evidenceWhat329Short;

  /// No description provided for @evidenceWhat329.
  ///
  /// In en, this message translates to:
  /// **'This phone keeps its own record: what it asked for, what it answered, and what you said on each consent card. Each line carries the stamp of the line before it, so if one word is changed the file no longer adds up.'**
  String get evidenceWhat329;

  /// No description provided for @evidenceNothing329.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded yet'**
  String get evidenceNothing329;

  /// No description provided for @evidenceCopied329.
  ///
  /// In en, this message translates to:
  /// **'Evidence copied'**
  String get evidenceCopied329;

  /// No description provided for @evidenceFile329.
  ///
  /// In en, this message translates to:
  /// **'The file'**
  String get evidenceFile329;

  /// No description provided for @evidenceHonest329.
  ///
  /// In en, this message translates to:
  /// **'This is a record, not a promise: it shows what this phone wrote. It is never uploaded, and it stays on the phone until you copy it out.'**
  String get evidenceHonest329;

  /// No description provided for @copyEvidence329.
  ///
  /// In en, this message translates to:
  /// **'Copy evidence'**
  String get copyEvidence329;

  /// No description provided for @checkAgain329.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get checkAgain329;

  /// No description provided for @evidenceChecksOut329.
  ///
  /// In en, this message translates to:
  /// **'All {n} lines add up'**
  String evidenceChecksOut329(int n);

  /// No description provided for @evidenceBroken329.
  ///
  /// In en, this message translates to:
  /// **'Line {n} does not add up - the file was changed'**
  String evidenceBroken329(int n);

  /// No description provided for @phoneToPhone327.
  ///
  /// In en, this message translates to:
  /// **'phone to phone · 0 MB'**
  String get phoneToPhone327;

  /// No description provided for @safetyNumber328.
  ///
  /// In en, this message translates to:
  /// **'Safety number'**
  String get safetyNumber328;

  /// No description provided for @safetyNumberNotYet328.
  ///
  /// In en, this message translates to:
  /// **'Not on this phone yet'**
  String get safetyNumberNotYet328;

  /// No description provided for @safetyNumberNotYetWhy328.
  ///
  /// In en, this message translates to:
  /// **'We do not have this person\'s keys on this phone yet. Open the app together once on the same Wi-Fi, then come back and compare.'**
  String get safetyNumberNotYetWhy328;

  /// No description provided for @compareInPerson328.
  ///
  /// In en, this message translates to:
  /// **'Read these numbers to each other in person, and check they are the same on both phones. If they match, nobody is standing in the middle.'**
  String get compareInPerson328;

  /// No description provided for @safetyNumberWhat328.
  ///
  /// In en, this message translates to:
  /// **'The number is made from both phones\' keys. It never goes to any server, and you can check it without internet.'**
  String get safetyNumberWhat328;

  /// No description provided for @askByQr330.
  ///
  /// In en, this message translates to:
  /// **'Ask by QR or link'**
  String get askByQr330;

  /// No description provided for @askByQrWhat330.
  ///
  /// In en, this message translates to:
  /// **'Show this to the other person when the two phones are not on the same Wi-Fi. Their phone files the same ask and answers when you are near again.'**
  String get askByQrWhat330;

  /// No description provided for @askCodeRead330.
  ///
  /// In en, this message translates to:
  /// **'or read these letters to each other'**
  String get askCodeRead330;

  /// No description provided for @copyAskLink330.
  ///
  /// In en, this message translates to:
  /// **'Copy the link'**
  String get copyAskLink330;

  /// No description provided for @scanTheirAsk330.
  ///
  /// In en, this message translates to:
  /// **'Scan their ask'**
  String get scanTheirAsk330;

  /// No description provided for @askLinkCopied330.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get askLinkCopied330;

  /// No description provided for @notAnAskLink330.
  ///
  /// In en, this message translates to:
  /// **'That is not an ask link'**
  String get notAnAskLink330;

  /// No description provided for @askTaken330.
  ///
  /// In en, this message translates to:
  /// **'Ask kept - it will be answered when you are near'**
  String get askTaken330;

  /// No description provided for @askTakeFailed330.
  ///
  /// In en, this message translates to:
  /// **'Could not keep that ask'**
  String get askTakeFailed330;

  /// No description provided for @askTaking330.
  ///
  /// In en, this message translates to:
  /// **'Keeping it…'**
  String get askTaking330;

  /// No description provided for @askByQrHonest330.
  ///
  /// In en, this message translates to:
  /// **'The link names a chat, not a session: it never expires, and it is answered phone to phone - nothing is uploaded.'**
  String get askByQrHonest330;

  /// No description provided for @whatThisPhoneCanDo331.
  ///
  /// In en, this message translates to:
  /// **'What this phone can do'**
  String get whatThisPhoneCanDo331;

  /// No description provided for @honestDatesAndLimits331.
  ///
  /// In en, this message translates to:
  /// **'Right now, and nothing dressed up'**
  String get honestDatesAndLimits331;

  /// No description provided for @askZeroMb331.
  ///
  /// In en, this message translates to:
  /// **'The chat comes from the other phone directly: nothing goes to the server.'**
  String get askZeroMb331;

  /// No description provided for @askHonest331.
  ///
  /// In en, this message translates to:
  /// **'No phone is linked this moment, so an ask waits. It is kept - nothing expires.'**
  String get askHonest331;

  /// No description provided for @nothingRecorded331.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded yet'**
  String get nothingRecorded331;

  /// No description provided for @honestNote331.
  ///
  /// In en, this message translates to:
  /// **'This screen only shows what the phone can actually see. If it says waiting, nothing is on its way - that is the honest answer, not a spinner.'**
  String get honestNote331;

  /// No description provided for @nothingToSend336.
  ///
  /// In en, this message translates to:
  /// **'nothing to send'**
  String get nothingToSend336;

  /// No description provided for @notRegistered338.
  ///
  /// In en, this message translates to:
  /// **'This phone is not registered with the server'**
  String get notRegistered338;

  /// No description provided for @notRegisteredWhy338.
  ///
  /// In en, this message translates to:
  /// **'The server holds a different security key for this account, so server features are off on this phone. Messages, calls and files still travel phone to phone.'**
  String get notRegisteredWhy338;

  /// No description provided for @reRegisterPhone338.
  ///
  /// In en, this message translates to:
  /// **'Re-register this phone'**
  String get reRegisterPhone338;

  /// No description provided for @reRegisterWhat338.
  ///
  /// In en, this message translates to:
  /// **'This replaces the key the server holds for your account. The other phone will need to re-register too.'**
  String get reRegisterWhat338;

  /// No description provided for @reRegisterNothingSent338.
  ///
  /// In en, this message translates to:
  /// **'Nothing is sent until you tap Send.'**
  String get reRegisterNothingSent338;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ur'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ur':
      return AppLocalizationsUr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
