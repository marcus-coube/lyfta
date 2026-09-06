import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/bioimpedance.dart';
import '../domain/evolution_scope.dart';
import '../widgets/bioimpedance_form.dart';
import 'bioimpedance_controller.dart';

/// Tela de lançamento de bioimpedância — mesmo desenho da
/// [MeasurementFormScreen].
class BioimpedanceFormScreen extends ConsumerStatefulWidget {
  const BioimpedanceFormScreen({super.key, required this.scope});

  final EvolutionScope scope;

  @override
  ConsumerState<BioimpedanceFormScreen> createState() =>
      _BioimpedanceFormScreenState();
}

class _BioimpedanceFormScreenState
    extends ConsumerState<BioimpedanceFormScreen> {
  bool _saving = false;
  String? _error;

  Future<void> _submit(BioimpedanceDraft draft) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(bioimpedanceProvider(widget.scope).notifier)
          .create(draft);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = describeApiError(context, error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(l10n.evolutionNewBioimpedance)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(LySpace.x4),
          children: [
            BioimpedanceForm(onSubmit: _submit, saving: _saving),
            if (_error != null) ...[
              const SizedBox(height: LySpace.x3),
              Text(_error!, style: LyType.bodySm(c.danger)),
            ],
          ],
        ),
      ),
    );
  }
}
