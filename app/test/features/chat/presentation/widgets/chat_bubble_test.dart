import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/chat/presentation/widgets/chat_bubble.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: LyTheme.dark(),
    locale: const Locale('pt'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('mensagem própria lida mostra o texto e o duplo check',
      (tester) async {
    await tester.pumpWidget(
      _host(
        ChatBubble(
          isMine: true,
          timestamp: DateTime(2026, 9, 11, 8, 5),
          body: 'Bom treino hoje!',
          read: true,
        ),
      ),
    );

    expect(find.text('Bom treino hoje!'), findsOneWidget);
    expect(find.text('08:05'), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(find.byIcon(Icons.done), findsNothing);
  });

  testWidgets('mensagem própria ainda não lida mostra check simples',
      (tester) async {
    await tester.pumpWidget(
      _host(
        ChatBubble(
          isMine: true,
          timestamp: DateTime(2026, 9, 11, 8, 5),
          body: 'Oi!',
        ),
      ),
    );

    expect(find.byIcon(Icons.done), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  testWidgets('mensagem do outro participante não mostra indicador de leitura',
      (tester) async {
    await tester.pumpWidget(
      _host(
        ChatBubble(
          isMine: false,
          timestamp: DateTime(2026, 9, 11, 8, 6),
          body: 'Valeu, professor!',
        ),
      ),
    );

    expect(find.text('Valeu, professor!'), findsOneWidget);
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  testWidgets('envio otimista em voo não mostra check nem hora de leitura',
      (tester) async {
    await tester.pumpWidget(
      _host(
        ChatBubble(
          isMine: true,
          timestamp: DateTime(2026, 9, 11, 8, 7),
          body: 'Mandando…',
          sending: true,
        ),
      ),
    );

    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  testWidgets('envio que falhou oferece tentar de novo e descartar',
      (tester) async {
    var retried = false;
    var discarded = false;
    await tester.pumpWidget(
      _host(
        ChatBubble(
          isMine: true,
          timestamp: DateTime(2026, 9, 11, 8, 8),
          body: 'Isso não foi',
          failed: true,
          onRetry: () => retried = true,
          onDiscard: () => discarded = true,
        ),
      ),
    );

    final l10n = AppLocalizations.of(tester.element(find.byType(ChatBubble)));
    expect(find.text(l10n.chatMessageFailed), findsOneWidget);

    // P8.3: alvo de toque >= 48 dp mesmo com o texto em caption.
    for (final label in [l10n.chatMessageRetry, l10n.commonRemove]) {
      final size = tester.getSize(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
      );
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    }

    await tester.tap(find.text(l10n.chatMessageRetry));
    expect(retried, isTrue);

    await tester.tap(find.text(l10n.commonRemove));
    expect(discarded, isTrue);
  });
}
