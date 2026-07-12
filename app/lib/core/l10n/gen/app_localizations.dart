import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
    Locale('pt', 'PT')
  ];

  /// Nome do app, exibido no título da janela/aba.
  ///
  /// In pt, this message translates to:
  /// **'Lyfta'**
  String get appTitle;

  /// Rótulo de versão exibido na tela de login.
  ///
  /// In pt, this message translates to:
  /// **'v0.1.0'**
  String get appVersion;

  /// No description provided for @loginWelcomeBack.
  ///
  /// In pt, this message translates to:
  /// **'Bem-vindo de volta'**
  String get loginWelcomeBack;

  /// No description provided for @loginSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Entre para acompanhar seus treinos e sua evolução.'**
  String get loginSubtitle;

  /// No description provided for @loginEmailLabel.
  ///
  /// In pt, this message translates to:
  /// **'E-mail'**
  String get loginEmailLabel;

  /// No description provided for @loginEmailHint.
  ///
  /// In pt, this message translates to:
  /// **'voce@exemplo.com'**
  String get loginEmailHint;

  /// No description provided for @loginPasswordLabel.
  ///
  /// In pt, this message translates to:
  /// **'Senha'**
  String get loginPasswordLabel;

  /// No description provided for @loginPasswordHint.
  ///
  /// In pt, this message translates to:
  /// **'••••••••'**
  String get loginPasswordHint;

  /// No description provided for @loginForgotPassword.
  ///
  /// In pt, this message translates to:
  /// **'Esqueci minha senha'**
  String get loginForgotPassword;

  /// No description provided for @loginSubmit.
  ///
  /// In pt, this message translates to:
  /// **'Entrar'**
  String get loginSubmit;

  /// No description provided for @loginOrDivider.
  ///
  /// In pt, this message translates to:
  /// **'ou'**
  String get loginOrDivider;

  /// No description provided for @loginContinueWithGoogle.
  ///
  /// In pt, this message translates to:
  /// **'Continuar com Google'**
  String get loginContinueWithGoogle;

  /// No description provided for @loginNewHerePrefix.
  ///
  /// In pt, this message translates to:
  /// **'Novo por aqui? '**
  String get loginNewHerePrefix;

  /// No description provided for @loginNewHereSuffix.
  ///
  /// In pt, this message translates to:
  /// **'Crie a conta da sua academia.'**
  String get loginNewHereSuffix;

  /// No description provided for @loginTenantSheetTitle.
  ///
  /// In pt, this message translates to:
  /// **'Escolha uma conta'**
  String get loginTenantSheetTitle;

  /// No description provided for @loginTenantSheetSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Este e-mail está em mais de uma conta. Selecione com qual entrar.'**
  String get loginTenantSheetSubtitle;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In pt, this message translates to:
  /// **'Recuperar senha'**
  String get forgotPasswordTitle;

  /// No description provided for @forgotPasswordSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Informe seu e-mail para receber o link de redefinição.'**
  String get forgotPasswordSubtitle;

  /// No description provided for @forgotPasswordSubmit.
  ///
  /// In pt, this message translates to:
  /// **'Enviar link'**
  String get forgotPasswordSubmit;

  /// No description provided for @forgotPasswordBackToLogin.
  ///
  /// In pt, this message translates to:
  /// **'Voltar para o login'**
  String get forgotPasswordBackToLogin;

  /// No description provided for @forgotPasswordSuccess.
  ///
  /// In pt, this message translates to:
  /// **'Se este e-mail tiver conta, enviamos um link de redefinição.'**
  String get forgotPasswordSuccess;

  /// No description provided for @resetPasswordTitle.
  ///
  /// In pt, this message translates to:
  /// **'Definir nova senha'**
  String get resetPasswordTitle;

  /// No description provided for @resetPasswordSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Escolha uma nova senha para sua conta.'**
  String get resetPasswordSubtitle;

  /// No description provided for @resetPasswordNewLabel.
  ///
  /// In pt, this message translates to:
  /// **'Nova senha'**
  String get resetPasswordNewLabel;

  /// No description provided for @resetPasswordSubmit.
  ///
  /// In pt, this message translates to:
  /// **'Salvar nova senha'**
  String get resetPasswordSubmit;

  /// No description provided for @resetPasswordSuccess.
  ///
  /// In pt, this message translates to:
  /// **'Senha redefinida. Entre com a nova senha.'**
  String get resetPasswordSuccess;

  /// No description provided for @resetPasswordInvalidLink.
  ///
  /// In pt, this message translates to:
  /// **'Link inválido. Solicite uma nova recuperação de senha.'**
  String get resetPasswordInvalidLink;

  /// No description provided for @signupTitle.
  ///
  /// In pt, this message translates to:
  /// **'Crie a conta da sua academia'**
  String get signupTitle;

  /// No description provided for @signupSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Cadastre seu negócio para começar a gerenciar alunos e treinos.'**
  String get signupSubtitle;

  /// No description provided for @signupBusinessNameLabel.
  ///
  /// In pt, this message translates to:
  /// **'Nome do negócio'**
  String get signupBusinessNameLabel;

  /// No description provided for @signupBusinessNameHint.
  ///
  /// In pt, this message translates to:
  /// **'Academia Exemplo'**
  String get signupBusinessNameHint;

  /// No description provided for @signupSlugLabel.
  ///
  /// In pt, this message translates to:
  /// **'Identificador'**
  String get signupSlugLabel;

  /// No description provided for @signupSlugHint.
  ///
  /// In pt, this message translates to:
  /// **'academia-exemplo'**
  String get signupSlugHint;

  /// No description provided for @signupNameLabel.
  ///
  /// In pt, this message translates to:
  /// **'Seu nome'**
  String get signupNameLabel;

  /// No description provided for @signupNameHint.
  ///
  /// In pt, this message translates to:
  /// **'Como você se chama'**
  String get signupNameHint;

  /// No description provided for @signupSubmit.
  ///
  /// In pt, this message translates to:
  /// **'Criar conta'**
  String get signupSubmit;

  /// No description provided for @signupBackToLogin.
  ///
  /// In pt, this message translates to:
  /// **'Já tenho conta'**
  String get signupBackToLogin;

  /// No description provided for @inviteTitle.
  ///
  /// In pt, this message translates to:
  /// **'Aceitar convite'**
  String get inviteTitle;

  /// No description provided for @inviteSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Defina sua senha para ativar sua conta.'**
  String get inviteSubtitle;

  /// No description provided for @inviteNewPasswordLabel.
  ///
  /// In pt, this message translates to:
  /// **'Nova senha'**
  String get inviteNewPasswordLabel;

  /// No description provided for @inviteSubmit.
  ///
  /// In pt, this message translates to:
  /// **'Ativar conta'**
  String get inviteSubmit;

  /// No description provided for @inviteInvalidLink.
  ///
  /// In pt, this message translates to:
  /// **'Link de convite inválido ou expirado.'**
  String get inviteInvalidLink;

  /// No description provided for @homeStudentTitle.
  ///
  /// In pt, this message translates to:
  /// **'Hoje'**
  String get homeStudentTitle;

  /// No description provided for @homeStudentTabToday.
  ///
  /// In pt, this message translates to:
  /// **'Hoje'**
  String get homeStudentTabToday;

  /// No description provided for @homeStudentTabEvolution.
  ///
  /// In pt, this message translates to:
  /// **'Evolução'**
  String get homeStudentTabEvolution;

  /// No description provided for @homeStudentTabChat.
  ///
  /// In pt, this message translates to:
  /// **'Chat'**
  String get homeStudentTabChat;

  /// No description provided for @homeStudentTabAgenda.
  ///
  /// In pt, this message translates to:
  /// **'Agenda'**
  String get homeStudentTabAgenda;

  /// No description provided for @homeCoachTitle.
  ///
  /// In pt, this message translates to:
  /// **'Alunos'**
  String get homeCoachTitle;

  /// No description provided for @homeCoachTabStudents.
  ///
  /// In pt, this message translates to:
  /// **'Alunos'**
  String get homeCoachTabStudents;

  /// No description provided for @homeCoachTabWorkouts.
  ///
  /// In pt, this message translates to:
  /// **'Treinos'**
  String get homeCoachTabWorkouts;

  /// No description provided for @homeCoachTabChat.
  ///
  /// In pt, this message translates to:
  /// **'Chat'**
  String get homeCoachTabChat;

  /// No description provided for @homePlaceholderBody.
  ///
  /// In pt, this message translates to:
  /// **'Em construção.'**
  String get homePlaceholderBody;

  /// No description provided for @roleSwitcherCoach.
  ///
  /// In pt, this message translates to:
  /// **'Professor'**
  String get roleSwitcherCoach;

  /// No description provided for @roleSwitcherStudent.
  ///
  /// In pt, this message translates to:
  /// **'Aluno'**
  String get roleSwitcherStudent;

  /// No description provided for @errorInvalidCredentials.
  ///
  /// In pt, this message translates to:
  /// **'E-mail ou senha inválidos.'**
  String get errorInvalidCredentials;

  /// No description provided for @errorMultipleTenants.
  ///
  /// In pt, this message translates to:
  /// **'Este e-mail está em mais de uma conta. Escolha uma para continuar.'**
  String get errorMultipleTenants;

  /// No description provided for @errorValidation.
  ///
  /// In pt, this message translates to:
  /// **'Verifique o campo \"{field}\".'**
  String errorValidation(String field);

  /// No description provided for @errorEmailTaken.
  ///
  /// In pt, this message translates to:
  /// **'Este e-mail já está em uso.'**
  String get errorEmailTaken;

  /// No description provided for @errorInvalidToken.
  ///
  /// In pt, this message translates to:
  /// **'Link inválido ou expirado.'**
  String get errorInvalidToken;

  /// No description provided for @errorUnauthenticated.
  ///
  /// In pt, this message translates to:
  /// **'Sua sessão expirou. Entre novamente.'**
  String get errorUnauthenticated;

  /// No description provided for @errorForbidden.
  ///
  /// In pt, this message translates to:
  /// **'Você não tem permissão para essa ação.'**
  String get errorForbidden;

  /// No description provided for @errorSlugTaken.
  ///
  /// In pt, this message translates to:
  /// **'Este identificador já está em uso.'**
  String get errorSlugTaken;

  /// No description provided for @errorInternal.
  ///
  /// In pt, this message translates to:
  /// **'Algo deu errado. Tente novamente.'**
  String get errorInternal;

  /// No description provided for @errorNetwork.
  ///
  /// In pt, this message translates to:
  /// **'Sem conexão com o servidor. Verifique sua internet.'**
  String get errorNetwork;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'PT':
            return AppLocalizationsPtPt();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
