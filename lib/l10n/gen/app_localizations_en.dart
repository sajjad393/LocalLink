// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aConsistentCopyOfTheLinkup =>
      'A consistent copy of the LinkUp database will be written to the server backup directory.';

  @override
  String get aLinkupPhoneHelpingToPass =>
      'A LinkUp phone helping to pass your messages. It can\'t read them.';

  @override
  String get aNearbyPhone => 'a nearby phone';

  @override
  String aNearbyPhone2(Object? firstCarrier) {
    return 'a nearby phone ($firstCarrier)';
  }

  @override
  String get aNewAccountIdentityKeyWill =>
      'A new account identity key will become active. The previous key is retained on this phone as local key history. Other devices will learn the new public key automatically.';

  @override
  String get aNewerLinkupIsNeededPlease =>
      'A newer LinkUp is needed. Please update.';

  @override
  String get aSmallMapOfYourContacts =>
      'A small map of your contacts at the top of Chats';

  @override
  String aboutFreeSpace(Object? sizeLabel) {
    return 'About $sizeLabel free space';
  }

  @override
  String get accept => 'Accept';

  @override
  String get acceptNewCode => 'Accept new code';

  @override
  String get account => 'Account';

  @override
  String get accountClosed => 'Account closed';

  @override
  String get accountClosedByAdmin => 'Account closed by admin';

  @override
  String get accountClosedByAdminYouCan =>
      'Account closed by admin. You can read old chats but can\'t send or call.';

  @override
  String get accountDataRestored => 'Account data restored';

  @override
  String accountPhonesBackup(Object? nickname) {
    return '@$nickname · Account, phones, backup';
  }

  @override
  String get accountPhonesBackup2 => 'Account, phones, backup';

  @override
  String get accountProfileMetadataDevicesGroupsMessages =>
      'Account/profile metadata, devices, groups, messages, group messages and call history. File content is not downloaded automatically.';

  @override
  String get accountRecoveredOnThisPhone => 'Account recovered on this phone.';

  @override
  String get accountRecoveredPreviousActiveDevicesWere =>
      'Account recovered. Previous active devices were revoked.';

  @override
  String get accountRecoveredSuccessfully => 'Account recovered successfully.';

  @override
  String get accountRecovery => 'Account recovery';

  @override
  String get accountRecoveryQueue => 'Account recovery queue';

  @override
  String get accountStopped => 'Account stopped';

  @override
  String get accountTurnedOnAgain => 'Account turned on again';

  @override
  String get accountsAndProfiles => 'Accounts and profiles';

  @override
  String get actionsGoToHerPhoneBy =>
      'Actions go to her phone by card (Pending until done). More actions after she joins the server.';

  @override
  String get actionsThePhonesDidShowHere => 'Actions the phones did show here.';

  @override
  String get actionsWaitHereUntilEachPhone =>
      'Actions wait here until each phone does it. There is no time limit.';

  @override
  String get active => 'Active';

  @override
  String get activeAgain => 'Active again';

  @override
  String get activeCalls => 'Active calls';

  @override
  String get activeSessions => 'Active sessions';

  @override
  String get activityAnalytics => 'Activity analytics';

  @override
  String get add => 'Add';

  @override
  String get addAContactOrDiscoverNearby =>
      'Add a contact or discover nearby LinkUp phones.';

  @override
  String addAsAFriend(Object? displayName) {
    return 'Add $displayName as a friend?';
  }

  @override
  String get addContact => 'Add Contact';

  @override
  String get addContact2 => 'Add contact';

  @override
  String get addFriend => 'Add friend';

  @override
  String get addGroupDescription => 'Add group description';

  @override
  String get addGroupPhotoOptional => 'Add group photo (optional)';

  @override
  String get addMeOnLinkup => 'ADD ME ON LINKUP';

  @override
  String get addMember => 'Add member';

  @override
  String get addMembers => 'Add members';

  @override
  String get addOption => 'Add option';

  @override
  String addPeopleUpTo(Object? kNewGroupMax) {
    return 'Add people · up to $kNewGroupMax';
  }

  @override
  String get addToGroup => 'Add to group';

  @override
  String added(Object? atMs) {
    return 'Added · $atMs';
  }

  @override
  String added2(Object? name) {
    return '$name added';
  }

  @override
  String get addedByYou => 'Added by you';

  @override
  String addedByYou2(Object? day, Object? month) {
    return 'Added by you · $day $month';
  }

  @override
  String addedByYouToday(Object? hh, Object? mm) {
    return 'Added by you · today $hh:$mm';
  }

  @override
  String addedMembers304(Object? actor, Object? targets) {
    return '$actor added $targets';
  }

  @override
  String addedToTheGroup(Object? selected) {
    return '$selected added to the group.';
  }

  @override
  String addedYou(Object? actor) {
    return '$actor added you';
  }

  @override
  String adding(Object? invites) {
    return 'Adding $invites';
  }

  @override
  String adding2(Object? phone) {
    return 'Adding $phone…';
  }

  @override
  String get addingNowNearby => 'Adding now · Nearby';

  @override
  String get addingPeople => 'Adding people';

  @override
  String get admin => 'Admin';

  @override
  String admin2(Object? level) {
    return 'Admin · $level';
  }

  @override
  String admin3(Object? r, Object? substring) {
    return 'Admin · $r$substring';
  }

  @override
  String get adminActions => 'Admin actions';

  @override
  String get adminActionsAreNotReadyOn =>
      'Admin actions are not ready on this phone';

  @override
  String get adminActionsSaved => 'Admin actions saved';

  @override
  String get adminBadge => 'Admin badge';

  @override
  String get adminBecomesTheNewOwner => ' (admin) becomes the new owner.';

  @override
  String get adminBlocked => 'Admin blocked';

  @override
  String get adminConsole => 'Admin console';

  @override
  String get adminPolicy => 'admin policy';

  @override
  String get adminSessionExpiredPleaseSignIn =>
      'Admin session expired. Please sign in again.';

  @override
  String get adminSettings => 'Admin settings';

  @override
  String get adminSettings2 => 'Admin Settings';

  @override
  String get adminTools => 'admin tools';

  @override
  String get adminToolsAreNotAvailableRight =>
      'Admin tools are not available right now';

  @override
  String get adminToolsAreOffOnThis => 'Admin tools are off on this phone.';

  @override
  String administration(Object? title) {
    return 'Administration / $title';
  }

  @override
  String get administratorNote => 'Administrator note';

  @override
  String get admins => 'Admins';

  @override
  String get adminsApprovePeopleWhoJoinBy =>
      'Admins approve people who join by QR';

  @override
  String get adminsDecide => 'Admins decide';

  @override
  String get adminsOnlyNotifyEveryone => 'Admins only: notify everyone';

  @override
  String get adminsSignedIn => 'Admins signed in';

  @override
  String affectsPhoneSeenNearby(Object? affects, Object? s) {
    return 'Affects $affects phone$s seen nearby';
  }

  @override
  String get alertAfter => 'Alert after';

  @override
  String get alertsAndPolicy => 'Alerts and policy';

  @override
  String all(Object? reactions) {
    return 'All $reactions';
  }

  @override
  String get all2 => 'All';

  @override
  String allAreYoursAndLessThan(Object? count) {
    return 'All $count are yours and less than 5 minutes old, so \"Delete for everyone\" is shown. A copy someone saved to the Gallery stays.';
  }

  @override
  String get allGood => 'All good';

  @override
  String get allMembers => 'All members';

  @override
  String get allMembersAddPeople => 'All members add people';

  @override
  String get allMessagesPhotosAndFilesIn =>
      'All messages, photos and files in this chat are ';

  @override
  String get allMessagesPhotosAndFilesOf =>
      'All messages, photos and files of this group are removed from this phone.';

  @override
  String get allTools => 'all tools';

  @override
  String get allow => 'Allow';

  @override
  String get allowNameSearchesToReturnYour =>
      'Allow name searches to return your profile';

  @override
  String get allowNearbyDevicesToReachPeople =>
      'Allow nearby devices to reach people without internet.';

  @override
  String get allowPeopleToFindYouWith =>
      'Allow people to find you with your phone number';

  @override
  String get allowTheNearbyDevicesPermissionThen =>
      'Allow the \"Nearby devices\" permission, then tap Add friend again.';

  @override
  String get allowed => 'Allowed';

  @override
  String get allowedRequired => 'Allowed — required';

  @override
  String get alreadyInTheGroup => 'Already in the group';

  @override
  String get alsoStopVeryOldApps => 'Also stop very old apps';

  @override
  String get always => 'Always';

  @override
  String get alwaysOff => 'Always off';

  @override
  String get alwaysOn => 'Always on';

  @override
  String get alwaysUseTheDarkTheme => 'Always use the dark theme.';

  @override
  String get alwaysUseTheLightTheme => 'Always use the light theme.';

  @override
  String get anAdmin => 'An admin';

  @override
  String get anAdmin2 => 'an admin';

  @override
  String anAdminMustAddYouThis(Object? from) {
    return 'An admin must add you. This stays for 24 hours. You get \"$from added you\" when it is done.';
  }

  @override
  String get anAdminMustSayYesThis =>
      'An admin must say yes. This stays for 24 hours. The group opens in your Chats when it is done.';

  @override
  String get anAndroidPhone => '•  An Android phone';

  @override
  String and(Object? join, Object? parts) {
    return '$join and $parts';
  }

  @override
  String andAreTyping(Object? clean, Object? clean2) {
    return '$clean and $clean2 are typing…';
  }

  @override
  String get andItLeavesYourChatsList => ' and it leaves your Chats list.';

  @override
  String andMoreAskedToJoin(Object? first, Object? n) {
    return '$first and $n more asked to join';
  }

  @override
  String get android => 'Android';

  @override
  String get android14FullScreenWhenLocked =>
      'Android 14+: full screen when locked';

  @override
  String get androidControls => 'Android controls';

  @override
  String get androidTurnedTheLinkupWiFi =>
      'Android turned the LinkUp Wi-Fi off.';

  @override
  String get androidWillAskConnectEachTime =>
      'Android will ask \"Connect?\" each time this phone joins another group or hotspot. Tap Connect to allow it. Needs Android 10 or newer.';

  @override
  String get androidWillAskYouToAllow =>
      'Android will ask you to allow installs from LinkUp. Turn it on, then come back.';

  @override
  String get anotherAccount => 'another account';

  @override
  String get anotherCallIsAlreadyActive => 'Another call is already active';

  @override
  String get answer => 'Answer';

  @override
  String get answerTheyCanChangeItFor =>
      ' answer. They can change it for 3 minutes after voting, then it\'s final.';

  @override
  String get anyoneCanFindYouByName =>
      'Anyone can find you by name and see your phone number.';

  @override
  String get anyoneThisPhoneHasSeenOr =>
      'Anyone this phone has seen, or nearby';

  @override
  String get anyoneWhoScansThisNearA =>
      'Anyone who scans this near a member can ask to join. It works without internet.\n';

  @override
  String get anyoneWithLinkupWhoOpensThis =>
      'Anyone with LinkUp who opens this link can ask to join, from anywhere. It needs internet (the server). With \"Approve new members\" on, an admin must say yes.';

  @override
  String get anyoneWithTheLinkCanAsk => 'Anyone with the link can ask to join';

  @override
  String get anyoneWithThisCodeCanReset =>
      'Anyone with this code can reset your password. LinkUp will never ask for it.';

  @override
  String get appInfoBatteryAllowBackgroundActivity =>
      'App info > Battery: Allow background activity';

  @override
  String get appInfoBatterySaverChooseNo =>
      'App info > Battery saver: choose No restrictions';

  @override
  String get appLaunchTurnOffManageAutomatically =>
      'App launch: turn off Manage automatically for LinkUp';

  @override
  String get appTooOldToAnswer => 'app too old to answer';

  @override
  String get appVersion => 'App version';

  @override
  String get appearance => 'Appearance';

  @override
  String get approveAndGiveCode => 'Approve and give code';

  @override
  String get approveNewMembers => 'Approve new members';

  @override
  String get approved => 'Approved';

  @override
  String get approvedEnterTheRecoveryCodeProvided =>
      'Approved. Enter the recovery code provided by the administrator.';

  @override
  String approvedRecoveryFor(Object? admin, Object? target) {
    return '$admin approved recovery for $target';
  }

  @override
  String get appsBefore3054Can =>
      'Apps before 3.0.54 can\'t read this rule. The server refuses them.';

  @override
  String get apr => 'Apr';

  @override
  String areRequiredFillThemInBefore(Object? and) {
    return '$and are required — fill them in before saving.';
  }

  @override
  String get askAQuestion => 'Ask a question';

  @override
  String get askPhones => 'Ask phones';

  @override
  String get askPhonesForAChatOwner => 'Ask phones for a chat · Owner only';

  @override
  String get askTheAdmin => 'Ask the admin';

  @override
  String get askTheAdminForTheCode => 'Ask the admin for the code.';

  @override
  String get askTheAdminToApproveIt => 'Ask the admin to approve it';

  @override
  String get askThemToOpenTheLink =>
      'Ask them to open the link again with the newest LinkUp.';

  @override
  String get askToJoin => 'Ask to join';

  @override
  String asked(Object? created_at, Object? expires_at) {
    return 'Asked $created_at · $expires_at';
  }

  @override
  String get askedThePhoneForTheFull => 'Asked the phone for the full file';

  @override
  String get atLeast8Characters => 'At least 8 characters';

  @override
  String get attach => 'Attach';

  @override
  String get auditLog => 'Audit log';

  @override
  String get auditLog2 => 'Audit Log';

  @override
  String get auditedEventsSessionsAndOutstandingRecovery =>
      'Audited events, sessions and outstanding recovery work';

  @override
  String get auditor => 'Auditor';

  @override
  String get aug => 'Aug';

  @override
  String get authenticatedDeviceSessions => 'Authenticated device sessions';

  @override
  String get authenticatedSessions => 'Authenticated sessions';

  @override
  String get autoFixed => 'Auto-fixed';

  @override
  String get autoLaunchTurnLinkupOn => 'Auto launch: turn LinkUp ON';

  @override
  String get autoStartTurnLinkupOn => 'Auto-start: turn LinkUp ON';

  @override
  String get autostartTurnLinkupOn => 'Autostart: turn LinkUp ON';

  @override
  String get available => 'Available';

  @override
  String get avoidWiFiDirectAndMesh =>
      'Avoid Wi-Fi Direct and mesh messaging. LinkUp uses the configured server connection when available; this does not guarantee that the server itself is on the public Internet.';

  @override
  String get back => 'Back';

  @override
  String get backToStep1 => '←  Back to step 1';

  @override
  String get backUpNow => 'Back up now';

  @override
  String get backgroundPowerUseAllowLinkup =>
      'Background power use: allow LinkUp';

  @override
  String get backup => 'Backup';

  @override
  String get backupAndRestore => 'Backup and restore';

  @override
  String get backupAndSafety => 'Backup and safety';

  @override
  String get backupCompleted => 'Backup completed.';

  @override
  String get backupCouldNotBeCreated => 'Backup could not be created.';

  @override
  String get backupMade => 'Backup made.';

  @override
  String get backupPassphrase => 'Backup passphrase';

  @override
  String backupWrittenTo(Object? path) {
    return 'Backup written to $path';
  }

  @override
  String get batteryChooseUnrestricted => 'Battery: choose Unrestricted';

  @override
  String get batteryLow10OrLess => 'Battery low (10% or less)';

  @override
  String batteryOptimizationIsAlreadyIgnored(Object? lockedToast) {
    return '$lockedToast Battery optimization is already ignored.';
  }

  @override
  String get batteryPermissionDialogsAreShownOnly =>
      'Battery-permission dialogs are shown only when you tap a row. Nothing is enabled silently.';

  @override
  String get becomesTheNewOwner => ' becomes the new owner.';

  @override
  String get below => ' below.';

  @override
  String get biggestFirstTapToOpenHold =>
      'Biggest first. Tap to open, hold to pick.';

  @override
  String get block => 'Block';

  @override
  String block2(Object? name) {
    return 'Block $name';
  }

  @override
  String block3(Object? name) {
    return 'Block $name?';
  }

  @override
  String get blockAUser => 'Block a user';

  @override
  String blockFailed(Object? error) {
    return 'Block failed: $error';
  }

  @override
  String get blockForEveryone => 'Block for everyone';

  @override
  String get blockOrUnblockAUser => 'Block or unblock a user';

  @override
  String get blockSavedOnTheServer => 'Block saved on the server';

  @override
  String blockSavedOnTheServer2(Object? user) {
    return '$user block saved on the server';
  }

  @override
  String get blockUser => 'Block user';

  @override
  String get blockUsersAllPhones => 'Block users (all phones)';

  @override
  String get blocked => 'Blocked';

  @override
  String blocked2(Object? toLocal) {
    return 'Blocked $toLocal';
  }

  @override
  String blocked3(Object? when) {
    return 'blocked $when';
  }

  @override
  String blocked4(Object? name) {
    return '$name blocked';
  }

  @override
  String blocked5(Object? admin, Object? target) {
    return '$admin blocked $target';
  }

  @override
  String blocked6(Object? label) {
    return '$label · Blocked';
  }

  @override
  String blockedBy(Object? by, Object? at, Object? phones) {
    return 'Blocked by $by · $at$phones';
  }

  @override
  String get blockedByAdmin => 'Blocked by admin';

  @override
  String get blockedByAdminYouCanT => 'Blocked by admin. You can\'t send.';

  @override
  String get blockedList => 'Blocked list';

  @override
  String blockedOn(Object? when) {
    return 'Blocked on $when.';
  }

  @override
  String blockedOnEveryLinkupPhoneIt(Object? all) {
    return '$all blocked · on every LinkUp phone it reaches';
  }

  @override
  String get blockedOnThisPhone => 'Blocked on this phone';

  @override
  String blockedOnThisPhone2(Object? name) {
    return '$name blocked on this phone.';
  }

  @override
  String get blockedPeople => 'Blocked people';

  @override
  String get blockedRelaysOnly => 'Blocked · relays only';

  @override
  String get blockedServerLater => 'Blocked · server later';

  @override
  String get blocks => 'Blocks';

  @override
  String blueInTheChatOnlyWhen(Object? total) {
    return 'Blue ✓✓ in the chat only when all $total have read it. People with read receipts off show under Delivered.';
  }

  @override
  String get bluetoothNotAllowed => 'Bluetooth not allowed';

  @override
  String get bluetoothOff => 'Bluetooth off';

  @override
  String get bluetoothOn => 'Bluetooth on';

  @override
  String get bridgeToWiFi => 'Bridge to Wi-Fi';

  @override
  String build(Object? build) {
    return 'Build $build';
  }

  @override
  String build2(Object? build) {
    return 'build $build';
  }

  @override
  String build3(Object? version, Object? build) {
    return '$version (build $build)';
  }

  @override
  String get busy => 'Busy';

  @override
  String get call => 'Call';

  @override
  String get callAlertsOffTapToTurn => 'Call alerts off - tap to turn on';

  @override
  String get callAlertsOn => 'Call alerts on';

  @override
  String get callAudio => 'Call audio';

  @override
  String get callBack => 'Call back';

  @override
  String get callCanceled => 'Call canceled';

  @override
  String get callEnded => 'Call ended';

  @override
  String get callEndedNoNearbyConnection => 'Call ended: no nearby connection';

  @override
  String get callFailed => 'Call failed';

  @override
  String get callInProgress => 'Call in progress';

  @override
  String get callIsNoLongerAvailable => 'Call is no longer available';

  @override
  String get callSessions => 'Call sessions';

  @override
  String get calling => 'Calling…';

  @override
  String callingTapToReturn(Object? name) {
    return '$name · Calling… — Tap to return';
  }

  @override
  String calls(Object? startedAt, Object? count) {
    return '$startedAt · $count calls';
  }

  @override
  String get calls2 => 'Calls';

  @override
  String get callsPassedOnNow => 'Calls passed on now';

  @override
  String get callsRingButNoAcceptButton => 'Calls ring, but no Accept button';

  @override
  String get callsRingWithAcceptReject => 'Calls ring with Accept / Reject';

  @override
  String get callsShowHereWithNamesAnd =>
      'Calls show here with names and times.';

  @override
  String get callsToday => 'Calls today';

  @override
  String get cameByLocalWiFi => 'Came by Local Wi-Fi';

  @override
  String get cameByMeshThroughAFriend =>
      'Came by Mesh (through a friend\'s phone)';

  @override
  String get cameByWiFiDirect => 'Came by Wi-Fi Direct';

  @override
  String get cameThroughTheServer => 'Came through the server';

  @override
  String get camera => 'Camera';

  @override
  String canAskAgainLater(Object? they) {
    return '$they can ask again later.';
  }

  @override
  String get canHelpIfYouForgetYour =>
      'Can help if you forget your password, lose a phone, or your Wi-Fi settings need fixing.';

  @override
  String get canOnlyLook => 'can only look';

  @override
  String get canSendMessages => ' can send messages.';

  @override
  String canStillReadThemUnblockAnytime(Object? first) {
    return '$first can still read them. Unblock anytime';
  }

  @override
  String get canTJoinTheServerYet => 'Can\'t join the server yet';

  @override
  String canTMessageOrCallYou(Object? name) {
    return '$name **can\'t message or call** you, and their adds are ignored.';
  }

  @override
  String get canTOpenTheLinkNow =>
      'Can\'t open the link now. Check the internet and try again.';

  @override
  String get canTPlayThisVideo => 'Can\'t play this video';

  @override
  String get canTSendOrGetThem => 'Can\'t send or get them on any phone';

  @override
  String get canTSignInForNow => 'Can’t sign in for now';

  @override
  String canTSignInUntilYou(Object? name) {
    return '$name can’t sign in until you set Active again.';
  }

  @override
  String get canUseLinkup => 'Can use LinkUp';

  @override
  String canUseLinkupAgain(Object? name) {
    return '$name can use LinkUp again.';
  }

  @override
  String canUseLinkupAtOnce(Object? first) {
    return '$first can use LinkUp at once';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get cancelAction => 'Cancel action';

  @override
  String get cancelDownload => 'Cancel download';

  @override
  String get cancelReply => 'Cancel reply';

  @override
  String get cancelRequest => 'Cancel request';

  @override
  String cancelThis(Object? what) {
    return 'Cancel this $what?';
  }

  @override
  String get cancelThisAction => 'Cancel this action?';

  @override
  String get cancelThisRequest => 'Cancel this request?';

  @override
  String get cancelTransfer => 'Cancel transfer';

  @override
  String get canceled => 'Canceled';

  @override
  String get cancelled => 'Cancelled';

  @override
  String cancelled2(Object? finishedAt) {
    return 'Cancelled $finishedAt';
  }

  @override
  String carriedBy(Object? n) {
    return 'carried by $n';
  }

  @override
  String get carriedByAPhone => 'carried by a phone';

  @override
  String get changeKey => 'Change key';

  @override
  String get changeProfilePhoto => 'Change profile photo';

  @override
  String get changeSecurityKey => 'Change security key?';

  @override
  String get changeTheRuleOnTheApp =>
      'Change the rule on the App version page.';

  @override
  String changedAdminSettings(Object? admin) {
    return '$admin changed admin settings';
  }

  @override
  String changedTheGroup(Object? actor) {
    return '$actor changed the group';
  }

  @override
  String changedTheGroupDescription(Object? actor) {
    return '$actor changed the group description';
  }

  @override
  String changedTheGroupNameTo(Object? actor, Object? name) {
    return '$actor changed the group name to \"$name\"';
  }

  @override
  String changedTheGroupSettings(Object? actor) {
    return '$actor changed the group settings';
  }

  @override
  String changedTheWiFiRuleOf(Object? admin, Object? target) {
    return '$admin changed the Wi-Fi rule of $target';
  }

  @override
  String changedThisGroupSPhoto(Object? actor) {
    return '$actor changed this group\'s photo';
  }

  @override
  String changedThisGroupSoAllMembers(Object? actor) {
    return '$actor changed this group so all members can add members';
  }

  @override
  String changedThisGroupSoAllMembers2(Object? actor) {
    return '$actor changed this group so all members can edit the group info';
  }

  @override
  String changedThisGroupSoAllMembers3(Object? actor) {
    return '$actor changed this group so all members can send messages';
  }

  @override
  String changedThisGroupSoOnlyAdmins(Object? actor) {
    return '$actor changed this group so only admins can add members';
  }

  @override
  String changedThisGroupSoOnlyAdmins2(Object? actor) {
    return '$actor changed this group so only admins can edit the group info';
  }

  @override
  String changedThisGroupSoOnlyAdmins3(Object? actor) {
    return '$actor changed this group so only admins can send messages';
  }

  @override
  String get chat => 'Chat';

  @override
  String get chatAndCallEvenWithoutInternet =>
      'Chat and call, even without internet';

  @override
  String get chats => 'Chats';

  @override
  String get chatsBiggestFirst => 'Chats, biggest first';

  @override
  String get chatsCallsPeople => 'Chats, calls, people';

  @override
  String get checkAgain => 'Check again';

  @override
  String get checkTheNewPasswordAndTry =>
      'Check the new password and try again.';

  @override
  String get checkedByTheServerForEvery =>
      'Checked by the server for every admin';

  @override
  String get checking => 'Checking…';

  @override
  String get checkingAndroidPermission => 'Checking Android permission…';

  @override
  String get checkingTheServer => 'Checking the server…';

  @override
  String get checksThatLinkupWorksWellCan =>
      'Checks that LinkUp works well. Can only look, can not change your account.';

  @override
  String get chooseAPasswordOfAtLeast =>
      'Choose a password of at least 8 characters.';

  @override
  String get chooseHowLinkupLooksOnThis =>
      'Choose how LinkUp looks on this phone.';

  @override
  String get chooseHowMuchMessageDetailAppears =>
      'Choose how much message detail appears when your phone is locked.';

  @override
  String get clear => 'Clear';

  @override
  String get clearCallsWithPeopleNearYou => 'Clear calls with people near you';

  @override
  String get clearChat => 'Clear chat';

  @override
  String clearChatWith(Object? name) {
    return 'Clear chat with $name?';
  }

  @override
  String get close => 'Close';

  @override
  String get closeDeleteThisCopy => 'Close (delete this copy)';

  @override
  String get closeOtherSharingAppsAndTry =>
      'Close other sharing apps and try again.';

  @override
  String get closeSearch => 'Close search';

  @override
  String get closeVideo => 'Close video';

  @override
  String get codeChanged => 'Code changed';

  @override
  String get codeCopied => 'Code copied';

  @override
  String get collapseMenu => 'Collapse menu';

  @override
  String compareThisCodeWithTheOne(Object? v) {
    return 'Compare this code with the one on $v\'s phone. If they are the same, nobody is in the middle of your chats and calls.';
  }

  @override
  String get completeRecovery => 'Complete recovery';

  @override
  String get completeTransfer => 'Complete transfer';

  @override
  String get completed => 'Completed';

  @override
  String get completingSecureAccountRecovery =>
      'Completing secure account recovery…';

  @override
  String get completingSecureDeviceTransfer =>
      'Completing secure device transfer…';

  @override
  String get confirm => 'Confirm';

  @override
  String get confirmItSMe => 'Confirm it\'s me';

  @override
  String get confirmItSYouToKeep =>
      'Confirm it\'s you to keep using LinkUp on this phone.';

  @override
  String get confirmPassphrase => 'Confirm passphrase';

  @override
  String get confirmYourAccount => 'Confirm your account';

  @override
  String get connectToTheServerOnceTo =>
      'Connect to the server once to turn on offline blocking';

  @override
  String get connectToTheServerOnceTo2 =>
      'Connect to the server once to turn on offline blocking.';

  @override
  String get connectToTheServerToUse =>
      'Connect to the server to use the old password.';

  @override
  String get connected => 'Connected';

  @override
  String get connectedByMesh => 'Connected by Mesh';

  @override
  String get connectedByWiFi => 'Connected by Wi-Fi';

  @override
  String get connectedByWiFiDirect => 'Connected by Wi-Fi Direct';

  @override
  String get connectedOnline => 'Connected Online';

  @override
  String get connecting => 'Connecting…';

  @override
  String get connectingSecurely => 'Connecting securely…';

  @override
  String get connectingVideo => 'Connecting video…';

  @override
  String connection(Object? label) {
    return 'Connection: $label';
  }

  @override
  String get connectionQuality => 'Connection quality';

  @override
  String connectionStatus(Object? label) {
    return 'Connection status: $label';
  }

  @override
  String connectionStatus2(Object? label, Object? detail) {
    return 'Connection status: $label$detail';
  }

  @override
  String get connectivity => 'Connectivity';

  @override
  String get contact => 'Contact';

  @override
  String get contactAdded => 'Contact added';

  @override
  String get contacts => 'Contacts';

  @override
  String contacts2(Object? all) {
    return '$all contacts';
  }

  @override
  String get contactsWithAnOlderLinkupWill =>
      'Contacts with an older LinkUp will not connect nearby until they update. Messages through the internet still work.';

  @override
  String get continueRecording => 'Continue recording';

  @override
  String get continueText => 'Continue';

  @override
  String get conversationInfo => 'Conversation info';

  @override
  String get conversations => 'Conversations';

  @override
  String get copied => 'Copied';

  @override
  String get copiedWhatsappIsNotOnThis =>
      'Copied. WhatsApp is not on this phone.';

  @override
  String get copy => 'Copy';

  @override
  String get copyLink => 'Copy link';

  @override
  String get copyText => 'Copy text';

  @override
  String get couldNotAcceptTheNewCode => 'Could not accept the new code';

  @override
  String get couldNotAddThisPersonTry =>
      'Could not add this person. Try again.';

  @override
  String couldNotAddTryAgain(Object? r) {
    return 'Could not add $r. Try again.';
  }

  @override
  String couldNotBlock(Object? name) {
    return 'Could not block $name';
  }

  @override
  String get couldNotConnectToLinkupMake =>
      'Could not connect to LinkUp. Make sure the LinkUp server is available on your private network.';

  @override
  String couldNotCreateYourQrCode(Object? error) {
    return 'Could not create your QR code. $error';
  }

  @override
  String get couldNotForwardTryAgain => 'Could not forward. Try again.';

  @override
  String get couldNotGetItNow => 'Could not get it now';

  @override
  String get couldNotMakeANewCode => 'Could not make a new code. Try again.';

  @override
  String get couldNotOpenNotificationSettingsRight =>
      'Could not open notification settings right now.';

  @override
  String get couldNotOpenTheBatteryDialog =>
      'Could not open the battery dialog right now — try again.';

  @override
  String get couldNotOpenTheCameraOr => 'Could not open the camera or gallery.';

  @override
  String get couldNotOpenYourPhoneS =>
      'Could not open your phone’s settings right now.';

  @override
  String get couldNotPrepareLogs => 'Could not prepare logs';

  @override
  String get couldNotReachTheSenderTry =>
      'Could not reach the sender. Try again when nearby.';

  @override
  String get couldNotReachTheServerTry =>
      'Could not reach the server. Try again.';

  @override
  String get couldNotRefreshTheRequestThe =>
      'Could not refresh the request. The local network may be temporarily unavailable.';

  @override
  String couldNotRemove(Object? name) {
    return 'Could not remove $name';
  }

  @override
  String couldNotSave(Object? e) {
    return 'Could not save: $e';
  }

  @override
  String get couldNotSaveFreeSomeSpace =>
      'Could not save. Free some space and try again.';

  @override
  String get couldNotSendTryAgain => 'Could not send. Try again';

  @override
  String get couldNotShareLogs => 'Could not share logs';

  @override
  String get couldNotStartTryingAgainLater =>
      'Could not start, trying again later';

  @override
  String couldNotUnblock(Object? label) {
    return 'Could not unblock $label';
  }

  @override
  String get couldnTAskToJoinTry => 'Couldn\'t ask to join. Try again.';

  @override
  String get couldnTBeAdded => 'Couldn\'t be added';

  @override
  String get couldnTGetTheAddressBy => 'Couldn\'t get the address by itself';

  @override
  String get couldnTLoadYourConversationsPlease =>
      'Couldn\'t load your conversations. Please try again in a moment.';

  @override
  String get couldnTReachTheServerConversations =>
      'Couldn\'t reach the server. Conversations will appear when it\'s back.';

  @override
  String get couldnTReachThemTryAgain => 'Couldn\'t reach them — try again';

  @override
  String get couldnTReadTheLinkupApp => 'Couldn\'t read the LinkUp app file';

  @override
  String get couldnTStartTheDownloadPage => 'Couldn\'t start the download page';

  @override
  String get couldnTSyncRightNowShowing =>
      'Couldn\'t sync right now — showing your saved conversations.';

  @override
  String get couldnTTurnOnWiFi => 'Couldn\'t turn on Wi-Fi';

  @override
  String get countUnknown => 'count unknown';

  @override
  String get create => 'Create';

  @override
  String get createAccount => 'Create account';

  @override
  String get createAnAccount => 'Create an account';

  @override
  String get createBackup => 'Create backup';

  @override
  String get createDatabaseBackup => 'Create database backup';

  @override
  String get createEncryptedKeyBackup => 'Create encrypted key backup';

  @override
  String get createGroup => 'Create group';

  @override
  String get createUpdateEncryptedKeyBackup =>
      'Create / update encrypted key backup';

  @override
  String get createYourAccount => 'Create your account';

  @override
  String createdBy(Object? creator) {
    return 'Created by $creator';
  }

  @override
  String createdGroup(Object? actor, Object? name) {
    return '$actor created group \"$name\"';
  }

  @override
  String get creatingYourAccount => 'Creating your account…';

  @override
  String get critical => 'Critical';

  @override
  String criticalAlertIn24h(Object? critical, Object? s) {
    return '$critical critical alert$s in 24h';
  }

  @override
  String crownShowsWhatTheyCanDo(Object? role) {
    return '$role crown. Shows what they can do';
  }

  @override
  String get currentIdentityKey => 'Current identity key';

  @override
  String get dark => 'Dark';

  @override
  String get darkTheme => 'Dark theme';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get dataBoundaries => 'Data boundaries';

  @override
  String get database => 'Database';

  @override
  String database2(Object? num) {
    return 'Database $num';
  }

  @override
  String get databaseBackup => 'Database backup';

  @override
  String get dates => 'Dates';

  @override
  String days(Object? d) {
    return '$d days';
  }

  @override
  String daysAgo(Object? days) {
    return '$days days ago';
  }

  @override
  String get dec => 'Dec';

  @override
  String get decline => 'Decline';

  @override
  String get declined => 'Declined';

  @override
  String defaultSameAsSAccount(Object? owner) {
    return 'Default = same as $owner’s account';
  }

  @override
  String get defaultText => 'Default';

  @override
  String get delete => 'Delete';

  @override
  String delete2(Object? groupName) {
    return 'Delete \"$groupName\"?';
  }

  @override
  String delete3(Object? picked, Object? files, Object? pickedBytes) {
    return 'Delete $picked $files ($pickedBytes)';
  }

  @override
  String delete4(Object? count, Object? files) {
    return 'Delete $count $files?';
  }

  @override
  String get deleteChat => 'Delete chat';

  @override
  String get deleteChatCompletely => 'Delete chat completely';

  @override
  String deleteChatWith(Object? name) {
    return 'Delete chat with $name?';
  }

  @override
  String get deleteCompletely => 'Delete completely';

  @override
  String get deleteCompletely2 => 'Delete completely?';

  @override
  String get deleteFiles => 'Delete files';

  @override
  String get deleteForEveryone => 'Delete for everyone';

  @override
  String deleteForEveryoneRemovesItFrom(
      Object? who, Object? phone, Object? vIs) {
    return '\"Delete for everyone\" removes it from $who$phone too, even if $vIs Offline now (it is removed when the phone gets the news). Only for your messages, up to 5 minutes old. A copy someone saved to the Gallery stays.';
  }

  @override
  String get deleteForMe => 'Delete for me';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String get deleteMessage => 'Delete message?';

  @override
  String deleteMessageCompletely(Object? count, Object? s) {
    return 'Delete $count message$s completely?';
  }

  @override
  String deleteMessages(Object? count) {
    return 'Delete $count messages?';
  }

  @override
  String deleteMessagesCompletely(Object? sel) {
    return 'Delete $sel messages completely';
  }

  @override
  String get deleteUnpublishedAccount => 'Delete unpublished account?';

  @override
  String get deleteVoiceNote => 'Delete voice note';

  @override
  String get deletedByUser => 'Deleted by user';

  @override
  String deletedByUser2(Object? t, Object? hm) {
    return 'Deleted by user · $t $hm';
  }

  @override
  String get deletedFromThisPhone => 'deleted from this phone';

  @override
  String deletedThisGroupSPhoto(Object? actor) {
    return '$actor deleted this group\'s photo';
  }

  @override
  String get delivered => 'Delivered';

  @override
  String deliveredTo(Object? delivered) {
    return 'Delivered to $delivered';
  }

  @override
  String deliveredToOf(Object? delivered, Object? total) {
    return 'Delivered to $delivered of $total';
  }

  @override
  String get description => 'Description';

  @override
  String get descriptionOptional => 'Description (optional)';

  @override
  String get developerAndCreatorOfLinkupBuilt =>
      'Developer and creator of LinkUp. Built this app so you can chat and call, even without internet.';

  @override
  String get devices => 'Devices';

  @override
  String get devicesSignedInToThisLinkup =>
      'Devices signed in to this LinkUp account.';

  @override
  String get diagnosticCaptureMode => 'Diagnostic capture mode';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get didNotWorkTryingAgainLater => 'Did not work, trying again later';

  @override
  String get directLinks => 'Direct links';

  @override
  String get directorySynchronization => 'Directory synchronization';

  @override
  String get directoryVisibility => 'Directory visibility';

  @override
  String get discoverableByName => 'Discoverable by name';

  @override
  String get discoverableByPhone => 'Discoverable by phone';

  @override
  String diskFull(Object? disk) {
    return 'Disk $disk% full';
  }

  @override
  String get dismissAsAdmin => 'Dismiss as admin';

  @override
  String dismissedAsGroupAdmin(Object? actor, Object? targets) {
    return '$actor dismissed $targets as group admin';
  }

  @override
  String dismissedYouAsGroupAdmin(Object? actor) {
    return '$actor dismissed you as group admin';
  }

  @override
  String get displayName => 'Display name';

  @override
  String get docs => 'Docs';

  @override
  String get document => 'Document';

  @override
  String get documentReceived => 'Document received';

  @override
  String get documents => 'Documents';

  @override
  String documentsReceived(Object? n) {
    return '$n documents received';
  }

  @override
  String done(Object? done) {
    return 'Done $done';
  }

  @override
  String get done2 => 'Done';

  @override
  String doneMb(Object? total) {
    return 'Done, $total MB';
  }

  @override
  String get download => 'Download';

  @override
  String get dragToMove => 'Drag to move';

  @override
  String get dragToScrollPinchToZoom => 'Drag to scroll · pinch to zoom';

  @override
  String get eachPhoneOnceByHowIt => 'Each phone once, by how it is linked now';

  @override
  String get earlier => 'Earlier';

  @override
  String get editGroup => 'Edit group';

  @override
  String get editGroupInfo => 'Edit group info';

  @override
  String effective(Object? allowed) {
    return 'Effective: $allowed';
  }

  @override
  String get enable => 'Enable';

  @override
  String get encryptedBackupOfYourAccount => 'Encrypted backup of your account';

  @override
  String get encryptedHistory => 'Encrypted history';

  @override
  String get encryptedIdentityBackupAvailable =>
      'Encrypted identity backup available';

  @override
  String get encryptedIdentityBackupSavedToThe =>
      'Encrypted identity backup saved to the LinkUp server';

  @override
  String get ended => 'Ended';

  @override
  String get ending => 'Ending…';

  @override
  String endsInH(Object? left) {
    return 'ends in $left h';
  }

  @override
  String endsInMin(Object? clamp) {
    return 'ends in $clamp min';
  }

  @override
  String get enterThe12DigitCodeFrom =>
      'Enter the 12-digit code from the admin.';

  @override
  String get enterTheCode => 'Enter the code';

  @override
  String get enterTheOneTimeCode => 'Enter the one-time code';

  @override
  String enterThePasswordOf(Object? username) {
    return 'Enter the password of @$username.';
  }

  @override
  String get enterTheRecoveryCode => 'Enter the recovery code.';

  @override
  String get enterYourPassword => 'Enter your password';

  @override
  String get enterYourRecoveryCodeLikeK7qm2 =>
      'Enter your recovery code (like K7QM2-XPA9T-RC4WN-E8D3F).';

  @override
  String get enterYourUsername => 'Enter your username.';

  @override
  String get enterYourUsernameAndPassword =>
      'Enter your username and password.';

  @override
  String get enterYourUsernameToRequestAccount =>
      'Enter your username to request account recovery.';

  @override
  String get event => 'Event';

  @override
  String get eventsInTheLast24Hours => 'Events in the last 24 hours';

  @override
  String get everyPhoneAndWhoOwnsIt => 'Every phone and who owns it';

  @override
  String get everyone => 'Everyone';

  @override
  String get everyoneCanSend => 'Everyone can send';

  @override
  String get everyoneInTheGroupSeesIt =>
      'Everyone in the group sees it at the top of the chat. Only one message is pinned at a time; a new pin replaces the old one.';

  @override
  String get everyoneNearbyIsAlreadyInYour =>
      'Everyone nearby is already in your contacts';

  @override
  String get everyoneOnLinkupIsAlreadyIn =>
      'Everyone on LinkUp is already in your contacts. To add someone new, search their name or use a QR code.';

  @override
  String get everyonePicks => 'Everyone picks ';

  @override
  String get excellent => 'Excellent';

  @override
  String exit(Object? groupName) {
    return 'Exit \"$groupName\"?';
  }

  @override
  String get exitFullScreen => 'Exit full screen';

  @override
  String get exitGroup => 'Exit group';

  @override
  String get expired => 'Expired';

  @override
  String expiresIn(Object? remainingLabel) {
    return 'Expires in $remainingLabel';
  }

  @override
  String get expiresIn24Hours => 'Expires in 24 hours';

  @override
  String get expiresIn24Hours2 => 'Expires in 24 hours.';

  @override
  String get extraNearbySafety => 'Extra nearby safety';

  @override
  String get failed => 'Failed';

  @override
  String failedLoginIn24h(Object? failedLogins, Object? s) {
    return '$failedLogins failed login$s in 24h';
  }

  @override
  String get failedLogins24h => 'Failed logins 24h';

  @override
  String get fair => 'Fair';

  @override
  String get feb => 'Feb';

  @override
  String get file => 'File';

  @override
  String get fileContents => 'File contents';

  @override
  String get fileInfo => 'File info';

  @override
  String get filePartsPassedOn => 'File parts passed on';

  @override
  String get fileRemovedAfter60DaysThumbnail =>
      'File removed after 60 days · thumbnail only';

  @override
  String get fileTooBig => 'File too big';

  @override
  String get fileTransfers => 'File transfers';

  @override
  String get fileTransfers2 => 'File Transfers';

  @override
  String get files => 'Files';

  @override
  String get filesPeopleSendShowHereWith =>
      'Files people send show here with kind and size.';

  @override
  String filesReceived(Object? n) {
    return '$n files received';
  }

  @override
  String get filesSentAndSpaceUsed => 'Files sent and space used';

  @override
  String filesTooBig(Object? count) {
    return '$count files too big';
  }

  @override
  String get filter => 'Filter';

  @override
  String get findANearbyPersonOrCreate =>
      'Find a nearby person or create a group to start chatting.';

  @override
  String get findAPerson => 'Find a person';

  @override
  String get findNearbyFriendsWhenClosed => 'Find nearby friends when closed';

  @override
  String get findNearbyFriendsWhenClosedTurn =>
      'Find nearby friends when closed - Turn on';

  @override
  String get findPeopleNearby => 'Find people nearby';

  @override
  String get findPeopleToAdd => 'Find people to add';

  @override
  String get findPhonesNearYou => 'Find phones near you';

  @override
  String get findServerNow => 'Find server now';

  @override
  String get findingTheMatchingLinkupServer =>
      'Finding the matching LinkUp server…';

  @override
  String get firstOrLetThemScanThe =>
      ' first, or let them scan the group QR later.';

  @override
  String get firstPerson => 'First person';

  @override
  String get flashlight => 'Flashlight';

  @override
  String get followAppTheme => 'Follow app theme';

  @override
  String get followTheAccountOrPhoneSetting =>
      'Follow the account or phone setting';

  @override
  String get followThePhoneSLightOr => 'Follow the phone’s light or dark mode.';

  @override
  String get forEveryPhoneOfThisAccount => 'For every phone of this account';

  @override
  String get forEveryoneOnAllLinkupPhones =>
      'For everyone, on all LinkUp phones';

  @override
  String get forcedOff => 'Forced OFF';

  @override
  String get forcedOn => 'Forced ON';

  @override
  String get forgotItUseTheRecoveryCode => 'Forgot it? Use the recovery code.';

  @override
  String get forgotPassword => 'Forgot password';

  @override
  String get forgotPassword2 => 'Forgot password?';

  @override
  String get forward => 'Forward';

  @override
  String get forwardTo => 'Forward to';

  @override
  String get forwarded => 'Forwarded';

  @override
  String get foundSomeone => 'Found someone!';

  @override
  String get freeUpSpaceAutomatically => 'Free up space automatically';

  @override
  String get freeUpSpaceAutomaticallyIsOff =>
      'Free up space automatically is OFF. Nothing removed.';

  @override
  String get fri => 'Fri';

  @override
  String get friendsOfFriendsScanToJoin => 'Friends of friends scan to join';

  @override
  String get friendsWithoutWiFiCanReach =>
      'Friends without Wi-Fi can reach you';

  @override
  String get fromEveryPhoneAlsoDeletedCopies =>
      'From every phone, also deleted copies';

  @override
  String get fromEveryPhoneOfThisChat =>
      'From every phone of this chat, also copies users deleted. This cannot be undone.';

  @override
  String get fromPhoto => 'From photo';

  @override
  String fromSPhone(Object? range, Object? from) {
    return '$range · from $from\'s phone';
  }

  @override
  String get fullChat => 'Full chat';

  @override
  String get fullMap => 'Full map';

  @override
  String get fullScreen => 'Full screen';

  @override
  String get gallery => 'Gallery';

  @override
  String gaveANewRecoveryCodeTo(Object? admin, Object? target) {
    return '$admin gave a new recovery code to $target';
  }

  @override
  String get general => 'General';

  @override
  String get generateANewQr => 'Generate a new QR';

  @override
  String get getAOneTimeCode => 'Get a one-time code';

  @override
  String get getChat => 'Get chat';

  @override
  String get getFile => 'Get file';

  @override
  String get getFullPhoto => 'Get full photo';

  @override
  String get getFullVideo => 'Get full video';

  @override
  String get getMessagesAndCallsWhenClosed =>
      'Get messages and calls when closed';

  @override
  String get getsItWhenNearbyOrOnline => 'gets it when Nearby or Online';

  @override
  String get getsTheGroupWhenNearbyOr => 'Gets the group when Nearby or Online';

  @override
  String get gettingIt => 'Getting it…';

  @override
  String get gettingItFromAnotherPhone => 'Getting it from another phone';

  @override
  String get gettingItFromTheServer => 'Getting it from the server…';

  @override
  String get gettingTheDownloadAddress => 'Getting the download address...';

  @override
  String get giveTheAppToANearby =>
      'Give the app to a nearby phone · no internet';

  @override
  String get giveThemLinkupNoInternet => 'Give them LinkUp · no internet';

  @override
  String get goToPeople => 'Go to People';

  @override
  String get goesOutRightAway => 'Goes out right away';

  @override
  String get goneFromEveryPhoneAndThe =>
      'Gone from every phone and the server, also copies users deleted. Users see nothing.';

  @override
  String get good => 'Good';

  @override
  String get group => 'Group';

  @override
  String group2(Object? count, Object? members) {
    return 'Group · $count $members';
  }

  @override
  String get groupChat => 'Group chat';

  @override
  String get groupConversation => 'Group conversation';

  @override
  String get groupDetails => 'Group details';

  @override
  String get groupInfo => 'Group info';

  @override
  String get groupInvite => 'Group invite';

  @override
  String groupInvite2(Object? members, Object? members2) {
    return 'Group invite · $members $members2';
  }

  @override
  String get groupMember => 'Group member';

  @override
  String groupMembers(Object? members) {
    return 'Group · $members members';
  }

  @override
  String groupMembersFromSCode(Object? count, Object? from) {
    return 'Group · $count members · from $from\'s code';
  }

  @override
  String get groupMessages => 'Group messages';

  @override
  String get groupName => 'Group name';

  @override
  String get groupPhoto => 'Group photo';

  @override
  String get groupSettings => 'Group settings';

  @override
  String get groupsAreMadeFromYourFriends =>
      'Groups are made from your friends. Add friends in ';

  @override
  String get halfCanBeReadNowThe =>
      'Half can be read now · the rest is on the way';

  @override
  String hasAnOldLinkup(Object? name) {
    return '$name has an old LinkUp';
  }

  @override
  String get haveAnAccount => 'Have an account?';

  @override
  String get healthy => 'Healthy';

  @override
  String get helpsRunLinkup => 'Helps run LinkUp.';

  @override
  String get hidden => 'Hidden';

  @override
  String get hideForToday => 'Hide for today';

  @override
  String get hideMap => 'Hide map';

  @override
  String get hideMessageTextOnTheLock => 'Hide message text on the lock screen';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get hideSensitiveContent => 'Hide sensitive content';

  @override
  String get hideText => 'Hide';

  @override
  String get historicalIdentityKeys => 'Historical identity keys';

  @override
  String get holdToRecordReleaseToSend => 'Hold to record, release to send';

  @override
  String get holdToRecordVoiceNote => 'Hold to record voice note';

  @override
  String get host => 'Host';

  @override
  String get hotspot => 'Hotspot';

  @override
  String hours(Object? d) {
    return '$d hours';
  }

  @override
  String get howOftenAdminPagesUpdate => 'How often admin pages update';

  @override
  String get howOtherPeopleSeeYou => 'How other people see you';

  @override
  String get howPhonesAreLinked => 'How phones are linked';

  @override
  String get iAlreadyHaveAnAccount => 'I already have an account';

  @override
  String get iDonTHaveIt => 'I don\'t have it';

  @override
  String get iSavedIt => 'I saved it';

  @override
  String identity(Object? platform, Object? status, Object? lastSeenAt,
      Object? unverified, Object? identityFingerprint) {
    return '$platform • $status\n$lastSeenAt\nIdentity: $unverified$identityFingerprint';
  }

  @override
  String get identityChanged => 'Identity changed';

  @override
  String get identityChangedOrRevokedVerifyThis =>
      'Identity changed or revoked — verify this user again';

  @override
  String get identityKeyHistory => 'Identity key history';

  @override
  String identityKeyRotatedToVersion(Object? currentVersion) {
    return 'Identity key rotated to version $currentVersion.';
  }

  @override
  String get identityKeysAreManagedLocallyAnd =>
      'Identity keys are managed locally and are not shown in your public profile.';

  @override
  String get identitySigning => 'Identity & signing';

  @override
  String get ifOffYouCanTSee =>
      'If off, you can\'t see when others read your messages, and they can\'t see when you read theirs.';

  @override
  String get ifTheNewPhoneSaysThis =>
      'If the new phone says \"This Wi-Fi has no internet. Stay connected?\" tap Yes / Stay.';

  @override
  String ifYouLoseThisPhoneIt(Object? user) {
    return 'If you lose this phone, it is the only way back into @$user.';
  }

  @override
  String ifYouUnblockCanMessageAnd(Object? label) {
    return 'If you unblock, $label can message and call you again.';
  }

  @override
  String get ignore => 'Ignore';

  @override
  String get ignoreBatteryOptimization => 'Ignore battery optimization';

  @override
  String get imageReceived => 'Image received';

  @override
  String imagesReceived(Object? n) {
    return '$n images received';
  }

  @override
  String inBothChatsTheMessageBox(Object? name) {
    return 'In both chats the message box is replaced by a short text, so **$name can see** they can\'t message you.';
  }

  @override
  String inLinkup(Object? token) {
    return 'In LinkUp: $token';
  }

  @override
  String get inYourContacts => 'In your contacts';

  @override
  String get includesTheGroupQrCode => 'Includes the group QR code';

  @override
  String get incoming => 'Incoming';

  @override
  String get incomingCall => 'Incoming call';

  @override
  String get info => 'Info';

  @override
  String get inheritPlatformState => 'Inherit / platform state';

  @override
  String get install => 'Install';

  @override
  String get internet => 'Internet';

  @override
  String get internetServerOnly => 'Internet / server only';

  @override
  String get inviteAFriendNearby => 'Invite a friend nearby';

  @override
  String inviteLinkFrom(Object? invitedBy) {
    return 'invite link from $invitedBy';
  }

  @override
  String get inviteWithLink => 'Invite with link';

  @override
  String get inviteWithQr => 'Invite with QR';

  @override
  String isBlocked(Object? label) {
    return '$label is blocked';
  }

  @override
  String isBlockedByAdmin(Object? name) {
    return '$name is blocked by admin';
  }

  @override
  String isBlockedForEveryone(Object? target) {
    return '$target is blocked for everyone.';
  }

  @override
  String isInYourFriends(Object? name) {
    return '$name is in your friends.';
  }

  @override
  String isNotInYourFriends(Object? name) {
    return '$name is not in your friends.';
  }

  @override
  String isNotInYourFriendsMember(Object? name, Object? via) {
    return '$name is not in your friends. $via (member) is his friend.';
  }

  @override
  String isNotInYourFriendsMembers(Object? name, Object? list) {
    return '$name is not in your friends. $list (members) are his friends.';
  }

  @override
  String isNotOnTheServerYet(
      Object? notOnServerName, Object? notOnServerName2) {
    return '$notOnServerName is not on the server yet. It goes when $notOnServerName2 is nearby or joins the server.';
  }

  @override
  String isNowTheGroupOwner(Object? owner) {
    return '$owner is now the group owner';
  }

  @override
  String isRemovedFromYourContacts(Object? name) {
    return '$name is **removed from your contacts**.';
  }

  @override
  String isRequiredFillItInBefore(Object? missing) {
    return '$missing is required — fill it in before saving.';
  }

  @override
  String isSignedOutOn(Object? name, Object? phone) {
    return '$name is signed out on $phone.';
  }

  @override
  String get isTheServerHealthy => 'Is the server healthy';

  @override
  String isTyping(Object? clean) {
    return '$clean is typing…';
  }

  @override
  String isUnblockedForEveryone(Object? target) {
    return '$target is unblocked for everyone.';
  }

  @override
  String isVerified(Object? v) {
    return '$v is verified';
  }

  @override
  String get itGoesToEveryPhoneNearby =>
      'It goes to every phone nearby, and to the server when online.';

  @override
  String get itGoesToHerPhoneBy =>
      'It goes to her phone by card, over any link. Pending until it is done.';

  @override
  String get itIsRemovedOnlyFromYour =>
      'It is removed only from your phone. The group still has it.';

  @override
  String itIsRemovedOnlyFromYour2(Object? peerName) {
    return 'It is removed only from your phone. $peerName still has it.';
  }

  @override
  String get itIsSignedOutAndMust => 'It is signed out and must sign in again.';

  @override
  String get itMustSignInAgain => 'It must sign in again.';

  @override
  String get itSyncsWhenTheServerAnswers =>
      'It syncs when the server answers. Your local key above is fine.';

  @override
  String get itWasInstalledInPartsFor =>
      'It was installed in parts (for example from a store). Ask a friend who installed the LinkUp file to share it.';

  @override
  String items(Object? files) {
    return '$files items';
  }

  @override
  String get jan => 'Jan';

  @override
  String get join => 'Join';

  @override
  String joinFullNearbyGroupsAsA(Object? linkStatusText) {
    return 'Join full nearby groups as a Wi-Fi user and join a LinkUp hotspot. $linkStatusText';
  }

  @override
  String get joinGroup => 'Join group';

  @override
  String get joinGroupWithQr => 'Join group with QR';

  @override
  String get joinMyGroup => 'JOIN MY GROUP';

  @override
  String joinMyLinkupGroup(Object? groupName) {
    return 'Join my LinkUp group \"$groupName\":';
  }

  @override
  String get joinWiFi => 'Join Wi-Fi';

  @override
  String get joinedALinkupHotspot => 'Joined a LinkUp hotspot';

  @override
  String joinedFromOffline(Object? joined_offline_at) {
    return 'Joined from offline · $joined_offline_at';
  }

  @override
  String joinedFromOffline2(Object? u) {
    return '$u · Joined from offline';
  }

  @override
  String joinedUsingThisGroupSInvite(Object? actor) {
    return '$actor joined using this group\'s invite link';
  }

  @override
  String get joining => 'Joining…';

  @override
  String get joiningALinkupHotspot => 'Joining a LinkUp hotspot…';

  @override
  String get joiningAnotherGroup => 'Joining another group…';

  @override
  String get jul => 'Jul';

  @override
  String get jumpToLatest => 'Jump to latest';

  @override
  String get jun => 'Jun';

  @override
  String get justNow => 'just now';

  @override
  String get k7qm2Xpa9tRc4wnE8d3f => 'K7QM2-XPA9T-RC4WN-E8D3F';

  @override
  String get keepItPrivateItLetsYou =>
      'Keep it private. It lets you set a new password.';

  @override
  String get keepKeepRunningInBackgroundOn =>
      'Keep \"Keep running in background\" on (above)';

  @override
  String get keepLinkupRunning => 'Keep LinkUp running';

  @override
  String get keepRunningInBackground => 'Keep running in background';

  @override
  String get keepTheNewPhoneConnectedTo =>
      'Keep the new phone connected to the private LinkUp network while waiting for approval.';

  @override
  String get keepThisPrivate => 'Keep this private';

  @override
  String get keepWiFiOnOnBoth => 'Keep Wi-Fi on, on both phones';

  @override
  String get keepsLinkupSafeCanHelpYou =>
      'Keeps LinkUp safe. Can help you get back in if you forget your password.';

  @override
  String get keyRotationChangesTheDevicePublic =>
      'Key rotation changes the device public identity used for future encrypted traffic. Previous private key versions stay only on this device and are never uploaded to the server. A new phone therefore needs a future encrypted key-migration/backup mechanism to recover historical ciphertext created for an older device identity.';

  @override
  String get lanAvailable => 'LAN available';

  @override
  String get lanServerConnected => 'LAN / Server connected';

  @override
  String last(Object? whenSub216, Object? bytes) {
    return 'Last: $whenSub216$bytes';
  }

  @override
  String get last1Hour => 'Last 1 hour';

  @override
  String get last30Days => 'Last 30 days';

  @override
  String get last7Days => 'Last 7 days';

  @override
  String lastCleanUp(Object? dayText, Object? time, Object? what) {
    return 'Last clean-up: $dayText, $time · $what';
  }

  @override
  String lastPolicyUpdate(Object? updated_at) {
    return 'Last policy update: $updated_at';
  }

  @override
  String get lastSeen => 'Last seen';

  @override
  String lastSeen2(Object? value) {
    return 'Last seen $value';
  }

  @override
  String get lastUpdate => 'Last update';

  @override
  String lastUpdated(Object? hour, Object? padLeft) {
    return 'Last updated $hour:$padLeft';
  }

  @override
  String get lastWeek => 'last week';

  @override
  String get later => 'Later';

  @override
  String left(Object? actor) {
    return '$actor left';
  }

  @override
  String get letAFriendScanYou => 'Let a friend scan you';

  @override
  String levelTapYourPhotoInSettings(Object? role) {
    return 'Level: $role · Tap your photo in Settings to switch.';
  }

  @override
  String get light => 'Light';

  @override
  String get lightTheme => 'Light theme';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get linkFullGroups => 'Link full groups';

  @override
  String get linkFullGroups2 => 'Link full groups?';

  @override
  String get linkNow => 'Link now';

  @override
  String get linkPaths => 'Link paths';

  @override
  String get linkedGroupHotspotTest => 'Linked group / hotspot (test)';

  @override
  String get linkedToAnotherGroup => 'Linked to another group';

  @override
  String get linksWithCheckedId => 'Links with checked id';

  @override
  String linkup(Object? version, Object? sizeLabel) {
    return 'LinkUp $version  ·  $sizeLabel';
  }

  @override
  String get linkupAccount => 'LinkUp account';

  @override
  String get linkupCallAndRoutingTransportIs =>
      'LinkUp call and routing transport is local-only: LAN, Wi-Fi Direct and multi-hop mesh.';

  @override
  String get linkupConnected => 'LinkUp connected';

  @override
  String get linkupCouldNotInitializeSafelyClose =>
      'LinkUp could not initialize safely. Close and reopen the app.';

  @override
  String get linkupCouldNotStart => 'LinkUp could not start';

  @override
  String get linkupCouldnTTurnOnIts =>
      'LinkUp couldn\'t turn on its own Wi-Fi. If your friend is on the same Wi-Fi as you, they can scan this:';

  @override
  String linkupIsDownloaded(Object? version) {
    return 'LinkUp$version is downloaded';
  }

  @override
  String get linkupKeepsNotificationContentSeparateFrom =>
      'LinkUp keeps notification content separate from your chat content.';

  @override
  String get linkupLogo => 'LinkUp logo';

  @override
  String get linkupNeedsTheNearbyDevicesPermission =>
      'LinkUp needs the \"Nearby devices\" permission to turn on its Wi-Fi. Allow it in LinkUp\'s app settings.';

  @override
  String get linkupNeedsThisToStayOn =>
      'LinkUp needs this to stay on — messages and calls must keep arriving in the background.';

  @override
  String get linkupNeedsYourOkOnce => 'LinkUp needs your OK once';

  @override
  String get linkupNotification => 'LinkUp notification';

  @override
  String get linkupOnThisPhone => 'LinkUp on this phone';

  @override
  String get linkupPhone => 'LinkUp phone';

  @override
  String get linkupServerIdentityChangedConnectionWas =>
      'LinkUp server identity changed. Connection was blocked for safety.';

  @override
  String get linkupTriesAgainLaterByItself =>
      'LinkUp tries again later by itself.';

  @override
  String linkupUpdatedTo(Object? kAppVersion) {
    return 'LinkUp updated to $kAppVersion';
  }

  @override
  String linkupUses(Object? bytes) {
    return 'LinkUp uses $bytes';
  }

  @override
  String get linkupVideoCall => 'LinkUp video call';

  @override
  String get linkupVoiceCall => 'LinkUp voice call';

  @override
  String get linkupWiFiIsOff => 'LinkUp Wi-Fi is off.';

  @override
  String get live => 'Live';

  @override
  String get liveNetwork => 'Live network';

  @override
  String liveOffline(Object? live, Object? offline) {
    return '$live live · $offline offline';
  }

  @override
  String get livePlatformTotalsWithTheActivity =>
      'Live platform totals with the activity recorded in the selected window';

  @override
  String get liveSubsystemHealth => 'Live subsystem health';

  @override
  String get liveSubsystemReadings => 'Live subsystem readings';

  @override
  String get llgq1 => 'llgq1:…';

  @override
  String get loading => 'Loading…';

  @override
  String get loadingGroupMessages => 'Loading group messages…';

  @override
  String get loadingMembers => 'Loading members…';

  @override
  String get loadingMessages => 'Loading messages…';

  @override
  String get loadingYourAccount => 'Loading your account…';

  @override
  String get loadingYourConversations => 'Loading your conversations…';

  @override
  String get localCallingServiceIsUnavailable =>
      'Local calling service is unavailable';

  @override
  String get localCallingServiceUnavailableReconnectAnd =>
      'Local calling service unavailable — reconnect and try again';

  @override
  String get localIpv4 => 'Local IPv4';

  @override
  String get localNetworkAvailable => 'Local network available';

  @override
  String get localPlatformState => 'local platform state';

  @override
  String get localWiFi => 'Local Wi-Fi';

  @override
  String get localWiFiOnly => 'Local Wi-Fi only';

  @override
  String get lockAppInRecents => 'Lock app in recents';

  @override
  String get lockLinkupInRecents => 'Lock LinkUp in Recents';

  @override
  String get lockScreenCallsOffTurnOn => 'Lock-screen calls off - turn on';

  @override
  String get lockScreenPrivacy => 'Lock-screen privacy';

  @override
  String get locked => 'Locked';

  @override
  String get lockedUsers => 'Locked users';

  @override
  String get logIn => 'Log in';

  @override
  String get logInToYourAccount => 'Log in to your account';

  @override
  String get longPressForMessageActions => 'Long press for message actions';

  @override
  String get lookingForPhonesNearYou => 'Looking for phones near you';

  @override
  String get lowestVersionAllowed => 'Lowest version allowed';

  @override
  String made(Object? now) {
    return 'Made $now';
  }

  @override
  String madeABackup(Object? admin) {
    return '$admin made a backup';
  }

  @override
  String madeAGroupAdmin(Object? actor, Object? targets) {
    return '$actor made $targets a group admin';
  }

  @override
  String madeAnAdmin(Object? admin, Object? target, Object? detail) {
    return '$admin made $target an admin$detail';
  }

  @override
  String madeYouAGroupAdmin(Object? actor) {
    return '$actor made you a group admin';
  }

  @override
  String get makeANewCode => 'Make a new code';

  @override
  String get makeANewCode2 => 'Make a new code?';

  @override
  String get makeARecoveryCode => 'Make a recovery code';

  @override
  String get makeGroupAdmin => 'Make group admin';

  @override
  String get makeMyCode => 'Make my code';

  @override
  String get makeNewCode => 'Make new code';

  @override
  String get makePrivate => 'Make private';

  @override
  String get makeYourProfilePrivate => 'Make your profile private?';

  @override
  String get makingAGroupNeedsOnlineFor =>
      'Making a group needs Online for now. Try again when Online.';

  @override
  String get manageDevices => 'Manage devices';

  @override
  String get manageSoundsVibrationAndImportanceIn =>
      'Manage sounds, vibration and importance in Android settings.';

  @override
  String get manageUsers => 'Manage users';

  @override
  String get mar => 'Mar';

  @override
  String get markAsRead => 'Mark as read';

  @override
  String get markAsVerified => 'Mark as verified';

  @override
  String get match => 'Match';

  @override
  String get may => 'May';

  @override
  String mayChangeIfTaken(Object? username) {
    return '@$username (may change if taken)';
  }

  @override
  String get media => 'Media';

  @override
  String get mediaLinksAndDocs => 'Media, links and docs';

  @override
  String mediaLinksAndDocs2(Object? files) {
    return 'Media, links and docs · $files';
  }

  @override
  String get member => 'Member';

  @override
  String member2(Object? members, Object? s) {
    return '$members member$s';
  }

  @override
  String get members => 'Members';

  @override
  String members2(Object? people) {
    return '$people members';
  }

  @override
  String membersSeeLeft(Object? me) {
    return 'Members see \"$me left\".';
  }

  @override
  String get memory => 'Memory';

  @override
  String get mesh => 'Mesh';

  @override
  String get meshCall => 'Mesh call';

  @override
  String get meshCapable => 'Mesh capable';

  @override
  String get meshLinks => 'Mesh links';

  @override
  String get meshOnly => 'Mesh only';

  @override
  String get meshPeers => 'Mesh peers';

  @override
  String get meshQueuedPackets => 'Mesh queued packets';

  @override
  String get message => 'Message';

  @override
  String message2(Object? name) {
    return 'Message $name';
  }

  @override
  String get messageActivity => 'Message activity';

  @override
  String get messageAndCallAlertsAreEnabled =>
      'Message and call alerts are enabled';

  @override
  String get messageCopied => 'Message copied';

  @override
  String get messageGroup => 'Message group';

  @override
  String get messageInfo => 'Message info';

  @override
  String get messageNotAvailable => 'Message not available';

  @override
  String get messageNotFound => 'Message not found';

  @override
  String get messageNotSent => 'Message not sent';

  @override
  String get messageNotSentTapToResend =>
      'Message not sent. Tap to resend or delete';

  @override
  String get messageOneFriend => 'Message one friend';

  @override
  String get messageText => 'Message text';

  @override
  String get messageWithAttachment => 'Message with attachment';

  @override
  String get messages => 'Messages';

  @override
  String messages2(Object? hits) {
    return 'Messages · $hits';
  }

  @override
  String messages3(Object? count) {
    return '$count messages';
  }

  @override
  String get messagesAcceptedByTheServerPer =>
      'Messages accepted by the server per bucket';

  @override
  String get messagesAndCallsGetWrongTimes =>
      'Messages and calls get wrong times. On the server PC: Settings > Time > Set time automatically > Sync now.';

  @override
  String get messagesAndCallsWorkAgain => 'Messages and calls work again';

  @override
  String get messagesAreSealedForGroupMembers =>
      'Messages are sealed for group members only';

  @override
  String get messagesArriveWhenTheAppIs =>
      'Messages arrive when the app is closed';

  @override
  String messagesCopied(Object? withText) {
    return '$withText messages copied';
  }

  @override
  String get messagesGroupsAndCalls => 'Messages, groups and calls';

  @override
  String get messagesPhotosVideos => 'Messages, photos, videos';

  @override
  String get messagesToday => 'Messages today';

  @override
  String get messagesWaitUntilItRunsAgain =>
      'Messages wait until it runs again';

  @override
  String get microphonePermissionNeededAllowItThen =>
      'Microphone permission needed — allow it, then answer again';

  @override
  String min(Object? left) {
    return '$left min';
  }

  @override
  String minAgo(Object? diff) {
    return '$diff min ago';
  }

  @override
  String get minVersion => 'Min. version';

  @override
  String get miniPlayer => 'Mini player';

  @override
  String get minimize => 'Minimize';

  @override
  String get minimumVersion => 'Minimum version';

  @override
  String missed(Object? missed) {
    return '$missed missed';
  }

  @override
  String get missed2 => 'Missed';

  @override
  String get missedCall => 'Missed call';

  @override
  String get missedVoiceCall => 'Missed voice call';

  @override
  String moAgo(Object? floor) {
    return '${floor}mo ago';
  }

  @override
  String get mon => 'Mon';

  @override
  String more(Object? files) {
    return '+$files more';
  }

  @override
  String get more2 => 'More';

  @override
  String get moreOptions => 'More options';

  @override
  String get moveThisAccountToAnotherPhone =>
      'Move this account to another phone';

  @override
  String get moveThisAccountToAnotherPhone2 =>
      'Move this account to another phone with a one-time QR transfer.';

  @override
  String get moveThisLinkupAccountToAnother =>
      'Move this LinkUp account to another phone.';

  @override
  String get moveToANewPhone => 'Move to a new phone';

  @override
  String get movedToANewPhone => 'Moved to a new phone';

  @override
  String msDelay(Object? rttMs) {
    return '$rttMs ms delay';
  }

  @override
  String msJitter(Object? jitterMs) {
    return '$jitterMs ms jitter';
  }

  @override
  String mustSignInAgain(Object? name) {
    return '$name must sign in again';
  }

  @override
  String mustSignInAgainOnEvery(Object? name) {
    return '$name must sign in again on every phone.';
  }

  @override
  String get mute => 'Mute';

  @override
  String get muteNotifications => 'Mute notifications';

  @override
  String get myAndroidPhone => 'My Android Phone';

  @override
  String get myLinks => 'My links';

  @override
  String get myLinkupAccount => 'My LinkUp account';

  @override
  String myLinkupRecoveryCodeKeepIt(Object? who, Object? code) {
    return 'My LinkUp recovery code (@$who): $code - keep it private.';
  }

  @override
  String myLinkupRecoveryCodeKeepIt2(Object? code) {
    return 'My LinkUp recovery code: $code - keep it private.';
  }

  @override
  String get myPhones => 'My phones';

  @override
  String get myQrCode => 'My QR code';

  @override
  String get nameAndPasswordInYourPhone =>
      'Name and password: in your phone\'s hotspot settings';

  @override
  String get nameAndPhoto => 'Name and photo';

  @override
  String get nameOnThisPhone => 'Name on this phone';

  @override
  String get namePhotoAndDescription => 'Name, photo and description';

  @override
  String get nearYou => 'Near you';

  @override
  String get nearby => 'Nearby';

  @override
  String get nearbyChatsWithOtherLinkupPhones =>
      'Nearby chats with other LinkUp phones may pause for a moment if your phone can\'t do both. They come back by themselves when you stop sharing.';

  @override
  String get nearbyDirectLink => 'Nearby - direct link';

  @override
  String get nearbyGroupsCanHaveUpTo =>
      'Nearby groups can have up to 32 people.';

  @override
  String get nearbyLinkupUser => 'Nearby LinkUp user';

  @override
  String get nearbyMesh => 'Nearby · Mesh';

  @override
  String nearbyMeshVia(Object? phonesBetween, Object? phones) {
    return 'Nearby · Mesh, via $phonesBetween $phones';
  }

  @override
  String get nearbyNow => 'Nearby now';

  @override
  String get nearbyNow2 => 'nearby now';

  @override
  String get nearbyNowAFewSeconds => 'Nearby now · a few seconds';

  @override
  String get nearbyNowAdding => 'Nearby now · adding…';

  @override
  String get nearbyOnlineOrOffline => 'Nearby, Online or Offline';

  @override
  String get nearbyPhonesNowServerWhenOnline =>
      'Nearby phones now, server when online';

  @override
  String get nearbyPhonesSeen => 'Nearby phones seen';

  @override
  String get nearbyTestsTestersOnly => 'Nearby tests (testers only)';

  @override
  String get nearbyWhileClosedBatteryLow => 'Nearby while closed: Battery low';

  @override
  String get nearbyWhileClosedNeedsLocation =>
      'Nearby while closed: Needs location';

  @override
  String get nearbyWhileClosedNeedsPermission =>
      'Nearby while closed: Needs permission';

  @override
  String get nearbyWhileClosedOffByAdmin => 'Nearby while closed: Off by admin';

  @override
  String get nearbyWhileClosedOn => 'Nearby while closed: On';

  @override
  String get nearbyWiFi => 'Nearby · Wi-Fi';

  @override
  String get nearbyWiFiDirect => 'Nearby · Wi-Fi Direct';

  @override
  String get needsALook => 'Needs a look';

  @override
  String get needsAndroid10OrNewer => 'Needs Android 10 or newer';

  @override
  String get needsTheServer => 'Needs the server';

  @override
  String get needsTheServer2 => 'Needs the server.';

  @override
  String get needsTheServerItOpensBy =>
      'Needs the server. It opens by itself when the server is back.';

  @override
  String get network => 'Network';

  @override
  String get networkDetails => 'Network details';

  @override
  String get networkMesh => 'Network & mesh';

  @override
  String get networkMesh2 => 'Network & Mesh';

  @override
  String get neverSeen => 'Never seen';

  @override
  String get neverShareItLinkupAndThe =>
      'Never share it. LinkUp and the admin never ask for it.';

  @override
  String get neverShown => 'Never shown';

  @override
  String get neverShownToAdmins => 'Never shown to admins';

  @override
  String get newCall => 'New call';

  @override
  String get newChat => 'New chat';

  @override
  String get newCode => 'New code';

  @override
  String get newConversation => 'New conversation';

  @override
  String get newDeviceName => 'New device name';

  @override
  String get newGroup => 'New group';

  @override
  String get newHere => 'New here?';

  @override
  String get newLinkMadeTheOldOne =>
      'New link made. The old one stops working.';

  @override
  String get newLinkupFoundNearby => 'New LinkUp found nearby';

  @override
  String get newLinkupOnTheServer => 'New LinkUp on the server';

  @override
  String get newMessage => 'New message';

  @override
  String newMessageFrom(Object? displayName) {
    return 'New message from $displayName';
  }

  @override
  String get newMessages => 'New messages';

  @override
  String newMessages2(Object? unreadCount) {
    return '$unreadCount new messages';
  }

  @override
  String newMessages3(Object? displayName, Object? unreadCount) {
    return '$displayName • $unreadCount new messages';
  }

  @override
  String get newNotification => 'New notification';

  @override
  String get newOwnerOfThisPhoneAsk =>
      'New owner of this phone? Ask the admin.';

  @override
  String get newPassword => 'New password';

  @override
  String get newPasswordAgain => 'New password again';

  @override
  String newPhone(Object? named) {
    return 'New phone: $named';
  }

  @override
  String newPhone2(Object? named, Object? created_at) {
    return 'New phone: $named · $created_at';
  }

  @override
  String get newPoll => 'New poll';

  @override
  String get newRecoveryCode => 'New recovery code';

  @override
  String get newRequest => 'New request';

  @override
  String get newSecurityCodeAccepted => 'New security code accepted';

  @override
  String get newSecurityKey => 'New security key';

  @override
  String newText(Object? unreadCount, Object? messages) {
    return '$unreadCount new $messages';
  }

  @override
  String get newer => 'Newer';

  @override
  String get newestFirstMergedAcrossUsersDevices =>
      'Newest first, merged across users, devices, files, calls and audit sources';

  @override
  String get next => 'Next';

  @override
  String get nextDownload => 'Next: Download  →';

  @override
  String get nextPhone => 'Next phone';

  @override
  String get noAccountWithThisUsername => 'No account with this username.';

  @override
  String get noActivityRecorded => 'No activity recorded';

  @override
  String get noAddressAtAllYourFriend =>
      'No address at all? Your friend joins the Wi-Fi (step 1), opens its Wi-Fi details, and types the \"Gateway\" address in Chrome with :8080';

  @override
  String get noAnswer => 'No answer';

  @override
  String get noBackupYet => 'No backup yet';

  @override
  String get noCallsYet => 'No calls yet';

  @override
  String get noChatsFound => 'No chats found';

  @override
  String get noChatsYet => 'No chats yet';

  @override
  String get noConnectionCheckYourNetworkAnd =>
      'No connection. Check your network and try again.';

  @override
  String get noContactsYet => 'No contacts yet';

  @override
  String get noConversationsYet => 'No conversations yet';

  @override
  String get noCriticalSecurityAlertsIn24h =>
      'No critical security alerts in 24h';

  @override
  String get noData => 'No data';

  @override
  String get noDataForThisPeriod => 'No data for this period';

  @override
  String get noDownloadsFor10Minutes => 'No downloads for 10 minutes.';

  @override
  String get noEncryptedIdentityBackupOnThe =>
      'No encrypted identity backup on the server';

  @override
  String get noFilesYet => 'No files yet';

  @override
  String get noFriendFound => 'No friend found';

  @override
  String get noFriendSPhoneCouldCheck =>
      'No friend\'s phone could check the code yet. Come near a friend\'s phone, or connect to the server.';

  @override
  String get noFriendsYet => 'No friends yet';

  @override
  String get noHealthReadings => 'No health readings';

  @override
  String get noInternetNoSimNeeded => '•  No internet, no SIM needed';

  @override
  String get noLink => 'No link';

  @override
  String get noLinkupServerWasFoundEnter =>
      'No LinkUp server was found. Enter the server address and try again.';

  @override
  String get noMessageHereYouCanOnly =>
      'No \"Message\" here: you can only chat 1:1 with friends. In the group you can still talk.';

  @override
  String get noMessages => 'No messages';

  @override
  String get noMessagesFound => 'No messages found';

  @override
  String get noMessagesInTheseDates => 'No messages in these dates.';

  @override
  String get noMessagesInThisChat => 'No messages in this chat';

  @override
  String get noMessagesOrCalls => 'No messages or calls';

  @override
  String get noMessagesWereExchangedInThis =>
      'No messages were exchanged in this window.';

  @override
  String get noMessagesYetToday => 'No messages yet today';

  @override
  String get noMinimum => 'No minimum';

  @override
  String get noModuleMatchesThatTermGlobal =>
      'No module matches that term. Global entity search across users, devices and transfers is available inside each module.';

  @override
  String get noNearbyPhoneCouldShareIt => 'No nearby phone could share it';

  @override
  String get noNewSignIn => 'No new sign-in';

  @override
  String get noOneCalled => 'No one called ';

  @override
  String noOneCalledOnTheMap(Object? q) {
    return 'No one called \"$q\" on the map';
  }

  @override
  String get noOneFound => 'No one found';

  @override
  String get noOneIsAsking => 'No one is asking';

  @override
  String get noOneIsBlockedByAdmin => 'No one is blocked by admin';

  @override
  String get noOneNearbyRightNow => 'No one nearby right now';

  @override
  String get noOneOnlineRightNow => 'No one online right now';

  @override
  String get noOneTimeCodeWasReturned => 'No one-time code was returned.';

  @override
  String get noOneToShowYetSearch =>
      'No one to show yet. Search a name or scan a QR code.';

  @override
  String get noOperationalEventsHaveBeenRecorded =>
      'No operational events have been recorded on this server yet.';

  @override
  String get noOtherPhonesLinked => 'No other phones linked';

  @override
  String get noOtherRegisteredDevicesAreAvailable =>
      'No other registered devices are available.';

  @override
  String get noOwner => 'No owner';

  @override
  String get noPendingRecoveryRequest => 'No pending recovery request';

  @override
  String get noPeopleFound => 'No people found';

  @override
  String get noPhone => 'no phone';

  @override
  String noPhoneReachedYet(Object? since) {
    return '$since · no phone reached yet';
  }

  @override
  String get noPhonesFound => 'No phones found';

  @override
  String get noPhonesOnline => 'No phones online';

  @override
  String get noQrCodeFoundInThis => 'No QR code found in this picture';

  @override
  String get noRecentActivity => 'No recent activity';

  @override
  String get noRecords => 'No records';

  @override
  String get noRequests => 'No requests';

  @override
  String get noResponseTrafficRecordedYet =>
      'No response traffic recorded yet.';

  @override
  String noResultsFor(Object? q) {
    return 'No results for \'$q\'';
  }

  @override
  String get noRoutesYet => 'No routes yet.';

  @override
  String get noRule => 'no rule';

  @override
  String get noServerAFriendSPhone =>
      'No server · a friend\'s phone nearby checks it';

  @override
  String get noServerRequestsGoByWi =>
      'No server · requests go by Wi-Fi Direct / mesh';

  @override
  String get noServerRightNow => 'No server right now';

  @override
  String get noServerSearchingNearbyPhones =>
      'No server - searching nearby phones';

  @override
  String get noServerShowingPeopleSeenNearby =>
      'No server · showing people seen nearby';

  @override
  String get noServerSideKeyHistoryYet => 'No server-side key history yet.';

  @override
  String get noWarnings => 'No warnings';

  @override
  String get noWayToReachRightNow =>
      'No way to reach right now. Messages wait and go when a way opens.';

  @override
  String get nobody => 'Nobody';

  @override
  String get nobodyCanFindYouByName =>
      '**Nobody can find you** by name search, and no phone shows you to others.';

  @override
  String get nobodyCanFindYouByName2 =>
      'Nobody can find you by name search. Only friends get your phone number.';

  @override
  String get nobodyIsBlockedHere => 'Nobody is blocked here';

  @override
  String get nobodyKnownOnThisPhoneYet => 'Nobody known on this phone yet.';

  @override
  String get nobodySignedIn => 'Nobody signed in';

  @override
  String get none => 'None';

  @override
  String get noneYetWaiting => 'None yet. Waiting…';

  @override
  String notAddedYetTheyNeedTo(Object? join) {
    return 'Not added yet: $join. They need to open LinkUp Online once.';
  }

  @override
  String get notApproved => 'Not approved';

  @override
  String get notAvailable => 'Not available';

  @override
  String get notAvailableOnThisDevice => 'Not available on this device.';

  @override
  String get notConnected => 'Not connected';

  @override
  String get notDownloadedYet => 'Not downloaded yet';

  @override
  String get notFoundItMayHaveBeen =>
      'Not found. It may have been removed or renamed.';

  @override
  String get notFoundTryAgainWhenYou =>
      'Not found. Try again when you\'re online or near friends.';

  @override
  String get notHereAskThemToOpen => 'Not here? Ask them to open ';

  @override
  String get notHereAskThemToOpen2 =>
      'Not here? Ask them to open My QR code, then tap Scan QR code below.';

  @override
  String get notInAGroup => 'Not in a group';

  @override
  String get notNow => 'Not now';

  @override
  String notOnServer(Object? local) {
    return '$local not on server';
  }

  @override
  String get notOnServer2 => 'Not on server';

  @override
  String get notOnServerYet => 'Not on server yet';

  @override
  String get notReachedIn7DaysTap => 'Not reached in 7 days · tap to try again';

  @override
  String notReachedIn7DaysTap2(Object? name) {
    return 'Not reached in 7 days. Tap Try again to send the group to $name again.';
  }

  @override
  String get notSaved => 'Not saved';

  @override
  String get notSeenFor30Days => 'Not seen for 30+ days';

  @override
  String get notSentTapToRetry => 'Not sent - tap to retry';

  @override
  String get notSentYet => 'Not sent yet';

  @override
  String get notVerified => 'Not verified';

  @override
  String get notVotedYet => 'Not voted yet';

  @override
  String get notYourFriendInThisGroup => 'Not your friend · in this group';

  @override
  String get nothingDoneYet => 'Nothing done yet';

  @override
  String get nothingNeedsALookRightNow => 'Nothing needs a look right now.';

  @override
  String get nothingPending => 'Nothing pending';

  @override
  String get nothingRecordedForThisPeriod =>
      'Nothing recorded for this period.';

  @override
  String get nothingRemoved => 'nothing removed';

  @override
  String get nothingToReport => 'Nothing to report';

  @override
  String get nothingYet => 'Nothing yet';

  @override
  String get notificationChannels => 'Notification channels';

  @override
  String get notifications => 'Notifications';

  @override
  String get notificationsAllowLinkupTurnOnBanners =>
      'Notifications: allow LinkUp, turn on Banners, Lock screen and Full-screen';

  @override
  String get notificationsAreDisabledInAndroidSettings =>
      'Notifications are disabled in Android settings';

  @override
  String get notificationsOffTapToAllow => 'Notifications off - tap to allow';

  @override
  String get notificationsOn => 'Notifications on';

  @override
  String get nov => 'Nov';

  @override
  String now(Object? rule) {
    return 'Now: $rule';
  }

  @override
  String get oct => 'Oct';

  @override
  String ofAdded(Object? added, Object? invites) {
    return '$added of $invites added';
  }

  @override
  String ofParts(Object? parts, Object? vOf) {
    return '$parts of $vOf parts';
  }

  @override
  String ofPartsTheRestIsOn(Object? parts, Object? vOf) {
    return '$parts of $vOf parts · the rest is on the way';
  }

  @override
  String ofPhones(Object? done, Object? need) {
    return '$done of $need phones';
  }

  @override
  String ofRegistered(Object? num) {
    return 'of $num registered';
  }

  @override
  String ofVoted(Object? voters, Object? members) {
    return '$voters of $members voted';
  }

  @override
  String ofVoted2(Object? question, Object? voters, Object? members) {
    return '$question · $voters of $members voted';
  }

  @override
  String get off => 'Off';

  @override
  String get offAccountClosed => 'Off (account closed)';

  @override
  String get offline => 'Offline';

  @override
  String get offlineAccount => 'Offline account';

  @override
  String get offlineAccountNotOnServerYet =>
      'Offline account · not on server yet';

  @override
  String get offlineAccountsNotSeenFor30 =>
      'Offline accounts not seen for 30 days';

  @override
  String get offlineBlockingIsNotReadyYet =>
      'Offline blocking is not ready yet.';

  @override
  String get offlineBlockingIsReady => 'Offline blocking is ready';

  @override
  String get offlineIdle => 'Offline / idle';

  @override
  String offlineToolsOnlyBlockAppVersion(Object? level) {
    return '$level · Offline tools only · block, app version';
  }

  @override
  String get offlineToolsStillWorkLockedOnes =>
      'Offline tools still work. Locked ones open by themselves.';

  @override
  String get offlineWorksOnThisPhone => 'Offline · works on this phone';

  @override
  String get oldAccount => 'old account';

  @override
  String get oldApp => 'Old app';

  @override
  String get oldAppRule => 'Old app rule';

  @override
  String get oldChatsStay => 'Old chats stay';

  @override
  String get oldLinkup => 'Old LinkUp';

  @override
  String get oldMessagesStayOnYourPhone =>
      'Old messages stay on your phone (read only). You can delete the group later.';

  @override
  String get oldVersionUpdateToCall => 'Old version. Update to call.';

  @override
  String get oldVersionUpdateToSend => 'Old version. Update to send.';

  @override
  String get older => 'Older';

  @override
  String get olderApps => 'Older apps';

  @override
  String get olderAppsCanOnlyReadChats =>
      'Older apps can only read chats from now. They see an Update button.';

  @override
  String get olderAppsSeeAYellowUpdate =>
      'Older apps see a yellow \"Update\" banner. They keep working.';

  @override
  String olderAppsSeeUpdateNeededIn(Object? days) {
    return 'Older apps see \"Update needed in $days days\". After that they can only read chats.';
  }

  @override
  String olderVersionsStopped(Object? v) {
    return '$v · older versions stopped';
  }

  @override
  String onAnOldApp(Object? phone) {
    return '$phone on an old app';
  }

  @override
  String get onCharger => 'On charger';

  @override
  String onEveryPhone(Object? adminBlocked) {
    return '$adminBlocked · on every phone';
  }

  @override
  String get onEveryPhoneTheUnblockReaches =>
      'On every phone the unblock reaches';

  @override
  String get onLinkup => ' on LinkUp';

  @override
  String get onNearbyLinkupPhonesCanJoin =>
      'On — nearby LinkUp phones can join';

  @override
  String get onServer => 'On server';

  @override
  String get onTheNewPhone => 'On the new phone:';

  @override
  String get onTheNewPhoneChooseTransfer =>
      'On the new phone, choose “Transfer account from old phone” and scan this QR code. Keep both phones on the same trusted LinkUp network.';

  @override
  String get onTheServer => 'On the server';

  @override
  String get onTheWebOrInThe => 'On the web or in the app';

  @override
  String get onThisPhoneAndroidNeedsLocation =>
      'On this phone Android needs Location on to start a LinkUp Wi-Fi. Nothing is tracked.';

  @override
  String get onWaitingForAFullGroup =>
      'On — waiting for a full group or a hotspot nearby';

  @override
  String get oneAnswerEachAVoteCan =>
      'One answer each. A vote can be changed for 3 minutes, then it\'s final.';

  @override
  String get oneRunAsIfFilesWere => 'One run as if files were 11 days old';

  @override
  String oneTimeCodeFor(Object? them) {
    return 'One-time code for $them';
  }

  @override
  String get oneTimeCodeFromTheAdmin => 'One-time code from the admin';

  @override
  String get oneTimeOnly => 'One time only\n';

  @override
  String get online => 'Online';

  @override
  String online2(Object? online) {
    return '$online online';
  }

  @override
  String online3(Object? phone, Object? online) {
    return '$phone · $online online';
  }

  @override
  String get onlineCall => 'Online call';

  @override
  String get onlineDevices => 'Online devices';

  @override
  String get onlineNow => 'Online now';

  @override
  String get onlineViaServer => 'Online - via server';

  @override
  String get only => 'Only ';

  @override
  String get onlyActionsYourAdminRolePermits =>
      'Only actions your admin role permits';

  @override
  String get onlyAdmins => 'Only admins';

  @override
  String get onlyAdminsAddPeople => 'Only admins add people';

  @override
  String get onlyAdminsAnnouncementGroup => 'Only admins = announcement group';

  @override
  String get onlyAdminsCanChangeTheGroup =>
      'Only admins can change the group photo.';

  @override
  String get onlyAdminsCanDoThis => 'Only admins can do this.';

  @override
  String get onlyAdminsCanPinMessages => 'Only admins can pin messages';

  @override
  String get onlyAdminsCanSeeAndChange =>
      'Only admins can see and change these.';

  @override
  String get onlyAdminsCanSendMessages => 'Only admins can send messages.';

  @override
  String get onlyAdminsSend => 'Only admins send';

  @override
  String get onlyContactsTheAppCanConfirm =>
      'Only contacts the app can confirm';

  @override
  String get onlyForThisPhone => 'Only for this phone?';

  @override
  String get onlyKindAndSizeNobodyCan =>
      'Only kind and size. Nobody can open the files.';

  @override
  String get onlyNamesAndTimesNobodyCan =>
      'Only names and times. Nobody can hear calls.';

  @override
  String get onlyPeopleThisPhoneHasSeen =>
      'Only people this phone has seen are listed. Others can be blocked from the web panel.';

  @override
  String get onlyTheOwnerAdminCanBlock =>
      'Only the owner admin can block users';

  @override
  String get onlyTheOwnerCanChangeThis => 'Only the Owner can change this.';

  @override
  String get onlyThisPhoneOnlineOrOffline =>
      'Only this phone, online or offline';

  @override
  String get onlyYouCanChangeThisTurn =>
      'Only you can change this. Turn it off any time.';

  @override
  String get onlyYouShouldSeeYourRecovery =>
      'Only you should see your recovery code.';

  @override
  String get onlyYouWillSeeThisName => 'Only you will see this name';

  @override
  String get open => 'Open';

  @override
  String get openAppVersion => 'Open App version';

  @override
  String get openAuditLog => 'Open audit log';

  @override
  String get openGroup => 'Open group';

  @override
  String get openHotspotSettings => 'Open hotspot settings';

  @override
  String get openLinkup => 'Open LinkUp';

  @override
  String get openLinkupNearAMember => 'Open LinkUp near a member';

  @override
  String get openNavigation => 'Open navigation';

  @override
  String get openNetworkTopology => 'Open Network Topology';

  @override
  String get openRecentsTapTheLinkupIcon =>
      'Open Recents, tap the LinkUp icon, choose Lock';

  @override
  String get openRecovery => 'Open Recovery';

  @override
  String get openSecurity => 'Open Security';

  @override
  String get openSettings => 'Open settings';

  @override
  String get openThisPersonFromPeopleTo =>
      'Open this person from People to block them.';

  @override
  String get openThisScreenAgainWhenYou =>
      'Open this screen again when you are back online.';

  @override
  String openedChat(Object? admin, Object? pair) {
    return '$admin opened chat $pair';
  }

  @override
  String openedTheGroupInviteLinkAdd(Object? name) {
    return '$name opened the group invite link. Add only people you know.';
  }

  @override
  String get openedTheInviteLink => 'opened the invite link';

  @override
  String get opensWhatsappChooseMessageYourself =>
      'Opens WhatsApp · choose \"Message yourself\"';

  @override
  String get operationalMetadataFromTheLinkupServer =>
      'Operational metadata from the LinkUp server.';

  @override
  String get operationalMetadataOnlyPasswordsPrivateKeys =>
      'Operational metadata only. Passwords, private keys, message bodies, call audio and decrypted media are never exposed to this dashboard.';

  @override
  String get operations => 'Operations';

  @override
  String get operatorText => 'Operator';

  @override
  String option(Object? i) {
    return 'Option $i';
  }

  @override
  String get optional => 'Optional';

  @override
  String get orScanWithTheCameraApp => '(or scan with the camera app)';

  @override
  String get orType => 'or type:';

  @override
  String get orTypeIt => 'Or type it';

  @override
  String get orWaitUntilAMemberIs => ', or wait until a member is Online once.';

  @override
  String get otherBrandTapToPick => 'Other brand? Tap to pick';

  @override
  String otherLinkupPhones(Object? n) {
    return '$n other LinkUp phones';
  }

  @override
  String otherLinkupPhonesJoinThisOne(Object? hotspotStatusText) {
    return 'Other LinkUp phones join this one. No internet is shared. $hotspotStatusText';
  }

  @override
  String get otherPhonesPixelMotorolaNokia =>
      'Other phones (Pixel, Motorola, Nokia...)';

  @override
  String get outgoing => 'Outgoing';

  @override
  String get outsideTheDatesPhoneClock => 'Outside the dates (phone clock)';

  @override
  String get overTheInternetThroughTheLinkup =>
      'Over the internet, through the LinkUp server.';

  @override
  String overall(Object? label) {
    return 'Overall: $label';
  }

  @override
  String get overview => 'Overview';

  @override
  String get owner => 'Owner';

  @override
  String get ownerCanRead => 'Owner can read';

  @override
  String get ownerCanReadEveryOpenIs => 'Owner can read; every open is saved';

  @override
  String get ownerOnly => 'Owner only';

  @override
  String packetLoss(Object? toStringAsFixed) {
    return '$toStringAsFixed% packet loss';
  }

  @override
  String get packetsPassedOn => 'Packets passed on';

  @override
  String get pairingCode => 'Pairing code';

  @override
  String get password => 'Password';

  @override
  String get passwordChanged => 'Password changed';

  @override
  String get passwordCopied => 'Password copied';

  @override
  String get passwordHasACharacterThatIs =>
      'Password has a character that is not allowed.';

  @override
  String get passwordIsTooLong => 'Password is too long.';

  @override
  String get passwordMustBeAtLeast8 =>
      'Password must be at least 8 characters.';

  @override
  String passwordOf(Object? username) {
    return 'Password of @$username';
  }

  @override
  String get passwords => 'Passwords';

  @override
  String get pasteCode => 'Paste code';

  @override
  String get pasteContactCode => 'Paste contact code';

  @override
  String get pasteGroupCode => 'Paste group code';

  @override
  String get pasteItInAnyApp => 'Paste it in any app';

  @override
  String get pasteTheSharedCodeTextHere => 'Paste the shared code text here';

  @override
  String get pause => 'Pause';

  @override
  String get pending => 'Pending';

  @override
  String pending2(Object? pending) {
    return 'Pending $pending';
  }

  @override
  String get pendingRecoveries => 'Pending recoveries';

  @override
  String get pendingUntilEachPhoneDoesIt => 'Pending until each phone does it';

  @override
  String pendingUntilEachPhoneDoesIt2(Object? pendingCount) {
    return '$pendingCount pending · until each phone does it';
  }

  @override
  String get people => 'People';

  @override
  String people2(Object? n) {
    return '$n people';
  }

  @override
  String peopleAreTyping(Object? clean) {
    return '$clean people are typing…';
  }

  @override
  String get peopleMovingToANewPhone => 'People moving to a new phone';

  @override
  String get peopleNearYouMustAskFirst =>
      'People near you must **ask first**, and you accept or decline. A **QR code** still adds at once.';

  @override
  String get peopleNearby => 'People nearby';

  @override
  String get peopleNearbyPhonesKnow => 'People nearby phones know';

  @override
  String get peopleSignedIn => 'People signed in';

  @override
  String get peopleWhoAlreadyHaveYouKeep =>
      'People who already have you **keep you**. They see a \"Private\" label next to your name.';

  @override
  String get peopleWithAnAccount => 'People with an account';

  @override
  String get peopleYouBlockHereAreStopped =>
      'People you block here are stopped on every phone.';

  @override
  String get peopleYouCanAdd => 'People you can add';

  @override
  String get percentagesAreLiveReadingsTheTick =>
      'Percentages are live readings; the tick marks the alert threshold';

  @override
  String get phone => 'Phone';

  @override
  String phone2(Object? number) {
    return 'Phone $number';
  }

  @override
  String phoneFullFree(Object? usedPercent, Object? free) {
    return 'Phone: $usedPercent% full · $free free';
  }

  @override
  String get phoneMasterPowerSavingLetLinkup =>
      'Phone Master > Power saving: let LinkUp run in background';

  @override
  String get phoneNumber => 'Phone number';

  @override
  String get phoneNumberVisibility => 'Phone number visibility';

  @override
  String get phoneRemoved => 'Phone removed';

  @override
  String get phoneToPhoneNoRouterNeeded =>
      'Phone to phone, no router needed. Messages and calls go straight between your phones.';

  @override
  String get phones => 'Phones';

  @override
  String phones2(Object? carriers) {
    return '$carriers phones';
  }

  @override
  String get phonesAroundYouWithLinkup => 'Phones around you with LinkUp';

  @override
  String phonesConfirmed(Object? since) {
    return '$since · phones confirmed';
  }

  @override
  String get phonesGettingLinkup => 'Phones getting LinkUp';

  @override
  String get phonesLinkedThisWay => 'Phones linked this way';

  @override
  String get phonesLive => 'Phones live';

  @override
  String get phonesNear => 'Phones near';

  @override
  String get phonesRightNow => 'Phones right now';

  @override
  String phonesSeenNearbyThatThisAffects(Object? affects) {
    return 'Phones seen nearby that this affects: $affects.';
  }

  @override
  String get phonesShowHereWhenTheyAre =>
      'Phones show here when they are linked.';

  @override
  String get phonesThatGotTheRule => 'phones that got the rule';

  @override
  String get phonesThatHavenTAnsweredYet =>
      'Phones that haven\'t answered yet won\'t answer.';

  @override
  String get phonesThatHavenTDoneIt =>
      'Phones that haven\'t done it yet won\'t do it. Phones that did it stay as they are.';

  @override
  String get phonesWiFiRulesRecovery => 'phones, Wi-Fi rules, recovery';

  @override
  String get photo => 'Photo';

  @override
  String get photos => 'Photos';

  @override
  String get pick => 'Pick';

  @override
  String get pickAUsernameYourFriendsKnow =>
      'Pick a username your friends know';

  @override
  String get pickAsManyChatsAsYou =>
      'Pick as many chats as you want. Photos and videos are sent again as new files.';

  @override
  String get pin => 'Pin';

  @override
  String get pinForHowLong => 'Pin for how long?';

  @override
  String pinnedAMessage(Object? actor) {
    return '$actor pinned a message';
  }

  @override
  String get pinnedMessage => 'Pinned message';

  @override
  String get platform => 'Platform';

  @override
  String get play => 'Play';

  @override
  String get played => 'Played';

  @override
  String get playingInMiniPlayer => 'Playing in mini player';

  @override
  String get pleaseWaitAFewSeconds => 'Please wait a few seconds';

  @override
  String get pointAtThisCode => 'Point at this code';

  @override
  String get pointAtThisCodeOrPick =>
      'Point at this code, or pick this picture';

  @override
  String get pointAtYourFriendSQr => 'Point at your friend\'s QR code';

  @override
  String poll(Object? question) {
    return '📊 Poll: $question';
  }

  @override
  String get pollChooseOne => 'POLL · CHOOSE ONE';

  @override
  String get pollChooseOneOrMore => 'POLL · CHOOSE ONE OR MORE';

  @override
  String get poor => 'Poor';

  @override
  String get preparing => 'Preparing…';

  @override
  String get preparingLogs => 'Preparing logs...';

  @override
  String get pressBackAgainToExit => 'Press back again to exit';

  @override
  String get pretendOldBuild => 'Pretend old build';

  @override
  String get privacy => 'Privacy';

  @override
  String get privacyAccess => 'Privacy & access';

  @override
  String get privacyAccess2 => 'Privacy & Access';

  @override
  String get privacyBoundary => 'Privacy boundary';

  @override
  String get privacySecurity => 'Privacy & Security';

  @override
  String get privacySettingsSaved => 'Privacy settings saved';

  @override
  String get private => 'Private';

  @override
  String get privateAndSecure => 'Private and secure';

  @override
  String get privateChat => 'Private chat';

  @override
  String get privateKeys => 'Private keys';

  @override
  String get privateProfile => 'Private profile';

  @override
  String get privateThingsStayPrivate => 'Private things stay private';

  @override
  String get profile => 'Profile';

  @override
  String get profileInformation => 'Profile information';

  @override
  String get profilePhoto => 'Profile photo';

  @override
  String get profileSaved => 'Profile saved';

  @override
  String get protectYourAccountWhenThisPhone =>
      'Protect your account when this phone is lost.';

  @override
  String publicKey(Object? currentPublicKey) {
    return 'Public key: $currentPublicKey';
  }

  @override
  String get publicKeyUnavailable => 'Public key unavailable';

  @override
  String qrImportFailed(Object? stage, Object? e) {
    return 'QR import failed ($stage): $e';
  }

  @override
  String get quickActions => 'Quick actions';

  @override
  String reached(Object? done) {
    return 'Reached $done';
  }

  @override
  String reachedPhone(Object? reached, Object? s) {
    return 'Reached $reached phone$s';
  }

  @override
  String get reachedThePhoneItMustReach =>
      'Reached the phone - it must reach the server once';

  @override
  String get reachedThePhoneItMustReach2 =>
      'reached the phone · it must reach the server once';

  @override
  String react(Object? emoji) {
    return 'React $emoji';
  }

  @override
  String get reactions => 'Reactions';

  @override
  String get read => 'Read';

  @override
  String readByOf(Object? read, Object? total) {
    return 'Read by $read of $total';
  }

  @override
  String get readChatsOnlyUpdateToSend =>
      'Read chats only. Update to send and call.';

  @override
  String get readOnlyAtOnce => 'Read only at once';

  @override
  String get readReceipts => 'Read receipts';

  @override
  String get readReceiptsAreOffTurnOn =>
      'Read receipts are off. Turn on in Settings › Privacy.';

  @override
  String get ready => 'Ready';

  @override
  String get readyToSend => 'Ready to send';

  @override
  String get readyToUpdate => 'Ready to update';

  @override
  String reason(Object? rejectedReason) {
    return 'Reason: $rejectedReason';
  }

  @override
  String get reasonOptional => 'Reason (optional)';

  @override
  String get recentActivity => 'Recent activity';

  @override
  String get recentChats => 'RECENT CHATS';

  @override
  String get recentSecurityEvents => 'RECENT SECURITY EVENTS';

  @override
  String get recentsLockLinkupTapItsIcon =>
      'Recents: lock LinkUp (tap its icon, choose Lock)';

  @override
  String get recommendedMessagesArriveInstantly =>
      'Recommended — messages arrive instantly';

  @override
  String get recommendedWhenReplacingTheOldPhone =>
      'Recommended when replacing the old phone.';

  @override
  String get reconnecting => 'Reconnecting';

  @override
  String get reconnecting2 => 'Reconnecting…';

  @override
  String get recoverYourAccount => 'Recover your account';

  @override
  String recovery(Object? v) {
    return 'Recovery $v';
  }

  @override
  String get recovery2 => 'Recovery';

  @override
  String get recoveryApproved => 'Recovery approved';

  @override
  String get recoveryAsked => 'Recovery asked';

  @override
  String recoveryAttempts(Object? recoveryAttempts) {
    return '$recoveryAttempts recovery attempts';
  }

  @override
  String get recoveryCanLook => 'recovery, can look';

  @override
  String get recoveryCode => 'RECOVERY CODE';

  @override
  String get recoveryCode2 => 'Recovery code';

  @override
  String get recoveryCodeSaved => 'Recovery code saved';

  @override
  String get recoveryCodeTurnedOff => 'Recovery code turned off';

  @override
  String get recoveryCompleted => 'Recovery completed';

  @override
  String get recoveryCompleted2 => 'Recovery completed.';

  @override
  String get recoveryCredentialExpires => 'Recovery credential expires';

  @override
  String get recoveryExpired => 'Recovery expired';

  @override
  String get recoveryFinished => 'Recovery finished';

  @override
  String get recoveryNewCode => 'Recovery new code';

  @override
  String get recoveryQueue => 'Recovery queue';

  @override
  String get recoveryRejected => 'Recovery rejected';

  @override
  String get recoveryStatus => 'Recovery status';

  @override
  String get refresh => 'Refresh';

  @override
  String get refreshData => 'Refresh data';

  @override
  String get refreshEvery => 'Refresh every';

  @override
  String get refreshNow => 'Refresh now';

  @override
  String get refreshTimeAlertsBackup => 'Refresh time, alerts, backup';

  @override
  String get refreshUnavailable => 'Refresh unavailable';

  @override
  String get registered => 'Registered';

  @override
  String get registeredDevices => 'Registered devices';

  @override
  String get registeredHardware => 'Registered hardware';

  @override
  String get reject => 'Reject';

  @override
  String get rejectThisRequest => 'Reject this request?';

  @override
  String get rejected => 'Rejected';

  @override
  String rejectedRecoveryFor(Object? admin, Object? target) {
    return '$admin rejected recovery for $target';
  }

  @override
  String get relayLinksNotContacts => 'Relay links (not contacts)';

  @override
  String get relaysForOthers => 'relays for others';

  @override
  String get remove => 'Remove';

  @override
  String get removeContact => 'Remove contact';

  @override
  String removeFrom(Object? name, Object? groupName) {
    return 'Remove $name from \"$groupName\"?';
  }

  @override
  String get removeFromGroup => 'Remove from group';

  @override
  String removeFromThisGroup(Object? label) {
    return 'Remove $label from this group?';
  }

  @override
  String removeFromYourContacts(Object? name) {
    return 'Remove $name from your contacts?';
  }

  @override
  String get removeMember => 'Remove member';

  @override
  String get removeMember2 => 'Remove member?';

  @override
  String get removeOption => 'Remove option';

  @override
  String get removePhone => 'Remove phone';

  @override
  String get removePhoto => 'Remove photo';

  @override
  String get removeRule => 'Remove rule';

  @override
  String get removeThisPhone => 'Remove this phone?';

  @override
  String get removeVerifiedMark => 'Remove verified mark';

  @override
  String removeYour(Object? emoji) {
    return 'Remove your $emoji';
  }

  @override
  String removed(Object? name) {
    return '$name removed';
  }

  @override
  String removed2(Object? label) {
    return '$label removed.';
  }

  @override
  String get removed3 => 'Removed';

  @override
  String removed4(Object? actor, Object? targets) {
    return '$actor removed $targets';
  }

  @override
  String removedAdminFrom(Object? admin, Object? target) {
    return '$admin removed admin from $target';
  }

  @override
  String get removedToSaveSpace => 'Removed to save space';

  @override
  String removedToSaveSpaceAskTo(Object? sender) {
    return 'Removed to save space. Ask $sender to send it again.';
  }

  @override
  String get removesPhotosVideosAndDocumentsAs =>
      'Removes photos, videos and documents as if they were 11 days old and the phone 80% full. Voice notes and unsent media stay. The messages stay with a small picture.';

  @override
  String get rename => 'Rename';

  @override
  String get renamePhone => 'Rename phone';

  @override
  String renamed(Object? admin, Object? target) {
    return '$admin renamed $target';
  }

  @override
  String get replaced => 'Replaced';

  @override
  String get replacedByANewerAction => 'Replaced by a newer action';

  @override
  String get reply => 'Reply';

  @override
  String get request => 'Request';

  @override
  String get requestDeclined => 'Request declined';

  @override
  String get requestSent => 'Request sent';

  @override
  String get requestSentByTheServer => 'Request sent by the server';

  @override
  String requestSentNeedsToAccept(Object? who) {
    return 'Request sent. $who needs to accept.';
  }

  @override
  String get requestSentToNearbyPhones => 'Request sent to nearby phones';

  @override
  String requestStatus(Object? substring, Object? status) {
    return 'Request: $substring…\nStatus: $status';
  }

  @override
  String get requestSubmittedAskTheLinkupAdministrator =>
      'Request submitted. Ask the LinkUp administrator to approve it and provide the recovery code.';

  @override
  String get requested => 'Requested';

  @override
  String get requested2 => 'Requested ✓';

  @override
  String get requests => 'Requests';

  @override
  String requests2(Object? requests) {
    return 'Requests $requests';
  }

  @override
  String requestsToJoin(Object? n) {
    return '$n requests to join';
  }

  @override
  String get requestsWaitHereUntilAPhone =>
      'Requests wait here until a phone answers. There is no time limit.';

  @override
  String get requiredText => 'Required';

  @override
  String get requiresTheRuntimeMetricsSampler =>
      'Requires the runtime metrics sampler';

  @override
  String get resend => 'Resend';

  @override
  String get reset => 'Reset';

  @override
  String get resetCode => 'Reset code';

  @override
  String get resetLink => 'Reset link';

  @override
  String get resetLink2 => 'Reset link?';

  @override
  String get resetSetup => 'Reset setup';

  @override
  String get resetSetup2 => 'Reset setup?';

  @override
  String get resetYourPassword => 'Reset your password';

  @override
  String get responseBytesServedPerBucket => 'Response bytes served per bucket';

  @override
  String get restoreAccountData => 'Restore account data';

  @override
  String get restoreAccountDataEncryptedKeys =>
      'Restore account data + encrypted keys';

  @override
  String get restoreEncryptedIdentityBackup =>
      'Restore encrypted identity backup';

  @override
  String get restoreEncryptedIdentityKeys => 'Restore encrypted identity keys?';

  @override
  String get restoreFailed => 'Restore failed';

  @override
  String get restoreKeys => 'Restore keys';

  @override
  String get restoringYourAccount => 'Restoring your account';

  @override
  String get results => 'Results';

  @override
  String resultsFor(Object? searchQuery) {
    return 'Results for \"$searchQuery\"';
  }

  @override
  String get resumingYourRecoveryRequest => 'Resuming your recovery request…';

  @override
  String get retry => 'Retry';

  @override
  String get returnText => 'Return';

  @override
  String get reviewReports => 'Review reports';

  @override
  String get revokeOldPhoneAfterTransfer => 'Revoke old phone after transfer';

  @override
  String get revoked => 'Revoked';

  @override
  String get revokedDevices => 'Revoked devices';

  @override
  String get rightsCheckedByTheServer => 'Rights checked by the server';

  @override
  String get ringing => 'Ringing…';

  @override
  String get role => 'Role';

  @override
  String get rollupsComputedFromPlatformTablesAnd =>
      'Rollups computed from platform tables and the runtime sampler';

  @override
  String get rotateIdentityKey => 'Rotate identity key';

  @override
  String get rotating => 'Rotating…';

  @override
  String get routerEchoWiFiDirectAnd =>
      'Router echo, Wi-Fi Direct and mesh checks';

  @override
  String routes(Object? routes) {
    return 'Routes ($routes)';
  }

  @override
  String get ruleRemovedForEveryone => 'Rule removed for everyone.';

  @override
  String get runTest => 'Run test';

  @override
  String get runningFor => 'Running for';

  @override
  String get runningNow => 'Running now';

  @override
  String sAccountIsClosedCanT(Object? name, Object? name2) {
    return '$name’s account is closed. $name2 can’t sign in.';
  }

  @override
  String sPhoneHasNotGotThe(Object? name, Object? name2) {
    return '$name\'s phone has not got the group yet. It is added by itself when $name2 is Nearby (Wi-Fi Direct or mesh) or Online.';
  }

  @override
  String sSecurityCodeChanged(Object? v) {
    return '$v\'s security code changed';
  }

  @override
  String sSecurityCodeChangedTapTo(Object? device) {
    return '$device\'s security code changed. Tap to check.';
  }

  @override
  String sSecurityCodeChangedTapTo2(Object? device) {
    return '$device\'s security code changed. Tap to learn more.';
  }

  @override
  String sSecurityCodeIsNotReady(Object? v) {
    return '$v\'s security code is not ready yet. It shows after you have chatted once nearby or over the server.';
  }

  @override
  String get safety => 'Safety';

  @override
  String get sajjad => 'Sajjad';

  @override
  String get sameWiFi => 'same Wi-Fi';

  @override
  String get sat => 'Sat';

  @override
  String get save => 'Save';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get saveContactAs => 'Save contact as';

  @override
  String get saveForEveryone => 'Save for everyone';

  @override
  String get saveItNowTheOldOne => 'Save it now. The old one no longer works.';

  @override
  String get saveOnWhatsapp => 'Save on WhatsApp';

  @override
  String get saveRule => 'Save rule';

  @override
  String saveStaysOffUntilTheNumber(Object? phoneHint256) {
    return '$phoneHint256. Save stays off until the number is right.';
  }

  @override
  String get saveToPhone => 'Save to phone';

  @override
  String get saveYourNewRecoveryCodeNow => 'Save your new recovery code now.';

  @override
  String get saveYourRecoveryCode => 'Save your recovery code';

  @override
  String get saved => 'Saved';

  @override
  String get saved2 => 'Saved.';

  @override
  String saved3(Object? size) {
    return '$size · Saved';
  }

  @override
  String get savedItIsSpreadingToNearby =>
      'Saved. It is spreading to nearby phones.';

  @override
  String get savedLocallyWillSyncWhenAvailable =>
      'Saved locally; will sync when available';

  @override
  String get savedOnThisPhone => 'Saved on this phone';

  @override
  String get savedToDownloadLinkup => 'Saved to Download › LinkUp';

  @override
  String get savedToGalleryLinkup => 'Saved to Gallery › LinkUp';

  @override
  String get saving => 'Saving…';

  @override
  String get savingPhoto => 'Saving photo…';

  @override
  String get scanAGroupCode => 'Scan a group code';

  @override
  String get scanInstead => 'Scan instead';

  @override
  String get scanQrCode => 'Scan QR code';

  @override
  String scanSCode(Object? v) {
    return 'Scan $v\'s code';
  }

  @override
  String get scanSecurityCode => 'Scan security code';

  @override
  String get scanTheQrShownOnYour => 'Scan the QR shown on your old phone.';

  @override
  String get scanWithTheCameraAppNot =>
      'Scan with the camera app,\nnot the Wi-Fi scanner';

  @override
  String get scannedTheGroupQr => 'scanned the group QR';

  @override
  String get scannedTheQr => 'scanned the QR';

  @override
  String get screenStaysOnWhileSharing => 'Screen stays on while sharing';

  @override
  String get search => 'Search';

  @override
  String get search2 => 'Search…';

  @override
  String get searchChatsAndMessages => 'Search chats and messages';

  @override
  String get searchFriends => 'Search friends';

  @override
  String get searchMessages => 'Search messages';

  @override
  String get searchModules => 'Search modules…';

  @override
  String get searchName => 'Search name';

  @override
  String get searchNameOrId => 'Search name or id';

  @override
  String get searchNameOrUsername => 'Search name or @username';

  @override
  String get searchPeople => 'Search people';

  @override
  String get searchPhoneOrNextHop => 'Search phone or next hop';

  @override
  String get searchPhoneOrOwner => 'Search phone or owner';

  @override
  String get searchUsersDevices => 'Search users, devices…';

  @override
  String get searching => 'Searching';

  @override
  String get searchingForConnection => 'Searching for connection';

  @override
  String get secondPerson => 'Second person';

  @override
  String get secureLocalFirstMessaging => 'Secure, local-first messaging';

  @override
  String get security => 'Security';

  @override
  String get securityAlerts => 'Security alerts';

  @override
  String get securityAndOperationalEventsAppearHere =>
      'Security and operational events appear here as the server records them.';

  @override
  String get securityCenter => 'Security center';

  @override
  String get securityCenter2 => 'Security Center';

  @override
  String get securityCode => 'Security code';

  @override
  String get securityCodeChanged => 'Security code changed';

  @override
  String get securityEvent => 'Security event';

  @override
  String get securityKey => 'Security key';

  @override
  String get securityOverview => 'Security overview';

  @override
  String get securityWarning => 'security warning';

  @override
  String get seeAndRemovePhonesSignedIn => 'See and remove phones signed in';

  @override
  String get seeAndUnblockPeopleYouBlocked =>
      'See and unblock people you blocked';

  @override
  String get seen => 'Seen';

  @override
  String seen2(Object? a) {
    return 'seen $a';
  }

  @override
  String get seenBefore => 'Seen before';

  @override
  String seenDaysAgo(Object? d) {
    return 'seen $d days ago';
  }

  @override
  String seenHAgo(Object? d) {
    return 'seen $d h ago';
  }

  @override
  String get seenJustNow => 'seen just now';

  @override
  String seenMinAgo(Object? s) {
    return 'Seen $s min ago';
  }

  @override
  String seenMinAgo2(Object? d) {
    return 'seen $d min ago';
  }

  @override
  String seenNearby(Object? join) {
    return 'Seen nearby: $join';
  }

  @override
  String get seenNearbyNoneYet => 'Seen nearby: none yet';

  @override
  String seenSAgo(Object? s) {
    return 'Seen $s s ago';
  }

  @override
  String get seenYesterday => 'seen yesterday';

  @override
  String get select => 'Select';

  @override
  String selectedUpTo(Object? picked, Object? kNewGroupMax) {
    return '$picked selected · up to $kNewGroupMax';
  }

  @override
  String get send => 'Send';

  @override
  String get sendAMessageOrShareA =>
      'Send a message or share a file with everyone in this group.';

  @override
  String get sendAMessagePhotoOrFile =>
      'Send a message, photo or file to begin chatting privately.';

  @override
  String get sendARequest => 'Send a request';

  @override
  String get sendMessage => 'Send message';

  @override
  String get sendMessages => 'Send messages';

  @override
  String get sendPoll => 'Send poll';

  @override
  String get sendRequest => 'Send request';

  @override
  String get sendThePictureToAFriend => 'Send the picture to a friend';

  @override
  String get sendVoiceNote => 'Send voice note';

  @override
  String get sending => 'Sending…';

  @override
  String sendingTheGroupToAgain(Object? name) {
    return 'Sending the group to $name again';
  }

  @override
  String get sendsAFriendRequest => 'Sends a friend request';

  @override
  String get sendsAfterTheCall => 'Sends after the call';

  @override
  String get sent => 'Sent';

  @override
  String sent2(Object? sentAgo) {
    return 'Sent $sentAgo';
  }

  @override
  String sentAsOneMessage(Object? summary) {
    return '$summary\nSent as one message';
  }

  @override
  String get sentByWiFiDirectPasses =>
      'Sent by Wi-Fi Direct · passes phone to phone\nNo time limit · goes to the server log later';

  @override
  String get sentOnlyWhenAllMembersGot =>
      '✓ = sent. ✓✓ only when all members got it.';

  @override
  String sentTo(Object? picks) {
    return 'Sent to $picks';
  }

  @override
  String get sentToAllPhonesPendingUntil =>
      'Sent to all phones · Pending until it is done';

  @override
  String sentToChats(Object? chats) {
    return 'Sent to $chats chats';
  }

  @override
  String get sentToTheAdmin => 'Sent to the admin';

  @override
  String get sep => 'Sep';

  @override
  String get serious => 'Serious';

  @override
  String server(Object? waiting) {
    return 'Server: $waiting';
  }

  @override
  String get server2 => 'Server';

  @override
  String get serverAddressOptionalFallback =>
      'Server address (optional fallback)';

  @override
  String get serverConfiguration => 'Server configuration';

  @override
  String get serverConnected => 'Server connected';

  @override
  String get serverConnectedRequestsGoByThe =>
      'Server connected · requests go by the server';

  @override
  String get serverDisconnected => 'Server disconnected';

  @override
  String serverError(Object? statusCode) {
    return 'Server error ($statusCode)';
  }

  @override
  String get serverHealth => 'Server health';

  @override
  String get serverHealthDetailsAreOffOn =>
      'Server health details are off on this server.';

  @override
  String get serverHistoryNotReachableRightNow =>
      'Server history not reachable right now.';

  @override
  String get serverIsBackToolsUnlocked => 'Server is back. Tools unlocked.';

  @override
  String get serverLinks => 'Server links';

  @override
  String get serverLost => 'Server lost';

  @override
  String get serverOffYourLinksOnly => 'Server off - your links only';

  @override
  String serverPcClockIsH(Object? h, Object? fast) {
    return 'Server PC clock is $h h $fast';
  }

  @override
  String get serverTraffic => 'Server traffic';

  @override
  String get sessions => 'Sessions';

  @override
  String setMinimumVersion(Object? admin, Object? detail) {
    return '$admin set minimum version $detail';
  }

  @override
  String get setNewPassword => 'Set new password';

  @override
  String get setOnceCannotBeChanged => 'Set once — cannot be changed';

  @override
  String setText(Object? label) {
    return 'Set $label';
  }

  @override
  String setTo(Object? name, Object? label) {
    return 'Set $name to $label?';
  }

  @override
  String setTo2(Object? admin, Object? target, Object? detail) {
    return '$admin set $target to $detail';
  }

  @override
  String get settings => 'Settings';

  @override
  String get settingsBatteryBackgroundUsageLimitsLinkup =>
      'Settings > Battery > Background usage limits: LinkUp must not be in Sleeping or Deep sleeping apps';

  @override
  String get settingsWiFiTapTheQr =>
      'Settings → Wi-Fi → tap the QR icon and scan this code.';

  @override
  String sha256Created(
      Object? publicKey, Object? createdAt, Object? retiredAt) {
    return 'SHA-256 $publicKey\nCreated $createdAt$retiredAt';
  }

  @override
  String get share => 'Share';

  @override
  String get shareAHotspot => 'Share a hotspot?';

  @override
  String get shareALinkupHotspot => 'Share a LinkUp hotspot';

  @override
  String get shareAgain => 'Share again';

  @override
  String get shareAnyway => 'Share anyway';

  @override
  String get shareCode => 'Share code';

  @override
  String get shareLink => 'Share link';

  @override
  String get shareLinkup => 'Share LinkUp';

  @override
  String get shareMyQr => 'Share my QR';

  @override
  String get shareYourLinkupIdentityWithAnother =>
      'Share your LinkUp identity with another phone.';

  @override
  String get shareYourSignedPublicProfileThrough =>
      'Share your signed public profile through LinkUp';

  @override
  String get sharingAHotspotTest => 'Sharing a hotspot (test)';

  @override
  String get sharingStopped => 'Sharing stopped';

  @override
  String get sharingStopsByItselfAfter10 =>
      'Sharing stops by itself after 10 minutes with no download, or when you leave this screen.';

  @override
  String get sharingUsesALotOfBattery =>
      'Sharing uses a lot of battery. Plug in the charger first.';

  @override
  String get shortRouteList => 'Short route list';

  @override
  String get showAGenericLinkupNotification =>
      'Show a generic LinkUp notification';

  @override
  String get showFullContent => 'Show full content';

  @override
  String showHidden(Object? count) {
    return 'Show hidden ($count)';
  }

  @override
  String showMoreLeft(Object? next, Object? left) {
    return 'Show $next more  ($left left)';
  }

  @override
  String get showMyCode => 'Show my code';

  @override
  String get showMyLinksMap => 'Show My links map';

  @override
  String get showMyQrCode => 'Show my QR code';

  @override
  String get showPassword => 'Show password';

  @override
  String get showSenderAndMessagePreview => 'Show sender and message preview';

  @override
  String get showSenderOnly => 'Show sender only';

  @override
  String get showText => 'Show';

  @override
  String get signIn => 'Sign in';

  @override
  String get signInAgain => 'Sign in again';

  @override
  String get signInToTheServerTo =>
      'Sign in to the server to open group links.';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOut2 => 'Sign out?';

  @override
  String get signOutAllPhones => 'Sign out all phones';

  @override
  String get signOutAllPhones2 => 'Sign out all phones?';

  @override
  String get signOutThisAdmin => 'Sign out this admin?';

  @override
  String get signOutThisPhone => 'Sign out this phone?';

  @override
  String get signedIn => 'Signed in';

  @override
  String signedIn2(Object? admin) {
    return '$admin signed in';
  }

  @override
  String signedOut(Object? admin) {
    return '$admin signed out';
  }

  @override
  String signedOut2(Object? admin, Object? target) {
    return '$admin signed out $target';
  }

  @override
  String get signedOutByAdmin => 'Signed out by admin';

  @override
  String get signedOutByAdminYourChats =>
      'Signed out by admin. Your chats are still here. Log in again when the server is on.';

  @override
  String get signedOutFromTheServerNearby =>
      'Signed out from the server. Nearby chats still work. Sign in again to use the server.';

  @override
  String get signingYouIn => 'Signing you in…';

  @override
  String since(Object? madeAt) {
    return 'since $madeAt';
  }

  @override
  String since2(Object? s, Object? created_at) {
    return '$s · since $created_at';
  }

  @override
  String sinceEnds(Object? created_at, Object? expires_at) {
    return 'Since $created_at · ends $expires_at';
  }

  @override
  String get skip => 'Skip';

  @override
  String get slideToCancel => 'Slide to cancel';

  @override
  String get small => 'Small';

  @override
  String get smallMap => 'Small map';

  @override
  String get someDataCouldNotLoad => 'Some data could not load';

  @override
  String get someOldPicturesWereLeftOut =>
      'Some old pictures were left out to keep the copy small.';

  @override
  String get someone => 'Someone';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get somethingWentWrongPleaseTryAgain =>
      'Something went wrong. Please try again.';

  @override
  String get somethingWentWrongTryAgain => 'Something went wrong. Try again.';

  @override
  String get speakerOff => 'Speaker off';

  @override
  String get speakerOn => 'Speaker on';

  @override
  String get start => 'Start';

  @override
  String get startAgain => 'Start again';

  @override
  String get startAgainOnThisPhone => 'Start again on this phone';

  @override
  String get startOver => 'Start over';

  @override
  String get startRecoveryFromTheLinkupWelcome =>
      'Start recovery from the LinkUp welcome screen to create a new request.';

  @override
  String get startTheConversation => 'Start the conversation';

  @override
  String get startTheGroupConversation => 'Start the group conversation';

  @override
  String started(Object? num, Object? windowLabel) {
    return '$num started $windowLabel';
  }

  @override
  String get startedByItselfYouCanKeep =>
      'Started by itself. You can keep using LinkUp.';

  @override
  String get starting => 'Starting';

  @override
  String get starting2 => 'Starting…';

  @override
  String get startingCamera => 'Starting camera…';

  @override
  String get startingRestore => 'Starting restore…';

  @override
  String get status => 'Status';

  @override
  String get statusUnknownStale => 'Status unknown / stale';

  @override
  String get stayReachableEvenWhenTheApp =>
      'Stay reachable even when the app is closed';

  @override
  String staysYourFriendANewMessage(Object? name) {
    return '$name stays your friend. A new message from them starts a new chat.';
  }

  @override
  String get stillHas => 'still has';

  @override
  String stillHasCopyPhotosYouSaved(Object? peerName, Object? their) {
    return '$peerName still has $their copy. Photos you saved to your Gallery stay.';
  }

  @override
  String get stillHave => 'still have';

  @override
  String get stillHelpsTheMesh => 'Still helps the mesh';

  @override
  String get stillReceivingOverWiFiIt =>
      'Still receiving over Wi-Fi. It will appear by itself.';

  @override
  String get stop => 'Stop';

  @override
  String stopAfterDay(Object? days, Object? s) {
    return 'Stop after $days day$s';
  }

  @override
  String stopInDay(Object? v, Object? days, Object? s) {
    return '$v · stop in $days day$s';
  }

  @override
  String get stopNow => 'Stop now';

  @override
  String get stopSharing => 'Stop sharing';

  @override
  String stopVersionsBelow(Object? v) {
    return 'Stop versions below $v?';
  }

  @override
  String get stopped => 'Stopped';

  @override
  String get stoppedByAdmin => 'Stopped by admin';

  @override
  String get stoppedByAdminUpdateToSend =>
      'Stopped by admin. Update to send and call.';

  @override
  String get stoppedByYourPhone => 'Stopped by your phone';

  @override
  String get storage => 'Storage';

  @override
  String get storageUsed => 'Storage used';

  @override
  String get strong => 'Strong';

  @override
  String get subsystemStateReportedByTheServer =>
      'Subsystem state reported by the server';

  @override
  String get sun => 'Sun';

  @override
  String get suspended => 'Suspended';

  @override
  String get swipeUpToAnswer => 'Swipe up to answer';

  @override
  String get switchAccount => 'Switch account';

  @override
  String get switchToDarkTheme => 'Switch to dark theme';

  @override
  String get switchToLightTheme => 'Switch to light theme';

  @override
  String get switchToVideoCall => 'Switch to video call?';

  @override
  String get system => 'System';

  @override
  String get systemDefault => 'System default';

  @override
  String get systemHealth => 'System health';

  @override
  String get t1AppInfoBatteryChooseUnrestricted =>
      '1. App info > Battery: choose Unrestricted';

  @override
  String get t1Day => '1 day';

  @override
  String get t1Message => '1 message';

  @override
  String get t1Min => '1 min';

  @override
  String get t1OpenLinkupOnTheOther =>
      '1. Open LinkUp on the other phone\n2. Tap Scan QR code and point at this\n3. You are added instantly';

  @override
  String get t1OpenTheRecentsRecentApps =>
      '1. Open the Recents (recent apps) screen.\n2. Tap the LinkUp app icon at the top of its card.\n3. Choose “Lock”. A padlock stays on the card — the system won’t swipe the app away in “clear all”.';

  @override
  String get t1OtherLinkupPhone => '1 other LinkUp phone';

  @override
  String get t1Person => '1 person';

  @override
  String get t1Phone => '1 phone';

  @override
  String get t1RequestToJoin => '1 request to join';

  @override
  String get t1UnreadMessage => '1 unread message';

  @override
  String get t1Week => '1 week';

  @override
  String get t24Hours => '24 hours';

  @override
  String get t2PowerManagerPowerManagementFor =>
      '2. Power manager > Power management for apps > LinkUp: turn OFF screen-lock cleaning';

  @override
  String get t30Days => '30 days';

  @override
  String get t7Days => '7 days';

  @override
  String get t8Hours => '8 hours';

  @override
  String get takesASecond => 'Takes a second';

  @override
  String get tapAPersonToSeeMore => 'Tap a person to see more.';

  @override
  String get tapAddFriendNextToThe =>
      'Tap Add friend next to the phone you want to add.';

  @override
  String get tapAnOptionInTheChat =>
      'Tap an option in the chat to vote; tap it again to take your vote back. Works Nearby and Online.';

  @override
  String get tapJoinGroupWithQr => 'Tap Join group with QR';

  @override
  String get tapOpenSettings => 'Tap Open settings';

  @override
  String get tapPhotoToAddOne => 'Tap photo to add one';

  @override
  String get tapPhotoToChange => 'Tap photo to change';

  @override
  String get tapScanQrCode => 'Tap Scan QR code';

  @override
  String get tapTheCameraToChooseA => 'Tap the camera to choose a photo';

  @override
  String get tapTheOneYourFriendCan => 'Tap the one your friend can open:';

  @override
  String get tapToCallBack => 'Tap to call back';

  @override
  String get tapToCancel => 'Tap to cancel';

  @override
  String get tapToDownload => 'Tap to download';

  @override
  String get tapToEditNameAndPhoto => 'Tap to edit name and photo';

  @override
  String get tapToRemove => 'Tap to remove';

  @override
  String tapToReturn(Object? name, Object? answered) {
    return '$name · $answered — Tap to return';
  }

  @override
  String get tapYourPhotoInSettingsTo =>
      'Tap your photo in Settings to switch.';

  @override
  String get testCleanUpNow => 'Test clean-up now';

  @override
  String get testCleanUpNow2 => 'Test clean-up now?';

  @override
  String testCleanUpRemoved(Object? removed, Object? files) {
    return 'Test clean-up: $removed $files removed';
  }

  @override
  String get testers => 'Testers';

  @override
  String get thatActionIsNotAllowedOn =>
      'That action is not allowed on this account.';

  @override
  String get thatAlreadyExistsTryADifferent =>
      'That already exists. Try a different name.';

  @override
  String get thatCodeIsNotRight => 'That code is not right.';

  @override
  String get thatFileIsTooLargeTo => 'That file is too large to send.';

  @override
  String get thatPasswordIsNotRight => 'That password is not right.';

  @override
  String get thatTookTooLongPleaseTry =>
      'That took too long. Please try again.';

  @override
  String get thatUsernameAndPasswordDoNot =>
      'That username and password do not match.';

  @override
  String theAccountHistoryCouldNotBe(Object? error) {
    return 'The account history could not be restored ($error). You can retry now — the app will NOT pretend the account is empty.';
  }

  @override
  String get theAdminApprovedIt => 'The admin approved it';

  @override
  String get theAdminApprovesIt => 'The admin approves it';

  @override
  String theAdminDidNotApproveIt(Object? rejectedReason) {
    return 'The admin did not approve it.$rejectedReason';
  }

  @override
  String get theAdminGivesItToYou => 'The admin gives it to you in person';

  @override
  String get theAdminHasNotApprovedIt => 'The admin has not approved it yet.';

  @override
  String get theAdministratorApprovedThisDeviceRecovery =>
      'The administrator approved this device recovery request.';

  @override
  String get theAdministratorRejectedThisRecoveryRequest =>
      'The administrator rejected this recovery request.';

  @override
  String get theAdministratorRejectedThisRequest =>
      'The administrator rejected this request.';

  @override
  String get theChatAndAllItsMessages =>
      'The chat and all its messages, photos and files are ';

  @override
  String get theChatStaysInYourChats =>
      'The chat stays in your Chats list, empty.';

  @override
  String get theCodeIsWrongOrToo =>
      'The code is wrong or too old. Ask the admin for a new code.';

  @override
  String theCodesDonTMatchAsk(Object? v) {
    return 'The codes don\'t match. Ask $v to open this screen again.';
  }

  @override
  String theDeletedFromThisPhone(Object? files, Object? are, Object? bytes) {
    return 'The $files $are deleted from this phone ($bytes).';
  }

  @override
  String get theGroup => 'the group';

  @override
  String get theGroupPhotoCanBeSet => 'The group photo can be set when Online.';

  @override
  String get theLinkWasLostLookingFor =>
      'The link was lost. Looking for a way again.';

  @override
  String get theMessagesStayInTheChat =>
      'The messages stay in the chat with a small picture and \"Removed to save space\".';

  @override
  String get theOldCodeStopsWorking => 'The old code stops working';

  @override
  String get theOldLinkStopsWorking => 'The old link stops working';

  @override
  String get theOldLinkStopsWorkingPeople =>
      'The old link stops working. People who have it can\'t use it to join.';

  @override
  String theOtherItemsWereForwarded(Object? first) {
    return '$first The other items were forwarded.';
  }

  @override
  String get theOtherMembers => 'The other members ';

  @override
  String get thePhoneCarriesOthersLockedMessages =>
      'The phone carries others\' locked messages';

  @override
  String get thePhoneDecides => 'The phone decides';

  @override
  String get theQrBelongsToADifferent =>
      'The QR belongs to a different or unavailable LinkUp server.';

  @override
  String get theQrShowsHereByItself =>
      'The QR shows here by itself.\n(up to 10 seconds)';

  @override
  String get theRequestOrItsRecoveryCredential =>
      'The request or its recovery credential is no longer valid.';

  @override
  String get theRestIsOnTheWay => 'the rest is on the way';

  @override
  String get theServerDidNotReturnSubsystem =>
      'The server did not return subsystem readings for this request.';

  @override
  String get theServerDidNotTakeIt =>
      'The server did not take it (your recovery code was changed). Use Forgot password again when online.';

  @override
  String get theServerIsHavingTroublePlease =>
      'The server is having trouble. Please try again in a moment.';

  @override
  String get theServerIsUnreachableCheckThat =>
      'The server is unreachable. Check that it is running and that this phone is on the same network.';

  @override
  String get theServerNeedsAPairingCode => 'The server needs a pairing code';

  @override
  String get theServerReturnedAReplyThe =>
      'The server returned a reply the app could not understand.';

  @override
  String get theServerReturnedNoActivityBuckets =>
      'The server returned no activity buckets for the selected range.';

  @override
  String get theServerSignedThisPhoneOut =>
      'The server signed this phone out. Type your password to sign in again. Your chats stay on this phone.';

  @override
  String get theServerStoresOnlyAnEncrypted =>
      'The server stores only an encrypted backup envelope. The backup passphrase stays on your device.';

  @override
  String get theServerTookTooLongTo =>
      'The server took too long to respond. It will keep retrying automatically.';

  @override
  String get theTwoPasswordsAreNotThe => 'The two passwords are not the same.';

  @override
  String get theirCopyPhotosYouSavedTo =>
      ' their copy. Photos you saved to your Gallery stay.';

  @override
  String get theirPhoneIsNotKnownYet =>
      'Their phone is not known yet. Ask them to open LinkUp near you, then try again.';

  @override
  String get theirPhonesSendTheseMessagesAlso =>
      'Their phones send these messages (also ones they deleted). They see nothing.';

  @override
  String get thenTap => ', then tap ';

  @override
  String get theseFilesAreBiggerThan50 =>
      'These files are bigger than 50 MB and can\'t be forwarded.';

  @override
  String get theseFilesAreBiggerThan502 =>
      'These files are bigger than 50 MB, so they were not added.';

  @override
  String get theseTwoAccountsAreOnThe =>
      'These two accounts are on the same phone.';

  @override
  String get they => 'They';

  @override
  String get theyAreAddedWhenNearbyOr => 'They are added when Nearby or Online';

  @override
  String get theyCanNoLongerMessageOr =>
      'They can no longer message or pair with this phone — online or offline. This applies right away on this phone.';

  @override
  String get theyCanTMessageOrCall => 'They can\'t message or call you.';

  @override
  String get thisAccountHasAnEncryptedBackup =>
      'This account has an encrypted backup of its identity keys. Enter the backup passphrase to also restore message decryption keys, or skip it.';

  @override
  String get thisAccountHasNoRecoveryCode =>
      'This account has no recovery code on this phone yet.';

  @override
  String get thisAccountIsNotActiveAsk =>
      'This account is not active. Ask the admin.';

  @override
  String get thisAdminSessionEndsNow => 'This admin session ends now.';

  @override
  String get thisCopyOfLinkupCanT => 'This copy of LinkUp can\'t be shared';

  @override
  String get thisDevice => 'This device';

  @override
  String get thisFileIsBiggerThan50 =>
      'This file is bigger than 50 MB and can\'t be forwarded.';

  @override
  String get thisFileIsBiggerThan502 =>
      'This file is bigger than 50 MB, so it was not added.';

  @override
  String get thisFileIsNoLongerOn => 'This file is no longer on your phone';

  @override
  String get thisFileIsNoLongerOn2 => 'This file is no longer on your phone.';

  @override
  String get thisGroupCodeHasExpiredAsk =>
      'This group code has expired. Ask for a new one.';

  @override
  String get thisGroupIsFull100People => 'This group is full (100 people).';

  @override
  String get thisGroupWorksOnlyNearbyIt =>
      'This group works only Nearby (it is not on the server yet), so a link can\'t work. Use ';

  @override
  String get thisHappensByItself => 'This happens by itself.';

  @override
  String thisHappensWhenReinstallsLinkupOr(Object? v, Object? v2) {
    return 'This happens when $v reinstalls LinkUp or uses a new phone. Until you accept, the old code is kept. If you are not sure, ask $v2 first.';
  }

  @override
  String get thisInviteLinkDoesnTWork =>
      'This invite link doesn\'t work any more.';

  @override
  String get thisInviteLinkDoesnTWork2 =>
      'This invite link doesn\'t work any more. Ask for a new one.';

  @override
  String get thisIsNotALinkupGroup => 'This is not a LinkUp group code.';

  @override
  String get thisIsYou => 'This is you';

  @override
  String get thisLinkupVersionIsStoppedBy =>
      'This LinkUp version is stopped by admin';

  @override
  String get thisMessageCannotBeResent => 'This message cannot be resent';

  @override
  String get thisNearbyPhoneCannotBeConnected =>
      'This nearby phone cannot be connected right now.';

  @override
  String get thisNeedsTheServerTryAgain =>
      'This needs the server. Try again when the server is back.';

  @override
  String get thisOne => 'This one';

  @override
  String get thisPageChecksTheLocalServer =>
      'This page checks the local server every few seconds.';

  @override
  String get thisPageIsLockedItOpens =>
      'This page is locked. It opens again by itself when the server is back.';

  @override
  String get thisPerson => 'This person';

  @override
  String get thisPersonCouldNotBeFound =>
      'This person could not be found now. Try again near them or scan their QR code.';

  @override
  String get thisPersonIsNotCurrentlyAvailable =>
      'This person is not currently available.';

  @override
  String get thisPhone => 'This phone';

  @override
  String get thisPhone2 => 'this phone';

  @override
  String get thisPhoneAlreadyHasAnAccount =>
      'This phone already has an account';

  @override
  String get thisPhoneBlocksHotspotsMadeBy =>
      'This phone blocks hotspots made by apps.';

  @override
  String get thisPhoneCanSignInOffline =>
      'This phone can sign in offline only with the last account used on it.';

  @override
  String get thisPhoneCannotReachThatPhone =>
      'This phone cannot reach that phone directly.';

  @override
  String get thisPhoneDoesnTAllowIt => 'This phone doesn\'t allow it';

  @override
  String get thisPhoneHasNoCopyOf =>
      'This phone has no copy of your password. Log in again on this phone, then try.';

  @override
  String get thisPhoneHasNoSavedSign =>
      'This phone has no saved sign-in yet. Turn the server on and sign in once.';

  @override
  String thisPhoneIsAlreadyLinkedTo(Object? who) {
    return 'This phone is already linked to $who on the server. Ask the admin to remove this phone on the web (Devices), then tap Try again.';
  }

  @override
  String get thisPhoneIsNotPairedWith =>
      'This phone is not paired with the server yet. Ask the admin for the pairing code.';

  @override
  String thisPhoneJoinedYourAccount(Object? name, Object? tail) {
    return 'This phone joined your account @$name. $tail';
  }

  @override
  String thisPhoneLinkupBuild(Object? kAppVersion, Object? kAppBuild) {
    return 'This phone: LinkUp $kAppVersion (build $kAppBuild)';
  }

  @override
  String thisPhoneLinkupBuild2(
      Object? kAppVersion, Object? kAppBuild, Object? sent) {
    return 'This phone: LinkUp $kAppVersion (build $kAppBuild)$sent';
  }

  @override
  String get thisPhoneNearbyNetwork => 'This phone — nearby network';

  @override
  String get thisPhoneReportsOneBuildLower =>
      'This phone reports one build lower';

  @override
  String thisPhoneStillHasAskThe(Object? username) {
    return 'This phone still has @$username. Ask the admin.';
  }

  @override
  String get thisPhoneWasRemovedByAdmin =>
      'This phone was removed by admin. Your chats are still here. Log in again when the server is on.';

  @override
  String get thisPhotoIsNoLongerOn => 'This photo is no longer on your phone.';

  @override
  String get thisPhotoIsTooBigTry => 'This photo is too big. Try another one.';

  @override
  String get thisQrContainsAOneTime =>
      'This QR contains a one-time transfer credential. Anyone who can scan it may transfer the account, so keep this screen private.';

  @override
  String get thisRecoveryRequestHasAlreadyBeen =>
      'This recovery request has already been completed.';

  @override
  String get thisRecoveryRequestHasExpiredStart =>
      'This recovery request has expired. Start a new request.';

  @override
  String get thisReturnsTheAppToIts =>
      'This returns the app to its setup state. Existing local data may be removed.';

  @override
  String get thisServerBuildDoesNotExpose =>
      'This server build does not expose the runtime sampler.';

  @override
  String get thisTransferQrHasExpiredGenerate =>
      'This transfer QR has expired. Generate a new QR on the old phone.';

  @override
  String get thisUserIdentityIsNotTrusted =>
      'This user identity is not trusted for local calling';

  @override
  String get thisUserIsBlocked => 'This user is blocked';

  @override
  String get thisUsesMoreBatterySomePhones =>
      'This uses more battery. Some phones cannot run it while on Wi-Fi. Only LinkUp phones with \"Link full groups\" on will join it.';

  @override
  String get thisVideoIsNoLongerOn => 'This video is no longer on your phone.';

  @override
  String get thisWeek => 'This week';

  @override
  String thisWeekWaiting(Object? file, Object? waiting) {
    return '$file this week · $waiting waiting';
  }

  @override
  String get thisWiFiBlocksPhonesFrom =>
      'This Wi-Fi blocks phones from seeing each other';

  @override
  String through(Object? other) {
    return 'through $other';
  }

  @override
  String through2(Object? link, Object? other) {
    return '$link, through $other';
  }

  @override
  String get thu => 'Thu';

  @override
  String get toStopSomeoneOnEveryPhone =>
      'To stop someone on every phone, use Blocked by admin.';

  @override
  String get toTheServer => 'to the server';

  @override
  String get today => 'Today';

  @override
  String today2(Object? t) {
    return 'today $t';
  }

  @override
  String get todayAtAGlance => 'Today at a glance';

  @override
  String get toggleFlash => 'Toggle flash';

  @override
  String get tooLateToDeleteForEveryone => 'Too late to delete for everyone';

  @override
  String get tooManyAttemptsPleaseWaitA =>
      'Too many attempts. Please wait a moment and try again.';

  @override
  String get tooManyTriesTryAgainIn => 'Too many tries. Try again in 1 minute.';

  @override
  String get topologyAndTransports => 'Topology and transports';

  @override
  String get totalUsers => 'Total users';

  @override
  String get trafficMetricsUnavailable => 'Traffic metrics unavailable';

  @override
  String get transferAccount => 'Transfer account';

  @override
  String get transferAccountToThisPhone => 'Transfer account to this phone';

  @override
  String get transferNeedsTheServer => 'Transfer needs the server';

  @override
  String get transferRequestDetected => 'Transfer request detected';

  @override
  String get transferring => 'Transferring';

  @override
  String transferring2(Object? text) {
    return 'Transferring $text';
  }

  @override
  String get transfersAndQuota => 'Transfers and quota';

  @override
  String get transport => 'Transport';

  @override
  String get transportStateReportedByConnectedDevices =>
      'Transport state reported by connected devices';

  @override
  String get trustCompliance => 'Trust & Compliance';

  @override
  String get tryADifferentWordOrPhrase => 'Try a different word or phrase.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get tryAgainInAMoment => 'Try again in a moment.';

  @override
  String get tryAnotherName => 'Try another name.';

  @override
  String get tryAnotherNameOrFilter => 'Try another name or filter.';

  @override
  String get tryAnotherNameOrUsername => 'Try another name or username.';

  @override
  String get tryLinkupWiFiAgain => 'Try LinkUp Wi-Fi again';

  @override
  String get tryingAgain => 'Trying again…';

  @override
  String get tue => 'Tue';

  @override
  String get turnCameraOff => 'Turn camera off';

  @override
  String get turnCameraOn => 'Turn camera on';

  @override
  String get turnItOnToFindPhones => 'Turn it on to find phones near you';

  @override
  String get turnOn => 'Turn on';

  @override
  String get turnOnAutoLaunchSecondaryLaunch =>
      'Turn ON Auto-launch, Secondary launch and Run in background';

  @override
  String get turnOnExtraNearbySafety => 'Turn on extra nearby safety?';

  @override
  String get turnOnLocation => 'Turn on Location';

  @override
  String get turnOnWiFi => 'Turn on Wi-Fi';

  @override
  String get turnOnWiFiToReach => 'Turn on Wi-Fi to reach people nearby.';

  @override
  String get turnYourHotspotOffAndTry =>
      'Turn your hotspot off and try again, or let your friend join your hotspot.';

  @override
  String turnedOnTheirCameraAcceptTo(Object? name) {
    return '$name turned on their camera. Accept to switch this call to video.';
  }

  @override
  String get turningOnLinkupWiFi => 'Turning on LinkUp Wi-Fi…';

  @override
  String get typeANameOrAWord => 'Type a name or a word';

  @override
  String get typeANameToContinue => 'Type a name to continue';

  @override
  String get typeTheOneTimeCode => 'Type the one-time code';

  @override
  String get typeYourPassword => 'Type your password.';

  @override
  String get unavailable => 'Unavailable';

  @override
  String get unblock => 'Unblock';

  @override
  String unblock2(Object? name) {
    return 'Unblock $name';
  }

  @override
  String unblock3(Object? target) {
    return 'Unblock $target?';
  }

  @override
  String get unblockAndAddBack => 'Unblock and add back';

  @override
  String get unblockForEveryone => 'Unblock for everyone';

  @override
  String get unblockOnly => 'Unblock only';

  @override
  String unblocked(Object? label) {
    return '$label unblocked';
  }

  @override
  String unblocked2(Object? admin, Object? target) {
    return '$admin unblocked $target';
  }

  @override
  String unblockedAndAddedBack(Object? label) {
    return '$label unblocked and added back';
  }

  @override
  String unblockedOnThisPhone(Object? r) {
    return '$r unblocked on this phone.';
  }

  @override
  String get unknown => 'Unknown';

  @override
  String get unknownRole => 'Unknown role';

  @override
  String get unmute => 'Unmute';

  @override
  String get unmuteNotifications => 'Unmute notifications';

  @override
  String get unpin => 'Unpin';

  @override
  String unreadMessages(Object? count) {
    return '$count unread messages';
  }

  @override
  String get unsupported => 'Unsupported';

  @override
  String until(
      Object? day, Object? month, Object? hh, Object? mm, Object? ampm) {
    return 'Until $day $month, $hh:$mm $ampm';
  }

  @override
  String get unverified => 'Unverified';

  @override
  String get upTo32PeopleNearby100 => 'Up to 32 people Nearby, 100 Online';

  @override
  String get update => 'Update';

  @override
  String get updateLinkupSoon => 'Update LinkUp soon';

  @override
  String updateNeededInAfterThatThis(Object? d) {
    return 'Update needed in $d. After that this version can only read chats.';
  }

  @override
  String updated(Object? cryptoBackupUpdatedAt) {
    return 'Updated $cryptoBackupUpdatedAt';
  }

  @override
  String updated2(Object? generatedAt, Object? s) {
    return 'Updated $generatedAt$s';
  }

  @override
  String uploadSizePerPhoneTlsSet(Object? maxFile, Object? quota, Object? off) {
    return 'Upload size $maxFile · $quota per phone · TLS $off. Set on the server, can’t be changed here.';
  }

  @override
  String get use03xxXxxxxxxOr923xx => 'Use 03xx xxxxxxx or +92 3xx xxxxxxx';

  @override
  String get useAtLeast10CharactersThis =>
      'Use at least 10 characters. This passphrase is never sent to the server.';

  @override
  String get useBlockedOnThisPhoneIt =>
      'Use \"Blocked on this phone\". It does not reach other phones.';

  @override
  String get useItInLinkupLoginForgot =>
      'Use it in LinkUp: Login > Forgot password';

  @override
  String get useItOnForgotPasswordIf =>
      'Use it on Forgot password if this phone is lost. Works offline.';

  @override
  String get useNewRequestToAskThe =>
      'Use New request to ask the phones of 2 people or a group.';

  @override
  String get useOldPassword => 'Use old password';

  @override
  String get useRecoveryCode => 'Use recovery code';

  @override
  String useTheUsername(Object? username) {
    return 'Use the username @$username.';
  }

  @override
  String used(Object? used) {
    return '$used used';
  }

  @override
  String get usedByAnotherAccountSavedOn =>
      'Used by another account. Saved on this phone only.';

  @override
  String usedLinkupOnThisPhone(Object? username) {
    return '@$username · used LinkUp on this phone';
  }

  @override
  String get username => 'Username';

  @override
  String get usernameMustBe332Characters =>
      'Username must be 3–32 characters and use letters, numbers, dot, dash, or underscore.';

  @override
  String get usernameOrRecoveryCodeIsWrong =>
      'Username or recovery code is wrong.';

  @override
  String get users => 'Users';

  @override
  String usersBlockedServer(
      Object? all, Object? blockedCount, Object? offline) {
    return '$all users · $blockedCount blocked · server $offline';
  }

  @override
  String get usesTheCodeSavedOnThis =>
      'Uses the code saved on this phone. The new password goes to the server when it is back.';

  @override
  String get usingNearbyGroupsInstead => 'Using nearby groups instead.';

  @override
  String get verboseLogsForSupportCapturesTurns =>
      'Verbose logs for support captures. Turns off when the app restarts.';

  @override
  String get verified => 'Verified';

  @override
  String version(Object? currentVersion) {
    return 'Version $currentVersion';
  }

  @override
  String version2(Object? keyVersion, Object? retired) {
    return 'Version $keyVersion$retired';
  }

  @override
  String get versionNewer => 'Version newer';

  @override
  String get veryOldAppsBefore30 =>
      'Very old apps (before 3.0.54) are stopped too.';

  @override
  String via(Object? nextHop, Object? state) {
    return 'via $nextHop$state';
  }

  @override
  String get viaMesh => 'via mesh';

  @override
  String get viaServer => 'via server';

  @override
  String get viaWiFi => 'via Wi-Fi';

  @override
  String get viaWiFiDirect => 'via Wi-Fi Direct';

  @override
  String get video => 'Video';

  @override
  String videoDbgRx(Object? cfg, Object? videoRxFrames, Object? drops) {
    return 'video dbg · $cfg · rx:$videoRxFrames · $drops';
  }

  @override
  String get videoReceived => 'Video received';

  @override
  String get videos => 'Videos';

  @override
  String videosReceived(Object? n) {
    return '$n videos received';
  }

  @override
  String get viewAsUser => 'View as User';

  @override
  String get viewAuditLog => 'View Audit Log';

  @override
  String get viewNetwork => 'View network';

  @override
  String get viewProfile => 'View profile';

  @override
  String get viewSecurityCenter => 'View Security Center';

  @override
  String get viewVotes => 'View votes';

  @override
  String get voice => 'Voice';

  @override
  String voice2(Object? started_at) {
    return 'Voice · $started_at';
  }

  @override
  String voice3(Object? secs, Object? started_at) {
    return 'Voice · $secs · $started_at';
  }

  @override
  String get voiceCall => 'Voice call';

  @override
  String get voiceCalls => 'Voice calls';

  @override
  String get voiceFramesPassedOn => 'Voice frames passed on';

  @override
  String get voiceMessage => 'voice message';

  @override
  String get voiceMessage2 => 'Voice message';

  @override
  String get voiceMessageReceived => 'Voice message received';

  @override
  String voiceMessagesReceived(Object? n) {
    return '$n voice messages received';
  }

  @override
  String get voiceNote => 'Voice note';

  @override
  String get votes => 'Votes';

  @override
  String get votesCanTBeChangedAfter =>
      'Votes can\'t be changed after 3 minutes';

  @override
  String get waiting => 'Waiting';

  @override
  String waiting2(Object? waiting) {
    return '$waiting waiting';
  }

  @override
  String get waitingCarriedByThisPhone => 'Waiting · carried by this phone';

  @override
  String waitingFor(Object? name) {
    return 'Waiting for $name';
  }

  @override
  String get waitingForARoute => 'Waiting for a route';

  @override
  String get waitingForAdministratorApproval =>
      'Waiting for administrator approval…';

  @override
  String get waitingForApproval => 'Waiting for approval';

  @override
  String get waitingForSender => 'Waiting for sender';

  @override
  String get waitingForTheAdmin => 'Waiting for the admin';

  @override
  String get waitingForThePhone => 'Waiting for the phone';

  @override
  String get waitingForTheServer => 'Waiting for the server';

  @override
  String get waitingForTheServerToBe => 'Waiting for the server to be updated.';

  @override
  String get waitingForThisMessage => '🔒 Waiting for this message';

  @override
  String get waitingForThisPhone => 'Waiting for this phone…';

  @override
  String waitingForToConnect(Object? shown) {
    return 'Waiting for $shown to connect…';
  }

  @override
  String waitingGetsItWhenTheyAre(Object? peerName) {
    return 'Waiting. $peerName gets it when they are Nearby or Online.';
  }

  @override
  String get waitingNotNearOrOnlineYet => 'Waiting · not near or online yet';

  @override
  String get waitingSendsWhenYourFriendIs =>
      'Waiting. Sends when your friend is online';

  @override
  String get waitingToJoinTheServer => 'Waiting to join the server';

  @override
  String wantsToAddYou(Object? username, Object? now) {
    return '${username}wants to add you · $now';
  }

  @override
  String get warnOnly => 'Warn only';

  @override
  String warnOnly2(Object? v) {
    return '$v · warn only';
  }

  @override
  String warnVersionsBelow(Object? v) {
    return 'Warn versions below $v?';
  }

  @override
  String get warning => 'Warning';

  @override
  String get warningFirstThenReadOnly => 'Warning first, then read only';

  @override
  String get warningsLikeWrongPasswords => 'Warnings like wrong passwords';

  @override
  String wasStoppedNoRight(Object? admin) {
    return '$admin was stopped (no right)';
  }

  @override
  String wasTakenSoYouAre(Object? was, Object? name, Object? tail) {
    return '@$was was taken, so you are @$name. $tail';
  }

  @override
  String get weak => 'Weak';

  @override
  String get webPanel => 'web panel';

  @override
  String get wed => 'Wed';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get whatAdminsCanNeverSee => 'What admins can never see';

  @override
  String get whatAdminsDid => 'What admins did';

  @override
  String get whatAdminsDoShowsHere => 'What admins do shows here.';

  @override
  String get whatIsRestored => 'What is restored?';

  @override
  String get whatYourFriendNeeds => 'What your friend needs';

  @override
  String get whatsappSmsEmail => 'WhatsApp, SMS, email…';

  @override
  String get whenSomeoneMovesToANew =>
      'When someone moves to a new phone and asks for help, it shows here.';

  @override
  String get whenThePhoneIsMoreThan =>
      'When the phone is more than 70% full, remove photos, videos and documents not opened for 10 days. Voice notes stay.';

  @override
  String get whenThisIsOffLinkupCan =>
      'When this is off, LinkUp can use the available local Wi-Fi, Wi-Fi Direct and mesh paths automatically.';

  @override
  String get whoCalledWhom => 'Who called whom';

  @override
  String get whoIsLinkedToWhomLive => 'Who is linked to whom, live';

  @override
  String get whoIsSignedInOnWhich => 'Who is signed in, on which phone';

  @override
  String get wholeMap => 'Whole map';

  @override
  String get wiFiCall => 'Wi-Fi call';

  @override
  String get wiFiDirect => 'Wi-Fi Direct';

  @override
  String get wiFiDirectCall => 'Wi-Fi Direct call';

  @override
  String get wiFiDirectLinks => 'Wi-Fi Direct links';

  @override
  String get wiFiDirectOff => 'Wi-Fi Direct off';

  @override
  String get wiFiDirectOn => 'Wi-Fi Direct on';

  @override
  String get wiFiDirectOnly => 'Wi-Fi Direct only';

  @override
  String get wiFiDirectPeers => 'Wi-Fi Direct peers';

  @override
  String get wiFiIsOff => 'Wi-Fi is off';

  @override
  String get wiFiIsOffOrAndroid => 'Wi-Fi is off or Android said no.';

  @override
  String get wiFiLinks => 'Wi-Fi links';

  @override
  String get wiFiName => 'Wi-Fi name';

  @override
  String get wiFiNameCopied => 'Wi-Fi name copied';

  @override
  String get wiFiOff => 'Wi-Fi off';

  @override
  String get wiFiOffUsingWiFi => 'Wi-Fi off - using Wi-Fi Direct';

  @override
  String get wiFiRadioPolicy => 'Wi-Fi radio policy';

  @override
  String get wiFiRule => 'Wi-Fi rule';

  @override
  String wiFiRule2(Object? detail) {
    return 'Wi-Fi rule: $detail';
  }

  @override
  String wiFiRuleFor(Object? name) {
    return 'Wi-Fi rule for $name';
  }

  @override
  String get wiFiRuleOpenAPerson =>
      'Wi-Fi rule: open a person in Users or a phone in Devices.';

  @override
  String get wiFiStaysOff => 'Wi-Fi stays off';

  @override
  String get wiFiStaysOn => 'Wi-Fi stays on';

  @override
  String get wiFiStopped => 'Wi-Fi stopped';

  @override
  String willBeSignedOutAndBlocked(Object? device) {
    return '“$device” will be signed out and blocked from this account. You can add it again later through the normal login flow.';
  }

  @override
  String willSeeRemovedYouTheyKeep(Object? name, Object? me) {
    return '$name will see \"$me removed you\". They keep the old messages but get no new ones.';
  }

  @override
  String withText(Object? other) {
    return 'with $other';
  }

  @override
  String get withoutTheServerThisWorksOnly =>
      'Without the server this works only for the last account on this phone.';

  @override
  String get workingNow => 'Working now';

  @override
  String get worksWithoutTheServerToo => 'Works without the server too.';

  @override
  String wrongPassword(Object? g, Object? s) {
    return '$g wrong password$s';
  }

  @override
  String get wrongPasswordTries => 'Wrong password tries';

  @override
  String get wrongPasswordTryAgain => 'Wrong password. Try again.';

  @override
  String get wrongPasswordYourCodeStaysHidden =>
      'Wrong password. Your code stays hidden.';

  @override
  String get wrongPasswordsAndOtherWarningsShow =>
      'Wrong passwords and other warnings show here.';

  @override
  String get yellowBannerKeepsWorking => 'Yellow banner, keeps working';

  @override
  String get yes => 'Yes';

  @override
  String get yesterday => 'Yesterday';

  @override
  String yesterday2(Object? t) {
    return 'Yesterday $t';
  }

  @override
  String get you => 'You: ';

  @override
  String you2(Object? text) {
    return 'You: $text';
  }

  @override
  String get you3 => 'You';

  @override
  String youAdded(Object? targets) {
    return 'You added $targets';
  }

  @override
  String get youAlreadyHaveThisChatTheir =>
      'You already have this chat. Their phone adds the messages they deleted.';

  @override
  String get youAreNoLongerAnAdmin => 'You are no longer an admin';

  @override
  String get youAreNowAnAdmin => 'You are now an admin 👑';

  @override
  String get youAreNowTheGroupOwner => 'You are now the group owner';

  @override
  String get youAreOnTheSameWi =>
      'You are on the same Wi-Fi router. Messages and calls go straight between your phones.';

  @override
  String youAreOnTheServerNow(Object? name, Object? tail) {
    return 'You are @$name on the server now. $tail';
  }

  @override
  String get youAreTheOwner => 'You are the owner: ';

  @override
  String youBlocked(Object? device) {
    return 'You blocked $device';
  }

  @override
  String youBlocked2(Object? device, Object? at) {
    return 'You blocked $device · $at';
  }

  @override
  String youBlocked3(Object? device) {
    return 'You blocked $device.';
  }

  @override
  String youBlockedOnTheyCanT(Object? name, Object? when) {
    return 'You blocked $name on $when. They can\'t message or call you.';
  }

  @override
  String youBlockedTheyCanTMessage(Object? name) {
    return 'You blocked $name. They can\'t message or call you.';
  }

  @override
  String get youBlockedThisPersonUnblockThem =>
      'You blocked this person. Unblock them first.';

  @override
  String get youCanAddThemAgainLater => 'You can add them again later.';

  @override
  String youCanAddUpToPeople(Object? kNewGroupMax) {
    return 'You can add up to $kNewGroupMax people';
  }

  @override
  String youCanChangeYourVoteFor(Object? left) {
    return 'You can change your vote for $left';
  }

  @override
  String get youCanMessageAndCallAfter =>
      'You can message and call after they update.';

  @override
  String get youCanOnlyAddYourFriends => 'You can only add your friends.';

  @override
  String get youCanOnlyLook => 'You can only look.';

  @override
  String get youCanReadChatsButCan => 'You can read chats but can\'t send.';

  @override
  String get youCanReadOldChatsBut =>
      'You can read old chats but can\'t send or call.';

  @override
  String youCanReadOldChatsUpdate(Object? newer) {
    return 'You can read old chats. Update to send and call$newer.';
  }

  @override
  String get youCanSendMessagesAndCall =>
      'You can send messages and call again.';

  @override
  String get youCanTAddYourself => 'You can\'t add yourself.';

  @override
  String get youCanTJoinThisGroup => 'You can\'t join this group.';

  @override
  String youCanTMessage(Object? device) {
    return 'You can\'t message $device.';
  }

  @override
  String youCanTMessageOrCall(Object? name) {
    return 'You can\'t message or call $name.';
  }

  @override
  String get youCanUnblockThemAnyTime => 'You can unblock them any time.';

  @override
  String get youCanWriteNowTheyGet =>
      'You can write now. They get your messages right after they join.';

  @override
  String youCreatedGroup(Object? name) {
    return 'You created group \"$name\"';
  }

  @override
  String get youCreatedThisGroup => 'You created this group';

  @override
  String get youHaveNotSavedItYet =>
      'You have not saved it yet. Keep it safe in case this phone is lost.';

  @override
  String get youHavenTBlockedAnyone => 'You haven\'t blocked anyone.';

  @override
  String get youJoinedUsingThisGroupS =>
      'You joined using this group\'s invite link';

  @override
  String get youLeft => 'You left';

  @override
  String youReAgain(Object? username) {
    return 'You\'re @$username again';
  }

  @override
  String get youReAlreadyInThisGroup => 'You\'re already in this group.';

  @override
  String get youReNoLongerAParticipant =>
      'You\'re no longer a participant in this group.';

  @override
  String get youReOnTheServerNow => 'You\'re on the server now';

  @override
  String get youReSignedIn => 'You\'re signed in';

  @override
  String get youStillGetMessagesAMention =>
      'You still get messages. A mention of you (@) still notifies you.';

  @override
  String get youVeAddedEveryone => 'You\'ve added everyone';

  @override
  String get yourAccountExistsOnlyOnThis =>
      'Your account exists ONLY on this phone and has never reached the server. Resetting deletes it permanently — chats, and its recovery code, will be unrecoverable.';

  @override
  String get yourAccountIsActiveAgain => 'Your account is active again';

  @override
  String get yourAccountIsBlockedByAdmin => 'Your account is blocked by admin';

  @override
  String get yourAccountIsBlockedByAdmin2 =>
      'Your account is blocked by admin. You can read old chats but can\'t send or call.';

  @override
  String yourAccountIsOnTheServer(Object? tail) {
    return 'Your account is on the server now. $tail';
  }

  @override
  String get yourAccountSSecretLock => 'Your account\'s secret lock';

  @override
  String yourAccountWasSentWithYou(Object? via) {
    return 'Your account was sent with $via. You join the server when a phone with internet passes it on.';
  }

  @override
  String get yourAccountYourChats => 'Your account, your chats';

  @override
  String yourAdminLevelIsNow(Object? role) {
    return 'Your admin level is now $role';
  }

  @override
  String get yourAndroidNeedsLocationAllThe =>
      'Your Android needs Location \"All the time\" for this. LinkUp never saves where you are.';

  @override
  String get yourCameraPreviewTapToFlip =>
      'Your camera preview. Tap to flip camera, drag to move.';

  @override
  String get yourChatWithThemStays => 'Your chat with them **stays**.';

  @override
  String get yourChatsAndAccountStayOn =>
      'Your chats and account stay on this phone.';

  @override
  String get yourChatsAndAccountStayOn2 =>
      'Your chats and account stay on this phone. Log back in with your password or recovery code whenever you are ready.';

  @override
  String get yourChatsStayOnThisPhone => 'Your chats stay on this phone.';

  @override
  String yourChatsWithSFriendsGo(Object? shownName) {
    return 'Your chats with $shownName\'s friends go on. The new account on this phone is removed.';
  }

  @override
  String get yourContact => 'Your contact';

  @override
  String get yourContacts => 'Your contacts';

  @override
  String get yourConversationsAndContactsAreRestored =>
      'Your conversations and contacts are restored.';

  @override
  String get yourFriendWillJoinThisWi =>
      'Your friend will join this Wi-Fi to download the app. No internet used.';

  @override
  String get yourFriends => 'Your friends';

  @override
  String get yourLinkupIsOld => 'Your LinkUp is old';

  @override
  String yourMessagesHopThroughSThey(
      Object? phones, Object? who, Object? who2) {
    return 'Your messages hop through $phones ($who\'s). They stay locked; $who2 can\'t read them. Calls may be a bit slower.';
  }

  @override
  String yourMessagesHopThroughTheyStay(Object? phones) {
    return 'Your messages hop through $phones. They stay locked; nobody in between can read them. Calls may be a bit slower.';
  }

  @override
  String get yourNewPasswordIsOnlyOn =>
      'Your new password is only on this phone';

  @override
  String get yourNewPasswordWorksOnThis =>
      'Your new password works on this phone now. It goes to the server when the server is back, then you get a new recovery code.';

  @override
  String get yourOldCodeNoLongerWorks => 'Your old code no longer works.';

  @override
  String get yourOldCodeStopsWorking => 'Your old code stops working.';

  @override
  String get yourOldMessagesStayOnThis =>
      'Your old messages stay on this phone';

  @override
  String get yourOtherPhonesStaySignedIn =>
      'Your other phones stay signed in. You get a new recovery code after this.';

  @override
  String get yourPhone => 'YOUR PHONE';

  @override
  String yourPhone2(Object? title) {
    return 'Your phone: $title';
  }

  @override
  String get yourPhoneHotspotIsAlreadyOn =>
      'Your phone hotspot is already on, so LinkUp can\'t start its own Wi-Fi. Ask your friend to join your hotspot, then scan:';

  @override
  String get yourPhoneHotspotIsOn => 'Your phone hotspot is on';

  @override
  String get yourPhoneNumberStaysOnThis =>
      'Your phone number stays on this phone only.';

  @override
  String yourPhoneNumberWasNotSaved(Object? reason) {
    return 'Your phone number was not saved: $reason';
  }

  @override
  String get yourProfile => 'Your profile';

  @override
  String yourProfileChangeWasNotSaved(Object? reason) {
    return 'Your profile change was not saved: $reason';
  }

  @override
  String get yourProfileIsNotReadyYet => 'Your profile is not ready yet.';

  @override
  String get yourProfileIsPrivate => 'Your profile is private';

  @override
  String get yourProfileIsPublicAgain => 'Your profile is public again';

  @override
  String get yourRecentLinkupCallsWillAppear =>
      'Your recent LinkUp calls will appear here.';

  @override
  String get yourRecoveryCode => 'Your recovery code';

  @override
  String get yourRecoveryCodeChanged => 'Your recovery code changed';

  @override
  String yourSavedProfileIsShown(Object? error) {
    return 'Your saved profile is shown. $error';
  }

  @override
  String get yourSessionHasExpiredPleaseLog =>
      'Your session has expired. Please log in again.';

  @override
  String get yourUniqueUsername => 'Your unique username';

  @override
  String get yourVoteIsFinal => 'Your vote is final';

  @override
  String get yourWayBackInIfThis => 'Your way back in if this phone is lost';

  @override
  String get zoomIn => 'Zoom in';

  @override
  String get zoomOut => 'Zoom out';

  @override
  String get youObject304 => 'you';

  @override
  String get language304 => 'Language';

  @override
  String get phoneLanguage304 => 'Phone language';

  @override
  String get phoneLanguageHint304 =>
      'Urdu when the phone is set to Urdu, English otherwise';

  @override
  String get chooseLanguage304 =>
      'Choose the language of LinkUp on this phone.';

  @override
  String get no304 => 'No';

  @override
  String groupCountOf304(Object? v0, Object? v1, Object? v2) {
    return '$v0 · $v1 of $v2';
  }

  @override
  String mbOf304(Object? v0, Object? v1) {
    return '$v0 of $v1 MB';
  }

  @override
  String get wiFiOn304 => 'Wi-Fi on';

  @override
  String get yourFriend304 => 'Your friend';

  @override
  String reasonSuffix304(Object? v0) {
    return ' Reason: $v0';
  }

  @override
  String todayAt304(Object? v0) {
    return 'Today, $v0';
  }

  @override
  String yesterdayAt304(Object? v0) {
    return 'Yesterday, $v0';
  }

  @override
  String cantAddYetOnline304(Object? v0) {
    return '$v0 can\'t be added yet. They need to open LinkUp Online once.';
  }

  @override
  String cantAddYetNearby304(Object? v0) {
    return '$v0 can\'t be added yet. They need to be Online or Nearby with you once.';
  }

  @override
  String get madeOnAdminPhone304 =>
      'This request was made on the admin phone. The answer opens there.';

  @override
  String get waitingForPhoneOfChat304 =>
      'Waiting for a phone of this chat. There is no time limit.';

  @override
  String get adminsLower304 => 'admins';

  @override
  String get oneLower304 => 'one';

  @override
  String get possPhone304 => '\'s phone';

  @override
  String get someoneIs304 => 'someone is';

  @override
  String get heIs304 => 'he is';

  @override
  String byWho304(Object? v0) {
    return 'By $v0';
  }

  @override
  String get fileWord304 => 'file';

  @override
  String get filesWord304 => 'files';

  @override
  String get slow304 => 'slow';

  @override
  String get fast304 => 'fast';

  @override
  String get todayLower304 => 'today';

  @override
  String get yesterdayLower304 => 'yesterday';

  @override
  String isBlockedByAdminYouCanEn304(Object? v0, Object? v1) {
    return '$v0 is blocked by admin. You can\'t message or call $v1.';
  }

  @override
  String hasAnOldLinkupTheyNeedEn304(Object? v0) {
    return '$v0 has an old LinkUp. They need to update.';
  }

  @override
  String get replyPhotoEn304 => '📷 Photo';

  @override
  String get replyVideoEn304 => '🎥 Video';

  @override
  String get replyVoiceEn304 => '🎤 Voice message';

  @override
  String get replyDocumentEn304 => '📄 Document';

  @override
  String get serverAddressIsNotConfiguredEn304 =>
      'Server address is not configured.';

  @override
  String get noAccountMadeOfflineToSendEn304 =>
      'No account made offline to send.';

  @override
  String get selectedImageNoLongerExistsEn304 =>
      'Selected image no longer exists';

  @override
  String get serverReturnedNoRecoveryCodeEn304 =>
      'Server returned no recovery code';

  @override
  String get adminIsNotOnForThisEn304 => 'Admin is not on for this phone.';

  @override
  String get yourAdminRoleCanTDoEn304 => 'Your admin role can\'t do this.';

  @override
  String get youCanTDoThisOnEn304 => 'You can\'t do this on your own account.';

  @override
  String get connectToTheServerOnceToEn304 =>
      'Connect to the server once to turn on offline admin actions.';

  @override
  String get finishOrCancelSomeActionsFirstEn304 =>
      'Finish or cancel some actions first';

  @override
  String thisPhoneDoesnTKnowSEn304(Object? v0) {
    return 'This phone doesn\'t know $v0\'s phone yet. Connect to the server.';
  }

  @override
  String get thisActionIsTooBigToEn304 => 'This action is too big to send.';

  @override
  String get thisActionIsNotPendingEn304 => 'This action is not pending.';

  @override
  String get thisActionIsNotOnThisEn304 => 'This action is not on this phone.';

  @override
  String get theseTwoAccountsAreOnTheEn304 =>
      'These two accounts are on the same phone - there is no chat between them.';

  @override
  String get adminActionsAreNotReadyEn304 => 'Admin actions are not ready.';

  @override
  String get thisPhoneDoesnTKnowTheirEn304 =>
      'This phone doesn\'t know their phones yet.';

  @override
  String get openTheChatAgainFirstEn304 => 'Open the chat again first.';

  @override
  String get youCanTBlockYourOwnEn304 => 'You can\'t block your own account.';

  @override
  String get pickThisPhoneSVersionOrEn304 =>
      'Pick this phone\'s version or a lower one.';

  @override
  String get connectToTheServerOnceToEn3042 =>
      'Connect to the server once to turn on offline admin.';

  @override
  String get onlyTheOwnerAdminCanSetEn304 =>
      'Only the owner admin can set the minimum version.';

  @override
  String get noLinkupServerIsAvailableOnEn304 =>
      'No LinkUp server is available on the local network.';

  @override
  String get chooseAUsernameBetween3AndEn304 =>
      'Choose a username between 3 and 32 characters.';

  @override
  String get linkupServerCouldNotBeVerifiedEn304 =>
      'LinkUp server could not be verified.';

  @override
  String get linkupServerIdentityChangedEn304 =>
      'LinkUp server identity changed.';

  @override
  String get userNotFoundOrUnavailableEn304 => 'User not found or unavailable';

  @override
  String get contactHasNoActiveDeviceEn304 => 'Contact has no active device';

  @override
  String get pairAnswerWasNotSentCheckEn304 =>
      'Pair answer was not sent — check the connection and ask them to pair again.';

  @override
  String get thisRequestHasExpiredEn304 => 'This request has expired.';

  @override
  String get thisRequestCouldNotBeCheckedEn304 =>
      'This request could not be checked.';

  @override
  String get deviceIdentityIsNotReadyYetEn304 =>
      'Device identity is not ready yet';

  @override
  String get finishSettingUpYourProfileBeforeEn304 =>
      'Finish setting up your profile before pairing';

  @override
  String get identityKeysAreNotReadyOnEn304 =>
      'Identity keys are not ready on this phone — restart the app once and try again.';

  @override
  String get couldNotSignYourIdentityForEn304 =>
      'Could not sign your identity for pairing.';

  @override
  String get thisContactIsUnavailableOrBlockedEn304 =>
      'This contact is unavailable or blocked';

  @override
  String get selectedFileIsNoLongerAvailableEn304 =>
      'Selected file is no longer available';

  @override
  String get wiFiDirectTransportIsUnavailableEn304 =>
      'Wi-Fi Direct transport is unavailable';

  @override
  String downloadFailedEn304(Object? v0) {
    return 'Download failed ($v0)';
  }

  @override
  String get noLocalLanWiFiDirectEn304 =>
      'No local LAN, Wi-Fi Direct, or mesh route is available';

  @override
  String get messageBodyIsTooLargeEn304 => 'Message body is too large';

  @override
  String get groupNotFoundEn304 => 'Group not found';

  @override
  String get messageBodyMustBe16kbOrEn304 =>
      'Message body must be 16KB or less';

  @override
  String get messageOrAttachmentRequiredEn304 =>
      'Message or attachment required';

  @override
  String get voiceRecordingCouldNotStartEn304 =>
      'Voice recording could not start';

  @override
  String get voiceRecordingCouldNotBeSavedEn304 =>
      'Voice recording could not be saved';

  @override
  String get voiceNoteCouldNotBeSavedEn304 => 'Voice note could not be saved';

  @override
  String get backupPassphraseMustBeAtLeastEn304 =>
      'Backup passphrase must be at least 10 characters';

  @override
  String get noEncryptedIdentityBackupIsAvailableEn304 =>
      'No encrypted identity backup is available';

  @override
  String get encryptedBackupBelongsToADifferentEn304 =>
      'Encrypted backup belongs to a different account';

  @override
  String get thisDeviceIsNotLinkedToEn304 =>
      'This device is not linked to a LinkUp account';

  @override
  String get fileTransferCancelledEn304 => 'File transfer cancelled';

  @override
  String fileUploadFailedEn304(Object? v0) {
    return 'File upload failed ($v0)';
  }

  @override
  String get invalidAdminServerResponseEn304 =>
      'Invalid admin server response.';

  @override
  String adminRequestFailedEn304(Object? v0) {
    return 'Admin request failed ($v0).';
  }
}
