// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Martha, sit';

  @override
  String get tabHome => 'Home';

  @override
  String get tabRosters => 'Schedule';

  @override
  String get tabCalendar => 'Calendar';

  @override
  String get tabMe => 'Me';

  @override
  String get undo => 'Undo';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get done => 'Done';

  @override
  String get retry => 'Try again';

  @override
  String get search => 'Search';

  @override
  String get clear => 'Clear';

  @override
  String get selected => 'Selected';

  @override
  String get close => 'Close';

  @override
  String get add => 'Add';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get deleted => 'Deleted';

  @override
  String get loadFailed => 'Couldn’t load. Check your connection and try again.';

  @override
  String get saveFailed => 'Couldn’t save. Check your connection and try again.';

  @override
  String get noPermission => 'You don’t have permission to do this';

  @override
  String get comingSoon => 'Still working on this. Coming soon.';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get signInWithApple => 'Sign in with Apple';

  @override
  String get signInWithEmail => 'Sign in with email';

  @override
  String inAppBrowserNote(String app) {
    return 'Google sign-in doesn’t work inside $app. Open this page in Safari or Chrome, or sign in with email.';
  }

  @override
  String get copyPageUrl => 'Copy link';

  @override
  String get pageUrlCopied => 'Link copied. Paste it into Safari or Chrome to open.';

  @override
  String get loginTagline =>
      '“Martha, Martha,” the Lord answered,\n“you are worried and upset about many things,\nbut few things are needed—or indeed only one.\nMary has chosen what is better,\nand it will not be taken away from her.”';

  @override
  String get loginTaglineSource => 'Luke 10:41–42';

  @override
  String loginInvitedTo(String church) {
    return 'You’re invited to join $church';
  }

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get yourName => 'Your name';

  @override
  String get signIn => 'Sign in';

  @override
  String get register => 'Sign up';

  @override
  String get createAccount => 'Create account';

  @override
  String get haveAccount => 'Already have an account? Sign in';

  @override
  String get forgotPassword => 'Forgot password';

  @override
  String resetSent(String email) {
    return 'Password reset email sent to $email';
  }

  @override
  String get errInvalidCredential => 'Wrong email or password';

  @override
  String get errEmailInUse => 'This email is already registered. Sign in, or sign in with Google.';

  @override
  String get errWeakPassword => 'Password must be at least 6 characters';

  @override
  String get errInvalidEmail => 'Enter a valid email';

  @override
  String get errNeedsLink =>
      'This email already has an account. Sign in the way you did before, and the accounts will be linked automatically.';

  @override
  String get errTooMany => 'Too many attempts. Try again later.';

  @override
  String get errNetwork => 'Can’t connect. Check your connection and try again.';

  @override
  String get errUnknown => 'Something went wrong. Try again.';

  @override
  String get nameRequired => 'Enter your name';

  @override
  String get emailRequired => 'Enter your email';

  @override
  String get verifyEmailTitle => 'Verify your email';

  @override
  String verifyEmailBody(String email) {
    return 'A verification email was sent to $email. Tap the link in it, then come back here.';
  }

  @override
  String get verifyResend => 'Resend email';

  @override
  String get verifyResent => 'Sent again';

  @override
  String get verifyDone => 'I’ve verified';

  @override
  String get verifyStill => 'Not verified yet. Tap the link in the email.';

  @override
  String get welcomeTitle => 'Join your church';

  @override
  String get welcomeBody => 'Ask your church’s admin for an invite link';

  @override
  String get enterInviteCode => 'Enter invite code';

  @override
  String get createChurch => 'Create a church';

  @override
  String get signOut => 'Sign out';

  @override
  String get inviteCode => 'Invite code';

  @override
  String get next => 'Next';

  @override
  String get churchName => 'Church name';

  @override
  String get createChurchVerifyFirst => 'Verify your email to create a church';

  @override
  String get create => 'Create';

  @override
  String get errDuplicateName =>
      'A church with this name already exists. If someone else took it first, report the problem.';

  @override
  String get contactUs => 'Report a problem';

  @override
  String joinTitle(String church) {
    return 'Join $church';
  }

  @override
  String get join => 'Join';

  @override
  String joined(String church) {
    return 'Joined $church';
  }

  @override
  String alreadyMember(String church) {
    return 'You’re already a team member at $church';
  }

  @override
  String get errInviteInvalid => 'Couldn’t find this invite. Check the code, or ask an admin for a new invite.';

  @override
  String get errInviteExpired => 'This invite has expired. Ask an admin for a new one.';

  @override
  String get errChurchClosed => 'This church is no longer active';

  @override
  String churchSuspendedTitle(String church) {
    return '$church is suspended';
  }

  @override
  String get churchSuspendedBody => 'If you have questions, contact your church’s admin';

  @override
  String churchDeletedTitle(String church) {
    return '$church was deleted';
  }

  @override
  String churchDeletedBody(String date) {
    return 'An admin can restore it before $date';
  }

  @override
  String get churchDeletedExpired => 'It’s been more than 30 days, so it can’t be restored';

  @override
  String get churchUnavailable => 'Can’t open this church';

  @override
  String get restoreChurch => 'Restore church';

  @override
  String get churchRestored => 'Church restored';

  @override
  String get switchChurch => 'Switch church';

  @override
  String get myServicesTitle => 'When you’re serving';

  @override
  String get noUpcomingServices => 'You’re not scheduled to serve. When you are, it’ll show up here.';

  @override
  String get viewRosters => 'View schedule';

  @override
  String get gettingStarted => 'Get started';

  @override
  String get inviteMembers => 'Invite team members';

  @override
  String get gettingStartedInviteBody => 'Create an invite link and send it to your team';

  @override
  String get gettingStartedServices => 'Service settings';

  @override
  String get gettingStartedServicesBody => 'Which days, and which roles to schedule';

  @override
  String get nobodyYet => 'TBD';

  @override
  String get noServicesConfigured => 'No services set up yet';

  @override
  String get setUpServices => 'Set up services';

  @override
  String get noRostersAhead => 'No upcoming services';

  @override
  String get rostersNobodyArranged => 'No one is scheduled yet';

  @override
  String get rostersStartArranging => 'Start scheduling';

  @override
  String get today => 'Today';

  @override
  String get tomorrow => 'Tomorrow';

  @override
  String get offlineShowingCached => 'Offline. Showing what was last loaded.';

  @override
  String dutyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count roles',
      one: '1 role',
    );
    return '$_temp0';
  }

  @override
  String get addDuty => 'Add role';

  @override
  String get dutyName => 'Role name';

  @override
  String get removeDuty => 'Remove role';

  @override
  String dutyRemoved(String duty) {
    return 'Removed $duty';
  }

  @override
  String dutyUpdated(String duty) {
    return 'Updated $duty';
  }

  @override
  String get pickerServes => 'Serves in this role';

  @override
  String get pickerOthers => 'Other team members';

  @override
  String pickerUseName(String name) {
    return 'Use “$name”';
  }

  @override
  String pickerNoOneServes(String duty) {
    return 'No one serves as $duty yet';
  }

  @override
  String pickerNoResults(String query) {
    return 'No results for “$query”';
  }

  @override
  String get pickerSearchHint => 'Search team members';

  @override
  String pickerAddDutyTitle(String name, String duty) {
    return 'Add $duty to $name’s roles?';
  }

  @override
  String pickerAddDutyBody(String duty) {
    return 'They’ll show up at the top next time you schedule $duty';
  }

  @override
  String get pickerAddDutyYes => 'Add';

  @override
  String get pickerAddDutyNo => 'Just this time';

  @override
  String get reorder => 'Reorder';

  @override
  String get reorderHint => 'Drag to reorder. Every week will use this order.';

  @override
  String get orderSaved => 'Order updated';

  @override
  String get swap => 'Swap';

  @override
  String swapWith(String duty) {
    return 'Swap $duty with whom?';
  }

  @override
  String get swapNone => 'No one on other dates to swap with';

  @override
  String swapped(String a, String b) {
    return 'Swapped $a and $b';
  }

  @override
  String moved(String name, String day) {
    return 'Moved $name to $day';
  }

  @override
  String get emptySlot => 'TBD';

  @override
  String removeFromDuty(String duty) {
    return 'Remove from $duty';
  }

  @override
  String get events => 'Occasions';

  @override
  String get eventsUpdated => 'Occasions updated';

  @override
  String get customEvent => 'Custom occasion';

  @override
  String get addEvent => 'Add occasion';

  @override
  String get eventName => 'Occasion name';

  @override
  String get addToCommon => 'Add to common occasions';

  @override
  String get eventColor => 'Color';

  @override
  String get colorName0 => 'Red';

  @override
  String get colorName1 => 'Orange';

  @override
  String get colorName2 => 'Yellow';

  @override
  String get colorName3 => 'Green';

  @override
  String get colorName4 => 'Blue';

  @override
  String get colorName5 => 'Purple';

  @override
  String removed(String name) {
    return 'Removed $name';
  }

  @override
  String get profile => 'Profile';

  @override
  String get name => 'Name';

  @override
  String get nameSaved => 'Name updated';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Use system language';

  @override
  String get churchInfo => 'Church info';

  @override
  String get members => 'Team members';

  @override
  String get serviceSettings => 'Service settings';

  @override
  String get invites => 'Invites';

  @override
  String get notifications => 'Notifications';

  @override
  String get account => 'Account';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get termsOfService => 'Terms of service';

  @override
  String get developer => 'Developer';

  @override
  String get components => 'Components';

  @override
  String get testCrash => 'Test crash';

  @override
  String get operatorConsole => 'Platform console';

  @override
  String get leaveChurch => 'Leave church';

  @override
  String leaveChurchTitle(String church) {
    return 'Leave $church?';
  }

  @override
  String get leaveChurchBody => 'You’ll need a new invite to come back';

  @override
  String get leave => 'Leave church';

  @override
  String leftChurch(String church) {
    return 'Left $church';
  }

  @override
  String get adminCannotLeave =>
      'Admins can’t leave right away. To leave, make another team member an admin, then ask them to remove your admin role.';

  @override
  String get churchLogo => 'Church logo';

  @override
  String get uploadLogo => 'Upload logo';

  @override
  String get changeLogo => 'Change logo';

  @override
  String get logoUploaded => 'Logo updated';

  @override
  String get logoTooLarge => 'This image is too large. Choose one under 1 MB.';

  @override
  String get logoNotImage => 'Choose an image';

  @override
  String memberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count team members',
      one: '1 team member',
    );
    return '$_temp0';
  }

  @override
  String get membersOnlyYou => 'No one else has joined yet';

  @override
  String get deleteChurch => 'Delete church';

  @override
  String deleteChurchTitle(String church) {
    return 'Delete $church?';
  }

  @override
  String get deleteChurchBody =>
      'No team members will be able to see this church. You can restore it within 30 days; after that, its data is deleted permanently.';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleLeader => 'Small group leader';

  @override
  String get roleStaff => 'Regular team member';

  @override
  String get roleMember => 'Group member';

  @override
  String get role => 'Church role';

  @override
  String get roleAdminCan => 'All settings, inviting and removing team members';

  @override
  String get groups => 'Permission groups';

  @override
  String get groupRosterEditors => 'Edit schedules';

  @override
  String get groupCalendarEditors => 'Edit calendar';

  @override
  String get zones => 'Services and roles';

  @override
  String get zonesFooter => 'Team members who can edit schedules can only schedule the services they belong to';

  @override
  String get removeMember => 'Remove team member';

  @override
  String memberRemoved(String name) {
    return 'Removed $name';
  }

  @override
  String get memberSaved => 'Saved';

  @override
  String get searchMembers => 'Search team members';

  @override
  String get noMembersFound => 'No team member found';

  @override
  String get you => 'You';

  @override
  String get inviteCreate => 'Create invite link';

  @override
  String get inviteValidFor => 'Valid for';

  @override
  String inviteDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Valid for $days days',
      one: 'Valid for 1 day',
    );
    return '$_temp0';
  }

  @override
  String get inviteCopy => 'Copy link';

  @override
  String get inviteCopied => 'Invite link copied';

  @override
  String get copyByHand => 'Couldn’t copy automatically. Select the text below and copy it yourself.';

  @override
  String get inviteShare => 'Share';

  @override
  String get inviteRevoke => 'Revoke';

  @override
  String get inviteRevoked => 'Revoked';

  @override
  String inviteExpiresOn(String date) {
    return 'Expires $date';
  }

  @override
  String get inviteNone => 'No invite links yet';

  @override
  String inviteMessage(String church, String link) {
    return 'You’re invited to join the $church serving schedule: $link';
  }

  @override
  String get servicesTitle => 'Services';

  @override
  String get serviceAdd => 'Add service';

  @override
  String get serviceName => 'Service name';

  @override
  String get weekday => 'Day';

  @override
  String get serviceEnabled => 'Active';

  @override
  String get serviceDisabledFooter => 'Inactive services won’t get new schedules. Existing ones are kept.';

  @override
  String get templateDuties => 'Roles';

  @override
  String get templateFooter => 'New schedules will include these roles. Schedules already made aren’t affected.';

  @override
  String get commonEvents => 'Common occasions';

  @override
  String get rename => 'Rename';

  @override
  String get remove => 'Remove';

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get saved => 'Saved';

  @override
  String get weekday1 => 'Mon';

  @override
  String get weekday2 => 'Tue';

  @override
  String get weekday3 => 'Wed';

  @override
  String get weekday4 => 'Thu';

  @override
  String get weekday5 => 'Fri';

  @override
  String get weekday6 => 'Sat';

  @override
  String get weekday7 => 'Sun';

  @override
  String get deleteAccountTitle => 'Delete your account?';

  @override
  String get deleteAccountBody =>
      'You’ll leave every church, and your account and personal info will be deleted for good. Your name stays on schedules.';

  @override
  String deleteAccountLastAdmin(String churches) {
    return 'You’re the only admin of $churches. Make another team member an admin first.';
  }

  @override
  String get goToMembers => 'Go to Team members';

  @override
  String get accountDeleted => 'Account deleted';

  @override
  String get serviceDisabled => 'Inactive';

  @override
  String get adminSearchHint => 'Church name or ID';

  @override
  String get adminNoChurches => 'No churches found';

  @override
  String get adminStats => 'Stats';

  @override
  String get adminRename => 'Rename';

  @override
  String get adminMakeAdmin => 'Make admin';

  @override
  String adminMadeAdmin(String name) {
    return '$name is now an admin';
  }

  @override
  String get adminSuspend => 'Suspend church';

  @override
  String get adminReopen => 'Reopen church';

  @override
  String adminSuspendTitle(String church) {
    return 'Suspend $church?';
  }

  @override
  String get adminSuspendBody => 'All team members will see the suspended screen right away';

  @override
  String get statusActive => 'Active';

  @override
  String get statusSuspended => 'Suspended';

  @override
  String get statusDeleted => 'Deleted';

  @override
  String get statsUsers => 'Users';

  @override
  String get statsChurches => 'Churches';

  @override
  String get statsMembers => 'Members';

  @override
  String get statsRosters => 'Schedules';

  @override
  String get statsReads => 'Firestore reads';

  @override
  String get statsWrites => 'Firestore writes';

  @override
  String get statsCost => 'Estimated cost (USD)';

  @override
  String get statsNone => 'No stats yet';

  @override
  String get statsMoreInConsole => 'Usage and error details are in the Firebase console';

  @override
  String get notifReminder => 'Serving reminders';

  @override
  String get notifReminderWeeklySub => 'Monday evenings, a list of this week’s serving';

  @override
  String get notifReminderDayBeforeSub => 'The evening before you serve';

  @override
  String get notifReminderBothSub => 'Monday evenings and the evening before you serve';

  @override
  String get notifReminderTime => 'Reminder time';

  @override
  String get notifReminderWeekly => 'Monday evenings';

  @override
  String get notifReminderDayBefore => 'The evening before';

  @override
  String get notifReminderBoth => 'Both';

  @override
  String get notifReminderTimeFooter => 'All at 7 p.m.';

  @override
  String get notifRosterChange => 'Schedule changes';

  @override
  String get notifRosterChangeSub => 'When you’re added to or removed from serving';

  @override
  String get notifMemberLeft => 'Team member left';

  @override
  String get notifMemberLeftSub => 'When someone leaves the church (admins only)';

  @override
  String get notifThisChurch => 'Notifications for this church';

  @override
  String get notifPermissionOff => 'Notifications are off. Turn them on in Settings.';

  @override
  String get notifEnable => 'Turn on notifications';

  @override
  String get notifNotAllowed => 'Notifications aren’t on yet. When asked, tap “Allow.”';

  @override
  String get notifRegisterFailed => 'Notifications aren’t set up yet. The app will try again next time you open it.';

  @override
  String get pushView => 'View';

  @override
  String get zoneSwitch => 'Belongs to this service';

  @override
  String zoneLeft(String service) {
    return 'No longer in $service';
  }

  @override
  String get eventRosterGone => 'Can’t find this event’s schedule';

  @override
  String get eventRoster => 'Schedule';

  @override
  String eventRosterPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return '$_temp0';
  }

  @override
  String get arrangeEventRoster => 'Arrange serving';

  @override
  String get eventRosterEmpty => 'No roles yet';

  @override
  String get copyDuties => 'Copy from another event';

  @override
  String get copyDutiesHeader => 'Copy roles from which event?';

  @override
  String get copyDutiesNone => 'No other event schedules yet';

  @override
  String dutiesCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count roles',
      one: 'Added 1 role',
    );
    return '$_temp0';
  }

  @override
  String get noZoneYet => 'You’re not in any services yet. Ask an admin to add you.';

  @override
  String get waitsForZone => 'No services yet';

  @override
  String waitingForZone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count team members have no services yet',
      one: '1 team member has no services yet',
    );
    return '$_temp0';
  }

  @override
  String get inviteZones => 'Joins these services';

  @override
  String get photoImport => 'Import from photo';

  @override
  String photoRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos left this month',
      one: '1 photo left this month',
    );
    return '$_temp0';
  }

  @override
  String get photoTake => 'Take photo';

  @override
  String get photoPick => 'Choose photo';

  @override
  String get photoPasteJson => 'Paste JSON';

  @override
  String get photoRecognizing => 'Reading the photo. This takes about a minute.';

  @override
  String photoChurchLimit(int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: 'This month’s $limit photos are used up',
      one: 'This month’s 1 photo is used up',
    );
    return '$_temp0. More on the 1st of next month. Until then, you can fill in the schedule yourself.';
  }

  @override
  String get photoPlatformOff =>
      'Photo import is paused this month (the app-wide limit is used up) and resumes next month. Until then, you can fill in the schedule yourself.';

  @override
  String get photoTooLarge => 'Photo is too large. Crop it to just the table and try again.';

  @override
  String get photoFailed => 'Couldn’t read this photo. Try a clearer one.';

  @override
  String get photoUnavailable =>
      'Photo import isn’t available right now. Try again later, or fill in the schedule yourself.';

  @override
  String get importPreview => 'Preview';

  @override
  String get importApply => 'Apply to schedule';

  @override
  String importApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count days',
      one: 'Imported 1 day',
    );
    return '$_temp0';
  }

  @override
  String get importNothing => 'No upcoming dates found in the photo';

  @override
  String get importNotInList => 'Not on the team member list (added as written, not linked to an account)';

  @override
  String importNear(String names) {
    return 'Similar names on the list: $names';
  }

  @override
  String get importAmbiguous => 'Not sure who this is (not linked to an account)';

  @override
  String get importUnknownDuties => 'This service doesn’t have these roles';

  @override
  String get importPastDays => 'Past dates, not imported';

  @override
  String get importBadRows => 'Unreadable rows';

  @override
  String get jsonHint => 'Paste the JSON result';

  @override
  String get next2 => 'Preview';

  @override
  String get calNotConnected => 'Your church hasn’t connected a calendar yet';

  @override
  String get calConnect => 'Connect Google Calendar';

  @override
  String get calReconnect => 'Reconnect';

  @override
  String get calNeedsReconnect => 'Calendar access has expired';

  @override
  String get calNeedsReconnectStaff => 'Can’t load the calendar right now. Ask an admin to reconnect it.';

  @override
  String get calPickCalendar => 'Choose a calendar';

  @override
  String get calNoCalendarYet => 'No calendar chosen';

  @override
  String get calDisconnect => 'Disconnect';

  @override
  String get calDisconnectTitle => 'Disconnect the calendar?';

  @override
  String get calDisconnectBody => 'Team members won’t see the calendar. Your Google Calendar itself won’t change.';

  @override
  String get calUnverifiedNote =>
      'Next, Google will say “Google hasn’t verified this app.” Tap “Advanced,” then “Go to…” to continue. It only reads and writes the calendar you choose.';

  @override
  String get calConnectedOk => 'Google Calendar connected';

  @override
  String get calConnectFailed => 'Couldn’t connect. Try again.';

  @override
  String get calNoEvents => 'No events this month';

  @override
  String get calAllDay => 'All day';

  @override
  String get calNewEvent => 'New event';

  @override
  String get calEditEvent => 'Edit event';

  @override
  String get calTitle => 'Event name';

  @override
  String get calLocation => 'Location';

  @override
  String get calStart => 'Starts';

  @override
  String get calEnd => 'Ends';

  @override
  String get calOtherTime => 'Other time…';

  @override
  String calLengthMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String calLengthHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String calLengthHoursMinutes(int hours, int minutes) {
    return '$hours hr $minutes min';
  }

  @override
  String get calDelete => 'Delete event';

  @override
  String calDeleted(String title) {
    return 'Deleted $title';
  }

  @override
  String get calSaved => 'Event saved';

  @override
  String get calPrevMonth => 'Previous month';

  @override
  String get calNextMonth => 'Next month';

  @override
  String get calShowMonth => 'Show month';

  @override
  String get calHideMonth => 'List only';

  @override
  String get calendarSetting => 'Calendar';

  @override
  String get support => 'Support Martha, sit';

  @override
  String get supportVerse =>
      'At the present time your plenty will supply what they need, so that in turn their plenty will supply what you need. The goal is equality,';

  @override
  String get supportVerseSource => '2 Corinthians 8:14';

  @override
  String get supportBody => 'Support is optional, covers only server costs, and every church gets the same features';

  @override
  String get supportTips => 'One-time support';

  @override
  String get supportMonthly => 'Monthly support';

  @override
  String get supportRestore => 'Restore purchases';

  @override
  String supportMonthlyTerms(String store) {
    return 'Renews automatically every month. Cancel anytime in your $store subscriptions.';
  }

  @override
  String get manageSubscription => 'Manage subscription';

  @override
  String get supportThanks => 'Thank you for your support';

  @override
  String get supportPending => 'Processing payment';

  @override
  String get supportFailed => 'Payment didn’t go through. You weren’t charged.';

  @override
  String get supportUnavailable => 'Can’t reach the store right now. Try again later.';

  @override
  String get supporterBadge => 'Supporter';

  @override
  String get appIcon => 'App icon';

  @override
  String get appIconSupporterOnly => 'Monthly supporters can change the app icon';

  @override
  String get appIconDefault => 'Default';

  @override
  String get appIconGreen => 'Green';

  @override
  String get appIconPurple => 'Purple';

  @override
  String get appIconNight => 'Night';

  @override
  String get goHome => 'Go home';

  @override
  String get churchNotFound => 'Can’t find this church';

  @override
  String get churchEntryNotMember =>
      'You’re not a team member of this church yet. Ask an admin for an invite link to join.';

  @override
  String get churchUrl => 'Church URL';

  @override
  String get churchUrlCopied => 'Church URL copied';

  @override
  String get churchUrlCopy => 'Copy church URL';

  @override
  String get churchUrlShare => 'Share church URL';

  @override
  String get homeName => 'Home Screen name';

  @override
  String get homeNameUnset => 'Same as church name';

  @override
  String get homeNameMayBeCut => 'May be cut off on some phones';

  @override
  String get homeNameFooter =>
      'The name shown under the icon when added to the Home Screen. Leave blank to use the church name.';

  @override
  String get addToHome => 'Add to Home Screen';

  @override
  String get addToHomeIosNote =>
      'On iPhone, icons already added won’t update. After changing the name or logo, delete the icon and add it again.';

  @override
  String get addToHomeLater => 'Not now';

  @override
  String addToHomeDone(String name) {
    return 'Added. From now on, tap the “$name” icon on your phone to open it.';
  }

  @override
  String get addToHomeIntro => 'Next time, tap the icon on your Home Screen to open the schedule';

  @override
  String addToHomeBrowserGuide(String device, String browser) {
    return '$device · $browser guide';
  }

  @override
  String get addToHomeChooseBrowser => 'Looks different?';

  @override
  String get addToHomeChooseGuide => 'Choose a guide';

  @override
  String get addToHomeChooseGuideNote => 'This only switches the guide. It won’t open another browser.';

  @override
  String get addToHomeSafariLayoutTitle => 'Safari layout';

  @override
  String get addToHomeSafariLayoutHint =>
      'Pick based on the buttons in your toolbar. No need to change Safari settings.';

  @override
  String get addToHomeSafariMoreChoice => 'I see “⋯”';

  @override
  String get addToHomeSafariShareChoice => 'I see the Share icon';

  @override
  String get addToHomeSafariMoreShare => 'Tap “⋯,” then “Share”';

  @override
  String get addToHomeSafariDirectShareHint =>
      'The address bar can be at the top or bottom. Look for the square with an up arrow.';

  @override
  String get addToHomeInApp => 'In-app browser';

  @override
  String get addToHomeOtherBrowser => 'Other browser';

  @override
  String get addToHomeScreenshotNote => 'Tap the circled button in your browser';

  @override
  String get addToHomeSafariScreenshot => 'Safari · iOS 26.5 · Simulator, Traditional Chinese';

  @override
  String get addToHomeChromeAndroidScreenshot =>
      'Chrome 113 · Android 14 · Simulator, Traditional Chinese (older menu)';

  @override
  String get addToHomeChromeIosScreenshot => 'Chrome 155 · iOS 27.2 · iPhone 13';

  @override
  String get addToHomeAddressBar => 'Address bar';

  @override
  String get addToHomeChromeShare => 'Tap the Share icon next to the address bar';

  @override
  String get addToHomeChromeShareHint => 'Not the “⋯” menu, and not “Share Chrome”';

  @override
  String get addToHomeChromeScroll => 'Don’t see it? Expand the share sheet, then scroll down.';

  @override
  String get addToHomeSafariShare => 'Tap the Share icon in Safari';

  @override
  String get addToHomeFirefoxShare => 'Tap the Share icon in the address bar';

  @override
  String get addToHomeIpadMore => 'On iPad, if you don’t see this option, tap “More” in the share sheet first';

  @override
  String get addToHomeSelectAdd => 'Tap “Add to Home Screen”';

  @override
  String get addToHomeShareMore =>
      'If you only see a row of icons, tap “View More” first. On older versions, scroll down.';

  @override
  String get addToHomeIosConfirm =>
      'If there’s an “Open as Web App” switch, leave it on. Then tap “Add” in the top right.';

  @override
  String get addToHomeOpenTitle => 'Go to your Home Screen and tap the new icon';

  @override
  String addToHomeMenu(String browser) {
    return 'Tap the $browser menu';
  }

  @override
  String get addToHomeChromeInstall => 'Add to Home screen → Install';

  @override
  String get addToHomeChromeInstallHint => 'Older versions may say “Install app.” Choose Install, not Create shortcut.';

  @override
  String get addToHomeFirefoxInstallHint =>
      'Then follow your phone’s prompts. If you only see “Add to Home screen,” it may only create a browser shortcut.';

  @override
  String get addToHomeTrouble => 'Can’t find “Add to Home Screen”?';

  @override
  String get addToHomeSafariTrouble =>
      'Swipe the share sheet up to see more actions. Still can’t find it? Tap “Edit Actions” at the bottom.';

  @override
  String addToHomeExternalTitle(String browser) {
    return 'Open in $browser first';
  }

  @override
  String addToHomeExternalHint(String browser) {
    return 'Copy the church URL, paste it into the $browser address bar, then continue the guide';
  }

  @override
  String get addToHomeEmbeddedHint => 'You’re viewing this page inside an app. Switch to your phone’s browser first.';

  @override
  String get addToHomeUnknownHint => 'This browser’s menu may be different. Continue with the steps below.';

  @override
  String addToHomeCopiedForBrowser(String browser) {
    return 'Copied. Open $browser and paste it into the address bar.';
  }

  @override
  String get addToHomePhoneOnly => 'Open the church URL on your phone, then add it to your Home Screen';

  @override
  String get addToHomeNotificationsAfter =>
      'After opening it from your Home Screen, turn on notifications in Me to get serving notifications';

  @override
  String get addToHomeIosShare => 'Share';

  @override
  String get addToHomeIosAdd => 'Add';

  @override
  String addToHomeIosOpen(String name) {
    return 'Tap the “$name” icon on your phone to open it, then sign in again';
  }

  @override
  String get addToHomeAndroidAdd => 'Add to Home screen';

  @override
  String get addToHomeAndroidInstall => 'Install';

  @override
  String addToHomeAndroidOpen(String name) {
    return 'Tap the “$name” icon on your phone to open it';
  }

  @override
  String get addToHomeCardBody => 'Open it in one tap and get serving notifications';

  @override
  String get addToHomeCardHide => 'Don’t show again';

  @override
  String get notifNeedsHomeScreen => 'Add to your Home Screen first to get notifications';

  @override
  String get churchLink => 'Church link';

  @override
  String get churchLinkNone => 'Not set';

  @override
  String get churchLinkTitle => 'Title';

  @override
  String get churchLinkBody => 'Description (optional)';

  @override
  String get churchLinkUrl => 'Link';

  @override
  String get churchLinkNeedsTitle => 'Enter a title';

  @override
  String get churchLinkNeedsHttps => 'Enter a link that starts with https://';

  @override
  String get churchLinkFooter => 'Shown at the top of every team member’s home page. Opens in the browser.';

  @override
  String get churchLinkRemove => 'Remove church link';

  @override
  String get churchLinkRemoved => 'Church link removed';

  @override
  String get churchLinkOpens => 'Opens in browser';

  @override
  String get linkSource => 'Daily content source (optional)';

  @override
  String get linkSourceUrl => 'JSON URL';

  @override
  String get linkFetchTime => 'Daily update time';

  @override
  String get linkSourceFooter =>
      'Fetched once a day at this time. The JSON needs date (today in the church’s time zone), title, body, and link (https).';

  @override
  String linkSourceUpdated(String time) {
    return 'Last updated: $time';
  }

  @override
  String linkSourceFailed(String reason) {
    return 'Last fetch failed: $reason';
  }

  @override
  String linkSourceFetched(String title) {
    return 'Saved. Fetched “$title.”';
  }

  @override
  String get linkErrTimeout => 'The site didn’t respond within 5 seconds';

  @override
  String get linkErrTooLarge => 'Content is larger than 64 KB';

  @override
  String get linkErrBadFormat => 'Content isn’t complete JSON with date, title, body, and link';

  @override
  String get linkErrNotHttps => 'The URL or a redirect isn’t https';

  @override
  String linkErrHttp(String status) {
    return 'The site returned an error ($status)';
  }

  @override
  String get linkErrNetwork => 'Couldn’t reach the site';

  @override
  String get linkErrUnknown => 'Something went wrong. Try again.';

  @override
  String get webhook => 'Webhook';

  @override
  String get webhookUrl => 'Receiving URL';

  @override
  String get webhookNeedsHttps => 'Enter a URL that starts with https://';

  @override
  String get webhookSecretOptional => 'Secret (optional; leave blank to generate one)';

  @override
  String get webhookSecretTooShort => 'Secret must be at least 16 characters';

  @override
  String get webhookCalendar => 'Calendar changes';

  @override
  String get webhookCalendarHint => 'Events added, edited, or deleted';

  @override
  String get webhookRoster => 'Schedule changes';

  @override
  String get webhookRosterHint => 'Changes within a few minutes are sent together';

  @override
  String get webhookFooter =>
      'When the calendar or a schedule changes, a notification is sent to this URL, for example to n8n to forward to a LINE group. Every notification is signed with the secret.';

  @override
  String get webhookTest => 'Send test';

  @override
  String webhookLast(String time, String result) {
    return 'Last sent: $time · $result';
  }

  @override
  String get webhookOk => 'Succeeded';

  @override
  String webhookHttp(String status) {
    return 'Responded $status';
  }

  @override
  String get webhookTimeout => 'Timed out';

  @override
  String get webhookNetwork => 'Couldn’t connect';

  @override
  String get webhookRotate => 'Replace secret';

  @override
  String get webhookRotateMessage => 'The old secret stops working right away. The receiver needs to use the new one.';

  @override
  String get webhookGenerate => 'Generate';

  @override
  String get webhookTypeOwn => 'Enter my own';

  @override
  String get webhookSecretTitle => 'Secret';

  @override
  String get webhookSecretOnce =>
      'This is shown only once. Paste it into the receiver to verify that notifications come from Martha, sit.';

  @override
  String get webhookCopySecret => 'Copy secret';

  @override
  String get webhookSecretCopied => 'Secret copied';

  @override
  String get webhookSecretChanged => 'Secret replaced';

  @override
  String get webhookOff => 'Turn off webhook';

  @override
  String get webhookOffTitle => 'Turn off webhook?';

  @override
  String get webhookOffMessage => 'The URL and secret will be deleted. You’ll need to set it up again.';

  @override
  String get webhookOffAction => 'Turn off';

  @override
  String get exportData => 'Export data';

  @override
  String get exportFooter => 'Export all of the church’s data: a JSON file, plus a schedule you can open in Excel';

  @override
  String get exported => 'Exported';

  @override
  String get exportCsvFile => 'Schedules.csv';

  @override
  String get exportCsvDate => 'Date';

  @override
  String get exportCsvService => 'Service or event';

  @override
  String get exportCsvRole => 'Role';

  @override
  String get exportCsvPeople => 'Team members';

  @override
  String get errMoveInvalid => 'This isn’t a move file. Make sure you chose the right file.';

  @override
  String get errMoveTooLarge =>
      'More than 2,000 team members or 20,000 schedule days can’t be moved automatically. Open an issue for church-staff-pwa on GitHub.';

  @override
  String get moveFromSelfHost => 'Move from old version';

  @override
  String get moveIntro =>
      'Run the move command in the old version’s (church-staff-pwa) Cloud Shell, then upload the move file it makes. The church is created only after you confirm the preview.';

  @override
  String get movePickFile => 'Choose move file';

  @override
  String get moveReading => 'Reading move file…';

  @override
  String get moveContents => 'Move file contents';

  @override
  String get moveMembers => 'Team members';

  @override
  String moveMembersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return '$_temp0';
  }

  @override
  String get moveRosters => 'Schedules';

  @override
  String moveRostersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get moveServices => 'Services';

  @override
  String get moveWhoAmI => 'This is me (optional)';

  @override
  String get moveWhoAmIFooter =>
      'If you choose someone, you take over their schedules, services, and permissions. Other team members are asked whether to join when they sign in to Martha, sit with the same email.';

  @override
  String get moveCreate => 'Create church and move';

  @override
  String moveDone(String church) {
    return 'Created “$church”';
  }

  @override
  String get notSignedInYet => 'Not signed in yet';

  @override
  String pendingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people haven’t signed in yet',
      one: '1 person hasn’t signed in yet',
    );
    return '$_temp0';
  }

  @override
  String claimPrompt(String church) {
    return 'Team member info for “$church” has been moved here. Join?';
  }

  @override
  String get claimJoin => 'Join';

  @override
  String get claimDecline => 'Don’t join';

  @override
  String get movedPasswordNote =>
      'Moved from the old version? Your old password won’t work. Sign up for a new account with the same email, or sign in with Google.';

  @override
  String get pendingDelete => 'Delete this record';

  @override
  String pendingDeleteTitle(String name) {
    return 'Delete the record for “$name”?';
  }

  @override
  String get pendingDeleteBody => 'They won’t be able to claim it by email. Their name stays on schedules.';

  @override
  String get pendingDeleted => 'Deleted';

  @override
  String get mergePending => 'Merge a pending record';

  @override
  String get mergePendingFooter =>
      'When a team member joins with a different email, merge their pending record from the old list. Their schedules, services, and permission groups carry over.';

  @override
  String get mergePendingPick => 'Choose a pending record';

  @override
  String mergePendingTitle(String pending, String member) {
    return 'Merge “$pending” into “$member”?';
  }

  @override
  String mergePendingBody(String pending) {
    return '“$pending” on schedules will become this team member, and their services and permission groups will be added';
  }

  @override
  String get mergePendingAction => 'Merge';

  @override
  String get merged => 'Merged';

  @override
  String get fundingTitle => 'This month’s server costs';

  @override
  String fundingProgress(String available, String target) {
    return '$available / $target';
  }

  @override
  String get fundingEnough => 'This month is covered';

  @override
  String fundingMonthsLeft(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months more months',
      one: '1 more month',
    );
    return 'This month is covered, with enough left for $_temp0';
  }

  @override
  String fundingCarried(String amount) {
    return 'Includes $amount carried over from earlier months';
  }

  @override
  String get fundingCosts => 'Server costs';

  @override
  String fundingTarget(String amount) {
    return 'Monthly goal $amount';
  }

  @override
  String get fundingCostsHeader => 'Costs';

  @override
  String get fundingCostsFooter => 'Update when prices change. Yearly items are split evenly across the months.';

  @override
  String get fundingMonthsHeader => 'Recent months';

  @override
  String fundingMonthValue(String received, String target) {
    return '$received / $target';
  }

  @override
  String get costAdd => 'Add item';

  @override
  String get costEdit => 'Cost item';

  @override
  String get costName => 'Name';

  @override
  String get costAmount => 'Amount';

  @override
  String get costPerMonth => 'Monthly';

  @override
  String get costPerYear => 'Yearly';

  @override
  String costValueMonth(String amount) {
    return '$amount · monthly';
  }

  @override
  String costValueYear(String amount) {
    return '$amount · yearly';
  }

  @override
  String moneyTwd(String amount) {
    return 'NT\$$amount';
  }

  @override
  String moneyUsd(String amount) {
    return 'US\$$amount';
  }

  @override
  String get currencyTwd => 'NT\$';

  @override
  String get currencyUsd => 'US\$';

  @override
  String get fundingRatesBy => 'Exchange rates: Exchange Rate API';

  @override
  String get importAdvanced => 'Advanced';

  @override
  String get importFormatHelp =>
      'date: YYYY-MM-DD; if no one is serving, set people to [].\nevents is optional; an occasion’s color accepts only palette numbers 0–5.';

  @override
  String get importPhotoFormatError =>
      'The recognized result isn’t in the right format. Recognize again or use advanced JSON.';

  @override
  String get importJsonSyntaxError => 'Invalid JSON. Use the array format in the example below.';

  @override
  String get importJsonEdit => 'Edit JSON';

  @override
  String get importJsonArrayRequired => 'Enter a JSON array';

  @override
  String importConfirmName(String name) {
    return 'Confirm “$name”';
  }

  @override
  String get importSameNameScope => 'Every instance of this name in this import uses this match';

  @override
  String importGuestChoice(String name) {
    return 'Keep “$name” as a guest';
  }

  @override
  String get importEditDate => 'Edit date';

  @override
  String get importDateFormatLabel => 'Date (YYYY-MM-DD)';

  @override
  String get importValidDate => 'Enter a valid YYYY-MM-DD date';

  @override
  String get importEditDuty => 'Edit role';

  @override
  String get importDutyLabel => 'Role';

  @override
  String get importPeopleLines => 'Names (one per line)';

  @override
  String get importAddEventAction => 'Add occasion';

  @override
  String get importEditEvent => 'Edit occasion';

  @override
  String get importConflict => 'The schedule has changed. Review the differences again before applying.';

  @override
  String get importScopeChanged => 'The church or account changed. Import again.';

  @override
  String importRow(int number) {
    return 'Row $number';
  }

  @override
  String get importDateLabel => 'Date';

  @override
  String get importDateMissing => 'Enter a date';

  @override
  String get importFixDuty => 'Fix role';

  @override
  String get importPeopleArrayHint => 'people must be an array of names';

  @override
  String get importFixEvent => 'Fix occasion';

  @override
  String importRemoveDuty(String role, String names) {
    return 'Remove $role: $names';
  }

  @override
  String importAddDuty(String role, String names) {
    return 'Add $role: $names';
  }

  @override
  String importChangeDuty(String role, String before, String after) {
    return '$role: $before → $after';
  }

  @override
  String importMemberIdentity(String name) {
    return '$name (team member)';
  }

  @override
  String importGuestIdentity(String name) {
    return '$name (guest)';
  }

  @override
  String importRemoveEvent(String name) {
    return 'Remove occasion: $name';
  }

  @override
  String importAddEvent(String name) {
    return 'Add occasion: $name';
  }

  @override
  String importChangeEvent(String name) {
    return 'Occasion: $name';
  }

  @override
  String importChangedColor(String before, String after) {
    return '$before → $after';
  }

  @override
  String get importNoChange => 'No changes to assignments';

  @override
  String get importNoCandidate => 'Keep as a guest or fix the name';

  @override
  String importCandidates(String names) {
    return 'Possible matches: $names';
  }

  @override
  String get importGuestUnlinked => 'Guest (not linked to an account)';

  @override
  String get importNameNeedsConfirm => 'Confirm the name';

  @override
  String importLinkedMember(String name) {
    return 'Team member: $name';
  }

  @override
  String get importMode => 'Import mode';

  @override
  String get importMerge => 'Merge (keep anything not mentioned)';

  @override
  String get importReplace => 'Replace everything on that day';

  @override
  String get importReplaceHelp => 'Removes roles and occasions not mentioned; other dates aren’t affected';

  @override
  String get importFixData => 'Fix the data before importing';

  @override
  String get importFixRow => 'Fix this row';

  @override
  String get importNameLinks => 'Name matches';

  @override
  String get importNamesNeedConfirm => 'Confirm names before importing';

  @override
  String get importRepairSettings => 'Fix church settings (optional)';

  @override
  String get importNoSettingsChange => 'This won’t change team members or church settings';

  @override
  String importAddConfiguredDuty(String role) {
    return 'Add to service settings: $role';
  }

  @override
  String importUnconfiguredDuty(String role) {
    return 'Role not set up: $role';
  }

  @override
  String importGrantQualification(String name, String role) {
    return 'Let $name serve as $role';
  }

  @override
  String importMissingQualification(String name, String role) {
    return '$name isn’t set up for $role';
  }

  @override
  String importAddCommonEvent(String name) {
    return 'Add to common occasions: $name';
  }

  @override
  String importNotCommonEvent(String name) {
    return 'Not a common occasion: $name';
  }

  @override
  String importDiff(String date) {
    return 'Changes after applying · $date';
  }

  @override
  String importRequiredField(String field) {
    return 'Enter $field';
  }

  @override
  String get importColor => 'Color';

  @override
  String get importIssueRowObject => 'Enter an object with date and duties';

  @override
  String get importIssueRowFields => 'Only the date, duties, and events fields are supported';

  @override
  String get importIssueDate => 'date must be a valid YYYY-MM-DD date';

  @override
  String get importIssueDuplicateDate => 'Duplicate date. Combine them into one row.';

  @override
  String get importIssueDutiesArray => 'duties must be an array';

  @override
  String importIssueDutyFields(int index) {
    return 'Role $index: only the role and people fields are supported';
  }

  @override
  String importIssueRole(int index) {
    return 'Role $index: role must be a unique role name';
  }

  @override
  String importIssuePeopleArray(int index) {
    return 'Role $index: people must be an array of non-blank names; use [] if no one is serving';
  }

  @override
  String importIssueDuplicatePeople(int index) {
    return 'Role $index: people can’t have duplicate names';
  }

  @override
  String get importIssueEventsArray => 'events must be an array';

  @override
  String importIssueEventObject(int index, String example) {
    return 'Occasion $index must be $example';
  }

  @override
  String importIssueEventName(int index) {
    return 'Occasion $index: name must be unique';
  }

  @override
  String importIssueEventColor(int index) {
    return 'Occasion $index: color must be a whole number from 0 to 5';
  }

  @override
  String importIssueResolvedDuplicatePeople(String role) {
    return '$role: names are duplicated after confirming. Remove the duplicates.';
  }

  @override
  String get appRunningVersion => 'Current version';

  @override
  String get appVersionDevelopment => 'Development build (no release yet)';

  @override
  String get appUpdateNativeTitle => 'App updates';

  @override
  String get appUpdateNativeNote => 'Check for updates in the App Store or Google Play';

  @override
  String get appUpdateCheck => 'Check for updates';

  @override
  String get appUpdateChecking => 'Checking…';

  @override
  String get appUpdateApply => 'Update and reopen';

  @override
  String get appUpdateApplying => 'Updating…';

  @override
  String get appUpdateCurrent => 'You’re on the latest version';

  @override
  String get appUpdateReady => 'A new version is available';

  @override
  String get appUpdateFinishEditing => 'You have unsaved changes. Save them, then update.';

  @override
  String get appUpdateFinishEditingNote => 'Save what you’re editing first';

  @override
  String get appUpdateFailed => 'Couldn’t update. Check your connection and try again.';

  @override
  String get appUpdateScopeChanged => 'The account or church changed. Check for updates again.';

  @override
  String get appUpdateBackToMe => 'Tap “Update and reopen” again';

  @override
  String get appUpdateCheckFirst => 'Check for updates first';

  @override
  String get servicesAdminOnly => 'Only admins can change service settings';

  @override
  String get importExampleRole => 'Piano';

  @override
  String get importExamplePerson => 'Grace Lee';

  @override
  String get importExampleEvent => 'Communion';

  @override
  String get rosterShowMore => 'Show more';

  @override
  String get pickerGuestNames => 'Guest names';

  @override
  String get serviceSettingsSaved => 'Service settings saved';

  @override
  String get serviceSyncOriginalEvent => 'Original occasion';

  @override
  String get serviceSyncOriginalDuty => 'Original role';

  @override
  String serviceFutureSyncTitle(String from, String to) {
    return 'Sync “$from” to “$to”';
  }

  @override
  String serviceFutureSyncSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Synced $count future schedules',
      one: 'Synced 1 future schedule',
    );
    return '$_temp0';
  }

  @override
  String serviceEventColorTitle(String name) {
    return '$name · Color';
  }

  @override
  String get serviceEventColor => 'Color';

  @override
  String get serviceSyncFutureRosters => 'Sync future schedules';

  @override
  String get rosterFutureChangesNone => 'No future schedules need changes';

  @override
  String get rosterFutureChangesFooter => 'Only saved schedules from tomorrow on are changed';

  @override
  String get rosterFutureChangesConflict => 'An item with the same name already exists. Change it first.';

  @override
  String get rosterApplyFutureChanges => 'Apply changes';

  @override
  String get rosterRemoveFutureGuest => 'Remove future guest assignments';

  @override
  String rosterRemoveFutureGuestTitle(String name) {
    return 'Remove future assignments for “$name”';
  }

  @override
  String rosterFutureGuestRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Removed $count future assignments',
      one: 'Removed 1 future assignment',
    );
    return '$_temp0';
  }

  @override
  String rosterFutureDutyChange(String role, String before, String after) {
    return '$role: $before → $after';
  }

  @override
  String rosterFutureEventChange(String before, String after) {
    return '$before → $after';
  }

  @override
  String get errConflict => 'Another team member just changed this. Reload and make your change again.';

  @override
  String get errOfflineReadOnly => 'You’re offline. Connect to save changes.';

  @override
  String get errTooManyChanges => 'You can change up to 500 schedules at a time. Make the changes in smaller batches.';

  @override
  String get undoDone => 'Undone';

  @override
  String get undoFailed => 'Couldn’t undo. Try again.';

  @override
  String get offlineReadOnlyBanner => 'Offline. Showing what was last loaded. Connect to save changes.';

  @override
  String get calendarCached => 'Showing what was last loaded';

  @override
  String calendarReadAt(String time) {
    return 'Updated $time';
  }

  @override
  String get calDescription => 'Event details';

  @override
  String get calDuplicate => 'Duplicate event';

  @override
  String get homeUpcomingEvents => 'Upcoming events';

  @override
  String get memberSmallGroups => 'Small groups';

  @override
  String get memberSmallGroupsHint => 'One small group per line';

  @override
  String get linkErrNotToday => 'The source hasn’t posted today’s content yet';

  @override
  String linkSourceToday(String reason) {
    return 'Today’s content didn’t update: $reason';
  }

  @override
  String get linkSourceRetry => 'Fetch again';

  @override
  String get listSeparator => ', ';

  @override
  String labelValue(String label, String value) {
    return '$label: $value';
  }

  @override
  String nameIsYou(String name) {
    return '$name (you)';
  }

  @override
  String get churchListSeparator => ', ';

  @override
  String dayWithEvents(String day, String events) {
    return '$day, $events';
  }

  @override
  String get dotSeparator => ' · ';

  @override
  String get churchStatus => 'Status';

  @override
  String get timeZone => 'Time zone';

  @override
  String timeZoneWithOffset(String city, String offset) {
    return '$city ($offset)';
  }

  @override
  String get timeZoneFooter => 'Today’s date, serving reminders, and calendar times follow the church’s time zone';

  @override
  String timeZoneChangeTitle(String city) {
    return 'Switch to $city time?';
  }

  @override
  String get timeZoneChangeBody => 'Event times will show in the new time zone. Schedule dates stay the same.';

  @override
  String timeZoneChange(String city) {
    return 'Switch to $city time';
  }

  @override
  String churchLocalTime(String city) {
    return 'Church local time ($city)';
  }

  @override
  String calendarTimeZoneDiffers(String zone, String city) {
    return 'This calendar is set to $zone, not the church’s time zone ($city). Calendar times follow the church’s time zone.';
  }

  @override
  String get cityAuckland => 'Auckland';

  @override
  String get citySydney => 'Sydney';

  @override
  String get cityMelbourne => 'Melbourne';

  @override
  String get cityTokyo => 'Tokyo';

  @override
  String get citySeoul => 'Seoul';

  @override
  String get cityTaipei => 'Taipei';

  @override
  String get cityHongKong => 'Hong Kong';

  @override
  String get citySingapore => 'Singapore';

  @override
  String get cityKualaLumpur => 'Kuala Lumpur';

  @override
  String get cityLondon => 'London';

  @override
  String get cityToronto => 'Toronto';

  @override
  String get cityNewYork => 'New York';

  @override
  String get cityChicago => 'Chicago';

  @override
  String get cityDenver => 'Denver';

  @override
  String get cityVancouver => 'Vancouver';

  @override
  String get cityLosAngeles => 'Los Angeles';
}
