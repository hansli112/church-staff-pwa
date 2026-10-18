import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backend.dart';
import '../../state/providers.dart';

/// [child], warming up the backend for [what] as the page opens
/// ([Backend.warmUp]).
class WarmUpOnOpen extends ConsumerStatefulWidget {
  const WarmUpOnOpen(this.what, {super.key, required this.child});

  final WarmUp what;
  final Widget child;

  @override
  ConsumerState<WarmUpOnOpen> createState() => _WarmUpOnOpenState();
}

class _WarmUpOnOpenState extends ConsumerState<WarmUpOnOpen> {
  @override
  void initState() {
    super.initState();
    ref.read(backendProvider).warmUp(widget.what);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
