import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../common/time_zones.dart';
import '../common/saving_indicator.dart';
import 'calendar_screen.dart';
import '../../state/session.dart';

final _calendarListProvider = FutureProvider.autoDispose<List<CalendarChoice>>(
  (ref) => openChurch(ref).calendar.choices(),
);

/// Says so when the picked calendar keeps another time zone than the
/// church's: its times look different in Google Calendar than here.
String? _timeZoneDiffers(L10n l10n, String? calendarTimeZone, ChurchTimeZone church) {
  if (calendarTimeZone == null || calendarTimeZone == church.id) return null;
  final known = ChurchTimeZone.byId(calendarTimeZone);
  // Another name for the same clock, winter and summer (Taipei and Hong Kong).
  final sameClock =
      known != null &&
      [DateTime.utc(2026), DateTime.utc(2026, 7)].every((t) => known.offsetAt(t) == church.offsetAt(t));
  if (sameClock) return null;
  return l10n.calendarTimeZoneDiffers(
    known == null ? calendarTimeZone : timeZoneCity(l10n, known),
    timeZoneCity(l10n, church),
  );
}

/// Admins connect the church's Google Calendar here and pick which calendar
/// it shows. The consent screen opens in a browser sheet over the phone app
/// (the web app's own tab on the web); the backend stores the grant and this
/// page updates when it arrives, closing the sheet where the phone lets it
/// (iOS; on Android its last page says to close it).
class CalendarSettingsScreen extends ConsumerStatefulWidget {
  const CalendarSettingsScreen({super.key, this.result});

  /// `connected`, `denied`, `expired`, … when the OAuth redirect lands here.
  final String? result;

  @override
  ConsumerState<CalendarSettingsScreen> createState() => _CalendarSettingsScreenState();
}

class _CalendarSettingsScreenState extends ConsumerState<CalendarSettingsScreen> {
  /// Asking the backend for Google's page, or 中斷連接 on its way: one tap,
  /// once.
  bool _connecting = false;
  bool _disconnecting = false;

  Future<void> _connect() async {
    if (_connecting) return;
    final l10n = L10n.of(context);
    setState(() => _connecting = true);
    try {
      final url = await ref.churchData.calendar.authUrl();
      await launchUrl(
        url,
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
        webOnlyWindowName: '_self',
      );
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    final l10n = L10n.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.calDisconnectTitle,
      message: l10n.calDisconnectBody,
      action: l10n.calDisconnect,
    );
    if (!ok || !mounted || _disconnecting) return;
    setState(() => _disconnecting = true);
    try {
      await ref.churchData.calendar.disconnect();
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final result = widget.result;
    final read = ref.watch(calendarSettingsProvider);
    final settings = read.value;
    ref.listen(calendarSettingsProvider, (before, now) {
      final was = before?.value;
      // Only a change seen here: not the settings arriving as the page opens.
      if (!kIsWeb && was != null && !was.usable && (now.value?.usable ?? false)) closeInAppWebView();
    });
    return Scaffold(
      appBar: AppBar(title: Text(l10n.calendarSetting), actions: savingActions(const [])),
      body: ListView(
        children: [
          if (result != null && result != 'connected')
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: BalancedText(
                result == 'scopes' ? l10n.calConnectScopes : l10n.calConnectFailed,
                textAlign: TextAlign.start,
                style: AppText.subheadline.copyWith(color: c.destructive),
              ),
            ),
          // Not read yet: not 連接 as if it were not connected.
          if (!read.hasValue)
            read.hasError
                ? ErrorRetry(message: l10n.loadFailed, onRetry: () => ref.invalidate(calendarSettingsProvider))
                : const Padding(
                    padding: EdgeInsets.all(Space.xl),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  )
          else if (settings == null || !settings.usable)
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BalancedText(
                    l10n.calConnectNote,
                    textAlign: TextAlign.start,
                    style: AppText.subheadline.copyWith(color: c.secondaryLabel),
                  ),
                  const SizedBox(height: Space.m),
                  PrimaryButton(
                    label: settings?.needsReconnect ?? false ? l10n.calReconnect : l10n.calConnect,
                    busy: _connecting,
                    onPressed: _connecting ? null : _connect,
                  ),
                ],
              ),
            )
          else
            Consumer(
              builder: (context, ref, _) {
                final list = ref.watch(_calendarListProvider);
                // The account's own calendar is listed under its email.
                final account = list.value?.where((cal) => cal.primary).firstOrNull?.id;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Which account is connected, and right under it the way
                    // off it: disconnecting then connecting switches accounts.
                    ListSection(
                      children: [
                        if (account != null) ListRow(leading: const _GoogleMark(), title: account),
                        ListRow(
                          title: l10n.calDisconnect,
                          destructive: !_disconnecting,
                          dimmed: _disconnecting,
                          onTap: _disconnecting ? null : _disconnect,
                        ),
                      ],
                    ),
                    list.when(
                      // The first call after a while can wait on a cold start.
                      loading: () => const Padding(
                        padding: EdgeInsets.all(Space.xl),
                        child: Center(child: CircularProgressIndicator.adaptive()),
                      ),
                      error: (e, _) =>
                          ErrorRetry(message: l10n.loadFailed, onRetry: () => ref.invalidate(_calendarListProvider)),
                      data: (calendars) => _CalendarPicker(calendars: calendars, settings: settings),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The church's calendars, the one in use marked. A tap marks it at once:
/// saving can wait on the backend waking up.
class _CalendarPicker extends ConsumerStatefulWidget {
  const _CalendarPicker({required this.calendars, required this.settings});

  final List<CalendarChoice> calendars;
  final CalendarSettings settings;

  @override
  ConsumerState<_CalendarPicker> createState() => _CalendarPickerState();
}

class _CalendarPickerState extends ConsumerState<_CalendarPicker> {
  /// The one tapped, until the saved settings say so: the call can answer
  /// before the settings arrive, and the old one must not show again between.
  CalendarChoice? _picking;

  @override
  void didUpdateWidget(_CalendarPicker old) {
    super.didUpdateWidget(old);
    if (_picking?.id == widget.settings.calendarId) _picking = null;
  }

  Future<void> _pick(CalendarChoice cal) async {
    final l10n = L10n.of(context);
    final first = widget.settings.calendarId == null;
    final telemetry = ref.read(telemetryProvider);
    setState(() => _picking = cal);
    try {
      await ref.churchData.calendar.select(cal.id, cal.name);
      if (first) telemetry.logEvent('calendar_connect');
    } catch (e) {
      if (!mounted) return;
      showToast(context, errorText(l10n, e));
      if (_picking == cal) setState(() => _picking = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final picked = _picking?.id ?? widget.settings.calendarId;
    return ListSection(
      header: l10n.calPickCalendar,
      footer: _timeZoneDiffers(
        l10n,
        widget.calendars.where((cal) => cal.id == picked).firstOrNull?.timeZone,
        ref.watch(churchTimeZoneProvider),
      ),
      children: [
        for (final cal in widget.calendars)
          ListRow(
            title: cal.name,
            selected: _picking == null ? widget.settings.calendarName == cal.name : _picking == cal,
            onTap: () => _pick(cal),
          ),
      ],
    );
  }
}

/// Google's G on white, as on its sign-in button and on 登入方式.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
    child: Image.asset('assets/icons/google_g.png', width: 14, height: 14, excludeFromSemantics: true),
  );
}
