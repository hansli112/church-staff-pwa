import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/auth/domain/repositories/auth_repository.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/session_provider.dart';
import 'package:church_staff_pwa/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The month grid used to draw a fixed six rows, so a month that needs five
/// reserved a whole empty row and pushed the card's bottom edge past the fold.
/// These tests pin the height to the rows the month actually occupies.
///
/// Everything here is derived from DateTime.now() rather than a fixed month:
/// the screen always opens on the current one, and which months need five rows
/// and which need six moves with the calendar.

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

/// Rows a month occupies: blanks before the 1st, plus its days, in whole weeks.
int _expectedRows(DateTime month) {
  final startOffset = DateTime(month.year, month.month, 1).weekday % 7;
  final days = DateUtils.getDaysInMonth(month.year, month.month);
  return ((startOffset + days) / 7).ceil();
}

/// The spacing between rows, mirroring _calendarMainAxisSpacing.
const double _rowSpacing = 6;

Future<void> _pumpCalendar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => SessionProvider(
        _FakeAuthRepository(
          User(
            id: 'u1',
            name: '測試者',
            email: 'a@b.c',
            username: 'tester',
            role: UserRole.member,
            groups: const {},
          ),
        ),
      ),
      child: const MaterialApp(home: CalendarScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

double _gridHeight(WidgetTester tester) =>
    tester.getSize(find.byType(PageView)).height;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_TW');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the grid is only as tall as the month needs', (tester) async {
    await _pumpCalendar(tester);

    final now = DateTime.now();
    final firstMonth = DateTime(now.year, now.month);
    // Cell height is the same in every month, so the first month on screen
    // fixes it; every later month is checked against that same cell.
    final firstRows = _expectedRows(firstMonth);
    final cellHeight =
        (_gridHeight(tester) - (_rowSpacing * (firstRows - 1))) / firstRows;

    final seenRowCounts = <int>{firstRows};

    // A year is enough to cover both five- and six-row months wherever "now"
    // happens to fall.
    for (var offset = 1; offset <= 12; offset++) {
      await tester.tap(find.byTooltip('下個月'));
      await tester.pumpAndSettle();

      final month = DateTime(now.year, now.month + offset);
      final rows = _expectedRows(month);
      seenRowCounts.add(rows);

      expect(
        _gridHeight(tester),
        closeTo((cellHeight * rows) + (_rowSpacing * (rows - 1)), 0.5),
        reason: '${month.year}/${month.month} 需要 $rows 列',
      );
    }

    // Guards the test itself: if every month came out the same height the
    // assertion above would pass without proving anything.
    expect(seenRowCounts.length, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a six-row month keeps all six rows while it slides in', (
    tester,
  ) async {
    await _pumpCalendar(tester);

    final now = DateTime.now();
    final firstRows = _expectedRows(DateTime(now.year, now.month));
    final cellHeight =
        (_gridHeight(tester) - (_rowSpacing * (firstRows - 1))) / firstRows;
    final sixRowHeight = (cellHeight * 6) + (_rowSpacing * 5);

    // Walk to the month before the next six-row one, so the swipe under test
    // is the one that has to grow the grid.
    var offset = 0;
    while (_expectedRows(DateTime(now.year, now.month + offset + 1)) != 6) {
      offset++;
      expect(offset, lessThan(12), reason: '一年內找不到六列的月份');
      await tester.tap(find.byTooltip('下個月'));
      await tester.pumpAndSettle();
    }
    expect(_gridHeight(tester), lessThan(sixRowHeight));

    await tester.tap(find.byTooltip('下個月'));
    // Mid-animation the six-row month is partly on screen, so the box has to
    // be tall enough for it already rather than clipping its last row. Two
    // pumps: the controller notifies during the first frame's animation phase,
    // which is after that frame has been laid out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_gridHeight(tester), closeTo(sixRowHeight, 0.5));

    await tester.pumpAndSettle();
    expect(_gridHeight(tester), closeTo(sixRowHeight, 0.5));
    expect(tester.takeException(), isNull);
  });
  testWidgets('the grid starts collapsing before the swipe lands', (
    tester,
  ) async {
    await _pumpCalendar(tester);

    final now = DateTime.now();
    final firstRows = _expectedRows(DateTime(now.year, now.month));
    final cellHeight =
        (_gridHeight(tester) - (_rowSpacing * (firstRows - 1))) / firstRows;
    double heightForRows(int rows) =>
        (cellHeight * rows) + (_rowSpacing * (rows - 1));

    // Walk to a six-row month whose successor is shorter — that is the swipe
    // that has to give the height back.
    var offset = 0;
    while (!(_expectedRows(DateTime(now.year, now.month + offset)) == 6 &&
        _expectedRows(DateTime(now.year, now.month + offset + 1)) < 6)) {
      offset++;
      expect(offset, lessThan(24), reason: '兩年內找不到六列接五列的月份');
      await tester.tap(find.byTooltip('下個月'));
      await tester.pumpAndSettle();
    }

    final tallHeight = heightForRows(6);
    final shortHeight = heightForRows(
      _expectedRows(DateTime(now.year, now.month + offset + 1)),
    );
    expect(_gridHeight(tester), closeTo(tallHeight, 0.5));

    await tester.tap(find.byTooltip('下個月'));
    await tester.pump();
    // Two thirds through the 260ms page animation the box is already on its
    // way down, rather than waiting for the page to land and then animating.
    await tester.pump(const Duration(milliseconds: 160));
    final midHeight = _gridHeight(tester);
    expect(midHeight, lessThan(tallHeight - 1));
    expect(midHeight, greaterThan(shortHeight));

    // And it is done when the page is done — no second animation trailing it.
    await tester.pump(const Duration(milliseconds: 140));
    expect(_gridHeight(tester), closeTo(shortHeight, 0.5));

    await tester.pumpAndSettle();
    expect(_gridHeight(tester), closeTo(shortHeight, 0.5));
    expect(tester.takeException(), isNull);
  });

}
