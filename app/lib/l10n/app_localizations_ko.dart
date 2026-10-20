// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class L10nKo extends L10n {
  L10nKo([String locale = 'ko']) : super(locale);

  @override
  String get appName => '마르다의 쉼표';

  @override
  String get tabHome => '홈';

  @override
  String get tabRosters => '봉사표';

  @override
  String get tabCalendar => '캘린더';

  @override
  String get tabSettings => '설정';

  @override
  String get undo => '실행 취소';

  @override
  String get cancel => '취소';

  @override
  String get save => '저장';

  @override
  String get done => '완료';

  @override
  String get retry => '다시 시도';

  @override
  String get search => '검색';

  @override
  String get clear => '지우기';

  @override
  String get selected => '선택됨';

  @override
  String get close => '닫기';

  @override
  String get add => '추가';

  @override
  String get delete => '삭제';

  @override
  String get edit => '편집';

  @override
  String get deleted => '삭제했어요';

  @override
  String get loadFailed => '불러오지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.';

  @override
  String get saveFailed => '저장하지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.';

  @override
  String get noPermission => '이 작업을 할 권한이 없어요';

  @override
  String get comingSoon => '아직 준비 중이에요';

  @override
  String get signInWithGoogle => 'Google로 로그인';

  @override
  String get signInWithApple => 'Apple로 로그인';

  @override
  String get signInWithEmail => '이메일로 로그인';

  @override
  String inAppBrowserNote(String app) {
    return '$app에서는 Google 로그인을 할 수 없어요. Safari나 Chrome에서 이 페이지를 열거나 이메일로 로그인해 주세요.';
  }

  @override
  String get copyPageUrl => '링크 복사';

  @override
  String get pageUrlCopied => '링크를 복사했어요. Safari나 Chrome에 붙여넣어 열어 주세요.';

  @override
  String get loginTagline =>
      '마르다야 마르다야\n네가 많은 일로 염려하고 근심하나\n몇 가지만 하든지\n혹은 한 가지만이라도 족하니라\n마리아는 이 좋은 편을 택하였으니\n빼앗기지 아니하리라';

  @override
  String get loginTaglineSource => '누가복음 10:41–42 (개역개정)';

  @override
  String loginInvitedTo(String church) {
    return '$church에 초대받았어요';
  }

  @override
  String get email => '이메일';

  @override
  String get password => '비밀번호';

  @override
  String get yourName => '이름';

  @override
  String get signIn => '로그인';

  @override
  String get register => '회원가입';

  @override
  String get createAccount => '새 계정 만들기';

  @override
  String get haveAccount => '이미 계정이 있나요? 로그인';

  @override
  String get forgotPassword => '비밀번호 찾기';

  @override
  String resetSent(String email) {
    return '$email 주소로 비밀번호 재설정 메일을 보냈어요';
  }

  @override
  String get errInvalidCredential => '이메일 또는 비밀번호가 맞지 않아요';

  @override
  String get errEmailInUse => '이미 가입된 이메일이에요. 바로 로그인하거나 Google로 로그인해 주세요.';

  @override
  String get errWeakPassword => '비밀번호는 6자 이상이어야 해요';

  @override
  String get errInvalidEmail => '이메일 형식이 올바르지 않아요';

  @override
  String get errNeedsLink => '이미 계정이 있는 이메일이에요. 원래 쓰던 방법으로 로그인하면 계정이 자동으로 연결돼요.';

  @override
  String get errTooMany => '시도 횟수가 너무 많아요. 잠시 후 다시 시도해 주세요.';

  @override
  String get errNetwork => '인터넷에 연결할 수 없어요. 확인 후 다시 시도해 주세요.';

  @override
  String get errUnknown => '문제가 생겼어요. 다시 시도해 주세요.';

  @override
  String get nameRequired => '이름을 입력해 주세요';

  @override
  String get emailRequired => '이메일을 입력해 주세요';

  @override
  String get verifyEmailTitle => '이메일 인증';

  @override
  String verifyEmailBody(String email) {
    return '$email 주소로 인증 메일을 보냈어요. 메일의 링크를 누른 뒤 여기로 돌아와 주세요.';
  }

  @override
  String get verifyResend => '인증 메일 재전송';

  @override
  String get verifyResent => '다시 보냈어요';

  @override
  String get verifyDone => '인증했어요';

  @override
  String get verifyStill => '아직 인증되지 않았어요. 메일의 링크를 눌러 주세요.';

  @override
  String get welcomeTitle => '교회에 가입하기';

  @override
  String get welcomeBody => '교회 관리자에게 초대 링크를 요청해 주세요';

  @override
  String get enterInviteCode => '초대 코드 입력';

  @override
  String get createChurch => '새 교회 만들기';

  @override
  String get signOut => '로그아웃';

  @override
  String get inviteCode => '초대 코드';

  @override
  String get next => '다음';

  @override
  String get churchName => '교회 이름';

  @override
  String get createChurchVerifyFirst => '이메일을 인증해야 교회를 만들 수 있어요';

  @override
  String get create => '만들기';

  @override
  String get errDuplicateName => '같은 이름의 교회가 이미 있어요. 다른 사람이 먼저 등록한 것이라면 문의해 주세요.';

  @override
  String get contactUs => '문의하기';

  @override
  String joinTitle(String church) {
    return '$church에 가입';
  }

  @override
  String get join => '가입';

  @override
  String joined(String church) {
    return '$church에 가입했어요';
  }

  @override
  String alreadyMember(String church) {
    return '이미 $church의 멤버예요';
  }

  @override
  String get errInviteInvalid => '초대를 찾을 수 없어요. 초대 코드를 확인하거나 관리자에게 새 초대를 요청해 주세요.';

  @override
  String get errInviteExpired => '만료된 초대예요. 관리자에게 새 초대를 요청해 주세요.';

  @override
  String get errChurchClosed => '사용이 중지된 교회예요';

  @override
  String churchSuspendedTitle(String church) {
    return '$church 사용 중지됨';
  }

  @override
  String get churchSuspendedBody => '궁금한 점은 교회 관리자에게 문의해 주세요';

  @override
  String churchDeletedTitle(String church) {
    return '$church 삭제됨';
  }

  @override
  String churchDeletedBody(String date) {
    return '관리자가 $date 전까지 복원할 수 있어요';
  }

  @override
  String get churchDeletedExpired => '30일이 지나서 더 이상 복원할 수 없어요';

  @override
  String get churchUnavailable => '이 교회를 열 수 없어요';

  @override
  String get restoreChurch => '교회 복원';

  @override
  String get churchRestored => '교회를 복원했어요';

  @override
  String get switchChurch => '교회 전환';

  @override
  String get myServicesTitle => '다가오는 내 봉사';

  @override
  String get noUpcomingServices => '예정된 봉사가 없어요. 봉사가 배정되면 여기에 표시돼요.';

  @override
  String get viewRosters => '봉사표 보기';

  @override
  String get gettingStarted => '시작하기';

  @override
  String get inviteMembers => '멤버 초대';

  @override
  String get gettingStartedInviteBody => '초대 링크를 만들어 멤버에게 보내 주세요';

  @override
  String get gettingStartedServices => '봉사 설정';

  @override
  String get gettingStartedServicesBody => '요일과 배정할 담당 정하기';

  @override
  String get nobodyYet => '미정';

  @override
  String get noServicesConfigured => '아직 설정된 예배가 없어요';

  @override
  String get setUpServices => '예배 설정';

  @override
  String get noRostersAhead => '예정된 예배가 없어요';

  @override
  String get rostersNobodyArranged => '아직 아무도 배정되지 않았어요';

  @override
  String get rostersStartArranging => '배정 시작하기';

  @override
  String get rostersImportPhoto => '사진으로 가져오기';

  @override
  String get today => '오늘';

  @override
  String get tomorrow => '내일';

  @override
  String get offlineShowingCached => '오프라인이에요. 마지막으로 불러온 내용을 보여 드려요.';

  @override
  String dutyCount(int count) {
    return '담당 $count개';
  }

  @override
  String get addDuty => '담당 추가';

  @override
  String get dutyName => '담당 이름';

  @override
  String get removeDuty => '이 담당 빼기';

  @override
  String dutyRemoved(String duty) {
    return '$duty 담당을 뺐어요';
  }

  @override
  String dutyUpdated(String duty) {
    return '$duty 담당을 수정했어요';
  }

  @override
  String pickerServes(String duty) {
    return '$duty 담당했던 멤버';
  }

  @override
  String get pickerOthers => '다른 멤버';

  @override
  String pickerUseName(String name) {
    return '‘$name’ 사용';
  }

  @override
  String pickerNoOneServes(String duty) {
    return '아직 $duty 담당자가 없어요';
  }

  @override
  String get pickerLearns => '이 예배의 멤버는 한 번 배정하면 다음부터 위쪽에 표시돼요';

  @override
  String pickerNoResults(String query) {
    return '‘$query’ 검색 결과가 없어요';
  }

  @override
  String get pickerSearchHint => '멤버 검색';

  @override
  String get reorder => '순서 변경';

  @override
  String get reorderHint => '드래그해서 순서를 바꿔 주세요. 매주 이 순서대로 표시돼요.';

  @override
  String get editListHint => '드래그해서 순서를 바꿔요. 뺀 사람도 검색하면 찾을 수 있어요.';

  @override
  String pickerTakeOff(String name) {
    return '$name 님을 목록에서 빼기';
  }

  @override
  String dutyListRemoved(String duty, String names) {
    return '$duty 목록에서 $names 님을 뺐어요';
  }

  @override
  String get orderSaved => '순서를 변경했어요';

  @override
  String get swap => '교환';

  @override
  String swapWith(String duty) {
    return '$duty 담당을 누구와 바꿀까요?';
  }

  @override
  String get swapNone => '다른 날짜에 바꿀 수 있는 사람이 없어요';

  @override
  String swapped(String a, String b) {
    return '$a, $b 자리를 바꿨어요';
  }

  @override
  String moved(String name, String day) {
    return '$name 님을 $day 봉사로 옮겼어요';
  }

  @override
  String get emptySlot => '미정';

  @override
  String removeFromDuty(String duty) {
    return '$duty 담당에서 빼기';
  }

  @override
  String get events => '특별 순서';

  @override
  String get eventsUpdated => '특별 순서를 업데이트했어요';

  @override
  String get customEvent => '직접 입력';

  @override
  String get addEvent => '특별 순서 추가';

  @override
  String get eventName => '특별 순서 이름';

  @override
  String get addToCommon => '자주 쓰는 항목에 추가';

  @override
  String get eventColor => '색상';

  @override
  String get colorName0 => '빨강';

  @override
  String get colorName1 => '주황';

  @override
  String get colorName2 => '노랑';

  @override
  String get colorName3 => '초록';

  @override
  String get colorName4 => '파랑';

  @override
  String get colorName5 => '보라';

  @override
  String removed(String name) {
    return '‘$name’을(를) 뺐어요';
  }

  @override
  String get name => '이름';

  @override
  String get nameSaved => '이름을 변경했어요';

  @override
  String get language => '언어';

  @override
  String get languageSystem => '시스템 언어 사용';

  @override
  String get churchInfo => '교회 정보';

  @override
  String get manageChurch => '교회 관리';

  @override
  String get lineCommunity => 'LINE 오픈채팅';

  @override
  String get lineCommunityNote => '질문하고, 문제를 알리고, 다른 교회와 이야기해요';

  @override
  String get members => '멤버';

  @override
  String get serviceSettings => '봉사 설정';

  @override
  String get invites => '초대';

  @override
  String get notifications => '알림';

  @override
  String get account => '계정';

  @override
  String get about => '마르다의 쉼표 정보';

  @override
  String get deleteAccount => '계정 삭제';

  @override
  String get privacyPolicy => '개인정보 처리방침';

  @override
  String get termsOfService => '서비스 이용약관';

  @override
  String get developer => '개발자';

  @override
  String get components => '컴포넌트';

  @override
  String get testCrash => '크래시 테스트';

  @override
  String get operatorConsole => '플랫폼 관리';

  @override
  String get leaveChurch => '교회 나가기';

  @override
  String leaveChurchTitle(String church) {
    return '$church에서 나갈까요?';
  }

  @override
  String get leaveChurchBody => '다시 돌아오려면 새 초대가 필요해요';

  @override
  String get leave => '교회 나가기';

  @override
  String leftChurch(String church) {
    return '$church에서 나갔어요';
  }

  @override
  String get adminCannotLeave => '관리자는 바로 나갈 수 없어요. 다른 멤버를 관리자로 지정한 뒤, 그 멤버에게 내 관리자 권한을 해제해 달라고 요청해 주세요.';

  @override
  String get churchLogo => '교회 로고';

  @override
  String get uploadLogo => '로고 업로드';

  @override
  String get changeLogo => '로고 변경';

  @override
  String get logoUploaded => '로고를 변경했어요';

  @override
  String get logoTooLarge => '이미지가 너무 커요. 1MB 이하의 이미지를 선택해 주세요.';

  @override
  String get logoNotImage => '이미지를 선택해 주세요';

  @override
  String memberCount(int count) {
    return '멤버 $count명';
  }

  @override
  String get membersOnlyYou => '아직 다른 멤버가 없어요';

  @override
  String get deleteChurch => '교회 삭제';

  @override
  String deleteChurchTitle(String church) {
    return '$church을(를) 삭제할까요?';
  }

  @override
  String get deleteChurchBody => '모든 멤버가 이 교회를 볼 수 없게 돼요. 30일 안에 복원할 수 있고, 그 후에는 데이터가 영구 삭제돼요.';

  @override
  String get roleAdmin => '관리자';

  @override
  String get role => '역할';

  @override
  String get identityOffice => '행정';

  @override
  String get identityPastor => '목회자';

  @override
  String get identityPastorChurch => '목회자 · 교회 전체';

  @override
  String identityPastorOf(String services) {
    return '목회자 · $services';
  }

  @override
  String identityLeadOf(String group) {
    return '$group 리더';
  }

  @override
  String get identityLead => '리더';

  @override
  String get identityServiceLead => '예배 리더';

  @override
  String get identityMinistryLead => '사역팀 리더';

  @override
  String get canAdmin => '모든 것을 관리할 수 있어요';

  @override
  String get canOffice => '모든 봉사표와 일정을 편집할 수 있지만 멤버와 설정은 관리할 수 없어요';

  @override
  String canServiceLead(String service) {
    return '$service의 봉사표를 편집하고 멤버를 추가하거나 뺄 수 있어요';
  }

  @override
  String canMinistryLead(String ministry) {
    return '$ministry의 담당을 배정하고 멤버를 추가하거나 뺄 수 있어요';
  }

  @override
  String get canStaff => '멤버: 모든 봉사표와 일정을 볼 수 있어요';

  @override
  String get addIdentity => '역할 추가';

  @override
  String get addAnotherIdentity => '하나 더 추가';

  @override
  String identityRemoved(String identity) {
    return '‘$identity’ 뺐어요';
  }

  @override
  String identityAdded(String identity) {
    return '‘$identity’ 추가함';
  }

  @override
  String get wholeChurch => '교회 전체';

  @override
  String get pickPastorScope => '목회 범위';

  @override
  String get pickService => '예배 선택';

  @override
  String get pickMinistry => '사역팀 선택';

  @override
  String get groupsTitle => '예배와 사역팀';

  @override
  String get ministries => '사역팀';

  @override
  String get addMinistry => '사역팀 추가';

  @override
  String get ministryName => '사역팀 이름';

  @override
  String get ministryDuties => '담당';

  @override
  String get ministryDutiesNone => '없음';

  @override
  String get ministryDutiesFooter => '리더는 어느 예배나 일정에서든 이 담당을 배정할 수 있어요';

  @override
  String get noMinistries => '아직 사역팀이 없어요. 예: 찬양팀, 음향팀';

  @override
  String get deleteMinistry => '사역팀 삭제';

  @override
  String ministryDeleted(String name) {
    return '‘$name’ 삭제함';
  }

  @override
  String get leads => '리더';

  @override
  String get noLeads => '아직 리더가 없어요';

  @override
  String get assignLead => '리더 지정';

  @override
  String get groupStaff => '멤버';

  @override
  String get noGroupStaff => '아직 멤버가 없어요';

  @override
  String groupCandidates(String group) {
    return '$group에서 봉사했지만 아직 멤버가 아닌 사람';
  }

  @override
  String groupCandidateServed(String duty, int count) {
    return '$duty $count회';
  }

  @override
  String get addAsStaff => '멤버로 추가';

  @override
  String addAsStaffLabel(String name, String group) {
    return '$name을(를) $group 멤버로 추가';
  }

  @override
  String removeFromGroup(String group) {
    return '$group에서 빼기';
  }

  @override
  String addedToGroup(String name, String group) {
    return '$name을(를) $group 멤버로 추가했어요';
  }

  @override
  String removedFromGroup(String name, String group) {
    return '$name을(를) $group에서 뺐어요';
  }

  @override
  String get myGroups => '내가 맡은 것';

  @override
  String get removeShort => '빼기';

  @override
  String removeIdentityLabel(String identity) {
    return '‘$identity’ 빼기';
  }

  @override
  String get moveOutShort => '빼기';

  @override
  String removeFromGroupLabel(String name, String group) {
    return '$name을(를) $group에서 빼기';
  }

  @override
  String get addGroupStaff => '멤버 추가';

  @override
  String get zones => '소속 예배와 담당';

  @override
  String get zonesFooter => '봉사표 편집 권한이 있어도 소속 예배의 봉사표만 편집할 수 있어요';

  @override
  String get removeMember => '멤버 내보내기';

  @override
  String memberRemoved(String name) {
    return '$name 님을 내보냈어요';
  }

  @override
  String get memberSaved => '저장했어요';

  @override
  String get searchMembers => '멤버 검색';

  @override
  String get noMembersFound => '멤버를 찾을 수 없어요';

  @override
  String get you => '나';

  @override
  String get inviteCreate => '초대 링크 만들기';

  @override
  String get inviteValidFor => '유효 기간';

  @override
  String inviteDays(int days) {
    return '$days일 동안 유효';
  }

  @override
  String get inviteCopy => '링크 복사';

  @override
  String get inviteCopied => '초대 링크를 복사했어요';

  @override
  String get copyByHand => '자동으로 복사하지 못했어요. 아래 텍스트를 선택해 직접 복사해 주세요.';

  @override
  String get inviteShare => '공유';

  @override
  String get inviteRevoke => '철회';

  @override
  String get inviteRevoked => '철회했어요';

  @override
  String inviteExpiresOn(String date) {
    return '$date 만료';
  }

  @override
  String get inviteNone => '아직 초대 링크가 없어요';

  @override
  String inviteMessage(String church, String link) {
    return '$church 봉사표에 초대합니다: $link';
  }

  @override
  String get servicesTitle => '예배';

  @override
  String get serviceAdd => '예배 추가';

  @override
  String get serviceName => '예배 이름';

  @override
  String get weekday => '요일';

  @override
  String get serviceEnabled => '진행 중';

  @override
  String get serviceDisabledFooter => '중지된 예배에는 새 봉사표가 생기지 않아요. 기존 봉사표는 남아 있어요.';

  @override
  String get templateDuties => '담당';

  @override
  String get templateFooter => '새 봉사표에 이 담당들이 들어가요. 이미 만든 봉사표는 바뀌지 않아요.';

  @override
  String get commonEvents => '자주 쓰는 특별 순서';

  @override
  String get rename => '이름 변경';

  @override
  String get remove => '빼기';

  @override
  String get moveUp => '위로 이동';

  @override
  String get moveDown => '아래로 이동';

  @override
  String get saved => '저장했어요';

  @override
  String get weekday1 => '월';

  @override
  String get weekday2 => '화';

  @override
  String get weekday3 => '수';

  @override
  String get weekday4 => '목';

  @override
  String get weekday5 => '금';

  @override
  String get weekday6 => '토';

  @override
  String get weekday7 => '일';

  @override
  String get deleteAccountTitle => '계정을 삭제할까요?';

  @override
  String get deleteAccountBody => '모든 교회에서 나가고, 계정과 개인정보가 영구 삭제돼요. 봉사표에 있는 이름은 남아요.';

  @override
  String deleteAccountLastAdmin(String churches) {
    return '$churches의 유일한 관리자예요. 먼저 다른 멤버를 관리자로 지정해 주세요.';
  }

  @override
  String get goToMembers => '멤버로 이동';

  @override
  String get accountDeleted => '계정을 삭제했어요';

  @override
  String get serviceDisabled => '중지됨';

  @override
  String get adminSearchHint => '교회 이름 또는 ID';

  @override
  String get adminNoChurches => '교회를 찾을 수 없어요';

  @override
  String get adminStats => '통계';

  @override
  String get adminChurches => '교회';

  @override
  String get adminRename => '이름 변경';

  @override
  String get adminMakeAdmin => '관리자로 지정';

  @override
  String adminMadeAdmin(String name) {
    return '$name 님을 관리자로 지정했어요';
  }

  @override
  String get adminSuspend => '교회 사용 중지';

  @override
  String get adminReopen => '교회 사용 재개';

  @override
  String adminSuspendTitle(String church) {
    return '$church 사용을 중지할까요?';
  }

  @override
  String get adminSuspendBody => '모든 멤버에게 바로 사용 중지 화면이 표시돼요';

  @override
  String get statusActive => '사용 중';

  @override
  String get statusSuspended => '중지됨';

  @override
  String get statusDeleted => '삭제됨';

  @override
  String get statsUsers => '사용자';

  @override
  String get statsChurches => '교회';

  @override
  String get statsMembers => '멤버';

  @override
  String get statsRosters => '봉사표';

  @override
  String get statsReads => 'Firestore 읽기';

  @override
  String get statsWrites => 'Firestore 쓰기';

  @override
  String get statsCost => '예상 비용(USD)';

  @override
  String get statsNone => '아직 통계가 없어요';

  @override
  String get statsMoreInConsole => '사용 현황과 오류 정보는 Firebase 콘솔에서 볼 수 있어요';

  @override
  String get notifReminder => '봉사 알림';

  @override
  String get notifReminderWeeklySub => '매주 월요일 저녁, 이번 주 봉사 목록';

  @override
  String get notifReminderDayBeforeSub => '봉사 전날 저녁에 알려 드려요';

  @override
  String get notifReminderBothSub => '매주 월요일 저녁과 봉사 전날 저녁';

  @override
  String get notifReminderTime => '봉사 알림 시간';

  @override
  String get notifReminderWeekly => '매주 월요일 저녁';

  @override
  String get notifReminderDayBefore => '전날 저녁';

  @override
  String get notifReminderBoth => '둘 다';

  @override
  String get notifReminderTimeFooter => '모두 저녁 7시에 보내요';

  @override
  String get notifRosterChange => '봉사표 변경';

  @override
  String get notifRosterChangeSub => '내가 봉사에 배정되거나 빠졌을 때. 밤 10시 이후의 변경은 아침 7시에 알려요.';

  @override
  String get notifMemberLeft => '멤버 나감';

  @override
  String get notifMemberLeftSub => '누군가 교회에서 나갔을 때(관리자만)';

  @override
  String get notifThisChurch => '이 교회의 알림';

  @override
  String get notifPermissionOff => '알림이 꺼져 있어요. 시스템 설정에서 켜 주세요.';

  @override
  String get notifEnable => '알림 켜기';

  @override
  String get notifAskTitle => '봉사에 배정되면 알려 드려요';

  @override
  String get notifAskBody => '봉사에 배정되거나 봉사표가 바뀌면 알려 드리고, 매주 월요일 저녁에 이번 주 봉사도 알려 드려요';

  @override
  String get notifAskLater => '나중에';

  @override
  String get notifCardHide => '다시 보지 않기';

  @override
  String get notifOpenSettings => '기기 설정에서 알림 켜기';

  @override
  String get notifNotAllowed => '알림이 아직 꺼져 있어요. 권한을 물으면 ‘허용’을 눌러 주세요.';

  @override
  String get notifRegisterFailed => '알림 설정을 아직 마치지 못했어요. 다음에 앱을 열 때 다시 시도할게요.';

  @override
  String get pushView => '보기';

  @override
  String get zoneSwitch => '이 예배에 소속';

  @override
  String zoneLeft(String service) {
    return '더 이상 $service 소속이 아니에요';
  }

  @override
  String get eventRosterGone => '이 행사의 봉사표를 찾을 수 없어요';

  @override
  String get eventRoster => '봉사표';

  @override
  String eventRosterPeople(int count) {
    return '$count명';
  }

  @override
  String get arrangeEventRoster => '봉사 배정';

  @override
  String get eventRosterEmpty => '아직 담당이 없어요';

  @override
  String get copyDuties => '다른 행사에서 가져오기';

  @override
  String get copyDutiesHeader => '어느 행사의 담당을 가져올까요?';

  @override
  String get copyDutiesNone => '아직 다른 행사의 봉사표가 없어요';

  @override
  String dutiesCopied(int count) {
    return '담당 $count개를 추가했어요';
  }

  @override
  String get noZoneYet => '아직 소속 예배가 없어요. 관리자에게 설정을 요청해 주세요.';

  @override
  String get waitsForZone => '소속 예배 미설정';

  @override
  String waitingForZone(int count) {
    return '멤버 $count명의 소속 예배가 아직 없어요';
  }

  @override
  String get inviteZones => '가입 후 소속 예배';

  @override
  String get photoImport => '사진으로 가져오기';

  @override
  String get photoImportAction => '사진 가져오기';

  @override
  String photoRemaining(int count) {
    return '이번 달 $count장 남음';
  }

  @override
  String get photoTake => '사진 찍기';

  @override
  String get photoPick => '사진 선택';

  @override
  String get photoPasteJson => 'JSON 붙여넣기';

  @override
  String get photoRecognizing => '인식하는 중이에요. 1분 정도 걸려요.';

  @override
  String photoChurchLimit(int limit) {
    return '이번 달 $limit장을 모두 사용했어요. 다음 달 1일에 다시 쓸 수 있어요. 그동안에는 봉사표를 직접 입력해 주세요.';
  }

  @override
  String get photoPlatformOff => '이번 달은 사진 인식이 중단됐어요(전체 인식 한도 소진). 다음 달에 다시 쓸 수 있어요. 그동안에는 봉사표를 직접 입력해 주세요.';

  @override
  String get photoTooLarge => '사진이 너무 커요. 표 부분만 잘라서 다시 시도해 주세요.';

  @override
  String get photoFailed => '인식하지 못했어요. 더 선명한 사진으로 다시 시도해 주세요.';

  @override
  String get photoUnavailable => '지금은 사진 인식을 쓸 수 없어요. 잠시 후 다시 시도하거나 봉사표를 직접 입력해 주세요.';

  @override
  String get importPreview => '미리보기';

  @override
  String get importApply => '봉사표에 적용';

  @override
  String importApplied(int count) {
    return '$count일분을 가져왔어요';
  }

  @override
  String get importNothing => '사진에서 앞으로의 날짜를 찾지 못했어요';

  @override
  String get importNotInList => '명단에 없는 이름이에요(입력된 그대로 저장되고 계정에 연결되지 않아요)';

  @override
  String importNear(String names) {
    return '명단의 비슷한 이름: $names';
  }

  @override
  String get importAmbiguous => '누구인지 확실하지 않아요(계정에 연결되지 않음)';

  @override
  String get importUnknownDuties => '이 예배에 없는 담당이에요';

  @override
  String get importPastDays => '지난 날짜라서 가져오지 않았어요';

  @override
  String get importBadRows => '읽을 수 없는 데이터';

  @override
  String get jsonHint => '인식 결과 JSON을 붙여넣어 주세요';

  @override
  String get next2 => '미리보기';

  @override
  String get calNotConnected => '교회에 아직 캘린더가 연결되지 않았어요';

  @override
  String get calConnect => 'Google 캘린더 연결';

  @override
  String get calReconnect => '다시 연결';

  @override
  String get calNeedsReconnect => '캘린더 권한이 만료됐어요';

  @override
  String get calNeedsReconnectStaff => '지금은 캘린더를 불러올 수 없어요. 관리자에게 다시 연결을 요청해 주세요.';

  @override
  String get calPickCalendar => '사용할 캘린더 선택';

  @override
  String get calNoCalendarYet => '선택한 캘린더 없음';

  @override
  String get calDisconnect => '연결 해제';

  @override
  String get calDisconnectTitle => '캘린더 연결을 해제할까요?';

  @override
  String get calDisconnectBody => '멤버들이 캘린더를 볼 수 없게 돼요. Google 캘린더 자체는 바뀌지 않아요.';

  @override
  String get calUnverifiedNote =>
      '다음 화면에서 Google이 ‘Google에서 확인하지 않은 앱’이라고 알려 줘요. ‘고급’ → ‘…(으)로 이동’을 눌러 계속해 주세요. 선택한 캘린더만 읽고 써요.';

  @override
  String get calConnectedOk => 'Google 캘린더를 연결했어요';

  @override
  String get calConnectFailed => '연결하지 못했어요. 다시 시도해 주세요.';

  @override
  String get calNoEvents => '이번 달에는 행사가 없어요';

  @override
  String get calNoEventsThatDay => '이날은 행사가 없어요';

  @override
  String get calAllDay => '종일';

  @override
  String get calNewEvent => '새 행사';

  @override
  String get calEditEvent => '행사 편집';

  @override
  String get calTitle => '행사 이름';

  @override
  String get calLocation => '장소';

  @override
  String get calStart => '시작';

  @override
  String get calEnd => '종료';

  @override
  String get calOtherTime => '다른 시간…';

  @override
  String calLengthMinutes(int minutes) {
    return '$minutes분';
  }

  @override
  String calLengthHours(int hours) {
    return '$hours시간';
  }

  @override
  String calLengthHoursMinutes(int hours, int minutes) {
    return '$hours시간 $minutes분';
  }

  @override
  String get calDelete => '행사 삭제';

  @override
  String calDeleted(String title) {
    return '‘$title’을(를) 삭제했어요';
  }

  @override
  String get calSaved => '행사를 저장했어요';

  @override
  String get calPrevMonth => '이전 달';

  @override
  String get calNextMonth => '다음 달';

  @override
  String get calShowMonth => '달력 보기';

  @override
  String get calHideMonth => '목록만 보기';

  @override
  String get calendarSetting => '캘린더';

  @override
  String get support => '마르다의 쉼표 후원하기';

  @override
  String get supportVerse =>
      '이제 너희의 넉넉한 것으로 그들의 부족한 것을 보충함은 후에 그들의 넉넉한 것으로 너희의 부족한 것을 보충하여 균등하게 하려 함이라 기록된 것 같이 많이 거둔 자도 남지 아니하였고 적게 거둔 자도 모자라지 아니하였느니라';

  @override
  String get supportVerseSource => '고린도후서 8:14–15 (개역개정)';

  @override
  String get supportBody => '후원은 자유이고 서버 비용에만 쓰여요. 교회에 드리는 헌금이 아니며, 어느 교회든 쓸 수 있는 기능은 똑같아요.';

  @override
  String get supportTips => '일시 후원';

  @override
  String get supportMonthly => '정기 후원';

  @override
  String supportPerMonth(String price) {
    return '월 $price';
  }

  @override
  String get supportRestore => '구매 복원';

  @override
  String get supportRate => '평점으로 응원하기';

  @override
  String supportMonthlyTerms(String store) {
    return '매월 자동으로 갱신돼요. $store의 구독 설정에서 언제든지 해지할 수 있어요.';
  }

  @override
  String get manageSubscription => '구독 관리';

  @override
  String get supportThanks => '후원해 주셔서 감사합니다';

  @override
  String get supportPending => '결제 처리 중';

  @override
  String get supportFailed => '결제가 완료되지 않았어요. 요금은 청구되지 않았어요.';

  @override
  String get supportUnavailable => '지금은 스토어에 연결할 수 없어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get supportComingSoon => '앱 안에서 후원하기는 곧 열려요';

  @override
  String get supporterBadge => '후원자';

  @override
  String get appIcon => '앱 아이콘';

  @override
  String get appIconSupporterOnly => '정기 후원자는 앱 아이콘을 바꿀 수 있어요';

  @override
  String supportMonthlyTermsAndIcons(String store) {
    return '정기 후원자는 앱 아이콘을 바꿀 수 있어요. 매월 자동으로 갱신돼요. $store의 구독 설정에서 언제든지 해지할 수 있어요.';
  }

  @override
  String get appIconDefault => '기본';

  @override
  String get appIconGreen => '초록';

  @override
  String get appIconPurple => '보라';

  @override
  String get appIconNight => '밤';

  @override
  String get goHome => '홈으로';

  @override
  String get churchNotFound => '교회를 찾을 수 없어요';

  @override
  String get churchEntryNotMember => '아직 이 교회의 멤버가 아니에요. 관리자에게 초대 링크를 받아 가입해 주세요.';

  @override
  String get churchUrl => '교회 주소';

  @override
  String get churchUrlCopied => '교회 주소를 복사했어요';

  @override
  String get churchUrlCopy => '교회 주소 복사';

  @override
  String get churchUrlShare => '교회 주소 공유';

  @override
  String get homeName => '홈 화면 이름';

  @override
  String get homeNameUnset => '교회 이름과 같음';

  @override
  String get homeNameMayBeCut => '일부 휴대폰에서는 잘릴 수 있어요';

  @override
  String get homeNameFooter => '홈 화면에 추가했을 때 아이콘 아래에 표시되는 이름이에요. 비워 두면 교회 이름을 사용해요.';

  @override
  String get addToHome => '홈 화면에 추가';

  @override
  String get addToHomeIosNote => 'iPhone에 이미 추가한 아이콘은 업데이트되지 않아요. 이름이나 로고를 바꾼 뒤에는 아이콘을 삭제하고 다시 추가해 주세요.';

  @override
  String get addToHomeLater => '나중에';

  @override
  String addToHomeDone(String name) {
    return '추가했어요. 앞으로 휴대폰의 ‘$name’ 아이콘을 눌러 열어 주세요.';
  }

  @override
  String get addToHomeIntro => '다음부터는 홈 화면 아이콘을 눌러 봉사표를 열 수 있어요';

  @override
  String addToHomeBrowserGuide(String device, String browser) {
    return '$device · $browser 안내';
  }

  @override
  String get addToHomeChooseBrowser => '화면이 다른가요?';

  @override
  String get addToHomeChooseGuide => '안내 선택';

  @override
  String get addToHomeChooseGuideNote => '안내만 바뀌고 다른 브라우저가 열리지는 않아요';

  @override
  String get addToHomeSafariLayoutTitle => 'Safari 화면';

  @override
  String get addToHomeSafariLayoutHint => '도구 막대의 버튼을 보고 골라 주세요. Safari 설정은 바꾸지 않아도 돼요.';

  @override
  String get addToHomeSafariMoreChoice => '‘⋯’이 보여요';

  @override
  String get addToHomeSafariShareChoice => '공유 아이콘이 보여요';

  @override
  String get addToHomeSafariMoreShare => '‘⋯’을 누른 뒤 ‘공유’ 선택';

  @override
  String get addToHomeSafariDirectShareHint => '주소창은 위나 아래에 있을 수 있어요. 위쪽 화살표가 있는 네모를 찾아 주세요.';

  @override
  String get addToHomeInApp => '앱 내 브라우저';

  @override
  String get addToHomeOtherBrowser => '다른 브라우저';

  @override
  String get addToHomeScreenshotNote => '브라우저에서 동그라미 친 버튼을 눌러 주세요';

  @override
  String get addToHomeSafariScreenshot => 'Safari · iOS 26.5 · 시뮬레이터(중국어 번체 화면)';

  @override
  String get addToHomeChromeAndroidScreenshot => 'Chrome 113 · Android 14 · 시뮬레이터(중국어 번체 화면, 이전 메뉴)';

  @override
  String get addToHomeChromeIosScreenshot => 'Chrome 155 · iOS 27.2 · iPhone 13 실기기 화면';

  @override
  String get addToHomeAddressBar => '주소창';

  @override
  String get addToHomeChromeShare => '주소창 옆의 공유 아이콘을 눌러 주세요';

  @override
  String get addToHomeChromeShareHint => '‘⋯’ 메뉴도, ‘Chrome 공유’도 아니에요';

  @override
  String get addToHomeChromeScroll => '보이지 않으면 공유 시트를 펼친 뒤 아래로 스크롤해 주세요';

  @override
  String get addToHomeSafariShare => 'Safari의 공유 아이콘을 눌러 주세요';

  @override
  String get addToHomeFirefoxShare => '주소창의 공유 아이콘을 눌러 주세요';

  @override
  String get addToHomeIpadMore => 'iPad에서 이 항목이 보이지 않으면 공유 시트에서 먼저 ‘더 보기’를 눌러 주세요';

  @override
  String get addToHomeSelectAdd => '‘홈 화면에 추가’를 눌러 주세요';

  @override
  String get addToHomeShareMore => '아이콘 한 줄만 보이면 먼저 ‘더 보기’를 눌러 주세요. 이전 버전에서는 아래로 스크롤해 주세요.';

  @override
  String get addToHomeIosConfirm => '‘웹 앱으로 열기’ 스위치가 있으면 켠 채로 두고, 오른쪽 위의 ‘추가’를 눌러 주세요';

  @override
  String get addToHomeOpenTitle => '홈 화면으로 가서 새 아이콘을 눌러 주세요';

  @override
  String addToHomeMenu(String browser) {
    return '$browser 메뉴를 눌러 주세요';
  }

  @override
  String get addToHomeChromeInstall => '홈 화면에 추가 → 설치';

  @override
  String get addToHomeChromeInstallHint => '이전 버전에서는 ‘앱 설치’라고 표시될 수 있어요. ‘바로가기 만들기’가 아니라 ‘설치’를 선택해 주세요.';

  @override
  String get addToHomeFirefoxInstallHint => '이어서 휴대폰 안내에 따라 추가해 주세요. ‘홈 화면에 추가’만 보이면 브라우저 바로가기만 만들어질 수 있어요.';

  @override
  String get addToHomeTrouble => '‘홈 화면에 추가’가 안 보이나요?';

  @override
  String get addToHomeSafariTrouble => '공유 시트를 위로 올려 아래쪽 동작을 확인해 주세요. 그래도 없으면 맨 아래의 ‘동작 편집’을 눌러 주세요.';

  @override
  String addToHomeExternalTitle(String browser) {
    return '먼저 $browser에서 열기';
  }

  @override
  String addToHomeExternalHint(String browser) {
    return '교회 주소를 복사해 $browser 주소창에 붙여넣고, 열리면 안내를 계속해 주세요';
  }

  @override
  String get addToHomeEmbeddedHint => '지금 앱 안에서 웹페이지를 보고 있어요. 먼저 휴대폰 브라우저로 옮겨 주세요.';

  @override
  String get addToHomeUnknownHint => '이 브라우저는 메뉴가 다를 수 있어요. 아래 방법으로 계속해 주세요.';

  @override
  String addToHomeCopiedForBrowser(String browser) {
    return '복사했어요. $browser 앱을 열고 주소창에 붙여넣어 주세요.';
  }

  @override
  String get addToHomePhoneOnly => '휴대폰에서 교회 주소를 연 뒤 홈 화면에 추가해 주세요';

  @override
  String get addToHomeNotificationsAfter => '홈 화면에서 연 뒤 ‘설정’에서 알림을 켜면 봉사 알림을 받을 수 있어요';

  @override
  String get addToHomeIosShare => '공유';

  @override
  String get addToHomeIosAdd => '추가';

  @override
  String addToHomeIosOpen(String name) {
    return '휴대폰의 ‘$name’ 아이콘을 눌러 열고, 다시 로그인해 주세요';
  }

  @override
  String get addToHomeAndroidAdd => '홈 화면에 추가';

  @override
  String get addToHomeAndroidInstall => '설치';

  @override
  String addToHomeAndroidOpen(String name) {
    return '휴대폰의 ‘$name’ 아이콘을 눌러 열어 주세요';
  }

  @override
  String get addToHomeCardBody => '한 번에 열고, 봉사 알림도 받을 수 있어요';

  @override
  String get addToHomeCardHide => '다시 보지 않기';

  @override
  String get notifNeedsHomeScreen => '알림을 받으려면 먼저 홈 화면에 추가해 주세요';

  @override
  String get churchLink => '교회 링크';

  @override
  String get churchLinkNone => '설정 안 됨';

  @override
  String get churchLinkTitle => '제목';

  @override
  String get churchLinkBody => '설명(선택)';

  @override
  String get churchLinkUrl => '링크';

  @override
  String get churchLinkNeedsTitle => '제목을 입력해 주세요';

  @override
  String get churchLinkNeedsHttps => 'https://로 시작하는 링크를 입력해 주세요';

  @override
  String get churchLinkFooter => '모든 멤버의 홈 맨 위에 표시되고, 누르면 브라우저에서 열려요';

  @override
  String get churchLinkRemove => '교회 링크 빼기';

  @override
  String get churchLinkRemoved => '교회 링크를 뺐어요';

  @override
  String get churchLinkOpens => '브라우저에서 열림';

  @override
  String get linkSource => '매일 콘텐츠 출처(선택)';

  @override
  String get linkSourceUrl => 'JSON 주소';

  @override
  String get linkFetchTime => '매일 업데이트 시간';

  @override
  String get linkSourceFooter => '매일 이 시간에 한 번 가져와요. JSON에는 date(교회 기준 오늘), title, body, link(https)가 있어야 해요.';

  @override
  String linkSourceUpdated(String time) {
    return '마지막 업데이트: $time';
  }

  @override
  String linkSourceFailed(String reason) {
    return '마지막 가져오기 실패: $reason';
  }

  @override
  String linkSourceFetched(String title) {
    return '저장했어요. ‘$title’을(를) 가져왔어요.';
  }

  @override
  String get linkErrTimeout => '상대 사이트가 5초 안에 응답하지 않았어요';

  @override
  String get linkErrTooLarge => '내용이 64KB를 넘어요';

  @override
  String get linkErrBadFormat => 'date, title, body, link가 모두 있는 JSON이 아니에요';

  @override
  String get linkErrNotHttps => '주소나 리디렉션이 https가 아니에요';

  @override
  String linkErrHttp(String status) {
    return '상대 사이트가 오류를 반환했어요($status)';
  }

  @override
  String get linkErrNetwork => '상대 사이트에 연결할 수 없어요';

  @override
  String get linkErrUnknown => '알 수 없는 오류예요. 다시 시도해 주세요.';

  @override
  String get webhook => '외부 알림';

  @override
  String get webhookUrl => '받는 주소';

  @override
  String get webhookNeedsHttps => 'https://로 시작하는 주소를 입력해 주세요';

  @override
  String get webhookSecretOptional => '비밀 키(선택, 비워 두면 자동 생성)';

  @override
  String get webhookSecretTooShort => '비밀 키는 16자 이상이어야 해요';

  @override
  String get webhookCalendar => '캘린더 변경';

  @override
  String get webhookCalendarHint => '행사 추가, 수정, 삭제';

  @override
  String get webhookRoster => '봉사표 변경';

  @override
  String get webhookRosterHint => '몇 분 안의 변경은 하나로 묶어 보내요';

  @override
  String get webhookFooter => '캘린더나 봉사표가 바뀌면 이 주소로 알림을 보내요. 예를 들어 n8n을 거쳐 LINE 그룹으로 전달할 수 있어요. 알림은 비밀 키로 서명돼요.';

  @override
  String get webhookTest => '테스트 보내기';

  @override
  String webhookLast(String time, String result) {
    return '마지막 전송: $time · $result';
  }

  @override
  String get webhookOk => '성공';

  @override
  String webhookHttp(String status) {
    return '응답 $status';
  }

  @override
  String get webhookTimeout => '시간 초과';

  @override
  String get webhookNetwork => '연결 실패';

  @override
  String get webhookRotate => '비밀 키 교체';

  @override
  String get webhookRotateMessage => '이전 비밀 키는 바로 쓸 수 없게 돼요. 받는 쪽도 새 키로 바꿔야 해요.';

  @override
  String get webhookGenerate => '자동 생성';

  @override
  String get webhookTypeOwn => '직접 입력';

  @override
  String get webhookSecretTitle => '비밀 키';

  @override
  String get webhookSecretOnce => '지금 한 번만 표시돼요. 받는 쪽에 붙여넣어, 마르다의 쉼표에서 보낸 알림인지 확인하는 데 쓰세요.';

  @override
  String get webhookCopySecret => '비밀 키 복사';

  @override
  String get webhookSecretCopied => '비밀 키를 복사했어요';

  @override
  String get webhookSecretChanged => '비밀 키를 교체했어요';

  @override
  String get webhookOff => '외부 알림 끄기';

  @override
  String get webhookOffTitle => '외부 알림을 끌까요?';

  @override
  String get webhookOffMessage => '주소와 비밀 키가 삭제돼요. 다시 쓰려면 처음부터 설정해야 해요.';

  @override
  String get webhookOffAction => '끄기';

  @override
  String get exportData => '데이터 내보내기';

  @override
  String get exportFooter => '교회의 모든 데이터를 내보내요. JSON 파일 하나와 Excel에서 열 수 있는 봉사표가 함께 들어 있어요.';

  @override
  String get exported => '내보냈어요';

  @override
  String get exportCsvFile => '봉사표.csv';

  @override
  String get exportCsvDate => '날짜';

  @override
  String get exportCsvService => '예배/행사';

  @override
  String get exportCsvRole => '담당';

  @override
  String get exportCsvPeople => '멤버';

  @override
  String get errMoveInvalid => '이전용 파일이 아니에요. 올바른 파일을 선택했는지 확인해 주세요.';

  @override
  String get errMoveTooLarge => '멤버가 2,000명 또는 봉사표가 20,000일을 넘으면 자동으로 옮길 수 없어요. GitHub의 church-staff-pwa에 이슈를 남겨 주세요.';

  @override
  String get moveFromSelfHost => '구버전에서 옮겨 오기';

  @override
  String get moveIntro =>
      '구버전(church-staff-pwa)의 Cloud Shell에서 이전 명령을 실행하고, 만들어진 이전용 파일을 업로드해 주세요. 미리보기를 확인해야 교회가 만들어져요.';

  @override
  String get movePickFile => '이전용 파일 선택';

  @override
  String get moveReading => '이전용 파일 읽는 중…';

  @override
  String get moveContents => '이전용 파일 내용';

  @override
  String get moveMembers => '멤버';

  @override
  String moveMembersCount(int count) {
    return '$count명';
  }

  @override
  String get moveRosters => '봉사표';

  @override
  String moveRostersCount(int count) {
    return '$count일';
  }

  @override
  String get moveServices => '예배';

  @override
  String get moveWhoAmI => '이 사람이 나예요(선택)';

  @override
  String get moveWhoAmIFooter => '선택하면 그 사람의 봉사표, 소속 예배, 권한을 이어받아요. 다른 멤버는 같은 이메일로 마르다의 쉼표에 로그인할 때 가입할지 묻는 안내를 받아요.';

  @override
  String get moveCreate => '교회 만들고 옮겨 오기';

  @override
  String moveDone(String church) {
    return '‘$church’을(를) 만들었어요';
  }

  @override
  String get notSignedInYet => '아직 로그인 안 함';

  @override
  String pendingCount(int count) {
    return '$count명이 아직 로그인하지 않았어요';
  }

  @override
  String claimPrompt(String church) {
    return '$church의 멤버 정보가 이곳으로 옮겨졌어요. 가입할까요?';
  }

  @override
  String get claimJoin => '가입';

  @override
  String get claimDecline => '가입 안 함';

  @override
  String get movedPasswordNote => '구버전에서 옮겨 온 멤버는 기존 비밀번호를 쓸 수 없어요. 같은 이메일로 새 계정을 만들거나 Google로 로그인해 주세요.';

  @override
  String get pendingDelete => '이 정보 삭제';

  @override
  String pendingDeleteTitle(String name) {
    return '‘$name’ 정보를 삭제할까요?';
  }

  @override
  String get pendingDeleteBody => '이제 이메일로 이 정보를 연결할 수 없어요. 봉사표의 이름은 남아요.';

  @override
  String get pendingDeleted => '삭제했어요';

  @override
  String get mergePending => '로그인 전 정보 합치기';

  @override
  String get mergePendingFooter => '멤버가 다른 이메일로 가입했다면 이전 명단의 정보를 합쳐 주세요. 봉사표, 소속 예배, 권한 그룹이 그대로 이어져요.';

  @override
  String get mergePendingPick => '로그인 전 정보 선택';

  @override
  String mergePendingTitle(String pending, String member) {
    return '‘$pending’ 정보를 ‘$member’ 님에게 합칠까요?';
  }

  @override
  String mergePendingBody(String pending) {
    return '봉사표의 ‘$pending’ 이름이 이 멤버로 바뀌고, 소속 예배와 권한 그룹도 추가돼요';
  }

  @override
  String get mergePendingAction => '합치기';

  @override
  String get merged => '합쳤어요';

  @override
  String get fundingTitle => '이번 달 후원';

  @override
  String fundingProgress(String available, String target) {
    return '$available / $target';
  }

  @override
  String get fundingEnough => '이번 달은 충분해요';

  @override
  String fundingMonthsLeft(int months) {
    return '이번 달은 충분하고, 남은 금액으로 $months개월 더 유지할 수 있어요';
  }

  @override
  String fundingCarried(String amount) {
    return '이전 달에서 이월된 $amount 포함';
  }

  @override
  String get fundingCosts => '서버 비용';

  @override
  String fundingTarget(String amount) {
    return '월 목표 $amount';
  }

  @override
  String get fundingTargetUpdating => '월 목표 업데이트 중…';

  @override
  String get fundingCostsHeader => '비용';

  @override
  String get fundingCostsFooter => '가격이 바뀌면 수정해 주세요. 연간 항목은 매달로 나눠 계산해요. 이름과 월 금액은 후원 페이지에 공개돼요.';

  @override
  String get fundingMonthsHeader => '최근 몇 달';

  @override
  String fundingMonthValue(String received, String target) {
    return '$received / $target';
  }

  @override
  String get costAdd => '항목 추가';

  @override
  String get costEdit => '비용 항목';

  @override
  String get costName => '이름';

  @override
  String get costAmount => '금액';

  @override
  String get costPerMonth => '매월';

  @override
  String get costPerYear => '매년';

  @override
  String costValueMonth(String amount) {
    return '$amount · 매월';
  }

  @override
  String costValueYear(String amount) {
    return '$amount · 매년';
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
  String get fundingWhereItGoes => '매달 쓰이는 곳';

  @override
  String get fundingYearlySplit => '연간 비용은 매달로 나눠 표시해요';

  @override
  String get fundingRatesBy => '환율: Exchange Rate API';

  @override
  String get importAdvanced => '고급';

  @override
  String get importCopyPrompt => 'AI 프롬프트 복사';

  @override
  String get importPromptCopied => '복사했어요. 사진과 함께 AI에 보내고, 받은 JSON을 붙여 넣어 주세요';

  @override
  String get importFormatHelp =>
      'date: YYYY-MM-DD. 아무도 없으면 people에 []를 넣어요.\nevents는 생략할 수 있고, 특별 순서 color는 색상 번호 0–5만 쓸 수 있어요.';

  @override
  String get importPhotoFormatError => '인식 결과 형식이 맞지 않아요. 다시 인식하거나 고급 JSON을 사용해 주세요.';

  @override
  String get importJsonSyntaxError => 'JSON 형식이 잘못됐어요. 아래 예시처럼 배열 형식을 사용해 주세요.';

  @override
  String get importJsonEdit => 'JSON 편집';

  @override
  String get importJsonArrayRequired => 'JSON 배열을 입력해 주세요';

  @override
  String importConfirmName(String name) {
    return '‘$name’ 확인';
  }

  @override
  String get importSameNameScope => '이번 가져오기에서 같은 이름은 모두 이 연결을 사용해요';

  @override
  String importGuestChoice(String name) {
    return '‘$name’ 게스트로 두기';
  }

  @override
  String get importEditDate => '날짜 편집';

  @override
  String get importDateFormatLabel => '날짜(YYYY-MM-DD)';

  @override
  String get importValidDate => '올바른 YYYY-MM-DD 날짜를 입력해 주세요';

  @override
  String get importEditDuty => '담당 편집';

  @override
  String get importDutyLabel => '담당';

  @override
  String get importPeopleLines => '이름(한 줄에 한 명)';

  @override
  String get importAddEventAction => '특별 순서 추가';

  @override
  String get importEditEvent => '특별 순서 편집';

  @override
  String get importConflict => '봉사표가 바뀌었어요. 변경 사항을 다시 확인한 뒤 적용해 주세요.';

  @override
  String get importScopeChanged => '교회나 계정이 바뀌었어요. 다시 가져와 주세요.';

  @override
  String importRow(int number) {
    return '$number행';
  }

  @override
  String get importDateLabel => '날짜';

  @override
  String get importDateMissing => '날짜를 입력해 주세요';

  @override
  String get importFixDuty => '담당 수정';

  @override
  String get importPeopleArrayHint => 'people에는 이름 배열을 넣어 주세요';

  @override
  String get importFixEvent => '특별 순서 수정';

  @override
  String importRemoveDuty(String role, String names) {
    return '$role 빼기: $names';
  }

  @override
  String importAddDuty(String role, String names) {
    return '$role 추가: $names';
  }

  @override
  String importChangeDuty(String role, String before, String after) {
    return '$role: $before → $after';
  }

  @override
  String importMemberIdentity(String name) {
    return '$name(멤버)';
  }

  @override
  String importGuestIdentity(String name) {
    return '$name(게스트)';
  }

  @override
  String importRemoveEvent(String name) {
    return '특별 순서 빼기: $name';
  }

  @override
  String importAddEvent(String name) {
    return '특별 순서 추가: $name';
  }

  @override
  String importChangeEvent(String name) {
    return '특별 순서: $name';
  }

  @override
  String importChangedColor(String before, String after) {
    return '$before → $after';
  }

  @override
  String get importNoChange => '배정 변경 없음';

  @override
  String get importNoCandidate => '게스트로 두거나 이름을 수정해 주세요';

  @override
  String importCandidates(String names) {
    return '후보: $names';
  }

  @override
  String get importGuestUnlinked => '게스트(계정에 연결되지 않음)';

  @override
  String get importNameNeedsConfirm => '이름을 확인해 주세요';

  @override
  String importLinkedMember(String name) {
    return '멤버: $name';
  }

  @override
  String get importMode => '가져오기 방식';

  @override
  String get importMerge => '합치기(언급되지 않은 배정은 유지)';

  @override
  String get importReplace => '그날 배정 전체 바꾸기';

  @override
  String get importReplaceHelp => '언급되지 않은 담당과 특별 순서는 빠져요. 다른 날짜에는 영향이 없어요.';

  @override
  String get importFixData => '데이터를 수정한 뒤 가져와 주세요';

  @override
  String get importFixRow => '이 행을 수정해 주세요';

  @override
  String get importNameLinks => '이름 연결';

  @override
  String get importNamesNeedConfirm => '이름을 확인해야 가져올 수 있어요';

  @override
  String get importRepairSettings => '교회 설정 수정(선택)';

  @override
  String get importNoSettingsChange => '이번 배정은 멤버나 교회 설정을 바꾸지 않아요';

  @override
  String importAddConfiguredDuty(String role) {
    return '봉사 설정에 추가: $role';
  }

  @override
  String importUnconfiguredDuty(String role) {
    return '설정되지 않은 담당: $role';
  }

  @override
  String importAddCommonEvent(String name) {
    return '자주 쓰는 특별 순서에 추가: $name';
  }

  @override
  String importNotCommonEvent(String name) {
    return '자주 쓰는 특별 순서 아님: $name';
  }

  @override
  String importDiff(String date) {
    return '적용 후 변경 사항 · $date';
  }

  @override
  String importRequiredField(String field) {
    return '$field 항목을 입력해 주세요';
  }

  @override
  String get importColor => '색상';

  @override
  String get importIssueRowObject => 'date와 duties가 있는 객체를 입력해 주세요';

  @override
  String get importIssueRowFields => 'date, duties, events 필드만 지원해요';

  @override
  String get importIssueDate => 'date에는 올바른 YYYY-MM-DD 날짜를 입력해 주세요';

  @override
  String get importIssueDuplicateDate => '날짜가 중복돼요. 한 행으로 합쳐 주세요.';

  @override
  String get importIssueDutiesArray => 'duties에는 배열을 입력해 주세요';

  @override
  String importIssueDutyFields(int index) {
    return '$index번째 담당은 role, people만 지원해요';
  }

  @override
  String importIssueRole(int index) {
    return '$index번째 role에는 중복되지 않는 담당 이름을 입력해 주세요';
  }

  @override
  String importIssuePeopleArray(int index) {
    return '$index번째 people에는 빈칸이 아닌 이름의 문자열 배열을 입력해 주세요. 아무도 없으면 []를 넣어요.';
  }

  @override
  String importIssueDuplicatePeople(int index) {
    return '$index번째 people에 중복된 이름이 있으면 안 돼요';
  }

  @override
  String get importIssueEventsArray => 'events에는 배열을 입력해 주세요';

  @override
  String importIssueEventObject(int index, String example) {
    return '$index번째 특별 순서는 $example 형식으로 입력해 주세요';
  }

  @override
  String importIssueEventName(int index) {
    return '$index번째 특별 순서의 name에는 중복되지 않는 이름을 입력해 주세요';
  }

  @override
  String importIssueEventColor(int index) {
    return '$index번째 특별 순서의 color에는 0부터 5까지의 정수를 입력해 주세요';
  }

  @override
  String importIssueResolvedDuplicatePeople(String role) {
    return '$role: 확인 후 이름이 중복돼요. 중복된 이름을 삭제해 주세요.';
  }

  @override
  String get appRunningVersion => '현재 버전';

  @override
  String appVersionWithFix(String version, int patch) {
    return '$version · 수정 $patch';
  }

  @override
  String get appVersionDevelopment => '개발 버전(아직 릴리스 없음)';

  @override
  String get updateRequiredTitle => '마르다의 쉼표를 업데이트해 주세요';

  @override
  String get updateRequiredBody => '이 버전은 너무 오래되었어요. 업데이트하면 계속 사용할 수 있어요.';

  @override
  String updateRequiredOpen(String store) {
    return '$store에서 업데이트';
  }

  @override
  String get appUpdateCheck => '업데이트 확인';

  @override
  String get appUpdateChecking => '확인 중…';

  @override
  String get appUpdateApply => '업데이트 후 다시 열기';

  @override
  String get appUpdateApplying => '업데이트 중…';

  @override
  String get saving => '저장 중…';

  @override
  String get appUpdateCurrent => '최신 버전이에요';

  @override
  String get appUpdateReady => '새 버전이 있어요';

  @override
  String get appUpdateFinishEditing => '저장하지 않은 내용이 있어요. 저장한 뒤 업데이트해 주세요.';

  @override
  String get appUpdateFinishEditingNote => '편집 중인 내용을 먼저 저장해 주세요';

  @override
  String get appUpdateFailed => '업데이트하지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.';

  @override
  String get appUpdateScopeChanged => '계정이나 교회가 바뀌었어요. 업데이트를 다시 확인해 주세요.';

  @override
  String get appUpdateBackToMe => '‘업데이트 후 다시 열기’를 한 번 더 눌러 주세요';

  @override
  String get appUpdateCheckFirst => '먼저 업데이트를 확인해 주세요';

  @override
  String get servicesAdminOnly => '봉사 설정은 관리자만 바꿀 수 있어요';

  @override
  String get importExampleRole => '반주';

  @override
  String get importExamplePerson => '김서연';

  @override
  String get importExampleEvent => '성찬';

  @override
  String get rosterShowMore => '더 보기';

  @override
  String get pickerGuestNames => '게스트 이름';

  @override
  String get serviceSettingsSaved => '봉사 설정을 저장했어요';

  @override
  String get serviceSyncOriginalEvent => '원래 특별 순서';

  @override
  String get serviceSyncOriginalDuty => '원래 담당';

  @override
  String serviceFutureSyncTitle(String from, String to) {
    return '‘$from’ → ‘$to’ 동기화';
  }

  @override
  String serviceFutureSyncSaved(int count) {
    return '이후 봉사표 $count개를 동기화했어요';
  }

  @override
  String serviceEventColorTitle(String name) {
    return '$name · 색상';
  }

  @override
  String get serviceEventColor => '색상';

  @override
  String get serviceSyncFutureRosters => '이후 봉사표 동기화';

  @override
  String get rosterFutureChangesNone => '변경할 이후 봉사표가 없어요';

  @override
  String get rosterFutureChangesFooter => '내일부터 저장된 봉사표만 바뀌어요';

  @override
  String get rosterFutureChangesConflict => '같은 이름의 항목이 이미 있어요. 먼저 수정해 주세요.';

  @override
  String get rosterApplyFutureChanges => '변경 적용';

  @override
  String get rosterRemoveFutureGuest => '이후 게스트 배정 빼기';

  @override
  String rosterRemoveFutureGuestTitle(String name) {
    return '‘$name’ 님의 이후 배정 빼기';
  }

  @override
  String rosterFutureGuestRemoved(int count) {
    return '이후 배정 $count개를 뺐어요';
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
  String get errConflict => '다른 멤버가 방금 수정했어요. 다시 불러온 뒤 다시 수정해 주세요.';

  @override
  String get errOfflineReadOnly => '오프라인이에요. 연결되면 저장할 수 있어요.';

  @override
  String get errTooManyChanges => '한 번에 봉사표를 500개까지 바꿀 수 있어요. 여러 번에 나눠서 바꿔 주세요.';

  @override
  String get undoDone => '되돌렸어요';

  @override
  String get undoFailed => '되돌리지 못했어요. 다시 시도해 주세요.';

  @override
  String get offlineReadOnlyBanner => '오프라인이에요. 마지막으로 불러온 내용을 보여 드려요. 연결되면 저장할 수 있어요.';

  @override
  String get calendarCached => '마지막으로 불러온 내용';

  @override
  String calendarReadAt(String time) {
    return '$time 기준';
  }

  @override
  String get calDescription => '행사 설명';

  @override
  String get calDuplicate => '행사 복제';

  @override
  String get homeUpcomingEvents => '다가오는 행사';

  @override
  String get memberSmallGroups => '소그룹';

  @override
  String get memberSmallGroupsHint => '한 줄에 소그룹 하나';

  @override
  String get linkErrNotToday => '출처에 아직 오늘 내용이 없어요';

  @override
  String linkSourceToday(String reason) {
    return '오늘 내용이 업데이트되지 않았어요: $reason';
  }

  @override
  String get linkSourceRetry => '다시 가져오기';

  @override
  String get listSeparator => ', ';

  @override
  String labelValue(String label, String value) {
    return '$label: $value';
  }

  @override
  String nameIsYou(String name) {
    return '$name(나)';
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
  String get churchStatus => '상태';

  @override
  String get timeZone => '시간대';

  @override
  String timeZoneWithOffset(String city, String offset) {
    return '$city($offset)';
  }

  @override
  String get timeZoneFooter => '오늘 날짜, 봉사 알림, 캘린더 시간은 모두 교회 시간대를 따라요';

  @override
  String timeZoneChangeTitle(String city) {
    return '$city 시간으로 바꿀까요?';
  }

  @override
  String get timeZoneChangeBody => '행사 시간은 새 시간대로 표시되고, 봉사표 날짜는 그대로예요';

  @override
  String timeZoneChange(String city) {
    return '$city 시간으로 변경';
  }

  @override
  String churchLocalTime(String city) {
    return '교회 현지 시간($city)';
  }

  @override
  String calendarTimeZoneDiffers(String zone, String city) {
    return '이 캘린더의 시간대($zone)는 교회 시간대($city)와 달라요. 캘린더 시간은 교회 시간대로 표시돼요.';
  }

  @override
  String get cityAuckland => '오클랜드';

  @override
  String get citySydney => '시드니';

  @override
  String get cityMelbourne => '멜버른';

  @override
  String get cityTokyo => '도쿄';

  @override
  String get citySeoul => '서울';

  @override
  String get cityTaipei => '타이베이';

  @override
  String get cityHongKong => '홍콩';

  @override
  String get citySingapore => '싱가포르';

  @override
  String get cityKualaLumpur => '쿠알라룸푸르';

  @override
  String get cityLondon => '런던';

  @override
  String get cityToronto => '토론토';

  @override
  String get cityNewYork => '뉴욕';

  @override
  String get cityChicago => '시카고';

  @override
  String get cityDenver => '덴버';

  @override
  String get cityVancouver => '밴쿠버';

  @override
  String get cityLosAngeles => '로스앤젤레스';

  @override
  String get signInMethods => '로그인 방법';

  @override
  String get signInMethodPassword => '이메일과 비밀번호';

  @override
  String get signInMethodsFooter => '어떤 방법으로 로그인해도 같은 계정이에요. 교회, 봉사표, 권한도 그대로예요.';

  @override
  String get linkGoogle => 'Google 계정 연결';

  @override
  String get linkGoogleFooter => 'Google 계정의 이메일은 이 계정과 달라도 돼요';

  @override
  String get linkedGoogle => 'Google 계정을 연결했어요';

  @override
  String get unlink => '연결 해제';

  @override
  String unlinkTitle(String method) {
    return '$method 연결을 해제할까요?';
  }

  @override
  String unlinkBody(String email) {
    return '앞으로 $email(으)로 이 계정에 로그인할 수 없어요';
  }

  @override
  String get errCredentialInUse => '그 계정은 이미 별도의 마르다의 쉼표 계정이라 연결할 수 없어요. 연결하려면 먼저 그 계정으로 로그인해 계정을 삭제한 뒤 다시 연결해 주세요.';

  @override
  String get onlineRefundHeader => '온라인 후원 환불';

  @override
  String get onlineRefundFooter => '綠界(ECPay) 관리 화면에서 환불한 뒤 그 결제의 가맹점 주문 번호를 입력하면 서버 비용에서 빠져요';

  @override
  String get onlineRefundAdd => '환불 반영하기';

  @override
  String get onlineRefundOrderNo => '가맹점 주문 번호(特店訂單編號)';

  @override
  String get onlineRefundApply => '반영하기';

  @override
  String onlineRefunded(String month, String amount) {
    return '$month에서 $amount을(를) 뺐어요';
  }

  @override
  String get onlineRefundNotFound => '그 주문 번호의 온라인 후원을 찾을 수 없어요. 綠界 관리 화면에서 번호를 확인해 주세요.';

  @override
  String get photoAiTitle => 'AI로 사진 읽기';

  @override
  String get photoAiBody => '사진과 교회 멤버 명단을 Google의 Gemini로 보내 봉사표로 읽어요. Google은 이 내용을 AI 학습에 쓰지 않아요.';

  @override
  String get photoAiAgree => '동의하고 계속';

  @override
  String onlineRefundAlready(String month) {
    return '이 결제는 이미 $month에서 뺐어요';
  }
}
