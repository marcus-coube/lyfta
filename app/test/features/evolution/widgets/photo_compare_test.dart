import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/evolution/domain/progress_photo.dart';
import 'package:lyfta/features/evolution/widgets/photo_compare.dart';

ProgressPhoto _photo(String id) => ProgressPhoto(
  id: id,
  studentId: 's',
  takenAt: DateTime(2026, 11, 7),
  pose: Pose.front,
  mediaUrl: 'https://example.invalid/$id.jpg',
  createdAt: DateTime(2026, 11, 7),
);

Widget _host(List<ProgressPhoto> items) => MaterialApp(
  theme: LyTheme.dark(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(child: PhotoCompare(items: items)),
  ),
);

List<String> _shownUrls(WidgetTester tester) => tester
    .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
    .map((w) => w.imageUrl)
    .toList();

void main() {
  // E2E P4.4: com uma foto só os dois lados apontavam para ela; ao chegar a
  // segunda (mesma data), o comparador seguia mostrando a mesma dos dois lados.
  testWidgets('a segunda foto abre o par: mais antiga × mais recente', (
    tester,
  ) async {
    final first = _photo('a');
    await tester.pumpWidget(_host([first]));

    // A lista vem da mais recente para a mais antiga.
    await tester.pumpWidget(_host([_photo('b'), first]));
    await tester.pump();

    expect(_shownUrls(tester), [
      'https://example.invalid/a.jpg',
      'https://example.invalid/b.jpg',
    ]);
  });
}
