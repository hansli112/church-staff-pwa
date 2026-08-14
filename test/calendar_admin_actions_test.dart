import 'dart:convert';

import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/auth/domain/repositories/auth_repository.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/session_provider.dart';
import 'package:church_staff_pwa/features/calendar/data/calendar_write_service.dart';
import 'package:church_staff_pwa/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:church_staff_pwa/features/calendar/presentation/widgets/_day_cell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The calendar is read-only for everyone except an admin, and the write path
/// reaches a real Google calendar. These tests pin the gate: a member must not
/// be shown any way in, and the form must send what the user actually typed.
///
/// The month listing cannot be stubbed — flutter_test refuses outbound HTTP, so
/// _loadEventsForMonth always fails here. Tests that need an event on screen
/// seed the SharedPreferences cache instead; see [_seedEventOn15th].

class _FakeAuthRepository implements AuthRepository {
  final User? user;
  _FakeAuthRepository(this.user);

  @override
  Future<User?> getCachedUser() async => user;

  @override
  Future<User?> getCurrentUser() async => user;

  @override
  Future<void> writeCachedUser(User user) async {}

  @override
  Future<User?> login(String username, String password) async => user;

  @override
  Future<void> logout() async {}

  @override
  Future<List<User>> getUsers() async => const [];

  @override
  Future<void> addUser(User user, String password) async {}

  @override
  Future<void> updateUser(User user, {String? password}) async {}

  @override
  Future<void> deleteUser(String id) async {}
}

User _user(UserRole role, Set<UserGroup> groups) => User(
  id: 'u1',
  name: '測試者',
  email: 'a@b.c',
  username: 'tester',
  role: role,
  groups: groups,
);

/// Records the outgoing request so a test can assert on the body the form built.
class _Recorder {
  final List<http.Request> requests = [];
  http.Response Function(http.Request)? respond;

  MockClient get client => MockClient((request) async {
    requests.add(request);
    return respond?.call(request) ??
        http.Response(
          jsonEncode({
            'id': 'evt-new',
            'summary': '青年小組',
            'start': {'date': '2026-08-20'},
            'end': {'date': '2026-08-21'},
          }),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
  });

  Map<String, dynamic> get lastBody =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;
}

/// Seeds one all-day event on the 15th of the current month.
///
/// Goes in through the SharedPreferences cache the screen already reads on
/// startup, which is the only way to get events on screen here — the live fetch
/// cannot reach Google from a test.
void _seedEventOn15th({String title = '既有活動'}) {
  final now = DateTime.now();
  final key =
      'calendar_events_${now.year}_${now.month.toString().padLeft(2, '0')}';
  String stamp(int day) => DateTime(now.year, now.month, day).toIso8601String();

  SharedPreferences.setMockInitialValues({
    key: jsonEncode([
      {
        'id': 'seeded-event',
        'startTime': stamp(15),
        'endTime': stamp(16),
        'isAllDay': true,
        'title': title,
        'location': null,
        'description': null,
      },
    ]),
  });
}

Finder _dayCell(int dayNumber) => find.byWidgetPredicate(
  (widget) => widget is DayCell && widget.dayNumber == dayNumber,
);

Future<void> _pumpCalendar(
  WidgetTester tester, {
  required _Recorder recorder,
  UserRole role = UserRole.member,
  Set<UserGroup> groups = const {},
}) async {
  final service = CalendarWriteService(
    client: recorder.client,
    endpoint: Uri.parse('https://app.example/api/calendar/events'),
    idToken: () async => 'token',
  );

  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => SessionProvider(_FakeAuthRepository(_user(role, groups))),
      child: MaterialApp(home: CalendarScreen(writeService: service)),
    ),
  );
  // SessionProvider restores asynchronously, so the first frame still has
  // no permissions — without pumping, an "admin sees it" test would pass for
  // the wrong reason. Settling also matters: the FAB appears via a scale
  // transition that ignores pointers until it finishes, so a tap mid-animation
  // silently lands on the calendar grid behind it.
  await tester.pumpAndSettle();
}

