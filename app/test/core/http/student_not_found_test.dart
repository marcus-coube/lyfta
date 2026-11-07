import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/http/api_exception.dart';
import 'package:lyfta/core/http/api_exception_l10n.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/shared/widgets/ly_error_state.dart';

void main() {
  const notFound = ApiException(code: 'student_not_found', statusCode: 404);

  testWidgets('student_not_found vira mensagem i18n e some o "tentar de novo"',
      (tester) async {
    late Object error;
    await tester.pumpWidget(
      MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            error = notFound;
            return Scaffold(
              body: LyErrorState(
                message: describeApiError(context, error),
                retryable: isRetryableError(error),
                onRetry: () {},
              ),
            );
          },
        ),
      ),
    );

    expect(
      find.text('Este aluno não está na sua lista de alunos.'),
      findsOneWidget,
    );
    expect(find.text('Tentar de novo'), findsNothing);
  });

  test('só student_not_found deixa de ser repetível', () {
    expect(isRetryableError(notFound), isFalse);
    expect(isRetryableError(const ApiException.network()), isTrue);
    expect(isRetryableError(Exception('x')), isTrue);
  });
}
