import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../data/backend.dart';
import '../../state/providers.dart';

/// [child], warming up the backend for [what] as the page opens
/// ([Backend.warmUp]); with [when], once it first holds while the page is
/// open: a call only some readers make, known once what tells them apart
/// has loaded.
class WarmUpOnOpen extends ConsumerStatefulWidget {
  const WarmUpOnOpen(this.what, {super.key, this.when, required this.child});

  final WarmUp what;
  final ProviderListenable<bool>? when;
  final Widget child;

  @override
  ConsumerState<WarmUpOnOpen> createState() => _WarmUpOnOpenState();
}

class _WarmUpOnOpenState extends ConsumerState<WarmUpOnOpen> {
  bool _warmed = false;

  @override
  void initState() {
    super.initState();
    final when = widget.when;
    if (when == null) {
      _warm();
    } else {
      ref.listenManual(when, (_, wanted) {
        if (wanted) _warm();
      }, fireImmediately: true);
    }
  }

  void _warm() {
    if (_warmed) return;
    _warmed = true;
    ref.read(backendProvider).warmUp(widget.what);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
