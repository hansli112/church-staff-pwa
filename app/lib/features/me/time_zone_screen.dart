import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../common/time_zones.dart';

/// 時區: the church's, picked by an admin from the zones the app knows,
/// east to west, each with how far it is from UTC today.
class TimeZoneScreen extends ConsumerStatefulWidget {
  const TimeZoneScreen({super.key});

  @override
  ConsumerState<TimeZoneScreen> createState() => _TimeZoneScreenState();
}

class _TimeZoneScreenState extends ConsumerState<TimeZoneScreen> {
  bool _saving = false;

  Future<void> _pick(ChurchTimeZone current, ChurchTimeZone timeZone) async {
    if (timeZone == current || _saving) return;
    final l10n = L10n.of(context);
    final ok = await askChoice(
      context,
      title: l10n.timeZoneChangeTitle(timeZoneCity(l10n, timeZone)),
      message: l10n.timeZoneChangeBody,
      yes: l10n.timeZoneChange(timeZoneCity(l10n, timeZone)),
      no: l10n.cancel,
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.churchData.setTimeZone(timeZone);
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final current = ref.watch(churchTimeZoneProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.timeZone)),
      body: ListView(
        children: [
          ListSection(
            footer: l10n.timeZoneFooter,
            children: [
              for (final timeZone in ChurchTimeZone.values)
                ListRow(
                  title: timeZoneCity(l10n, timeZone),
                  value: utcOffset(timeZone.offsetAt(now)),
                  selected: timeZone == current,
                  onTap: _saving ? null : () => _pick(current, timeZone),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
