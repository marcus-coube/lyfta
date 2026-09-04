import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/measurement.dart';
import '../widgets/measurement_form.dart';
import 'measurements_controller.dart';

/// Tela de lançamento de medida corporal — envolve o [MeasurementForm]
/// (widget "burro", reusável no P2.5) com o repositório e a navegação.
class MeasurementFormScreen extends ConsumerStatefulWidget {
  const MeasurementFormScreen({super.key});

  @override
  ConsumerState<MeasurementFormScreen> createState() =>
      _MeasurementFormScreenState();
}

class _MeasurementFormScreenState extends ConsumerState<MeasurementFormScreen> {
  bool _saving = false;
  String? _error;

  Future<void> _submit(MeasurementDraft draft) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(measurementsProvider.notifier).create(draft);
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
      appBar: AppBar(title: Text(l10n.evolutionNewMeasurement)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(LySpace.x4),
          children: [
            MeasurementForm(onSubmit: _submit, saving: _saving),
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