/// Opens the add form from the FAB.
Future<void> _openAddForm(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_TW');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a member sees no way to add an event', (tester) async {
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.member, recorder: recorder);

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  // 權限看 group，不看 role：小組長沒有被授予就沒有入口。
  testWidgets('a leader with no group sees no add button', (tester) async {
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.leader, recorder: recorder);

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  // 反過來：一般同工被授予行事曆 group 就看得到入口。
  testWidgets('a staff member in calendar-editors gets an add button', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pumpCalendar(
      tester,
      role: UserRole.staff,
      groups: {UserGroup.calendarEditors},
      recorder: recorder,
    );

    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  // 兩個 group 是正交的：只有服事表權限的人碰不到行事曆。
  testWidgets('a roster editor alone gets no add button', (tester) async {
    final recorder = _Recorder();
    await _pumpCalendar(
      tester,
      role: UserRole.staff,
      groups: {UserGroup.rosterEditors},
      recorder: recorder,
    );

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('an admin gets an add button', (tester) async {
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.admin, recorder: recorder);

    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  // The day sheet is how an admin adds an event on a specific date without
  // touching the date picker at all, so an empty day has to open it.
  testWidgets('an admin can open an empty day and add from there', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.admin, recorder: recorder);

    await tester.tap(find.byType(DayCell).first);
    await tester.pumpAndSettle();

    expect(find.text('當天沒有活動'), findsOneWidget);
    expect(find.text('新增活動'), findsOneWidget);
  });

  testWidgets('a member tapping an empty day gets no sheet', (tester) async {
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.member, recorder: recorder);

    await tester.tap(find.byType(DayCell).first);
    await tester.pumpAndSettle();

    expect(find.text('當天沒有活動'), findsNothing);
  });

  // A member's day sheet does open when the day has events, so the add button
  // needs its own gate — "the sheet never opens" is not enough.
  testWidgets('a member sees the day sheet but no add button', (tester) async {
    _seedEventOn15th();
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.member, recorder: recorder);

    await tester.tap(_dayCell(15));
    await tester.pumpAndSettle();

    expect(find.text('當天活動 1 筆'), findsOneWidget);
    expect(find.text('新增活動'), findsNothing);
  });

  testWidgets('an admin sees the add button on a day that already has events', (
    tester,
  ) async {
    _seedEventOn15th();
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.admin, recorder: recorder);

    await tester.tap(_dayCell(15));
    await tester.pumpAndSettle();

    expect(find.text('新增活動'), findsOneWidget);
  });

  testWidgets('a member opening an event gets no edit or delete', (
    tester,
  ) async {
    _seedEventOn15th();
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.member, recorder: recorder);

    await tester.tap(_dayCell(15));
    await tester.pumpAndSettle();
    await tester.tap(find.text('既有活動').last);
    await tester.pumpAndSettle();

    expect(find.text('編輯'), findsNothing);
    expect(find.text('刪除'), findsNothing);
  });

  testWidgets('an admin opening an event gets edit and delete', (tester) async {
    _seedEventOn15th();
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.admin, recorder: recorder);

    await tester.tap(_dayCell(15));
    await tester.pumpAndSettle();
    await tester.tap(find.text('既有活動').last);
    await tester.pumpAndSettle();

    expect(find.text('編輯'), findsOneWidget);
    expect(find.text('刪除'), findsOneWidget);
  });

  testWidgets('editing pre-fills the form and patches by id', (tester) async {
    _seedEventOn15th();
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.admin, recorder: recorder);

    await tester.tap(_dayCell(15));
    await tester.pumpAndSettle();
    await tester.tap(find.text('既有活動').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('編輯'));
    await tester.pumpAndSettle();

    expect(find.text('編輯活動'), findsOneWidget);
    // The title arrives already filled in — nobody should retype it to fix a
    // date.
    expect(find.widgetWithText(TextField, '既有活動'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '改過的名字');
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    expect(recorder.requests.single.method, 'PATCH');
    expect(recorder.requests.single.url.pathSegments.last, 'seeded-event');
    expect(recorder.lastBody['title'], '改過的名字');
  });

  testWidgets('deleting asks first and sends nothing when refused', (
    tester,
  ) async {
    _seedEventOn15th();
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.admin, recorder: recorder);

    await tester.tap(_dayCell(15));
    await tester.pumpAndSettle();
    await tester.tap(find.text('既有活動').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();

    expect(find.text('刪除活動'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(recorder.requests, isEmpty);
  });

  testWidgets('confirming the delete removes the event from the grid', (
    tester,
  ) async {
    _seedEventOn15th();
    final recorder = _Recorder();
    recorder.respond = (_) => http.Response('', 204);
    await _pumpCalendar(tester, role: UserRole.admin, recorder: recorder);

    expect(find.text('既有活動'), findsWidgets);

    await tester.tap(_dayCell(15));
    await tester.pumpAndSettle();
    await tester.tap(find.text('既有活動').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();
    // The confirm dialog's own button, not the detail sheet's.
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await tester.pumpAndSettle();

    expect(recorder.requests.single.method, 'DELETE');
    expect(find.text('已刪除活動'), findsOneWidget);
    // Gone from the month grid too, without waiting for a refetch that cannot
    // succeed in a test.
    expect(find.text('既有活動'), findsNothing);
  });

  testWidgets('the form defaults to an all-day event and sends the title', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.admin, recorder: recorder);
    await _openAddForm(tester);

    expect(find.text('新增活動'), findsOneWidget);
    // All-day by default, so no time pickers are on screen to distract from
    // the one field that has to be filled in.
    expect(find.byIcon(Icons.schedule), findsNothing);

    await tester.enterText(find.byType(TextField).first, '青年小組');
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    expect(recorder.requests, hasLength(1));
    expect(recorder.requests.single.method, 'POST');
    expect(recorder.lastBody['title'], '青年小組');
    expect(recorder.lastBody['allDay'], isTrue);
    expect(recorder.lastBody['start'], recorder.lastBody['end']);
  });

  testWidgets('turning off all-day reveals the time pickers', (tester) async {
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.admin, recorder: recorder);
    await _openAddForm(tester);

    expect(find.byIcon(Icons.schedule), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    // One for the start, one for the end.
    expect(find.byIcon(Icons.schedule), findsNWidgets(2));
  });

  testWidgets('an empty title is refused without a round trip', (tester) async {
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.admin, recorder: recorder);
    await _openAddForm(tester);

    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    expect(find.text('請填寫標題'), findsOneWidget);
    expect(recorder.requests, isEmpty);
    // The sheet stays open so the user can fix it in place.
    expect(find.text('新增活動'), findsOneWidget);
  });

  testWidgets('a rejected save keeps the sheet open and shows the reason', (
    tester,
  ) async {
    final recorder = _Recorder();
    recorder.respond = (_) => http.Response(
      jsonEncode({'error': '沒有編輯行事曆的權限'}),
      403,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    await _pumpCalendar(tester, role: UserRole.admin, recorder: recorder);
    await _openAddForm(tester);

    await tester.enterText(find.byType(TextField).first, '青年小組');
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    expect(find.text('沒有編輯行事曆的權限'), findsOneWidget);
    expect(find.text('新增活動'), findsOneWidget);
  });

  testWidgets('a successful save closes the sheet and confirms', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.admin, recorder: recorder);
    await _openAddForm(tester);

    await tester.enterText(find.byType(TextField).first, '青年小組');
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    expect(find.text('新增活動'), findsNothing);
    expect(find.text('已新增活動'), findsOneWidget);
  });

  testWidgets('cancelling sends nothing', (tester) async {
    final recorder = _Recorder();
    await _pumpCalendar(tester, role: UserRole.admin, recorder: recorder);
    await _openAddForm(tester);

    await tester.enterText(find.byType(TextField).first, '青年小組');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(recorder.requests, isEmpty);
    expect(find.text('新增活動'), findsNothing);
  });
}
