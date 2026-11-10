import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../../billing/presentation/billing_providers.dart';
import '../../billing/presentation/student_billing_tab.dart';
import '../../checkin/presentation/coach_checkins_tab.dart';
import '../../evolution/domain/evolution_scope.dart';
import '../../evolution/presentation/evolution_screen.dart';
import 'student_data_tab.dart';
import 'student_plans_tab.dart';
import 'students_controller.dart';

/// Abas da ficha. O nome entra na URL (`/students/:id?tab=checkins`), que o
/// push de check-in usa para abrir direto na avaliação.
enum StudentTab {
  data,
  workout,
  evolution,
  checkins,

  /// Só owner e coach `own_students` (P7.4); sempre a última.
  billing;

  static StudentTab parse(String? raw) => StudentTab.values.firstWhere(
        (t) => t.name == raw,
        orElse: () => StudentTab.data,
      );
}

/// Ficha do aluno vista pelo professor (P5.4): Dados, Treino, Evolução,
/// Check-ins e, quando o papel permite, Financeiro (P7.4). É rota de primeira
/// classe — recarregar a página na web não perde onde o professor estava.
class StudentDetailScreen extends ConsumerStatefulWidget {
  const StudentDetailScreen({
    required this.studentId,
    this.studentName,
    this.initialTab = StudentTab.data,
    super.key,
  });

  final String studentId;

  /// Vem por `extra` da lista, só para o título aparecer sem esperar a
  /// ficha; nulo quando a URL é aberta direto.
  final String? studentName;
  final StudentTab initialTab;

  @override
  ConsumerState<StudentDetailScreen> createState() =>
      _StudentDetailScreenState();
}

class _StudentDetailScreenState extends ConsumerState<StudentDetailScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;

  /// O controlador acompanha a quantidade de abas (o Financeiro aparece
  /// quando a configuração da organização chega) sem perder a aba atual.
  TabController _controller(int length) {
    final current = _tabs;
    if (current != null && current.length == length) return current;
    final index = current?.index ?? widget.initialTab.index;
    if (current != null) {
      // O TabBar antigo ainda está na árvore neste build: descarta depois.
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return _tabs = TabController(
      length: length,
      vsync: this,
      initialIndex: index.clamp(0, length - 1),
    );
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(studentDetailProvider(widget.studentId));
    // `valueOrNull` guarda a ficha anterior enquanto recarrega: salvar o
    // cadastro não pode piscar a tela inteira.
    final student = detail.valueOrNull;
    final title =
        student?.name ?? widget.studentName ?? l10n.studentDetailTitle;

    final showBilling = ref.watch(billingAccessProvider).canOperate;
    final tabs = _controller(
      showBilling ? StudentTab.values.length : StudentTab.values.length - 1,
    );

    Widget body;
    if (student != null) {
      body = Column(
        children: [
          ColoredBox(
            color: c.surface,
            child: TabBar(
              controller: tabs,
              labelColor: c.accent,
              unselectedLabelColor: c.textSecondary,
              indicatorColor: c.accent,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: l10n.studentTabData),
                Tab(text: l10n.studentTabWorkout),
                Tab(text: l10n.studentTabEvolution),
                Tab(child: CheckinsTabLabel(studentId: student.id)),
                if (showBilling) Tab(text: l10n.studentTabBilling),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: tabs,
              children: [
                StudentDataTab(student: student),
                StudentPlansTab(studentId: student.id),
                EvolutionScreen(
                  scope: EvolutionScope.student(student.id),
                  showCheckins: false,
                ),
                CoachCheckinsTab(studentId: student.id),
                if (showBilling)
                  StudentBillingTab(
                    studentId: student.id,
                    studentName: student.name,
                  ),
              ],
            ),
          ),
        ],
      );
    } else if (detail.hasError) {
      final error = detail.error!;
      body = LyErrorState(
        message: describeApiError(context, error),
        retryable: isRetryableError(error),
        onRetry: () => ref.invalidate(studentDetailProvider(widget.studentId)),
      );
    } else {
      body = const Padding(
        padding: EdgeInsets.all(LySpace.x4),
        child: Column(
          children: [
            LySkeletonListTile(),
            SizedBox(height: LySpace.x3),
            LySkeletonListTile(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: body),
    );
  }
}
