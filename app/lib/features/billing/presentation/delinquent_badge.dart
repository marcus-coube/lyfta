import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'billing_format.dart';
import 'billing_providers.dart';

/// Selo "inadimplente" da ficha do aluno: nada enquanto carrega, quando o
/// aluno está em dia ou quando o `billing` não respondeu.
class DelinquentBadge extends ConsumerWidget {
  const DelinquentBadge({required this.studentId, super.key});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(studentBillingStatusProvider(studentId));
    if (status.valueOrNull != 'delinquent') return const SizedBox.shrink();
    return const Align(
      alignment: Alignment.centerLeft,
      child: DelinquentChip(),
    );
  }
}
