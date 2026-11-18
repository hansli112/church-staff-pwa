import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/session.dart';

/// The bar of a page shown with no 設定 to go to (in no church yet, the
/// email not verified, the church closed): nothing but 帳號 at the corner.
/// The page under it is centered on the whole screen, so put it on a
/// Scaffold with extendBodyBehindAppBar.
PreferredSizeWidget accountBar() => AppBar(
  automaticallyImplyLeading: false,
  backgroundColor: Colors.transparent,
  actions: const [AccountMenu()],
);

/// 帳號 at the top corner: whom I am signed in as (someone here is often in
/// the wrong account), 登出, 刪除帳號. A menu from the button, as Apple's
/// pull-down buttons and the app's other top-bar menus.
class AccountMenu extends ConsumerWidget {
  const AccountMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final email = ref.watch(authUserProvider.select((u) => u.value?.email ?? ''));
    return PopupMenuButton<_AccountAction>(
      icon: const Icon(Symbols.account_circle_rounded),
      tooltip: l10n.account,
      // Below the button, as it was pulled down from it.
      position: PopupMenuPosition.under,
      onSelected: (action) => switch (action) {
        _AccountAction.signOut => signOut(ref),
        _AccountAction.delete => context.push('/account'),
      },
      itemBuilder: (context) => [
        if (email.isNotEmpty) ...[
          PopupMenuItem<_AccountAction>(
            enabled: false,
            child: Text(email, style: AppText.footnote.copyWith(color: c.secondaryLabel)),
          ),
          const PopupMenuDivider(),
        ],
        PopupMenuItem(value: _AccountAction.signOut, child: Text(l10n.signOut)),
        PopupMenuItem(
          value: _AccountAction.delete,
          child: Text(l10n.deleteAccount, style: TextStyle(color: c.destructive)),
        ),
      ],
    );
  }
}

enum _AccountAction { signOut, delete }
