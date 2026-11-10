import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/account/data/account_repository.dart';
import 'package:lyfta/features/account/presentation/profile_section.dart';

class _FakeAccount extends AccountRepository {
  _FakeAccount() : super(Dio(), termsVersion: 'v1');

  final saved = <({String phone, String birth})>[];

  @override
  Future<MyProfile> profile() async => const MyProfile(phone: '11999990000');

  @override
  Future<MyProfile> updateProfile({
    required String phone,
    required String birthDate,
  }) async {
    saved.add((phone: phone, birth: birthDate));
    return MyProfile(phone: phone);
  }
}

void main() {
  testWidgets('aluno edita o telefone e salva por PATCH /v1/me',
      (tester) async {
    final fake = _FakeAccount();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(
          theme: LyTheme.dark(),
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
              body: SingleChildScrollView(child: ProfileSection()),),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('11999990000'), findsOneWidget);
    expect(find.text('Não informado'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('profile_phone')), '21988887777',);
    await tester.pump();
    await tester.tap(find.byKey(const Key('profile_save')));
    await tester.pumpAndSettle();

    expect(fake.saved, [(phone: '21988887777', birth: '')]);
    expect(find.text('Dados salvos.'), findsOneWidget);
  });
}
