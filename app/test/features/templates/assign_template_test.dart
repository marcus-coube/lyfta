import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/http/api_exception.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/chat/data/participant_directory.dart';
import 'package:lyfta/features/students/data/student_repository.dart';
import 'package:lyfta/features/students/domain/student.dart';
import 'package:lyfta/features/students/presentation/students_controller.dart';
import 'package:lyfta/features/templates/data/template_repository.dart';
import 'package:lyfta/features/templates/domain/template.dart';
import 'package:lyfta/features/templates/presentation/assign_template_screen.dart';
import 'package:lyfta/features/templates/presentation/template_recipients_screen.dart';

class _FakeStudents extends StudentRepository {
  _FakeStudents(this.all) : super(Dio());

  final List<Student> all;

  @override
  Future<StudentPage> list({
    String query = '',
    StudentStatusFilter status = StudentStatusFilter.active,
    String? coachId,
    String? cursor,
    int? limit,
  }) async =>
      StudentPage(
        items: all
            .where((s) => s.name.toLowerCase().contains(query.toLowerCase()))
            .toList(),
      );
}

class _FakeTemplates extends TemplateRepository {
  _FakeTemplates() : super(Dio());

  final assigned = <({List<String> ids, bool publish})>[];
  final reapplied = <List<String>>[];
  var recipientItems = <TemplateRecipient>[];

  @override
  Future<List<BatchItem>> assign(
    String id, {
    required List<String> studentIds,
    required bool publish,
  }) async {
    assigned.add((ids: studentIds, publish: publish));
    // O segundo aluno está fora do vínculo: erro só nele, o lote segue.
    return [
      for (var i = 0; i < studentIds.length; i++)
        i == 1
            ? BatchItem(
                ok: false,
                studentId: studentIds[i],
                error: const ApiException(code: 'student_not_found'),
              )
            : BatchItem(ok: true, studentId: studentIds[i], planId: 'p$i'),
    ];
  }

  @override
  Future<TemplateRecipients> recipients(String id) async => TemplateRecipients(
        templateVersionNo: 3,
        items: recipientItems,
      );

  @override
  Future<List<BatchItem>> reapply(
    String id, {
    required List<String> planIds,
  }) async {
    reapplied.add(planIds);
    return [
      for (final p in planIds) BatchItem(ok: true, planId: p, versionNo: 4),
    ];
  }
}

class _FakeDirectory extends ParticipantDirectoryRepository {
  _FakeDirectory() : super(Dio());

  @override
  Future<Map<String, String>> names(Iterable<String> ids) async =>
      {'a1': 'Ana Alves', 'b2': 'Bruno Braga'};
}

const _students = [
  Student(id: 'a1', name: 'Ana Alves', email: 'ana@x.com', status: 'active'),
  Student(
      id: 'b2', name: 'Bruno Braga', email: 'bruno@x.com', status: 'active',),
  Student(id: 'c3', name: 'Carla Cruz', email: 'carla@x.com', status: 'active'),
];

Future<void> _pump(
    WidgetTester tester, Widget screen, _FakeTemplates fake,) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        studentRepositoryProvider.overrideWithValue(_FakeStudents(_students)),
        templateRepositoryProvider.overrideWithValue(fake),
        participantDirectoryRepositoryProvider
            .overrideWithValue(_FakeDirectory()),
      ],
      child: MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('seleção múltipla e resultado parcial por aluno', (tester) async {
    final fake = _FakeTemplates();
    await _pump(
      tester,
      const AssignTemplateScreen(templateId: 't1', templateTitle: 'Full body'),
      fake,
    );

    // Aplicar só habilita com alguém selecionado.
    expect(find.text('Nenhum aluno selecionado'), findsOneWidget);

    await tester.tap(find.byKey(const Key('assign_student_a1')));
    await tester.tap(find.byKey(const Key('assign_student_b2')));
    await tester.tap(find.byKey(const Key('assign_student_c3')));
    await tester.pump();
    expect(find.text('3 alunos selecionados'), findsOneWidget);

    // Desmarcar tira da seleção.
    await tester.tap(find.byKey(const Key('assign_student_c3')));
    await tester.pump();
    expect(find.text('2 alunos selecionados'), findsOneWidget);

    await tester.tap(find.byKey(const Key('assign_publish')));
    await tester.pump();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(fake.assigned, hasLength(1));
    expect(fake.assigned.single.ids, ['a1', 'b2']);
    expect(fake.assigned.single.publish, isTrue);

    // Resultado parcial: um sucesso e um erro traduzido, cada um no seu aluno.
    expect(find.text('1 de 2 com sucesso.'), findsOneWidget);
    expect(find.text('Ana Alves'), findsOneWidget);
    expect(find.text('Plano criado'), findsOneWidget);
    expect(find.text('Bruno Braga'), findsOneWidget);
    expect(
      find.text('Este aluno não está na sua lista de alunos.'),
      findsOneWidget,
    );

    // "Tentar de novo" volta à seleção só com quem falhou.
    await tester.tap(find.byKey(const Key('batch_back')));
    await tester.pumpAndSettle();
    expect(find.text('1 aluno selecionado'), findsOneWidget);
  });

  testWidgets('reaplicar destaca o editado, avisa e mostra o resultado',
      (tester) async {
    final fake = _FakeTemplates()
      ..recipientItems = const [
        TemplateRecipient(
          planId: 'p1',
          studentId: 'a1',
          title: 'Full body',
          status: 'published',
          isActive: true,
          sourceVersionNo: 3,
          editedAfterSource: false,
        ),
        TemplateRecipient(
          planId: 'p2',
          studentId: 'b2',
          title: 'Full body',
          status: 'published',
          isActive: true,
          sourceVersionNo: 2,
          editedAfterSource: true,
        ),
      ];
    await _pump(
      tester,
      const TemplateRecipientsScreen(
          templateId: 't1', templateTitle: 'Full body',),
      fake,
    );

    expect(find.text('Na versão atual'), findsOneWidget);
    expect(find.text('Na v2 do modelo'), findsOneWidget);
    expect(find.byKey(const Key('recipient_edited_p2')), findsOneWidget);
    expect(find.byKey(const Key('recipient_edited_p1')), findsNothing);

    // "Selecionar desatualizados" pega só o p2 (versão antiga + editado).
    await tester.tap(find.byKey(const Key('recipients_select_outdated')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('recipients_submit')));
    await tester.pumpAndSettle();

    // Aviso de que os ajustes individuais serão substituídos.
    expect(find.textContaining('ajustes individuais'), findsOneWidget);
    expect(find.textContaining('1 deles foi editado'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recipients_confirm')));
    await tester.pumpAndSettle();

    expect(fake.reapplied.single, ['p2']);
    expect(find.text('1 de 1 com sucesso.'), findsOneWidget);
    expect(find.text('Bruno Braga'), findsOneWidget);
    expect(find.text('Versão 4 publicada'), findsOneWidget);
  });
}
