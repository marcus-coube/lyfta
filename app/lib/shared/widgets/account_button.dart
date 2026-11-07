import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';

/// Atalho para a tela Conta no app bar dos dois shells (P4.5).
class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('account_button'),
      icon: const Icon(Icons.account_circle_outlined),
      tooltip: AppLocalizations.of(context).accountTooltip,
      onPressed: () => context.push('/account'),
    );
  }
}
