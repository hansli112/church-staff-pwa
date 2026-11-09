// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class L10nJa extends L10n {
  L10nJa([String locale = 'ja']) : super(locale);

  @override
  String get appName => 'マルタ、ひと休み';

  @override
  String get tabHome => 'ホーム';

  @override
  String get tabRosters => '奉仕表';

  @override
  String get tabCalendar => 'カレンダー';

  @override
  String get tabSettings => '設定';

  @override
  String get undo => '元に戻す';

  @override
  String get cancel => 'キャンセル';

  @override
  String get save => '保存';

  @override
  String get done => '完了';

  @override
  String get retry => '再試行';

  @override
  String get search => '検索';

  @override
  String get clear => 'クリア';

  @override
  String get selected => '選択済み';

  @override
  String get close => '閉じる';

  @override
  String get add => '追加';

  @override
  String get delete => '削除';

  @override
  String get edit => '編集';

  @override
  String get deleted => '削除しました';

  @override
  String get loadFailed => '読み込めませんでした。接続を確認して、もう一度お試しください。';

  @override
  String get saveFailed => '保存できませんでした。接続を確認して、もう一度お試しください。';

  @override
  String get noPermission => 'この操作を行う権限がありません';

  @override
  String get comingSoon => '準備中です';

  @override
  String get signInWithGoogle => 'Google でログイン';

  @override
  String get signInWithApple => 'Appleでサインイン';

  @override
  String get signInWithEmail => 'メールでログイン';

  @override
  String inAppBrowserNote(String app) {
    return '$app の中では Google でログインできません。Safari か Chrome でこのページを開くか、メールでログインしてください。';
  }

  @override
  String get copyPageUrl => 'リンクをコピー';

  @override
  String get pageUrlCopied => 'リンクをコピーしました。Safari か Chrome に貼り付けて開いてください。';

  @override
  String get loginTagline => '「マルタ、マルタ、\nあなたは多くのことに思い悩み、心を乱している。\nしかし、必要なことはただ一つだけである。\nマリアは良い方を選んだ。\nそれを取り上げてはならない。」';

  @override
  String get loginTaglineSource => 'ルカによる福音書 10:41–42（新共同訳）';

  @override
  String loginInvitedTo(String church) {
    return '「$church」に招待されています';
  }

  @override
  String get email => 'メールアドレス';

  @override
  String get password => 'パスワード';

  @override
  String get yourName => 'お名前';

  @override
  String get yourNameFooter => '教会で呼ばれている名前';

  @override
  String get signIn => 'ログイン';

  @override
  String get register => '新規登録';

  @override
  String get createAccount => 'アカウントを作成';

  @override
  String get haveAccount => 'アカウントをお持ちの方はログイン';

  @override
  String get forgotPassword => 'パスワードを忘れた場合';

  @override
  String resetSent(String email) {
    return 'パスワード再設定のメールを $email に送信しました';
  }

  @override
  String get errInvalidCredential => 'メールアドレスまたはパスワードが正しくありません';

  @override
  String get errEmailInUse => 'このメールアドレスは登録済みです。そのままログインするか、Google でログインしてください。';

  @override
  String get errWeakPassword => 'パスワードは6文字以上にしてください';

  @override
  String get errInvalidEmail => 'メールアドレスの形式が正しくありません';

  @override
  String get errNeedsLink => 'このメールアドレスにはすでにアカウントがあります。以前と同じ方法でログインすると、自動的に連携されます。';

  @override
  String get errTooMany => '試行回数が多すぎます。しばらくしてからもう一度お試しください。';

  @override
  String get errLastAdmin => '教会には管理者が1人以上必要です';

  @override
  String get errNetwork => 'ネットワークに接続できません。確認してもう一度お試しください。';

  @override
  String get errUnknown => 'うまくいきませんでした。もう一度お試しください。';

  @override
  String get nameRequired => '名前を入力してください';

  @override
  String get emailRequired => 'メールアドレスを入力してください';

  @override
  String get verifyEmailTitle => 'メールのリンクをタップしてください';

  @override
  String verifyEmailBody(String email) {
    return '確認メールを $email に送信しました。メール内のリンクをタップすると、この画面は自動で先に進みます。';
  }

  @override
  String get verifyEmailNoMail => '届かない場合は迷惑メールフォルダを確認するか、再送してください';

  @override
  String get verifyResend => '確認メールを再送';

  @override
  String get verifyResent => '再送しました';

  @override
  String get welcomeTitle => '教会に参加する';

  @override
  String get welcomeBody => '教会の管理者に招待リンクをもらってください';

  @override
  String get enterInviteCode => '招待コードを入力';

  @override
  String get createChurch => '新しい教会を作成';

  @override
  String get signOut => 'ログアウト';

  @override
  String get inviteCode => '招待コード';

  @override
  String get next => '次へ';

  @override
  String get churchName => '教会名';

  @override
  String get createChurchVerifyFirst => '教会を作成するには、メールアドレスの確認が必要です';

  @override
  String get create => '作成';

  @override
  String get errDuplicateName => '同じ名前の教会がすでにあります。ほかの人に先に登録された場合は、お問い合わせください。';

  @override
  String get contactUs => 'お問い合わせ';

  @override
  String joinTitle(String church) {
    return '「$church」に参加';
  }

  @override
  String get join => '参加';

  @override
  String joined(String church) {
    return '「$church」に参加しました';
  }

  @override
  String alreadyMember(String church) {
    return 'すでに「$church」のメンバーです';
  }

  @override
  String get errInviteInvalid => 'この招待が見つかりません。招待コードを確認するか、管理者に新しい招待をもらってください。';

  @override
  String get errInviteExpired => 'この招待は期限切れです。管理者に新しい招待をもらってください。';

  @override
  String get errChurchClosed => 'この教会は停止されています';

  @override
  String churchSuspendedTitle(String church) {
    return '「$church」は停止されています';
  }

  @override
  String get churchSuspendedBody => 'ご不明な点は教会の管理者にお問い合わせください';

  @override
  String churchDeletedTitle(String church) {
    return '「$church」は削除されました';
  }

  @override
  String churchDeletedBody(String date) {
    return '$dateまでは管理者が復元できます';
  }

  @override
  String get churchDeletedExpired => '30日を過ぎたため、復元できません';

  @override
  String get churchUnavailable => 'この教会を開けません';

  @override
  String get restoreChurch => '教会を復元';

  @override
  String get churchRestored => '教会を復元しました';

  @override
  String get switchChurch => '教会を切り替え';

  @override
  String get myServicesTitle => 'これからの奉仕';

  @override
  String get noUpcomingServices => '予定されている奉仕はありません';

  @override
  String get viewRosters => '奉仕表を見る';

  @override
  String get gettingStarted => 'はじめに';

  @override
  String get inviteMembers => 'メンバーを招待';

  @override
  String get gettingStartedInviteBody => '招待リンクを作成して、メンバーに送りましょう';

  @override
  String get gettingStartedServices => '集会を設定';

  @override
  String get gettingStartedServicesBody => '曜日と、割り当てる担当';

  @override
  String get nobodyYet => '未定';

  @override
  String get noServicesConfigured => '集会がまだ設定されていません';

  @override
  String get setUpServices => '集会を設定';

  @override
  String get noRostersAhead => '今後の集会はありません';

  @override
  String get rostersNobodyArranged => 'まだ誰も割り当てられていません';

  @override
  String get rostersStartArranging => '割り当てを始める';

  @override
  String get rostersImportPhoto => '写真から読み込む';

  @override
  String get today => '今日';

  @override
  String get tomorrow => '明日';

  @override
  String get offlineShowingCached => 'オフラインです。前回のデータを表示しています。';

  @override
  String dutyCount(int count) {
    return '担当$count件';
  }

  @override
  String get addDuty => '担当を追加';

  @override
  String get dutyName => '担当名';

  @override
  String get removeDuty => 'この担当を外す';

  @override
  String dutyRemoved(String duty) {
    return '$dutyを外しました';
  }

  @override
  String dutyUpdated(String duty) {
    return '$dutyを更新しました';
  }

  @override
  String pickerServes(String duty) {
    return '$dutyを担当したメンバー';
  }

  @override
  String get pickerOthers => 'ほかのメンバー';

  @override
  String get pickerAddAnother => 'もう一人追加';

  @override
  String get pickerSwapDay => '別の週と交換';

  @override
  String pickerUseName(String name) {
    return '「$name」を追加';
  }

  @override
  String get pickerUseNameDetail => 'アカウントのない名前';

  @override
  String pickerNoOneServes(String duty) {
    return '$dutyの担当者はまだいません';
  }

  @override
  String pickerNoResults(String query) {
    return '「$query」は見つかりません';
  }

  @override
  String get pickerSearchHint => 'メンバーを検索';

  @override
  String get reorder => '並べ替え';

  @override
  String get reorderHint => 'ドラッグして並べ替えます。毎週この順番になります。';

  @override
  String get editListHint => 'ドラッグで並べ替えます';

  @override
  String pickerTakeOff(String name) {
    return '$nameをリストから外す';
  }

  @override
  String dutyListRemoved(String duty, String names) {
    return '$dutyのリストから$namesを外しました';
  }

  @override
  String get orderSaved => '順番を更新しました';

  @override
  String get swap => '交換';

  @override
  String swapWith(String duty) {
    return '$dutyを誰と交換しますか？';
  }

  @override
  String get swapNone => 'ほかの日に交換できる人がいません';

  @override
  String swapped(String a, String b) {
    return '$aと$bを交換しました';
  }

  @override
  String moved(String name, String day) {
    return '$nameを$dayに移動しました';
  }

  @override
  String get emptySlot => '未定';

  @override
  String removeFromDuty(String duty) {
    return '$dutyから外す';
  }

  @override
  String get events => '特別行事';

  @override
  String get eventsUpdated => '特別行事を更新しました';

  @override
  String get customEvent => 'その他の特別行事';

  @override
  String get addEvent => '特別行事を追加';

  @override
  String get eventName => '特別行事の名前';

  @override
  String get addToCommon => 'よく使う項目に追加';

  @override
  String get eventColor => '色';

  @override
  String get colorName0 => '赤';

  @override
  String get colorName1 => 'オレンジ';

  @override
  String get colorName2 => '黄';

  @override
  String get colorName3 => '緑';

  @override
  String get colorName4 => '青';

  @override
  String get colorName5 => '紫';

  @override
  String removed(String name) {
    return '$nameを外しました';
  }

  @override
  String get name => '名前';

  @override
  String get nameSaved => '名前を更新しました';

  @override
  String get language => '言語';

  @override
  String get languageSystem => 'システムに合わせる';

  @override
  String get churchInfo => '教会情報';

  @override
  String get manageChurch => '教会の管理';

  @override
  String get lineCommunity => 'LINE オープンチャット';

  @override
  String get members => 'メンバー';

  @override
  String get invites => '招待';

  @override
  String get notifications => '通知';

  @override
  String get account => 'アカウント';

  @override
  String get about => '「マルタ、ひと休み」について';

  @override
  String get deleteAccount => 'アカウントを削除';

  @override
  String get privacyPolicy => 'プライバシーポリシー';

  @override
  String get termsOfService => '利用規約';

  @override
  String get developer => '開発';

  @override
  String get components => 'コンポーネント';

  @override
  String get testCrash => 'クラッシュテスト';

  @override
  String get operatorConsole => '運営コンソール';

  @override
  String get leaveChurch => '教会を退出';

  @override
  String leaveChurchTitle(String church) {
    return '「$church」を退出しますか？';
  }

  @override
  String get leaveChurchBody => '戻るには、もう一度招待してもらう必要があります';

  @override
  String get leave => '教会を退出';

  @override
  String leftChurch(String church) {
    return '「$church」を退出しました';
  }

  @override
  String get adminCannotLeave => '退出するには、先に管理者をほかの人に引き継いでください';

  @override
  String get churchLogo => '教会のロゴ';

  @override
  String get uploadLogo => 'ロゴをアップロード';

  @override
  String get changeLogo => 'ロゴを変更';

  @override
  String get logoUploaded => 'ロゴを更新しました';

  @override
  String get logoTooLarge => '画像が大きすぎます。1MB以下の画像を選んでください。';

  @override
  String get logoNotImage => '画像を選んでください';

  @override
  String memberCount(int count) {
    return 'メンバー$count人';
  }

  @override
  String get membersOnlyYou => 'まだほかのメンバーはいません';

  @override
  String get deleteChurch => '教会を削除';

  @override
  String deleteChurchTitle(String church) {
    return '「$church」を削除しますか？';
  }

  @override
  String get deleteChurchBody => 'すべてのメンバーがこの教会を見られなくなります。30日以内なら復元できますが、その後はデータが完全に削除されます。';

  @override
  String get roleAdmin => '管理者';

  @override
  String get role => '役割';

  @override
  String get identityOffice => '事務';

  @override
  String get identityPastor => '牧師';

  @override
  String get identityPastorChurch => '牧師 · 教会全体';

  @override
  String identityPastorOf(String services) {
    return '牧師 · $services';
  }

  @override
  String identityLeadOf(String group) {
    return '$group リーダー';
  }

  @override
  String get identityLead => 'リーダー';

  @override
  String get identityServiceLead => '集会リーダー';

  @override
  String get identityMinistryLead => 'ミニストリーリーダー';

  @override
  String get canAdmin => 'すべて管理できる';

  @override
  String get canOffice => 'すべての奉仕表と行事を編集できるが、メンバーと設定は管理できない';

  @override
  String canServiceLead(String service) {
    return '$serviceの奉仕表を編集し、メンバーを加えたり外したりできる';
  }

  @override
  String canMinistryLead(String ministry) {
    return '$ministryの担当を割り当て、メンバーを加えたり外したりできる';
  }

  @override
  String get canStaff => 'メンバー：すべての奉仕表と行事を見られる';

  @override
  String get addIdentity => '役割を追加';

  @override
  String get addAnotherIdentity => 'もう1つ追加';

  @override
  String identityRemoved(String identity) {
    return '「$identity」を外しました';
  }

  @override
  String identityAdded(String identity) {
    return '「$identity」を追加しました';
  }

  @override
  String get wholeChurch => '教会全体';

  @override
  String get pickPastorScope => '牧会の範囲';

  @override
  String get pickService => '集会を選ぶ';

  @override
  String get pickMinistry => 'ミニストリーを選ぶ';

  @override
  String get groupsTitle => '集会とミニストリー';

  @override
  String get groupsSub => '担当、リーダー、メンバー';

  @override
  String get ministries => 'ミニストリー';

  @override
  String get addMinistry => 'ミニストリーを追加';

  @override
  String get ministryName => 'ミニストリー名';

  @override
  String get ministryDuties => '担当';

  @override
  String get dutyOthers => 'ほかの人';

  @override
  String get dutyMinistry => 'ミニストリー';

  @override
  String get ministryPickDuties => '担当を選ぶ';

  @override
  String get ministryDutiesNone => 'なし';

  @override
  String get deleteMinistry => 'ミニストリーを削除';

  @override
  String ministryDeleted(String name) {
    return '「$name」を削除しました';
  }

  @override
  String get leads => 'リーダー';

  @override
  String get noLeads => 'リーダーはまだいません';

  @override
  String get assignLead => 'リーダーを指名';

  @override
  String get groupStaff => 'メンバー';

  @override
  String groupStaffTitle(String group) {
    return '$groupのメンバー';
  }

  @override
  String groupStaffCount(int count) {
    return '$count人';
  }

  @override
  String get noGroupStaff => 'メンバーはまだいません';

  @override
  String groupCandidates(String group) {
    return '$groupで奉仕したが、まだメンバーではない人';
  }

  @override
  String groupCandidateServed(String duty, int count) {
    return '$duty $count回';
  }

  @override
  String get addAsStaff => 'メンバーにする';

  @override
  String addAsStaffLabel(String name, String group) {
    return '$nameを$groupのメンバーにする';
  }

  @override
  String removeFromGroup(String group) {
    return '$groupから外す';
  }

  @override
  String addedToGroup(String name, String group) {
    return '$nameを$groupのメンバーにしました';
  }

  @override
  String removedFromGroup(String name, String group) {
    return '$nameを$groupから外しました';
  }

  @override
  String get myGroups => '担当しているもの';

  @override
  String get eventGroup => '所属';

  @override
  String eventOfGroup(String group) {
    return '$groupの行事';
  }

  @override
  String get calFilter => '絞り込み';

  @override
  String get calFilterMine => '自分に関係あるもの';

  @override
  String get calFilterAll => 'すべて';

  @override
  String get removeShort => '外す';

  @override
  String removeIdentityLabel(String identity) {
    return '「$identity」を外す';
  }

  @override
  String get moveOutShort => '外す';

  @override
  String removeFromGroupLabel(String name, String group) {
    return '$nameを$groupから外す';
  }

  @override
  String get addGroupStaff => 'メンバーを加える';

  @override
  String get zones => '所属集会と担当';

  @override
  String get removeMember => 'メンバーを外す';

  @override
  String memberRemoved(String name) {
    return '$nameを外しました';
  }

  @override
  String get memberSaved => '保存しました';

  @override
  String get searchMembers => 'メンバーを検索';

  @override
  String get noMembersFound => 'メンバーが見つかりません';

  @override
  String get you => '自分';

  @override
  String get inviteCreate => '招待リンクを作成';

  @override
  String get inviteValidFor => '有効期間';

  @override
  String inviteDays(int days) {
    return '$days日間有効';
  }

  @override
  String get inviteCopy => 'リンクをコピー';

  @override
  String get inviteCopied => '招待リンクをコピーしました';

  @override
  String get copyByHand => '自動でコピーできませんでした。下のテキストを選択してコピーしてください。';

  @override
  String get inviteShare => '共有';

  @override
  String get inviteRevoke => '取り消す';

  @override
  String get inviteRevoked => '取り消しました';

  @override
  String inviteExpiresOn(String date) {
    return '$dateまで有効';
  }

  @override
  String get inviteNone => '招待リンクはまだありません';

  @override
  String inviteMessage(String church, String link) {
    return '「$church」の奉仕表へのご招待です：$link';
  }

  @override
  String get servicesTitle => '集会';

  @override
  String get serviceAdd => '集会を追加';

  @override
  String get serviceName => '集会名';

  @override
  String get weekday => '曜日';

  @override
  String get serviceEnabled => '実施中';

  @override
  String get serviceDisabledFooter => '停止した集会には新しい奉仕表が作られません';

  @override
  String dutyPeopleCount(int count) {
    return '$count人';
  }

  @override
  String get templateDuties => '担当';

  @override
  String get commonEvents => 'よく使う特別行事';

  @override
  String get rename => '名前を変更';

  @override
  String get remove => '外す';

  @override
  String get saved => '保存しました';

  @override
  String get weekday1 => '月曜';

  @override
  String get weekday2 => '火曜';

  @override
  String get weekday3 => '水曜';

  @override
  String get weekday4 => '木曜';

  @override
  String get weekday5 => '金曜';

  @override
  String get weekday6 => '土曜';

  @override
  String get weekday7 => '日曜';

  @override
  String get deleteAccountTitle => 'アカウントを削除しますか？';

  @override
  String get deleteAccountBody => 'すべての教会から退出し、アカウントと個人情報は削除されて元に戻せません。奉仕表上の名前は残ります。';

  @override
  String deleteAccountLastAdmin(String churches) {
    return 'あなたは「$churches」の唯一の管理者です。先にほかのメンバーを管理者にしてください。';
  }

  @override
  String deleteAccountChurchesToo(String churches, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '「$churches」にはほかにだれもいないので、アカウントといっしょに削除されます。',
    );
    return '$_temp0';
  }

  @override
  String get goToMembers => 'メンバーを開く';

  @override
  String get accountDeleted => 'アカウントを削除しました';

  @override
  String get serviceDisabled => '停止中';

  @override
  String get adminSearchHint => '教会名または ID';

  @override
  String get adminNoChurches => '教会が見つかりません';

  @override
  String get adminStats => '統計';

  @override
  String get adminChurches => '教会';

  @override
  String get adminRename => '名前を変更';

  @override
  String get adminMakeAdmin => '管理者にする';

  @override
  String get adminRevokeAdmin => '管理者から外す';

  @override
  String adminRevokedAdmin(String name) {
    return '$nameを管理者から外しました';
  }

  @override
  String adminMadeAdmin(String name) {
    return '$nameを管理者にしました';
  }

  @override
  String get adminSuspend => '教会を停止';

  @override
  String get adminReopen => '教会を再開';

  @override
  String adminSuspendTitle(String church) {
    return '「$church」を停止しますか？';
  }

  @override
  String get adminSuspendBody => 'すべてのメンバーにすぐ停止画面が表示されます';

  @override
  String get statusActive => '利用中';

  @override
  String get statusSuspended => '停止中';

  @override
  String get statusDeleted => '削除済み';

  @override
  String get statsUsers => 'ユーザー';

  @override
  String get statsChurches => '教会';

  @override
  String get statsMembers => 'メンバー';

  @override
  String get statsRosters => '奉仕表';

  @override
  String get statsReads => 'Firestore 読み取り';

  @override
  String get statsWrites => 'Firestore 書き込み';

  @override
  String get statsCost => '推定費用（USD）';

  @override
  String get statsNone => '統計データはまだありません';

  @override
  String get statsMoreInConsole => '利用状況とエラーの詳細は Firebase コンソールで確認できます';

  @override
  String get notifReminder => '奉仕のリマインダー';

  @override
  String get notifReminderWeeklySub => '毎週月曜の夜に、その週の奉仕をお知らせします';

  @override
  String get notifReminderDayBeforeSub => '奉仕の前日の夜にお知らせします';

  @override
  String get notifReminderBothSub => '毎週月曜の夜と、奉仕の前日の夜';

  @override
  String get notifReminderTime => 'リマインダーの時間';

  @override
  String get notifReminderWeekly => '毎週月曜の夜';

  @override
  String get notifReminderDayBefore => '前日の夜';

  @override
  String get notifReminderBoth => '両方';

  @override
  String get notifReminderTimeFooter => 'どちらも夜7時です';

  @override
  String get notifRosterChange => '奉仕表の変更';

  @override
  String get notifRosterChangeSub => '奉仕に入ったり外れたりしたとき。夜10時以降の変更は朝7時に届きます。';

  @override
  String get notifMemberJoined => 'メンバーの参加';

  @override
  String get notifMemberJoinedSub => '誰かが招待で教会に参加したとき（管理者のみ）';

  @override
  String get notifMemberLeft => 'メンバーの退出';

  @override
  String get notifMemberLeftSub => '誰かが教会を退出したとき（管理者のみ）';

  @override
  String get notifThisChurch => 'この教会の通知';

  @override
  String get notifPermissionOff => '通知がオフになっています。システムの設定でオンにしてください。';

  @override
  String get notifEnable => '通知をオンにする';

  @override
  String get notifAskTitle => '奉仕に入ったらお知らせします';

  @override
  String get notifAskBody => '奉仕に入ったときや奉仕表が変わったときにお知らせします。毎週月曜の夜には、その週の奉仕もお知らせします。';

  @override
  String get notifAskLater => 'あとで';

  @override
  String get notifCardHide => '今後表示しない';

  @override
  String get notifOpenSettings => '端末の設定で通知をオンにする';

  @override
  String get notifNotAllowed => '通知がまだオンになっていません。確認が表示されたら「許可」をタップしてください。';

  @override
  String get notifRegisterFailed => '通知の設定が完了していません。次にアプリを開いたときにもう一度試します。';

  @override
  String get pushView => '表示';

  @override
  String zoneSwitch(String service) {
    return '$serviceのメンバー';
  }

  @override
  String zoneLeft(String service) {
    return '$serviceの所属から外れました';
  }

  @override
  String get eventRosterGone => 'この行事の奉仕表が見つかりません';

  @override
  String get eventRoster => '奉仕表';

  @override
  String eventRosterPeople(int count) {
    return '$count人';
  }

  @override
  String get arrangeEventRoster => '奉仕を割り当てる';

  @override
  String get eventRosterEmpty => '担当はまだありません';

  @override
  String get copyDuties => 'ほかの行事からコピー';

  @override
  String get copyDutiesHeader => 'どの行事の担当をコピーしますか';

  @override
  String get copyDutiesNone => 'ほかの行事の奉仕表はまだありません';

  @override
  String dutiesCopied(int count) {
    return '担当を$count件追加しました';
  }

  @override
  String get noZoneYet => 'まだどの集会にも所属していません。管理者に設定を依頼してください。';

  @override
  String get waitsForZone => '所属集会が未設定';

  @override
  String waitingForZone(int count) {
    return '$count人のメンバーの所属集会が未設定です';
  }

  @override
  String get inviteZones => '参加後の所属集会';

  @override
  String get photoImport => '写真から読み込み';

  @override
  String get photoImportAction => '写真読込';

  @override
  String photoRemaining(int count) {
    return '今月はあと$count枚読み取れます';
  }

  @override
  String get photoTake => '写真を撮る';

  @override
  String get photoPick => '写真を選ぶ';

  @override
  String get photoPasteJson => 'JSON を貼り付け';

  @override
  String get photoRecognizing => '読み取り中です。1分ほどかかります。';

  @override
  String photoChurchLimit(int limit) {
    return '今月の$limit枚を使い切りました。来月1日に戻ります。';
  }

  @override
  String get photoPlatformOff => '写真の読み取りは今月停止しています。来月に再開します。';

  @override
  String get photoTooLarge => '写真が大きすぎます。表の部分だけに切り抜いて、もう一度お試しください。';

  @override
  String get photoFailed => '読み取れませんでした。もっと鮮明な写真でお試しください。';

  @override
  String get photoUnavailable => '写真の読み取りは現在利用できません。しばらくしてからお試しください。';

  @override
  String get importPreview => 'プレビュー';

  @override
  String get importApply => '奉仕表に適用';

  @override
  String importConfirmNamesFirst(int count) {
    return '先に名前を$count件確認';
  }

  @override
  String importApplied(int count) {
    return '$count日分を読み込みました';
  }

  @override
  String get importNothing => '写真から今後の日付が読み取れませんでした';

  @override
  String get importNotInList => '名簿にない人です（書かれたとおりに記入し、アカウントにはつながっていません）';

  @override
  String importNear(String names) {
    return '名簿に似た名前があります：$names';
  }

  @override
  String get importAmbiguous => '誰なのか特定できません（アカウントにはつながっていません）';

  @override
  String get importUnknownDuties => 'この集会にない担当です';

  @override
  String get importPastDays => '過ぎた日付のため読み込んでいません';

  @override
  String get importBadRows => '読み取れなかったデータ';

  @override
  String get jsonHint => '読み取り結果の JSON を貼り付け';

  @override
  String get next2 => 'プレビュー';

  @override
  String get calNotConnected => '教会のカレンダーがまだ接続されていません';

  @override
  String get calConnect => 'Google カレンダーに接続';

  @override
  String get calReconnect => '再接続';

  @override
  String get calNeedsReconnect => 'カレンダーの認証が切れています';

  @override
  String get calNeedsReconnectStaff => '現在カレンダーを読み込めません。管理者に再接続を依頼してください。';

  @override
  String get calPickCalendar => '使うカレンダーを選択';

  @override
  String get calNoCalendarYet => 'カレンダーが選ばれていません';

  @override
  String get calDisconnect => '接続を解除';

  @override
  String get calDisconnectTitle => 'カレンダーの接続を解除しますか？';

  @override
  String get calDisconnectBody => 'メンバーはカレンダーを見られなくなります。Google カレンダー自体は変わりません。';

  @override
  String get calUnverifiedNote =>
      'このあと Google に「このアプリは Google で確認されていません」と表示されます。「詳細」→「（アプリ名）に移動」をタップして進んでください。読み書きするのは選んだカレンダーだけです。';

  @override
  String get calConnectedOk => 'Google カレンダーに接続しました';

  @override
  String get calConnectFailed => '接続できませんでした。もう一度お試しください。';

  @override
  String get calConnectScopes => '接続できませんでした。Google の画面で、すべての権限にチェックを入れてください。';

  @override
  String get calNoEvents => '今月の行事はありません';

  @override
  String get calNoEventsThatDay => 'この日の行事はありません';

  @override
  String get calAllDay => '終日';

  @override
  String get calGoogleOnly => 'この行事は Google カレンダーで変更してください';

  @override
  String get calNewEvent => '行事を追加';

  @override
  String get calEditEvent => '行事を編集';

  @override
  String get calTitle => '行事名';

  @override
  String get calLocation => '場所';

  @override
  String get calStart => '開始';

  @override
  String get calEnd => '終了';

  @override
  String calLengthMinutes(int minutes) {
    return '$minutes分';
  }

  @override
  String calLengthHours(int hours) {
    return '$hours時間';
  }

  @override
  String calLengthHoursMinutes(int hours, int minutes) {
    return '$hours時間$minutes分';
  }

  @override
  String get calDelete => '行事を削除';

  @override
  String calDeleted(String title) {
    return '$titleを削除しました';
  }

  @override
  String get calSaved => '行事を保存しました';

  @override
  String get calPrevMonth => '前の月';

  @override
  String get calNextMonth => '次の月';

  @override
  String get calShowMonth => '月表示';

  @override
  String get calHideMonth => 'リストのみ';

  @override
  String get calendarSetting => 'カレンダー';

  @override
  String get support => '「マルタ、ひと休み」を応援';

  @override
  String get supportVerse =>
      'あなたがたの現在のゆとりが彼らの欠乏を補えば、いつか彼らのゆとりもあなたがたの欠乏を補うことになり、こうして釣り合いがとれるのです。「多く集めた者も、余ることはなく、わずかしか集めなかった者も、不足することはなかった」と書いてあるとおりです。';

  @override
  String get supportVerseSource => 'コリントの信徒への手紙二 8:14–15（新共同訳）';

  @override
  String get supportTips => '1回の応援';

  @override
  String get supportMonthly => '毎月の応援';

  @override
  String supportPerMonth(String price) {
    return '$price/月';
  }

  @override
  String get supportRestore => '購入を復元';

  @override
  String get supportRate => '評価で応援する';

  @override
  String supportMonthlyTerms(String store) {
    return '毎月自動で更新されます。$store のサブスクリプション設定からいつでも解約できます。';
  }

  @override
  String get manageSubscription => 'サブスクリプションを管理';

  @override
  String get supportThanks => '応援ありがとうございます';

  @override
  String get supportThanksBody => 'いただいた応援は「マルタ、ひと休み」のサーバー費用にあてます';

  @override
  String get supportPending => '支払いを処理中';

  @override
  String get supportFailed => '支払いは完了していません。請求はされていません。';

  @override
  String get supportUnavailable => '現在ストアに接続できません。しばらくしてからもう一度お試しください。';

  @override
  String get supportComingSoon => 'アプリ内での応援はまもなく始まります';

  @override
  String get supporterBadge => '応援者';

  @override
  String get appIcon => 'アプリのアイコン';

  @override
  String get appIconSupporterOnly => '毎月の応援者はアプリのアイコンを変えられます';

  @override
  String supportMonthlyTermsAndIcons(String store) {
    return '毎月の応援者はアプリのアイコンを変えられます。毎月自動で更新されます。$store のサブスクリプション設定からいつでも解約できます。';
  }

  @override
  String get appIconDefault => '標準';

  @override
  String get appIconGreen => '緑';

  @override
  String get appIconPurple => '紫';

  @override
  String get appIconNight => '夜';

  @override
  String churchIconChanged(String church) {
    return 'ホーム画面のアイコンを「$church」に変えました';
  }

  @override
  String get goHome => 'ホームに戻る';

  @override
  String get churchNotFound => 'この教会が見つかりません';

  @override
  String get churchEntryNotMember => '管理者に招待リンクをもらってください';

  @override
  String get churchUrl => '教会の URL';

  @override
  String get churchUrlCopied => '教会の URL をコピーしました';

  @override
  String get churchUrlCopy => '教会の URL をコピー';

  @override
  String get churchUrlShare => '教会の URL を共有';

  @override
  String get homeName => 'ホーム画面の名前';

  @override
  String get homeNameUnset => '教会名と同じ';

  @override
  String get homeNameMayBeCut => '一部のスマホでは途中で切れることがあります';

  @override
  String get homeNameFooter => 'ホーム画面に追加したとき、アイコンの下に表示される名前です。空欄なら教会名を使います。';

  @override
  String get addToHome => 'ホーム画面に追加';

  @override
  String get addToHomeIosNote => 'iPhone では、追加済みのアイコンは更新されません。名前やロゴを変えたら、アイコンを削除してもう一度追加してください。';

  @override
  String get addToHomeLater => 'あとで';

  @override
  String addToHomeDone(String name) {
    return '追加しました。これからはスマホの「$name」アイコンをタップして開いてください。';
  }

  @override
  String get addToHomeIntro => '次からはホーム画面のアイコンをタップすると奉仕表が開きます';

  @override
  String addToHomeBrowserGuide(String device, String browser) {
    return '$device · $browser の手順';
  }

  @override
  String get addToHomeChooseBrowser => '画面が違いますか？';

  @override
  String get addToHomeChooseGuide => '見たい手順を選択';

  @override
  String get addToHomeSafariLayoutTitle => 'Safari の画面';

  @override
  String get addToHomeSafariLayoutHint => 'ツールバーのボタンに合わせて選んでください';

  @override
  String get addToHomeSafariMoreChoice => '「⋯」が見える';

  @override
  String get addToHomeSafariShareChoice => '共有アイコンが見える';

  @override
  String get addToHomeSafariMoreShare => '「⋯」をタップして「共有」を選択';

  @override
  String get addToHomeSafariDirectShareHint => 'アドレスバーは上でも下でもかまいません。「四角から上向きの矢印」のアイコンを探してください。';

  @override
  String get addToHomeInApp => 'アプリ内ブラウザ';

  @override
  String get addToHomeOtherBrowser => 'その他のブラウザ';

  @override
  String get addToHomeScreenshotNote => 'ブラウザの丸で囲んだボタンをタップしてください';

  @override
  String get addToHomeAddressBar => 'アドレスバー';

  @override
  String get addToHomeChromeShare => 'アドレスバーの横の共有アイコンをタップ';

  @override
  String get addToHomeChromeShareHint => '「⋯」メニューでも「Chrome を共有」でもありません';

  @override
  String get addToHomeChromeScroll => '見つからないときは、共有シートを広げてから下にスクロールしてください';

  @override
  String get addToHomeSafariShare => 'Safari の共有アイコンをタップ';

  @override
  String get addToHomeFirefoxShare => 'アドレスバーの共有アイコンをタップ';

  @override
  String get addToHomeIpadMore => 'iPad でこの項目が見つからない場合は、先に共有シートの「その他」をタップしてください';

  @override
  String get addToHomeSelectAdd => '「ホーム画面に追加」をタップ';

  @override
  String get addToHomeShareMore => 'アイコンが1列しか見えない場合は、先に「さらに表示」をタップしてください。古いバージョンでは下にスクロールします。';

  @override
  String get addToHomeIosConfirm => '「Web アプリとして開く」のスイッチがあればオンのままにして、最後に右上の「追加」をタップしてください';

  @override
  String get addToHomeOpenTitle => 'ホーム画面に戻り、新しいアイコンをタップして開く';

  @override
  String addToHomeMenu(String browser) {
    return '$browser のメニューをタップ';
  }

  @override
  String get addToHomeChromeInstall => 'ホーム画面に追加 → インストール';

  @override
  String get addToHomeChromeInstallHint => '古いバージョンでは「アプリをインストール」と表示されることがあります。「ショートカットを作成」ではなく「インストール」を選んでください。';

  @override
  String get addToHomeFirefoxInstallHint => 'そのあとはスマホの案内に従って追加してください。「ホーム画面に追加」しかない場合は、ブラウザのショートカットが作られるだけのことがあります。';

  @override
  String get addToHomeTrouble => '「ホーム画面に追加」が見つからない場合';

  @override
  String get addToHomeSafariTrouble => '共有シートを上にスワイプして、下のほうのアクションを確認してください。それでも見つからない場合は、いちばん下の「アクションを編集」をタップしてください。';

  @override
  String addToHomeExternalTitle(String browser) {
    return 'まず $browser で開く';
  }

  @override
  String addToHomeExternalHint(String browser) {
    return '教会の URL をコピーし、$browser のアドレスバーに貼り付けて開いてから、手順を続けてください';
  }

  @override
  String get addToHomeEmbeddedHint => 'アプリの中でページを見ています。先にスマホのブラウザに切り替えてください。';

  @override
  String get addToHomeUnknownHint => '下の方法をお試しください';

  @override
  String addToHomeCopiedForBrowser(String browser) {
    return 'コピーしました。$browser を開いてアドレスバーに貼り付けてください。';
  }

  @override
  String get addToHomePhoneOnly => 'スマホで教会の URL を開いてから、ホーム画面に追加してください';

  @override
  String get addToHomeNotificationsAfter => 'ホーム画面から開いたら、「設定」で通知をオンにすると奉仕の通知が届きます';

  @override
  String get addToHomeIosShare => '共有';

  @override
  String get addToHomeIosAdd => '追加';

  @override
  String addToHomeIosOpen(String name) {
    return 'スマホの「$name」アイコンをタップして開き、もう一度ログインしてください';
  }

  @override
  String get addToHomeAndroidAdd => 'ホーム画面に追加';

  @override
  String get addToHomeAndroidInstall => 'インストール';

  @override
  String addToHomeAndroidOpen(String name) {
    return 'スマホの「$name」アイコンをタップして開いてください';
  }

  @override
  String get addToHomeCardBody => 'タップひとつで開けて、奉仕の通知も届きます';

  @override
  String get addToHomeCardHide => '今後表示しない';

  @override
  String get notifNeedsHomeScreen => '通知を受け取るには、先にホーム画面に追加してください';

  @override
  String get churchLink => '教会のリンク';

  @override
  String get churchLinkNone => '未設定';

  @override
  String get churchLinkTitle => 'タイトル';

  @override
  String get churchLinkBody => '説明（任意）';

  @override
  String get churchLinkUrl => 'リンク';

  @override
  String get churchLinkNeedsTitle => 'タイトルを入力してください';

  @override
  String get churchLinkNeedsHttps => 'https:// で始まるリンクを入力してください';

  @override
  String get churchLinkFooter => 'すべてのメンバーのホームのいちばん上に表示されます';

  @override
  String get churchLinkRemove => '教会のリンクを外す';

  @override
  String get churchLinkRemoved => '教会のリンクを外しました';

  @override
  String get churchLinkOpens => 'ブラウザで開く';

  @override
  String get linkSource => '毎日のコンテンツの取得元（任意）';

  @override
  String get linkSourceUrl => 'JSON の URL';

  @override
  String get linkFetchTime => '毎日の更新時刻';

  @override
  String get linkSourceFooter => 'JSON には date（YYYY-MM-DD）、title、body、link が必要です';

  @override
  String linkSourceUpdated(String time) {
    return '前回の更新：$time';
  }

  @override
  String linkSourceFailed(String reason) {
    return '前回は取得できませんでした：$reason';
  }

  @override
  String linkSourceFetched(String title) {
    return '保存しました。「$title」を取得しました。';
  }

  @override
  String get linkErrTimeout => '相手のサイトが5秒以内に応答しませんでした';

  @override
  String get linkErrTooLarge => '内容が64KBを超えています';

  @override
  String get linkErrBadFormat => '内容が date、title、body、link のそろった JSON ではありません';

  @override
  String get linkErrNotHttps => 'URL またはリダイレクト先が https ではありません';

  @override
  String linkErrHttp(String status) {
    return '相手のサイトがエラーを返しました（$status）';
  }

  @override
  String get linkErrNetwork => '相手のサイトに接続できません';

  @override
  String get linkErrUnknown => '原因不明です。もう一度お試しください。';

  @override
  String get webhook => '外部通知';

  @override
  String get webhookUrl => '受信 URL';

  @override
  String get webhookNeedsHttps => 'https:// で始まる URL を入力してください';

  @override
  String get webhookSecretOptional => 'シークレット（任意、空欄なら自動生成）';

  @override
  String get webhookSecretTooShort => 'シークレットは16文字以上にしてください';

  @override
  String get webhookCalendar => 'カレンダーの変更';

  @override
  String get webhookCalendarHint => '行事の追加・変更・削除';

  @override
  String get webhookRoster => '奉仕表の変更';

  @override
  String get webhookRosterHint => '数分以内の変更は1件にまとめて送ります';

  @override
  String get webhookFooter => 'カレンダーや奉仕表が変更されたとき、この URL に通知を送ります。たとえば n8n で受けて LINE グループに転送できます。';

  @override
  String get webhookTest => 'テスト送信';

  @override
  String webhookLast(String time, String result) {
    return '前回の送信：$time・$result';
  }

  @override
  String get webhookOk => '成功';

  @override
  String webhookHttp(String status) {
    return '応答 $status';
  }

  @override
  String get webhookTimeout => 'タイムアウト';

  @override
  String get webhookNetwork => '接続できません';

  @override
  String get webhookRotate => 'シークレットを新しくする';

  @override
  String get webhookRotateMessage => '古いシークレットはすぐに使えなくなります。受信側で新しいものに切り替えてください。';

  @override
  String get webhookGenerate => '自動生成';

  @override
  String get webhookTypeOwn => '自分で入力';

  @override
  String get webhookSecretTitle => 'シークレット';

  @override
  String get webhookSecretOnce => '表示されるのはこの1回だけです。受信側に貼り付けて、通知が「マルタ、ひと休み」から送られたことの確認に使ってください。';

  @override
  String get webhookCopySecret => 'シークレットをコピー';

  @override
  String get webhookSecretCopied => 'シークレットをコピーしました';

  @override
  String get webhookSecretChanged => '新しいシークレットに変更しました';

  @override
  String get webhookOff => '外部通知をオフにする';

  @override
  String get webhookOffTitle => '外部通知をオフにしますか？';

  @override
  String get webhookOffMessage => 'URL とシークレットは削除され、もう一度設定が必要になります';

  @override
  String get webhookOffAction => 'オフにする';

  @override
  String get exportData => 'データをエクスポート';

  @override
  String get exported => 'エクスポートしました';

  @override
  String get exportCsvFile => '奉仕表.csv';

  @override
  String get exportCsvDate => '日付';

  @override
  String get exportCsvService => '集会・行事';

  @override
  String get exportCsvRole => '担当';

  @override
  String get exportCsvPeople => 'メンバー';

  @override
  String get errMoveInvalid => '移行ファイルではありません。正しいファイルを選んだか確認してください。';

  @override
  String get errMoveTooLarge =>
      'メンバーが2,000人、または奉仕表が20,000件を超えるため、自動で移行できません。GitHub の church-staff-pwa で issue を作成してください。';

  @override
  String get moveFromSelfHost => '旧バージョンから移行';

  @override
  String get moveIntro =>
      '旧バージョン（church-staff-pwa）の Cloud Shell で移行コマンドを実行し、できた移行ファイルをアップロードしてください。プレビューを確認すると教会が作成されます。';

  @override
  String get movePickFile => '移行ファイルを選択';

  @override
  String get moveReading => '移行ファイルを読み込み中…';

  @override
  String get moveContents => '移行ファイルの内容';

  @override
  String get moveMembers => 'メンバー';

  @override
  String moveMembersCount(int count) {
    return '$count人';
  }

  @override
  String get moveRosters => '奉仕表';

  @override
  String moveRostersCount(int count) {
    return '$count件';
  }

  @override
  String get moveServices => '集会';

  @override
  String get moveWhoAmI => 'これは自分です（任意）';

  @override
  String get moveWhoAmIFooter => '選ぶと、その人の奉仕を引き継ぎます';

  @override
  String get moveCreate => '教会を作成して移行';

  @override
  String moveDone(String church) {
    return '「$church」を作成しました';
  }

  @override
  String get notSignedInYet => '未ログイン';

  @override
  String pendingCount(int count) {
    return '$count人が未ログイン';
  }

  @override
  String claimTitle(String church) {
    return '$churchに参加しますか？';
  }

  @override
  String get claimBody => '教会がこのアプリに移りました。これまでの奉仕はもうここにあります。';

  @override
  String claimByNameTitle(String name) {
    return '奉仕表の「$name」はあなたですか？';
  }

  @override
  String claimByNameBody(String name) {
    return 'そうであれば、「$name」の奉仕と所属集会があなたに引き継がれます';
  }

  @override
  String claimServe(String service, String duty) {
    return '$service・$duty';
  }

  @override
  String get claimByNameYes => '私です';

  @override
  String get claimByNameNo => '違います';

  @override
  String claimByNameDone(String name) {
    return '「$name」の奉仕を引き継ぎました';
  }

  @override
  String get claimJoin => '参加';

  @override
  String get claimDecline => '参加しない';

  @override
  String get movedPasswordNote => '旧バージョンから移行したメンバーの方へ：古いパスワードは使えません。同じメールアドレスで新しくアカウントを登録するか、Google でログインしてください。';

  @override
  String get pendingDelete => 'このデータを削除';

  @override
  String pendingDeleteTitle(String name) {
    return '「$name」のデータを削除しますか？';
  }

  @override
  String get pendingDeleteBody => 'この人はメールアドレスで引き継げなくなります。奉仕表上の名前は残ります。';

  @override
  String get pendingDeleted => '削除しました';

  @override
  String get mergePending => '未ログインのデータを統合';

  @override
  String get mergePendingFooter => 'メールアドレスがない、または別のメールアドレスで参加したメンバーに使います';

  @override
  String get mergePendingPick => '未ログインのデータを選択';

  @override
  String mergePendingTitle(String pending) {
    return '未ログインの「$pending」を統合しますか？';
  }

  @override
  String mergePendingBody(String pending, String member) {
    return '未ログインの「$pending」が「$member」に統合されます';
  }

  @override
  String get mergePendingAction => '統合';

  @override
  String get merged => '統合しました';

  @override
  String mergeSuggestion(String name) {
    return '未ログインのデータにも「$name」があります';
  }

  @override
  String mergeSuggestionLabel(String name) {
    return '$nameを統合';
  }

  @override
  String get fundingTitle => '今月の応援';

  @override
  String fundingProgress(String available, String target) {
    return '$available / $target';
  }

  @override
  String get fundingEnough => '今月分は足りています';

  @override
  String fundingMonthsLeft(int months) {
    return '今月分は足りています。余りであと$monthsか月まかなえます。';
  }

  @override
  String fundingCarried(String amount) {
    return '前月までの繰越$amountを含む';
  }

  @override
  String get fundingCosts => 'サーバー費用';

  @override
  String fundingTarget(String amount) {
    return '毎月の目標 $amount';
  }

  @override
  String get fundingTargetUpdating => '毎月の目標を更新中…';

  @override
  String get fundingCostsHeader => '費用';

  @override
  String get fundingCostsFooter => '価格が変わったら更新してください。年払いの項目は各月に均等に割ります。名前と月額は応援ページで公開されます。';

  @override
  String get fundingMonthsHeader => '最近の数か月';

  @override
  String fundingMonthValue(String received, String target) {
    return '$received / $target';
  }

  @override
  String get costAdd => '項目を追加';

  @override
  String get costEdit => '費用の項目';

  @override
  String get costName => '名前';

  @override
  String get costNamesOther => 'ほかの言語での名前（任意）。空欄の言語は英語の名前、英語も空欄なら上の名前を表示します。簡体字中国語が空欄なら上の名前を表示します。';

  @override
  String get costAmount => '金額';

  @override
  String get costPerMonth => '月額';

  @override
  String get costPerYear => '年額';

  @override
  String costValueMonth(String amount) {
    return '$amount・月額';
  }

  @override
  String costValueYear(String amount) {
    return '$amount・年額';
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
  String get fundingWhereItGoes => '毎月の使いみち';

  @override
  String get fundingYearlySplit => '年払いの費用は月割りで表示しています';

  @override
  String get fundingRatesBy => '為替レート：Exchange Rate API';

  @override
  String get importAdvanced => '詳細設定';

  @override
  String get importCopyPrompt => 'AI への指示をコピー';

  @override
  String get importPromptCopied => 'コピーしました。写真と一緒に AI に送り、返ってきた JSON を貼り付けてください';

  @override
  String get importFormatHelp => 'date：YYYY-MM-DD。担当者がいない場合は people を [] にします。\nevents は省略可。特別行事の color は色番号 0〜5。';

  @override
  String get importPhotoFormatError => '読み取り結果の形式が正しくありません。もう一度読み取るか、詳細設定の JSON を使ってください。';

  @override
  String get importJsonSyntaxError => 'JSON の形式が正しくありません。下の例の配列形式を使ってください。';

  @override
  String get importJsonEdit => 'JSON を編集';

  @override
  String get importJsonArrayRequired => 'JSON 配列を入力してください';

  @override
  String importConfirmName(String name) {
    return '「$name」を確認';
  }

  @override
  String get importSameNameScope => 'この読み込みに含まれる同じ名前には、すべてこの対応を使います';

  @override
  String importGuestChoice(String name) {
    return '「$name」をアカウントなしのままにする';
  }

  @override
  String get importEditDate => '日付を編集';

  @override
  String get importEditDuty => '担当を編集';

  @override
  String get importDutyLabel => '担当';

  @override
  String get importPeopleLines => '名前（1行に1人）';

  @override
  String get importAddEventAction => '特別行事を追加';

  @override
  String get importEditEvent => '特別行事を編集';

  @override
  String get importConflict => '奉仕表が変更されました。差分をもう一度確認してから適用してください。';

  @override
  String get importScopeChanged => '教会またはアカウントが切り替わりました。もう一度読み込んでください。';

  @override
  String importRow(int number) {
    return '$number行目';
  }

  @override
  String get importDateLabel => '日付';

  @override
  String get importDateMissing => '日付を入力してください';

  @override
  String get importFixDuty => '担当を修正';

  @override
  String get importPeopleArrayHint => 'people には名前の配列を入力してください';

  @override
  String get importFixEvent => '特別行事を修正';

  @override
  String importRemoveDuty(String role, String names) {
    return '$roleを外す：$names';
  }

  @override
  String importAddDuty(String role, String names) {
    return '$roleを追加：$names';
  }

  @override
  String importChangeDuty(String role, String before, String after) {
    return '$role：$before → $after';
  }

  @override
  String importMemberIdentity(String name) {
    return '$name（メンバー）';
  }

  @override
  String importGuestIdentity(String name) {
    return '$name（アカウントなし）';
  }

  @override
  String importRemoveEvent(String name) {
    return '特別行事を外す：$name';
  }

  @override
  String importAddEvent(String name) {
    return '特別行事を追加：$name';
  }

  @override
  String importChangeEvent(String name) {
    return '特別行事：$name';
  }

  @override
  String importChangedColor(String before, String after) {
    return '$before → $after';
  }

  @override
  String get importNoChange => '割り当ての変更はありません';

  @override
  String get importNoCandidate => 'アカウントなしのままにするか、名前を修正してください';

  @override
  String importCandidates(String names) {
    return '候補：$names';
  }

  @override
  String get importGuestUnlinked => 'アカウントなし';

  @override
  String get importNameNeedsConfirm => '名前を確認してください';

  @override
  String importLinkedMember(String name) {
    return 'メンバー：$name';
  }

  @override
  String get importMode => '読み込み方法';

  @override
  String get importMerge => '統合（記載のない割り当ては残す）';

  @override
  String get importReplace => 'その日の割り当てをすべて置き換え';

  @override
  String get importReplaceHelp => '記載のない担当と特別行事を外します。ほかの日付には影響しません。';

  @override
  String get importFixData => 'データを修正してから読み込んでください';

  @override
  String get importFixRow => 'この行のデータを修正してください';

  @override
  String get importNameLinks => '名前の対応';

  @override
  String get importNamesNeedConfirm => '名前を確認すると読み込めます';

  @override
  String get importRepairSettings => '教会の設定を修正（任意）';

  @override
  String get importNoSettingsChange => '今回の割り当てでは、メンバーや教会の設定は変わりません';

  @override
  String importAddConfiguredDuty(String role) {
    return '担当を追加：$role';
  }

  @override
  String importUnconfiguredDuty(String role) {
    return '未設定の担当：$role';
  }

  @override
  String importAddCommonEvent(String name) {
    return 'よく使う特別行事に追加：$name';
  }

  @override
  String importNotCommonEvent(String name) {
    return 'よく使う特別行事に未設定：$name';
  }

  @override
  String importDiff(String date) {
    return '適用後の差分・$date';
  }

  @override
  String importRequiredField(String field) {
    return '$fieldを入力してください';
  }

  @override
  String get importColor => '色';

  @override
  String get importIssueRowObject => 'date と duties を含むオブジェクトを入力してください';

  @override
  String get importIssueRowFields => '使える項目は date、duties、events だけです';

  @override
  String get importIssueDate => 'date には有効な YYYY-MM-DD 形式の日付を入力してください';

  @override
  String get importIssueDuplicateDate => '日付が重複しています。1つの行にまとめてください。';

  @override
  String get importIssueDutiesArray => 'duties には配列を入力してください';

  @override
  String importIssueDutyFields(int index) {
    return '$index番目の担当に使える項目は role と people だけです';
  }

  @override
  String importIssueRole(int index) {
    return '$index番目の role には重複しない担当名を入力してください';
  }

  @override
  String importIssuePeopleArray(int index) {
    return '$index番目の people には空白でない名前の文字列配列を入力してください。担当者がいない場合は [] にします。';
  }

  @override
  String importIssueDuplicatePeople(int index) {
    return '$index番目の people に同じ名前を重複させないでください';
  }

  @override
  String get importIssueEventsArray => 'events には配列を入力してください';

  @override
  String importIssueEventObject(int index, String example) {
    return '$index番目の特別行事は $example の形式で入力してください';
  }

  @override
  String importIssueEventName(int index) {
    return '$index番目の特別行事の name には重複しない名前を入力してください';
  }

  @override
  String importIssueEventColor(int index) {
    return '$index番目の特別行事の color には 0〜5 の整数を入力してください';
  }

  @override
  String importIssueResolvedDuplicatePeople(String role) {
    return '$role：確認後に名前が重複しています。重複した名前を削除してください。';
  }

  @override
  String get appRunningVersion => '現在のバージョン';

  @override
  String appVersionWithFix(String version, int patch) {
    return '$version · 修正 $patch';
  }

  @override
  String get appVersionDevelopment => '開発版（リリース版はまだありません）';

  @override
  String get updateRequiredTitle => '「マルタ、ひと休み」をアップデートしてください';

  @override
  String get updateRequiredBody => 'このバージョンは古くなりました。引き続き使うにはアップデートしてください。';

  @override
  String updateRequiredOpen(String store) {
    return '$store でアップデート';
  }

  @override
  String get appUpdateCheck => 'アップデートを確認';

  @override
  String get appUpdateChecking => '確認中…';

  @override
  String get appUpdateApply => '更新して開き直す';

  @override
  String get appUpdateApplying => 'アップデート中…';

  @override
  String get saving => '保存中…';

  @override
  String get appUpdateCurrent => '最新のバージョンです';

  @override
  String get appUpdateReady => '新しいバージョンがあります';

  @override
  String get appUpdateFinishEditing => '保存していない内容があります。保存してから更新してください。';

  @override
  String get appUpdateFinishEditingNote => '先に編集中の内容を保存してください';

  @override
  String get appUpdateFailed => 'アップデートできませんでした。接続を確認して、もう一度お試しください。';

  @override
  String get appUpdateScopeChanged => 'アカウントまたは教会が変わりました。もう一度アップデートを確認してください。';

  @override
  String get appUpdateBackToMe => 'もう一度「更新して開き直す」をタップしてください';

  @override
  String get appUpdateCheckFirst => '先にアップデートを確認してください';

  @override
  String get importExampleRole => '奏楽';

  @override
  String get importExamplePerson => '佐藤 美咲';

  @override
  String get importExampleEvent => '聖餐式';

  @override
  String get rosterShowMore => 'さらに表示';

  @override
  String get rosterShowPrevious => '前回を表示';

  @override
  String get rosterNoEarlier => 'これより前の奉仕表はありません';

  @override
  String get pickerGuestNames => 'アカウントのない名前';

  @override
  String get serviceSettingsSaved => '集会を更新しました';

  @override
  String get serviceSyncOriginalEvent => '元の特別行事';

  @override
  String get serviceSyncOriginalDuty => '元の担当';

  @override
  String serviceFutureSyncTitle(String from, String to) {
    return '「$from」を「$to」に同期';
  }

  @override
  String serviceFutureSyncSaved(int count) {
    return '今後の奉仕表$count件を同期しました';
  }

  @override
  String serviceEventColorTitle(String name) {
    return '$name・色';
  }

  @override
  String get serviceEventColor => '色';

  @override
  String get serviceSyncFutureRosters => '今後の奉仕表を同期';

  @override
  String get rosterFutureChangesNone => '変更が必要な今後の奉仕表はありません';

  @override
  String get rosterFutureChangesFooter => '変更するのは明日以降の保存済みの奉仕表だけです';

  @override
  String get rosterFutureChangesConflict => '同じ名前の項目がすでにあります。先に調整してください。';

  @override
  String get rosterApplyFutureChanges => '変更を適用';

  @override
  String get rosterRemoveFutureGuest => '今後の割り当てを外す';

  @override
  String rosterRemoveFutureGuestTitle(String name) {
    return '「$name」の今後の割り当てを外す';
  }

  @override
  String rosterFutureGuestRemoved(int count) {
    return '今後の割り当てを$count件外しました';
  }

  @override
  String rosterFutureDutyChange(String role, String before, String after) {
    return '$role：$before → $after';
  }

  @override
  String rosterFutureEventChange(String before, String after) {
    return '$before → $after';
  }

  @override
  String get errConflict => 'ほかのメンバーが変更したばかりです。再読み込みしてから、もう一度変更してください。';

  @override
  String get errOfflineReadOnly => 'オフラインです。接続すると保存できます。';

  @override
  String get errTooManyChanges => '一度に変更できる奉仕表は500件までです。何回かに分けて変更してください。';

  @override
  String get undoDone => '元に戻しました';

  @override
  String get undoFailed => '元に戻せませんでした。もう一度お試しください。';

  @override
  String get offlineReadOnlyBanner => 'オフラインです。前回のデータを表示しています。接続すると保存できます。';

  @override
  String get calendarCached => '前回のデータを表示しています';

  @override
  String calendarReadAt(String time) {
    return '$timeに更新';
  }

  @override
  String get calDescription => '行事の説明';

  @override
  String get calDuplicate => '行事を複製';

  @override
  String get homeUpcomingEvents => '近日の行事';

  @override
  String get linkErrNotToday => '取得元に今日の内容がまだありません';

  @override
  String linkSourceToday(String reason) {
    return '今日の内容が更新されていません：$reason';
  }

  @override
  String get linkSourceRetry => '今すぐ更新';

  @override
  String get listSeparator => '、';

  @override
  String labelValue(String label, String value) {
    return '$label：$value';
  }

  @override
  String nameIsYou(String name) {
    return '$name（自分）';
  }

  @override
  String get churchListSeparator => '」「';

  @override
  String dayWithEvents(String day, String events) {
    return '$day、$events';
  }

  @override
  String get dotSeparator => '・';

  @override
  String get churchStatus => '状態';

  @override
  String get timeZone => 'タイムゾーン';

  @override
  String timeZoneChangeTitle(String city) {
    return '$city時間に変更しますか？';
  }

  @override
  String get timeZoneChangeBody => '行事の時刻は新しいタイムゾーンで表示されます。奉仕表の日付は変わりません。';

  @override
  String timeZoneChange(String city) {
    return '$city時間に変更';
  }

  @override
  String churchLocalTime(String city) {
    return '教会の現地時間（$city）';
  }

  @override
  String calendarTimeZoneDiffers(String zone, String city) {
    return 'このカレンダーのタイムゾーンは$zoneで、教会のタイムゾーン（$city）と異なります。カレンダーの時刻は教会のタイムゾーンで表示されます。';
  }

  @override
  String get cityAuckland => 'オークランド';

  @override
  String get citySydney => 'シドニー';

  @override
  String get cityMelbourne => 'メルボルン';

  @override
  String get cityTokyo => '東京';

  @override
  String get citySeoul => 'ソウル';

  @override
  String get cityTaipei => '台北';

  @override
  String get cityHongKong => '香港';

  @override
  String get citySingapore => 'シンガポール';

  @override
  String get cityKualaLumpur => 'クアラルンプール';

  @override
  String get cityLondon => 'ロンドン';

  @override
  String get cityToronto => 'トロント';

  @override
  String get cityNewYork => 'ニューヨーク';

  @override
  String get cityChicago => 'シカゴ';

  @override
  String get cityDenver => 'デンバー';

  @override
  String get cityVancouver => 'バンクーバー';

  @override
  String get cityLosAngeles => 'ロサンゼルス';

  @override
  String get cityBrisbane => 'ブリスベン';

  @override
  String get cityBangkok => 'バンコク';

  @override
  String get cityJakarta => 'ジャカルタ';

  @override
  String get cityBerlin => 'ベルリン';

  @override
  String get cityParis => 'パリ';

  @override
  String get cityPhoenix => 'フェニックス';

  @override
  String get cityHonolulu => 'ホノルル';

  @override
  String get signInMethods => 'ログイン方法';

  @override
  String get signInMethodPassword => 'メールアドレスとパスワード';

  @override
  String get linkGoogle => 'Google アカウントを連携';

  @override
  String get linkedGoogle => 'Google アカウントを連携しました';

  @override
  String get linkApple => 'Apple アカウントを連携';

  @override
  String get linkedApple => 'Apple アカウントを連携しました';

  @override
  String get unlink => '連携を解除';

  @override
  String unlinkTitle(String method) {
    return '$method の連携を解除しますか？';
  }

  @override
  String unlinkBody(String email) {
    return '$email でこのアカウントにログインできなくなります';
  }

  @override
  String get errCredentialInUse => 'そのアカウントはすでに「マルタ、ひと休み」に登録されています。連携するには、先にそのアカウントでログインして削除してください。';

  @override
  String get onlineRefundHeader => 'オンライン応援の返金';

  @override
  String get onlineRefundFooter => '綠界（ECPay）の管理画面で返金したら、その支払いの加盟店注文番号を入力すると、サーバー費用から差し引かれます';

  @override
  String get onlineRefundAdd => '返金を差し引く';

  @override
  String get onlineRefundOrderNo => '加盟店注文番号（特店訂單編號）';

  @override
  String get onlineRefundApply => '差し引く';

  @override
  String onlineRefunded(String month, String amount) {
    return '$month から $amount を差し引きました';
  }

  @override
  String get onlineRefundNotFound => 'その注文番号のオンライン応援は見つかりません。綠界の管理画面で番号を確かめてください。';

  @override
  String get photoAiTitle => 'AIで写真を読み取る';

  @override
  String get photoAiBody => '写真と教会のメンバー名簿を Google の Gemini に送り、奉仕表に読み取ります。Google がこの内容を AI の学習に使うことはありません。';

  @override
  String get photoAiAgree => '同意して続ける';

  @override
  String onlineRefundAlready(String month) {
    return 'この支払いは $month から差し引き済みです';
  }

  @override
  String get identitySmallGroupLead => '小グループリーダー';

  @override
  String identitySmallGroupLeadOf(String group) {
    return '$groupの小グループリーダー';
  }

  @override
  String canSmallGroupLead(String group) {
    return '$groupの行事を管理し、人数を記録し、メンバーを加えたり外したりできる';
  }

  @override
  String get pickSmallGroup => '小グループを選ぶ';

  @override
  String get smallGroups => '小グループ';

  @override
  String get addSmallGroup => '小グループを追加';

  @override
  String get smallGroupName => '小グループ名';

  @override
  String get smallGroupService => '所属';

  @override
  String get smallGroupMeets => '集まる日';

  @override
  String get meetsNotSet => '未設定';

  @override
  String meetsWeekly(String weekday) {
    return '毎週$weekday';
  }

  @override
  String meetsBiweekly(String weekday) {
    return '隔週$weekday';
  }

  @override
  String get meetsEveryWeek => '毎週';

  @override
  String get meetsEveryOtherWeek => '隔週';

  @override
  String get nextMeeting => '次の集まり';

  @override
  String get assignSmallGroupLead => 'リーダーを指名';

  @override
  String get smallGroupLeadUnassigned => '未指名';

  @override
  String get smallGroupLeadClear => '指名を取り消す';

  @override
  String get deleteSmallGroup => '小グループを閉じる';

  @override
  String deleteSmallGroupTitle(String name) {
    return '「$name」を閉じますか？';
  }

  @override
  String get deleteSmallGroupBody => 'リーダーとメンバーはこの小グループから外れますが、記録した人数は残ります';

  @override
  String smallGroupDeleted(String name) {
    return '「$name」を閉じました';
  }

  @override
  String inSmallGroup(String group) {
    return '$groupのメンバー';
  }

  @override
  String get attendance => '人数の記録';

  @override
  String get attendanceSub => '集まりの日の21時に、リーダーに何人来たかの記録をお知らせします';

  @override
  String get attendanceHeader => '人数';

  @override
  String attendanceCount(int count) {
    return '$count人';
  }

  @override
  String get attendanceMissing => '未記入';

  @override
  String get attendanceNone => '集まりなし';

  @override
  String get attendanceFill => '人数を記録';

  @override
  String get attendanceCountField => '人数';

  @override
  String get attendanceNote => 'メモ';

  @override
  String get attendanceNoMeeting => '今回は集まりなし';

  @override
  String get attendanceSkip => '集まらない回';

  @override
  String attendanceSkipping(int count) {
    return 'この先 $count 回は集まりなし';
  }

  @override
  String get attendanceSkipFooter => 'チェックした回はお知らせせず、「未記入」も残りません';

  @override
  String get attendanceNoDays => '記録する集まりはまだありません';

  @override
  String attendanceNext(String day) {
    return '次の集まり $day';
  }

  @override
  String get attendanceNoMeets => '集まりの日時がまだ未設定';

  @override
  String get attendanceOtherDay => '別の日に集まった';

  @override
  String get attendanceSaved => '記録しました';

  @override
  String get attendanceOff => 'オフ';

  @override
  String attendanceOverviewMissing(int count) {
    return '未記入が$count件あります';
  }

  @override
  String get attendanceOverviewDone => 'すべて記録済み';

  @override
  String get attendanceRemind => '知らせる';

  @override
  String get attendanceRemindSent => '知らせました';

  @override
  String get attendanceRemindNobody => '知らせるリーダーがいません。直接連絡してください';

  @override
  String get attendanceEveryWeek => '毎週記録する';

  @override
  String get attendanceEveryWeekSub => '当番表がない日も記録します';

  @override
  String get attendanceTogether => '一緒に集まった小グループ';

  @override
  String attendanceWith(String name) {
    return '$nameと一緒';
  }

  @override
  String get errRemindedToday => '今日はすでに知らせました';

  @override
  String get errTogetherFilled => '選んだ小グループはその日の人数が記録済みです';

  @override
  String get notifAttendance => '人数の記録のお知らせ';

  @override
  String get notifAttendanceSub => '集まりの日と翌日の21時に、まだ誰も記録していないとき';

  @override
  String get churchEntryCanAsk => 'まだこの教会のメンバーではありません。参加を申請すると、管理者が承認したときに参加できます。';

  @override
  String get askToJoin => '参加を申請';

  @override
  String askToJoinTitle(String church) {
    return '$churchへの参加を申請';
  }

  @override
  String get joinNoteLabel => '管理者へのメッセージ（任意）';

  @override
  String get joinNoteHint => '例：賛美チームのミンです';

  @override
  String get joinRequestSent => '申請を送信しました';

  @override
  String get joinRequestPending => '申請を送信しました。管理者が承認すると参加できます。';

  @override
  String welcomeAskedToJoin(String church) {
    return '$churchに参加を申請しました。管理者の承認待ちです。';
  }

  @override
  String get withdrawJoinRequest => '申請を取り消す';

  @override
  String get joinRequestWithdrawn => '申請を取り消しました';

  @override
  String get joinRequestRejected => '今回の申請は承認されませんでした。教会に直接お問い合わせください。';

  @override
  String get askAgain => 'もう一度申請';

  @override
  String get joinVerifyFirst => '参加を申請するには、メールアドレスの確認が必要です';

  @override
  String joinRequestsCount(int count) {
    return '$count人が参加を申請';
  }

  @override
  String joinRequestAskedOn(String date) {
    return '$dateに申請';
  }

  @override
  String get allowJoin => '承認';

  @override
  String get declineJoin => '拒否';

  @override
  String allowJoinLabel(String name) {
    return '$nameの参加を承認';
  }

  @override
  String declineJoinLabel(String name) {
    return '$nameの申請を拒否';
  }

  @override
  String joinAllowedToast(String name) {
    return '$nameが参加しました';
  }

  @override
  String joinDeclinedToast(String name) {
    return '$nameの申請を拒否しました';
  }

  @override
  String get errRequestsClosed => 'この教会は参加申請を受け付けていません。管理者に招待リンクをもらってください。';

  @override
  String get errRequestGone => 'この申請は取り消されたか、期限が切れています';

  @override
  String get takesJoinRequests => '参加申請を受け付ける';

  @override
  String get takesJoinRequestsFooter => '教会の URL を知っている人が申請でき、管理者が承認すると参加します';

  @override
  String get notifJoinRequest => '参加申請';

  @override
  String get notifJoinRequestSub => '誰かが参加を申請したとき（管理者のみ）';

  @override
  String get notifListEmpty => '過去30日間の通知はありません';

  @override
  String get notifSettings => '通知設定';

  @override
  String get notifUnread => '未読';

  @override
  String get notifUnreadLabel => '通知、未読あり';

  @override
  String get notifJustNow => 'たった今';

  @override
  String notifMinutesAgo(int count) {
    return '$count分前';
  }

  @override
  String notifHoursAgo(int count) {
    return '$count時間前';
  }

  @override
  String get planWeeksAction => '奉仕を割り当てる';

  @override
  String get planWeeksTitle => '奉仕を割り当てる';

  @override
  String planWeeksTitleOne(String duty) {
    return '$dutyを割り当てる';
  }

  @override
  String get planWeeksHint => '「完了」を押すと通知されます';

  @override
  String get planNotYetTold => 'ここで担当に入った人・外れた人にはまだ通知していません';

  @override
  String get planNotifyNow => '通知する';

  @override
  String planNotified(int count) {
    return '$count人に通知しました';
  }

  @override
  String planNotifiedLater(int count) {
    return '朝7時に$count人に通知します';
  }

  @override
  String get planShowEarlier => '前の月を表示';

  @override
  String planOpenDay(String day) {
    return '$dayを開く';
  }

  @override
  String pickerMonthCount(int count) {
    return '今月すでに$count回';
  }

  @override
  String pickerSameDay(String what) {
    return '同じ日：$what';
  }

  @override
  String gettingStartedAs(String identity) {
    return 'はじめに · $identity';
  }

  @override
  String get gettingStartedArrange => '奉仕表を組む';

  @override
  String get gettingStartedArrangeBody => '数週間分をまとめて組み、最後に一度だけ通知しましょう';

  @override
  String gettingStartedAddStaff(String group) {
    return '$groupにメンバーを加える';
  }

  @override
  String gettingStartedPlan(String service) {
    return '$serviceの奉仕を組む';
  }

  @override
  String gettingStartedMeets(String group) {
    return '$groupの集まる日を決める';
  }

  @override
  String get gettingStartedAddStaffAny => '集会にメンバーを加える';

  @override
  String get gettingStartedSmallGroups => '小グループを作る';

  @override
  String get gettingStartedSmallGroupsBody => '任意 · リーダーが自分のメンバーを加え、人数を報告します';

  @override
  String get gettingStartedInviteWaiting => '招待済み、メンバーの参加待ち';

  @override
  String get gettingStartedAfterJoin => 'メンバーが参加してからできます';

  @override
  String get gettingStartedDone => '完了';

  @override
  String gettingStartedNext(String step) {
    return '次へ：$step';
  }

  @override
  String get gettingStartedHide => '今後表示しない';

  @override
  String get guides => '使い方ガイド';

  @override
  String get howToUse => '使い方';

  @override
  String get discardChangesTitle => '変更を破棄しますか？';

  @override
  String get discardChanges => '変更を破棄';

  @override
  String get keepEditing => '編集を続ける';

  @override
  String get ministriesChurchWide => '教会全体のミニストリー';

  @override
  String get ministryNeedsDuties => '担当を選ぶと、リーダーが集会や行事でそれを割り当てられます';

  @override
  String ministryLeadsCan(int count, String leads, String duties) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$leadsはそれぞれ$dutiesを割り当て、その担当の名簿を変えられます',
      one: '$leadsは$dutiesを割り当て、その担当の名簿を変えられます',
    );
    return '$_temp0';
  }

  @override
  String ministryOnceLeads(String duties) {
    return 'リーダーを指名すると、$dutiesを割り当て、その担当の名簿を変えられます';
  }

  @override
  String dutiesOfServices(String services, String duties) {
    return '$servicesの$duties';
  }

  @override
  String get dutyGroupSeparator => '；';

  @override
  String get ministryEvents => '行事';

  @override
  String get addAnotherLead => 'リーダーをもう一人指名';

  @override
  String get unavailableTitle => '奉仕できない日';

  @override
  String get unavailableHint => '日をタップすると終日奉仕できない日になり、もう一度タップで解除。長押しして数日なぞると期間で入力できます。奉仕を割り当てる人だけが見られます。';

  @override
  String get unavailableAddRange => '期間を追加';

  @override
  String get unavailableFirstDay => '最初の日';

  @override
  String get unavailableLastDay => '最後の日';

  @override
  String get unavailableMarked => '入力した日';

  @override
  String get unavailableNote => '理由';

  @override
  String get unavailableNoteHint => '任意（例：旅行）';

  @override
  String get unavailableNoteFooter => 'タップすると理由を書けます。奉仕を割り当てる人が選ぶときに見えます';

  @override
  String get unavailableServing => 'この日はすでに奉仕が入っています';

  @override
  String get unavailableServingFooter => 'リーダーには、この日は奉仕できないと表示されます';

  @override
  String get pickerUnavailable => 'この日は不可';

  @override
  String pickerUnavailableBecause(String note) {
    return 'この日は不可：$note';
  }

  @override
  String dutyUpdatedUnavailable(String duty, String names) {
    return '$dutyを更新しました・$namesはこの日は不可';
  }

  @override
  String get planAskUnavailable => '奉仕できない日の入力を依頼';

  @override
  String planAskedLast(String date) {
    return '前回の依頼 $date';
  }

  @override
  String get planAskUntil => '何月までの分ですか？';

  @override
  String planAskConfirm(int count, String months) {
    return '$count人のメンバーに$monthsの奉仕できない日の入力を依頼しますか？';
  }

  @override
  String planAskMonths(String from, String to) {
    return '$from〜$to';
  }

  @override
  String get planAskSend => '依頼する';

  @override
  String get notifSwap => '代わり・交換';

  @override
  String get notifSwapSub => '代わり・交換・奉仕できない日の入力';

  @override
  String get swapMenu => '代わり・交換';

  @override
  String get swapAskCover => '代わりを頼む';

  @override
  String get swapAskCoverSub => 'その日に空いているリストのメンバーに送られ、最初に「引き受ける」を押した人が担当します';

  @override
  String get swapAskSwap => '別の週と交換';

  @override
  String get swapAskSwapSub => '日とその日の人を選び、相手が受けたら交換します';

  @override
  String swapAskedCover(int count) {
    return '$count人のメンバーに頼みました。引き受けた人がいたら通知します。';
  }

  @override
  String swapAskedSwap(String name) {
    return '$nameさんに頼みました。受けてもらえたら交換します。';
  }

  @override
  String swapPickTitle(String duty) {
    return '$dutyを誰と交換しますか？';
  }

  @override
  String get swapNoDays => 'この先、この担当に入っている人はいません';

  @override
  String get swapPendingCover => '代わりを頼んでいます。まだ引き受けた人はいません。';

  @override
  String swapPendingSwap(String name) {
    return '$nameさんに交換を頼んでいます。まだ返事はありません。';
  }

  @override
  String get swapWithdraw => '取り下げる';

  @override
  String get swapWithdrawn => '取り下げました';

  @override
  String get swapRequestTitle => '代わり・交換';

  @override
  String swapCoverAsks(String name) {
    return '$nameさんから代わりを頼まれています';
  }

  @override
  String swapSwapAsks(String name) {
    return '$nameさんが交換を希望しています';
  }

  @override
  String get swapYouGet => 'あなたの担当';

  @override
  String swapTheyGet(String name) {
    return '$nameさんの担当';
  }

  @override
  String get swapTake => '引き受ける';

  @override
  String get swapAccept => '受ける';

  @override
  String get swapDecline => '都合が悪い';

  @override
  String get swapTook => '引き受けました';

  @override
  String get swapTraded => '交換しました';

  @override
  String get swapDeclined => '都合が悪いと返事しました';

  @override
  String swapStatusTaken(String name) {
    return '$nameさんが引き受けました';
  }

  @override
  String get swapStatusMine => 'あなたが引き受けました';

  @override
  String swapStatusWithdrawn(String name) {
    return '$nameさんがこの依頼を取り下げました';
  }

  @override
  String get swapStatusVoided => 'この依頼は無効になりました。奉仕表が変わったか、日付が過ぎました。';

  @override
  String get swapStatusDeclined => '都合が悪いと返事しました';

  @override
  String get errSwapClosed => 'この依頼はもう終わっています';

  @override
  String get errNobodyToAsk => 'その日に空いているリストのメンバーがいません。リーダーに相談してください。';

  @override
  String get swapOutCover => '代わりを依頼中';

  @override
  String get swapOutSwap => '交換を依頼中';
}
