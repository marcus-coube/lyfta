import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';

/// Tela de aceite de convite — apenas visual por ora (P0.6 liga ao endpoint
/// `POST /v1/invitations/accept`; o token chega via query param da rota
/// `/invite` tanto em web quanto por deep link `lyfta://` no mobile).
class InviteAcceptScreen extends StatelessWidget {
  const InviteAcceptScreen({super.key, this.token});

  final String? token;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(LySpace.x6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.inviteTitle, style: LyType.display(c.textPrimary)),
                  const SizedBox(height: LySpace.x2),
                  Text(
                    l10n.inviteSubtitle,
                    style: LyType.body(c.textSecondary),
                  ),
                  const SizedBox(height: LySpace.x8),
                  LyTextField(
                    label: l10n.inviteNewPasswordLabel,
                    hint: l10n.loginPasswordHint,
                    prefixIcon: Icons.lock_outline,
                    obscure: true,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: LySpace.x6),
                  LyButton(label: l10n.inviteSubmit, onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
