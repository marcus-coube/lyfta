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

  /// Rótulo de versão exibido na tela de login. `version` vem de AppConfig.appRelease, sem o número de build.
  ///
  /// In pt, this message translates to:
  /// **'v{version}'**
  String appVersion(String version);

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

  /// No description provided for @homeCoachTabStudents.
  ///
  /// In pt, this message translates to:
  /// **'Alunos'**
  String get homeCoachTabStudents;

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

  /// No description provided for @homeCoachTabLibrary.
  ///
  /// In pt, this message translates to:
  /// **'Biblioteca'**
  String get homeCoachTabLibrary;

  /// No description provided for @commonRetry.
  ///
  /// In pt, this message translates to:
  /// **'Tentar de novo'**
  String get commonRetry;

  /// No description provided for @commonSave.
  ///
  /// In pt, this message translates to:
  /// **'Salvar'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In pt, this message translates to:
  /// **'Cancelar'**
  String get commonCancel;

  /// No description provided for @commonCreate.
  ///
  /// In pt, this message translates to:
  /// **'Criar'**
  String get commonCreate;

  /// No description provided for @commonRemove.
  ///
  /// In pt, this message translates to:
  /// **'Remover'**
  String get commonRemove;

  /// No description provided for @commonLoadMore.
  ///
  /// In pt, this message translates to:
  /// **'Carregar mais'**
  String get commonLoadMore;

  /// No description provided for @commonShowPassword.
  ///
  /// In pt, this message translates to:
  /// **'Mostrar senha'**
  String get commonShowPassword;

  /// No description provided for @commonHidePassword.
  ///
  /// In pt, this message translates to:
  /// **'Ocultar senha'**
  String get commonHidePassword;

  /// No description provided for @libraryNewExercise.
  ///
  /// In pt, this message translates to:
  /// **'Novo exercício'**
  String get libraryNewExercise;

  /// No description provided for @librarySearchLabel.
  ///
  /// In pt, this message translates to:
  /// **'Buscar exercício'**
  String get librarySearchLabel;

  /// No description provided for @librarySearchHint.
  ///
  /// In pt, this message translates to:
  /// **'supino, agachamento…'**
  String get librarySearchHint;

  /// No description provided for @libraryFilterMuscle.
  ///
  /// In pt, this message translates to:
  /// **'Músculo'**
  String get libraryFilterMuscle;

  /// No description provided for @libraryFilterEquipment.
  ///
  /// In pt, this message translates to:
  /// **'Equipamento'**
  String get libraryFilterEquipment;

  /// No description provided for @libraryFilterAll.
  ///
  /// In pt, this message translates to:
  /// **'Todos'**
  String get libraryFilterAll;

  /// Selo do exercício da biblioteca global da Lyfta.
  ///
  /// In pt, this message translates to:
  /// **'Lyfta'**
  String get libraryGlobalBadge;

  /// No description provided for @libraryEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum exercício encontrado.'**
  String get libraryEmpty;

  /// No description provided for @exerciseFormNewTitle.
  ///
  /// In pt, this message translates to:
  /// **'Novo exercício'**
  String get exerciseFormNewTitle;

  /// No description provided for @exerciseFormEditTitle.
  ///
  /// In pt, this message translates to:
  /// **'Editar exercício'**
  String get exerciseFormEditTitle;

  /// No description provided for @exerciseFormDuplicateTitle.
  ///
  /// In pt, this message translates to:
  /// **'Duplicar exercício'**
  String get exerciseFormDuplicateTitle;

  /// No description provided for @exerciseFormDuplicateHint.
  ///
  /// In pt, this message translates to:
  /// **'Exercícios da Lyfta não podem ser editados. Salvar cria uma cópia na biblioteca da sua academia.'**
  String get exerciseFormDuplicateHint;

  /// No description provided for @exerciseFormNameLabel.
  ///
  /// In pt, this message translates to:
  /// **'Nome'**
  String get exerciseFormNameLabel;

  /// No description provided for @exerciseFormNameHint.
  ///
  /// In pt, this message translates to:
  /// **'Supino reto com barra'**
  String get exerciseFormNameHint;

  /// No description provided for @exerciseFormNameRequired.
  ///
  /// In pt, this message translates to:
  /// **'Informe o nome do exercício.'**
  String get exerciseFormNameRequired;

  /// No description provided for @exerciseFormMuscleLabel.
  ///
  /// In pt, this message translates to:
  /// **'Músculo principal'**
  String get exerciseFormMuscleLabel;

  /// No description provided for @exerciseFormEquipmentLabel.
  ///
  /// In pt, this message translates to:
  /// **'Equipamento'**
  String get exerciseFormEquipmentLabel;

  /// No description provided for @exerciseFormLevelLabel.
  ///
  /// In pt, this message translates to:
  /// **'Nível'**
  String get exerciseFormLevelLabel;

  /// No description provided for @exerciseFormInstructionsLabel.
  ///
  /// In pt, this message translates to:
  /// **'Instruções'**
  String get exerciseFormInstructionsLabel;

  /// No description provided for @exerciseFormInstructionsHint.
  ///
  /// In pt, this message translates to:
  /// **'Como executar o movimento'**
  String get exerciseFormInstructionsHint;

  /// No description provided for @exerciseFormMediaLabel.
  ///
  /// In pt, this message translates to:
  /// **'Mídia'**
  String get exerciseFormMediaLabel;

  /// No description provided for @exerciseFormMediaHint.
  ///
  /// In pt, this message translates to:
  /// **'GIF ou vídeo curto de até 50 MB.'**
  String get exerciseFormMediaHint;

  /// No description provided for @exerciseFormMediaPick.
  ///
  /// In pt, this message translates to:
  /// **'Escolher arquivo'**
  String get exerciseFormMediaPick;

  /// No description provided for @exerciseFormMediaReplace.
  ///
  /// In pt, this message translates to:
  /// **'Trocar arquivo'**
  String get exerciseFormMediaReplace;

  /// No description provided for @builderTitle.
  ///
  /// In pt, this message translates to:
  /// **'Montar treino'**
  String get builderTitle;

  /// No description provided for @builderDayTitle.
  ///
  /// In pt, this message translates to:
  /// **'Título do dia'**
  String get builderDayTitle;

  /// No description provided for @builderAddDay.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar dia'**
  String get builderAddDay;

  /// No description provided for @builderNoDays.
  ///
  /// In pt, this message translates to:
  /// **'Este plano ainda não tem nenhum dia. Comece pelo treino A.'**
  String get builderNoDays;

  /// No description provided for @builderAddBlock.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar bloco'**
  String get builderAddBlock;

  /// No description provided for @builderAddExercise.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar exercício'**
  String get builderAddExercise;

  /// No description provided for @builderAddSet.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar série'**
  String get builderAddSet;

  /// No description provided for @builderDuplicateSet.
  ///
  /// In pt, this message translates to:
  /// **'Duplicar série'**
  String get builderDuplicateSet;

  /// No description provided for @builderPickExercise.
  ///
  /// In pt, this message translates to:
  /// **'Escolher exercício'**
  String get builderPickExercise;

  /// No description provided for @builderUnknownExercise.
  ///
  /// In pt, this message translates to:
  /// **'Exercício removido da biblioteca'**
  String get builderUnknownExercise;

  /// No description provided for @builderBlockRest.
  ///
  /// In pt, this message translates to:
  /// **'Descanso (s)'**
  String get builderBlockRest;

  /// No description provided for @builderRepsMin.
  ///
  /// In pt, this message translates to:
  /// **'Reps mín.'**
  String get builderRepsMin;

  /// No description provided for @builderRepsMax.
  ///
  /// In pt, this message translates to:
  /// **'Reps máx.'**
  String get builderRepsMax;

  /// No description provided for @builderRestSeconds.
  ///
  /// In pt, this message translates to:
  /// **'Descanso (s)'**
  String get builderRestSeconds;

  /// No description provided for @builderTargetUnit.
  ///
  /// In pt, this message translates to:
  /// **'Unidade do alvo'**
  String get builderTargetUnit;

  /// No description provided for @builderTargetKg.
  ///
  /// In pt, this message translates to:
  /// **'Carga (kg)'**
  String get builderTargetKg;

  /// No description provided for @builderTargetPercent1rm.
  ///
  /// In pt, this message translates to:
  /// **'% de 1RM'**
  String get builderTargetPercent1rm;

  /// No description provided for @builderTargetRpe.
  ///
  /// In pt, this message translates to:
  /// **'RPE'**
  String get builderTargetRpe;

  /// No description provided for @builderTargetRir.
  ///
  /// In pt, this message translates to:
  /// **'RIR'**
  String get builderTargetRir;

  /// No description provided for @builderBlockStraight.
  ///
  /// In pt, this message translates to:
  /// **'Série simples'**
  String get builderBlockStraight;

  /// Bloco de dois exercícios alternados sem descanso entre eles.
  ///
  /// In pt, this message translates to:
  /// **'Bi-set'**
  String get builderBlockSuperset;

  /// No description provided for @builderBlockDropset.
  ///
  /// In pt, this message translates to:
  /// **'Drop set'**
  String get builderBlockDropset;

  /// No description provided for @builderBlockRestPause.
  ///
  /// In pt, this message translates to:
  /// **'Rest-pause'**
  String get builderBlockRestPause;

  /// No description provided for @builderBlockCircuit.
  ///
  /// In pt, this message translates to:
  /// **'Circuito'**
  String get builderBlockCircuit;

  /// No description provided for @builderSaveDraft.
  ///
  /// In pt, this message translates to:
  /// **'Salvar rascunho'**
  String get builderSaveDraft;

  /// No description provided for @builderSaved.
  ///
  /// In pt, this message translates to:
  /// **'Rascunho salvo'**
  String get builderSaved;

  /// No description provided for @builderDraftSaved.
  ///
  /// In pt, this message translates to:
  /// **'Rascunho salvo.'**
  String get builderDraftSaved;

  /// No description provided for @builderPublish.
  ///
  /// In pt, this message translates to:
  /// **'Publicar'**
  String get builderPublish;

  /// No description provided for @builderMoveUp.
  ///
  /// In pt, this message translates to:
  /// **'Mover para cima'**
  String get builderMoveUp;

  /// No description provided for @builderMoveDown.
  ///
  /// In pt, this message translates to:
  /// **'Mover para baixo'**
  String get builderMoveDown;

  /// No description provided for @studentsSearchLabel.
  ///
  /// In pt, this message translates to:
  /// **'Buscar aluno'**
  String get studentsSearchLabel;

  /// No description provided for @studentsSearchHint.
  ///
  /// In pt, this message translates to:
  /// **'nome ou e-mail'**
  String get studentsSearchHint;

  /// No description provided for @studentsEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum aluno ainda. Convide o primeiro.'**
  String get studentsEmpty;

  /// No description provided for @studentsNoPlan.
  ///
  /// In pt, this message translates to:
  /// **'Sem plano'**
  String get studentsNoPlan;

  /// No description provided for @studentsNewPlan.
  ///
  /// In pt, this message translates to:
  /// **'Novo plano'**
  String get studentsNewPlan;

  /// No description provided for @studentsOpenPlan.
  ///
  /// In pt, this message translates to:
  /// **'Abrir'**
  String get studentsOpenPlan;

  /// No description provided for @studentsNewPlanTitle.
  ///
  /// In pt, this message translates to:
  /// **'Novo plano'**
  String get studentsNewPlanTitle;

  /// No description provided for @studentsNewPlanDefaultTitle.
  ///
  /// In pt, this message translates to:
  /// **'Treino A/B'**
  String get studentsNewPlanDefaultTitle;

  /// No description provided for @studentsPlanTitleLabel.
  ///
  /// In pt, this message translates to:
  /// **'Nome do plano'**
  String get studentsPlanTitleLabel;

  /// Aluno que ainda não aceitou o convite.
  ///
  /// In pt, this message translates to:
  /// **'convite pendente'**
  String get studentsPendingBadge;

  /// No description provided for @studentsInviteTitle.
  ///
  /// In pt, this message translates to:
  /// **'Convidar aluno'**
  String get studentsInviteTitle;

  /// No description provided for @studentsInviteNameLabel.
  ///
  /// In pt, this message translates to:
  /// **'Nome'**
  String get studentsInviteNameLabel;

  /// No description provided for @studentsInviteEmailLabel.
  ///
  /// In pt, this message translates to:
  /// **'E-mail'**
  String get studentsInviteEmailLabel;

  /// No description provided for @studentsInviteSubmit.
  ///
  /// In pt, this message translates to:
  /// **'Convidar'**
  String get studentsInviteSubmit;

  /// No description provided for @errorNotFound.
  ///
  /// In pt, this message translates to:
  /// **'Não encontramos o que você procurava.'**
  String get errorNotFound;

  /// No description provided for @errorInvalidCursor.
  ///
  /// In pt, this message translates to:
  /// **'A lista mudou. Recarregue a página.'**
  String get errorInvalidCursor;

  /// No description provided for @errorExerciseIsGlobal.
  ///
  /// In pt, this message translates to:
  /// **'Exercícios da Lyfta não podem ser editados. Duplique para criar o seu.'**
  String get errorExerciseIsGlobal;

  /// No description provided for @errorUnsupportedMedia.
  ///
  /// In pt, this message translates to:
  /// **'Formato não aceito. Use GIF, MP4 ou WebM.'**
  String get errorUnsupportedMedia;

  /// No description provided for @errorFileTooLarge.
  ///
  /// In pt, this message translates to:
  /// **'Arquivo grande demais. O limite é 50 MB.'**
  String get errorFileTooLarge;

  /// No description provided for @errorPlanNoDays.
  ///
  /// In pt, this message translates to:
  /// **'Adicione ao menos um dia antes de publicar.'**
  String get errorPlanNoDays;

  /// No description provided for @errorPlanDayWithoutBlock.
  ///
  /// In pt, this message translates to:
  /// **'Há um dia sem nenhum bloco. Complete antes de publicar.'**
  String get errorPlanDayWithoutBlock;

  /// No description provided for @errorPlanBlockWithoutExercise.
  ///
  /// In pt, this message translates to:
  /// **'Há um bloco sem exercício. Complete antes de publicar.'**
  String get errorPlanBlockWithoutExercise;

  /// No description provided for @errorPlanExerciseWithoutSet.
  ///
  /// In pt, this message translates to:
  /// **'Há um exercício sem série prescrita. Complete antes de publicar.'**
  String get errorPlanExerciseWithoutSet;

  /// No description provided for @errorNoDraftToPublish.
  ///
  /// In pt, this message translates to:
  /// **'Não há alterações novas para publicar.'**
  String get errorNoDraftToPublish;

  /// No description provided for @errorUnknownExercise.
  ///
  /// In pt, this message translates to:
  /// **'Um dos exercícios não está mais disponível na biblioteca.'**
  String get errorUnknownExercise;

  /// No description provided for @muscleChest.
  ///
  /// In pt, this message translates to:
  /// **'Peitoral'**
  String get muscleChest;

  /// No description provided for @muscleBack.
  ///
  /// In pt, this message translates to:
  /// **'Costas'**
  String get muscleBack;

  /// No description provided for @muscleLats.
  ///
  /// In pt, this message translates to:
  /// **'Dorsais'**
  String get muscleLats;

  /// No description provided for @muscleTraps.
  ///
  /// In pt, this message translates to:
  /// **'Trapézio'**
  String get muscleTraps;

  /// No description provided for @muscleLowerBack.
  ///
  /// In pt, this message translates to:
  /// **'Lombar'**
  String get muscleLowerBack;

  /// No description provided for @muscleShoulders.
  ///
  /// In pt, this message translates to:
  /// **'Ombros'**
  String get muscleShoulders;

  /// No description provided for @muscleBiceps.
  ///
  /// In pt, this message translates to:
  /// **'Bíceps'**
  String get muscleBiceps;

  /// No description provided for @muscleTriceps.
  ///
  /// In pt, this message translates to:
  /// **'Tríceps'**
  String get muscleTriceps;

  /// No description provided for @muscleForearms.
  ///
  /// In pt, this message translates to:
  /// **'Antebraço'**
  String get muscleForearms;

  /// No description provided for @muscleAbs.
  ///
  /// In pt, this message translates to:
  /// **'Abdômen'**
  String get muscleAbs;

  /// No description provided for @muscleObliques.
  ///
  /// In pt, this message translates to:
  /// **'Oblíquos'**
  String get muscleObliques;

  /// No description provided for @muscleQuadriceps.
  ///
  /// In pt, this message translates to:
  /// **'Quadríceps'**
  String get muscleQuadriceps;

  /// No description provided for @muscleHamstrings.
  ///
  /// In pt, this message translates to:
  /// **'Posterior de coxa'**
  String get muscleHamstrings;

  /// No description provided for @muscleGlutes.
  ///
  /// In pt, this message translates to:
  /// **'Glúteos'**
  String get muscleGlutes;

  /// No description provided for @muscleCalves.
  ///
  /// In pt, this message translates to:
  /// **'Panturrilha'**
  String get muscleCalves;

  /// No description provided for @muscleAdductors.
  ///
  /// In pt, this message translates to:
  /// **'Adutores'**
  String get muscleAdductors;

  /// No description provided for @muscleAbductors.
  ///
  /// In pt, this message translates to:
  /// **'Abdutores'**
  String get muscleAbductors;

  /// No description provided for @muscleFullBody.
  ///
  /// In pt, this message translates to:
  /// **'Corpo inteiro'**
  String get muscleFullBody;

  /// No description provided for @equipmentBarbell.
  ///
  /// In pt, this message translates to:
  /// **'Barra'**
  String get equipmentBarbell;

  /// No description provided for @equipmentDumbbell.
  ///
  /// In pt, this message translates to:
  /// **'Halteres'**
  String get equipmentDumbbell;

  /// No description provided for @equipmentMachine.
  ///
  /// In pt, this message translates to:
  /// **'Máquina'**
  String get equipmentMachine;

  /// No description provided for @equipmentCable.
  ///
  /// In pt, this message translates to:
  /// **'Polia'**
  String get equipmentCable;

  /// No description provided for @equipmentSmith.
  ///
  /// In pt, this message translates to:
  /// **'Smith'**
  String get equipmentSmith;

  /// No description provided for @equipmentBodyweight.
  ///
  /// In pt, this message translates to:
  /// **'Peso do corpo'**
  String get equipmentBodyweight;

  /// No description provided for @equipmentKettlebell.
  ///
  /// In pt, this message translates to:
  /// **'Kettlebell'**
  String get equipmentKettlebell;

  /// No description provided for @equipmentBand.
  ///
  /// In pt, this message translates to:
  /// **'Elástico'**
  String get equipmentBand;

  /// No description provided for @equipmentBench.
  ///
  /// In pt, this message translates to:
  /// **'Banco'**
  String get equipmentBench;

  /// No description provided for @equipmentOther.
  ///
  /// In pt, this message translates to:
  /// **'Outro'**
  String get equipmentOther;

  /// No description provided for @levelBeginner.
  ///
  /// In pt, this message translates to:
  /// **'Iniciante'**
  String get levelBeginner;

  /// No description provided for @levelIntermediate.
  ///
  /// In pt, this message translates to:
  /// **'Intermediário'**
  String get levelIntermediate;

  /// No description provided for @levelAdvanced.
  ///
  /// In pt, this message translates to:
  /// **'Avançado'**
  String get levelAdvanced;

  /// Rótulo da versão em edição.
  ///
  /// In pt, this message translates to:
  /// **'rascunho v{version}'**
  String builderDraftVersion(int version);

  /// Rótulo da versão publicada.
  ///
  /// In pt, this message translates to:
  /// **'v{version} publicada'**
  String builderPublishedVersion(int version);

  /// Corpo da confirmação de publicação.
  ///
  /// In pt, this message translates to:
  /// **'Publicar congela esta versão e envia o treino para o aluno. A versão {version} não poderá mais ser editada.'**
  String builderPublishBody(int version);

  /// Confirmação após publicar.
  ///
  /// In pt, this message translates to:
  /// **'Versão {version} publicada.'**
  String builderPublished(int version);

  /// Plano ativo do aluno com o número da versão.
  ///
  /// In pt, this message translates to:
  /// **'{title} · v{version}'**
  String studentsPlanActive(String title, int version);

  /// Plano do aluno que ainda não foi publicado.
  ///
  /// In pt, this message translates to:
  /// **'{title} · rascunho'**
  String studentsPlanDraft(String title);

  /// No description provided for @builderPublishTitle.
  ///
  /// In pt, this message translates to:
  /// **'Publicar treino?'**
  String get builderPublishTitle;

  /// Estado da tela Hoje quando o aluno não tem plano ativo.
  ///
  /// In pt, this message translates to:
  /// **'Seu professor ainda não montou seu treino'**
  String get todayNoPlanTitle;

  /// Explicação do estado sem plano.
  ///
  /// In pt, this message translates to:
  /// **'Assim que ele publicar o plano, o treino do dia aparece aqui.'**
  String get todayNoPlanBody;

  /// Estado da tela Hoje sem treino programado.
  ///
  /// In pt, this message translates to:
  /// **'Dia de descanso'**
  String get todayRestTitle;

  /// Explicação do dia de descanso.
  ///
  /// In pt, this message translates to:
  /// **'Nada programado para hoje. Descanso também faz parte do treino.'**
  String get todayRestBody;

  /// Botão que começa a execução do treino do dia.
  ///
  /// In pt, this message translates to:
  /// **'Iniciar treino'**
  String get todayStart;

  /// Botão quando já existe uma sessão aberta no aparelho.
  ///
  /// In pt, this message translates to:
  /// **'Continuar treino'**
  String get todayResume;

  /// Aviso discreto de que o conteúdo veio do cache local.
  ///
  /// In pt, this message translates to:
  /// **'Sem conexão — este é o treino baixado no aparelho.'**
  String get todayOffline;

  /// Erro ao carregar a tela Hoje sem cache local.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível carregar o treino.'**
  String get todayLoadError;

  /// Chip do exercício que o aluno nunca executou.
  ///
  /// In pt, this message translates to:
  /// **'Primeira vez'**
  String get todayNoPreviousLoad;

  /// Título do histórico recente na tela Hoje.
  ///
  /// In pt, this message translates to:
  /// **'Últimos treinos'**
  String get todayRecentTitle;

  /// Indicador de sincronização em andamento.
  ///
  /// In pt, this message translates to:
  /// **'Sincronizando…'**
  String get todaySyncing;

  /// Indicador de fila vazia.
  ///
  /// In pt, this message translates to:
  /// **'Tudo sincronizado'**
  String get todaySynced;

  /// Dia publicado sem bloco algum.
  ///
  /// In pt, this message translates to:
  /// **'Este treino não tem exercícios.'**
  String get todayEmptyDay;

  /// Rótulo do campo de repetições executadas.
  ///
  /// In pt, this message translates to:
  /// **'Reps'**
  String get sessionReps;

  /// Rótulo do campo de carga executada.
  ///
  /// In pt, this message translates to:
  /// **'Carga (kg)'**
  String get sessionLoadKg;

  /// Ação que grava a série executada.
  ///
  /// In pt, this message translates to:
  /// **'Registrar série'**
  String get sessionMarkDone;

  /// Estado da série já registrada.
  ///
  /// In pt, this message translates to:
  /// **'Registrada'**
  String get sessionSetDone;

  /// Título do cronômetro de descanso.
  ///
  /// In pt, this message translates to:
  /// **'Descanso'**
  String get sessionRestTitle;

  /// Ação que encerra o descanso antes da hora.
  ///
  /// In pt, this message translates to:
  /// **'Pular descanso'**
  String get sessionRestSkip;

  /// Fim da contagem de descanso.
  ///
  /// In pt, this message translates to:
  /// **'Descanso concluído'**
  String get sessionRestOver;

  /// Título da notificação local do descanso.
  ///
  /// In pt, this message translates to:
  /// **'Fim do descanso'**
  String get sessionRestNotificationTitle;

  /// Ação que encerra a sessão.
  ///
  /// In pt, this message translates to:
  /// **'Finalizar treino'**
  String get sessionFinish;

  /// Título da confirmação de fim de treino.
  ///
  /// In pt, this message translates to:
  /// **'Finalizar treino?'**
  String get sessionFinishTitle;

  /// Título do resumo do fim do treino.
  ///
  /// In pt, this message translates to:
  /// **'Treino concluído'**
  String get sessionSummaryTitle;

  /// Rótulo do total de séries no resumo.
  ///
  /// In pt, this message translates to:
  /// **'Séries'**
  String get sessionSummarySets;

  /// Rótulo do volume total no resumo.
  ///
  /// In pt, this message translates to:
  /// **'Volume'**
  String get sessionSummaryVolume;

  /// Rótulo da duração no resumo.
  ///
  /// In pt, this message translates to:
  /// **'Duração'**
  String get sessionSummaryDuration;

  /// Fecha o resumo do treino.
  ///
  /// In pt, this message translates to:
  /// **'Fechar'**
  String get sessionSummaryClose;

  /// Prescrição sem faixa de repetições.
  ///
  /// In pt, this message translates to:
  /// **'reps livres'**
  String get sessionTargetFreeReps;

  /// Cabeçalho do dia da rotação (A, B, C…).
  ///
  /// In pt, this message translates to:
  /// **'Treino {label}'**
  String todayDayHeading(String label);

  /// Qual treino a rotação entrega depois do de hoje.
  ///
  /// In pt, this message translates to:
  /// **'Próximo: treino {label}'**
  String todayNextWorkout(String label);

  /// Ação que abre a lista de treinos do rodízio.
  ///
  /// In pt, this message translates to:
  /// **'Trocar treino de hoje'**
  String get todaySwitch;

  /// Título da folha de troca de treino.
  ///
  /// In pt, this message translates to:
  /// **'Qual treino você quer fazer hoje?'**
  String get todaySwitchTitle;

  /// Marca o dia que a rotação já entrega hoje.
  ///
  /// In pt, this message translates to:
  /// **'Hoje'**
  String get todaySwitchCurrent;

  /// A troca de treino é a única ação do aluno que exige rede.
  ///
  /// In pt, this message translates to:
  /// **'Sem conexão — trocar o treino precisa de internet.'**
  String get todaySwitchOffline;

  /// Falha genérica ao trocar o treino do dia.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível trocar o treino.'**
  String get todaySwitchError;

  /// Chip com a maior carga da última vez que o exercício foi feito.
  ///
  /// In pt, this message translates to:
  /// **'Anterior: {load} kg'**
  String todayPreviousLoad(String load);

  /// Quantidade de séries prescritas de um exercício.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =1{1 série} other{{count} séries}}'**
  String todaySetsCount(int count);

  /// Linha do histórico recente.
  ///
  /// In pt, this message translates to:
  /// **'Treino {label} · {sets} séries · {volume} kg'**
  String todayRecentEntry(String label, int sets, String volume);

  /// Fila de execução ainda não sincronizada.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =1{1 registro por enviar} other{{count} registros por enviar}}'**
  String todaySyncPending(int count);

  /// Título do player de execução.
  ///
  /// In pt, this message translates to:
  /// **'Treino {label}'**
  String sessionTitle(String label);

  /// Rótulo de uma série dentro do exercício.
  ///
  /// In pt, this message translates to:
  /// **'Série {number}'**
  String sessionSet(int number);

  /// Título do diálogo de correção de uma série já registrada.
  ///
  /// In pt, this message translates to:
  /// **'Corrigir série {number}'**
  String sessionEditSet(int number);

  /// Faixa de repetições prescrita.
  ///
  /// In pt, this message translates to:
  /// **'{min}–{max} reps'**
  String sessionTargetRepsRange(int min, int max);

  /// Repetições prescritas sem faixa.
  ///
  /// In pt, this message translates to:
  /// **'{reps} reps'**
  String sessionTargetReps(int reps);

  /// Alvo de carga prescrito com a unidade (kg, %1RM, RPE, RIR).
  ///
  /// In pt, this message translates to:
  /// **'{value} {unit}'**
  String sessionTargetWithUnit(String value, String unit);

  /// Corpo da notificação de fim de descanso.
  ///
  /// In pt, this message translates to:
  /// **'Hora da próxima série de {exercise}.'**
  String sessionRestNotificationBody(String exercise);

  /// Corpo da confirmação de fim de treino.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =0{Você não registrou nenhuma série — o treino de hoje não será marcado como feito.} =1{Você registrou 1 série. O treino de hoje será concluído.} other{Você registrou {count} séries. O treino de hoje será concluído.}}'**
  String sessionFinishBody(int count);

  /// Duração do treino em minutos.
  ///
  /// In pt, this message translates to:
  /// **'{minutes} min'**
  String sessionDurationMinutes(int minutes);

  /// Resumo de uma série já registrada no player.
  ///
  /// In pt, this message translates to:
  /// **'{reps} reps · {load} kg'**
  String sessionLoggedSet(String reps, String load);

  /// Marcador de valor não informado numa série registrada.
  ///
  /// In pt, this message translates to:
  /// **'—'**
  String get sessionEmptyValue;

  /// Botão da lista de alunos que abre a ficha de evolução.
  ///
  /// In pt, this message translates to:
  /// **'Evolução'**
  String get studentsOpenEvolution;

  /// Botão da lista de alunos que abre (ou cria) a conversa com o aluno.
  ///
  /// In pt, this message translates to:
  /// **'Chat'**
  String get studentsOpenChat;

  /// Aba de resumo na ficha de evolução do aluno (só o professor vê).
  ///
  /// In pt, this message translates to:
  /// **'Resumo'**
  String get evolutionTabSummary;

  /// No description provided for @evolutionTabLoad.
  ///
  /// In pt, this message translates to:
  /// **'Carga'**
  String get evolutionTabLoad;

  /// No description provided for @evolutionTabMeasurements.
  ///
  /// In pt, this message translates to:
  /// **'Medidas'**
  String get evolutionTabMeasurements;

  /// No description provided for @evolutionTabPhotos.
  ///
  /// In pt, this message translates to:
  /// **'Fotos'**
  String get evolutionTabPhotos;

  /// Aba com a fila de avaliações de treino do aluno (só o professor vê).
  ///
  /// In pt, this message translates to:
  /// **'Check-ins'**
  String get evolutionTabCheckins;

  /// Título do cartão com a medida corporal mais recente do aluno.
  ///
  /// In pt, this message translates to:
  /// **'Última medida'**
  String get evolutionSummaryLatestMeasurement;

  /// Título do cartão com a leitura de bioimpedância mais recente.
  ///
  /// In pt, this message translates to:
  /// **'Última bioimpedância'**
  String get evolutionSummaryLatestBioimpedance;

  /// Rótulo da contagem de fotos no resumo do aluno.
  ///
  /// In pt, this message translates to:
  /// **'Fotos de evolução'**
  String get evolutionSummaryPhotoCount;

  /// Título da ficha de evolução do aluno aberta pelo professor.
  ///
  /// In pt, this message translates to:
  /// **'Evolução'**
  String get evolutionStudentTitle;

  /// No description provided for @evolutionMeasurementsSection.
  ///
  /// In pt, this message translates to:
  /// **'Medidas corporais'**
  String get evolutionMeasurementsSection;

  /// No description provided for @evolutionAddMeasurement.
  ///
  /// In pt, this message translates to:
  /// **'Nova medida'**
  String get evolutionAddMeasurement;

  /// No description provided for @evolutionBioimpedanceSection.
  ///
  /// In pt, this message translates to:
  /// **'Bioimpedância'**
  String get evolutionBioimpedanceSection;

  /// No description provided for @evolutionAddBioimpedance.
  ///
  /// In pt, this message translates to:
  /// **'Nova leitura'**
  String get evolutionAddBioimpedance;

  /// No description provided for @evolutionPhotosSection.
  ///
  /// In pt, this message translates to:
  /// **'Fotos de evolução'**
  String get evolutionPhotosSection;

  /// No description provided for @evolutionAddPhoto.
  ///
  /// In pt, this message translates to:
  /// **'Nova foto'**
  String get evolutionAddPhoto;

  /// No description provided for @evolutionDeleteTitle.
  ///
  /// In pt, this message translates to:
  /// **'Apagar registro?'**
  String get evolutionDeleteTitle;

  /// No description provided for @evolutionDeleteBody.
  ///
  /// In pt, this message translates to:
  /// **'Essa ação não pode ser desfeita.'**
  String get evolutionDeleteBody;

  /// No description provided for @evolutionPhotosCompareTitle.
  ///
  /// In pt, this message translates to:
  /// **'Comparar antes/depois'**
  String get evolutionPhotosCompareTitle;

  /// No description provided for @evolutionDateLabel.
  ///
  /// In pt, this message translates to:
  /// **'Data'**
  String get evolutionDateLabel;

  /// No description provided for @evolutionValueHint.
  ///
  /// In pt, this message translates to:
  /// **'0'**
  String get evolutionValueHint;

  /// No description provided for @evolutionNotesLabel.
  ///
  /// In pt, this message translates to:
  /// **'Observações'**
  String get evolutionNotesLabel;

  /// No description provided for @measurementFormEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Preencha ao menos uma medida.'**
  String get measurementFormEmpty;

  /// No description provided for @evolutionMeasurementsEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma medida registrada ainda.'**
  String get evolutionMeasurementsEmpty;

  /// No description provided for @evolutionBioimpedanceEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma leitura de bioimpedância ainda.'**
  String get evolutionBioimpedanceEmpty;

  /// No description provided for @evolutionMetricMaxLoad.
  ///
  /// In pt, this message translates to:
  /// **'Carga máxima'**
  String get evolutionMetricMaxLoad;

  /// No description provided for @evolutionMetricVolume.
  ///
  /// In pt, this message translates to:
  /// **'Volume'**
  String get evolutionMetricVolume;

  /// No description provided for @evolutionRangeOneMonth.
  ///
  /// In pt, this message translates to:
  /// **'1 mês'**
  String get evolutionRangeOneMonth;

  /// No description provided for @evolutionRangeThreeMonths.
  ///
  /// In pt, this message translates to:
  /// **'3 meses'**
  String get evolutionRangeThreeMonths;

  /// No description provided for @evolutionRangeSixMonths.
  ///
  /// In pt, this message translates to:
  /// **'6 meses'**
  String get evolutionRangeSixMonths;

  /// No description provided for @evolutionRangeAll.
  ///
  /// In pt, this message translates to:
  /// **'Tudo'**
  String get evolutionRangeAll;

  /// No description provided for @evolutionNoDataForRange.
  ///
  /// In pt, this message translates to:
  /// **'Sem registros neste período.'**
  String get evolutionNoDataForRange;

  /// No description provided for @evolutionNoExercisesYet.
  ///
  /// In pt, this message translates to:
  /// **'Você ainda não registrou nenhuma série. Treine para ver o gráfico aqui.'**
  String get evolutionNoExercisesYet;

  /// No description provided for @evolutionPhotosEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma foto ainda.'**
  String get evolutionPhotosEmpty;

  /// No description provided for @evolutionPhotosCompareNeedTwo.
  ///
  /// In pt, this message translates to:
  /// **'Registre pelo menos duas fotos para comparar.'**
  String get evolutionPhotosCompareNeedTwo;

  /// No description provided for @evolutionPoseFront.
  ///
  /// In pt, this message translates to:
  /// **'Frente'**
  String get evolutionPoseFront;

  /// No description provided for @evolutionPoseSide.
  ///
  /// In pt, this message translates to:
  /// **'Lado'**
  String get evolutionPoseSide;

  /// No description provided for @evolutionPoseBack.
  ///
  /// In pt, this message translates to:
  /// **'Costas'**
  String get evolutionPoseBack;

  /// No description provided for @evolutionNewMeasurement.
  ///
  /// In pt, this message translates to:
  /// **'Nova medida'**
  String get evolutionNewMeasurement;

  /// No description provided for @evolutionNewBioimpedance.
  ///
  /// In pt, this message translates to:
  /// **'Nova leitura de bioimpedância'**
  String get evolutionNewBioimpedance;

  /// No description provided for @evolutionNewPhoto.
  ///
  /// In pt, this message translates to:
  /// **'Nova foto'**
  String get evolutionNewPhoto;

  /// No description provided for @evolutionPhotoFromCamera.
  ///
  /// In pt, this message translates to:
  /// **'Câmera'**
  String get evolutionPhotoFromCamera;

  /// No description provided for @evolutionPhotoFromGallery.
  ///
  /// In pt, this message translates to:
  /// **'Galeria'**
  String get evolutionPhotoFromGallery;

  /// No description provided for @evolutionPhotoEmptyPreview.
  ///
  /// In pt, this message translates to:
  /// **'Escolha uma foto para continuar.'**
  String get evolutionPhotoEmptyPreview;

  /// No description provided for @evolutionPhotoRequired.
  ///
  /// In pt, this message translates to:
  /// **'Escolha uma foto antes de salvar.'**
  String get evolutionPhotoRequired;

  /// No description provided for @evolutionPhotoPickError.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível processar a foto. Tente outra.'**
  String get evolutionPhotoPickError;

  /// No description provided for @measurementFieldWeightKg.
  ///
  /// In pt, this message translates to:
  /// **'Peso (kg)'**
  String get measurementFieldWeightKg;

  /// No description provided for @measurementFieldHeightCm.
  ///
  /// In pt, this message translates to:
  /// **'Altura (cm)'**
  String get measurementFieldHeightCm;

  /// No description provided for @measurementFieldNeckCm.
  ///
  /// In pt, this message translates to:
  /// **'Pescoço (cm)'**
  String get measurementFieldNeckCm;

  /// No description provided for @measurementFieldShoulderCm.
  ///
  /// In pt, this message translates to:
  /// **'Ombro (cm)'**
  String get measurementFieldShoulderCm;

  /// No description provided for @measurementFieldChestCm.
  ///
  /// In pt, this message translates to:
  /// **'Peito (cm)'**
  String get measurementFieldChestCm;

  /// No description provided for @measurementFieldWaistCm.
  ///
  /// In pt, this message translates to:
  /// **'Cintura (cm)'**
  String get measurementFieldWaistCm;

  /// No description provided for @measurementFieldAbdomenCm.
  ///
  /// In pt, this message translates to:
  /// **'Abdômen (cm)'**
  String get measurementFieldAbdomenCm;

  /// No description provided for @measurementFieldHipCm.
  ///
  /// In pt, this message translates to:
  /// **'Quadril (cm)'**
  String get measurementFieldHipCm;

  /// No description provided for @measurementFieldArmLCm.
  ///
  /// In pt, this message translates to:
  /// **'Braço esq. (cm)'**
  String get measurementFieldArmLCm;

  /// No description provided for @measurementFieldArmRCm.
  ///
  /// In pt, this message translates to:
  /// **'Braço dir. (cm)'**
  String get measurementFieldArmRCm;

  /// No description provided for @measurementFieldThighLCm.
  ///
  /// In pt, this message translates to:
  /// **'Coxa esq. (cm)'**
  String get measurementFieldThighLCm;

  /// No description provided for @measurementFieldThighRCm.
  ///
  /// In pt, this message translates to:
  /// **'Coxa dir. (cm)'**
  String get measurementFieldThighRCm;

  /// No description provided for @measurementFieldCalfLCm.
  ///
  /// In pt, this message translates to:
  /// **'Panturrilha esq. (cm)'**
  String get measurementFieldCalfLCm;

  /// No description provided for @measurementFieldCalfRCm.
  ///
  /// In pt, this message translates to:
  /// **'Panturrilha dir. (cm)'**
  String get measurementFieldCalfRCm;

  /// No description provided for @bioimpedanceFieldBodyFatPct.
  ///
  /// In pt, this message translates to:
  /// **'% de gordura'**
  String get bioimpedanceFieldBodyFatPct;

  /// No description provided for @bioimpedanceFieldMuscleMassKg.
  ///
  /// In pt, this message translates to:
  /// **'Massa muscular (kg)'**
  String get bioimpedanceFieldMuscleMassKg;

  /// No description provided for @bioimpedanceFieldVisceralFat.
  ///
  /// In pt, this message translates to:
  /// **'Gordura visceral'**
  String get bioimpedanceFieldVisceralFat;

  /// No description provided for @bioimpedanceFieldBodyWaterPct.
  ///
  /// In pt, this message translates to:
  /// **'% de água corporal'**
  String get bioimpedanceFieldBodyWaterPct;

  /// No description provided for @bioimpedanceFieldBoneMassKg.
  ///
  /// In pt, this message translates to:
  /// **'Massa óssea (kg)'**
  String get bioimpedanceFieldBoneMassKg;

  /// No description provided for @bioimpedanceFieldBmrKcal.
  ///
  /// In pt, this message translates to:
  /// **'Taxa metabólica basal (kcal)'**
  String get bioimpedanceFieldBmrKcal;

  /// Título da tela de conversa quando o nome do outro participante não está disponível.
  ///
  /// In pt, this message translates to:
  /// **'Chat'**
  String get chatTitleFallback;

  /// No description provided for @chatEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma mensagem ainda. Diga oi!'**
  String get chatEmpty;

  /// No description provided for @chatConversationsEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma conversa ainda.'**
  String get chatConversationsEmpty;

  /// Estado vazio da aba Chat do aluno, acima do botão que abre a conversa com o professor.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma conversa ainda. Fale com seu professor por aqui.'**
  String get chatStudentNoConversation;

  /// Botão do aluno para abrir a conversa com o próprio professor.
  ///
  /// In pt, this message translates to:
  /// **'Falar com meu professor'**
  String get chatStudentStart;

  /// No description provided for @chatNoMessagesYet.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma mensagem ainda'**
  String get chatNoMessagesYet;

  /// Prévia da última mensagem na lista de conversas quando ela é uma imagem.
  ///
  /// In pt, this message translates to:
  /// **'📷 Foto'**
  String get chatImagePreview;

  /// No description provided for @chatMessageHint.
  ///
  /// In pt, this message translates to:
  /// **'Escreva uma mensagem…'**
  String get chatMessageHint;

  /// No description provided for @chatAttachImage.
  ///
  /// In pt, this message translates to:
  /// **'Anexar foto'**
  String get chatAttachImage;

  /// No description provided for @chatSend.
  ///
  /// In pt, this message translates to:
  /// **'Enviar'**
  String get chatSend;

  /// No description provided for @chatMessageFailed.
  ///
  /// In pt, this message translates to:
  /// **'Não enviada.'**
  String get chatMessageFailed;

  /// No description provided for @chatMessageRetry.
  ///
  /// In pt, this message translates to:
  /// **'Tentar de novo'**
  String get chatMessageRetry;

  /// No description provided for @checkinTitle.
  ///
  /// In pt, this message translates to:
  /// **'Como foi o treino?'**
  String get checkinTitle;

  /// No description provided for @checkinSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Sua avaliação ajuda seu professor a ajustar o próximo treino.'**
  String get checkinSubtitle;

  /// No description provided for @checkinRatingLabel.
  ///
  /// In pt, this message translates to:
  /// **'Nota geral'**
  String get checkinRatingLabel;

  /// No description provided for @checkinDifficultyLabel.
  ///
  /// In pt, this message translates to:
  /// **'Dificuldade'**
  String get checkinDifficultyLabel;

  /// No description provided for @checkinPainLabel.
  ///
  /// In pt, this message translates to:
  /// **'Sentiu dor?'**
  String get checkinPainLabel;

  /// No description provided for @checkinPainNone.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma'**
  String get checkinPainNone;

  /// No description provided for @checkinPainMild.
  ///
  /// In pt, this message translates to:
  /// **'Leve'**
  String get checkinPainMild;

  /// No description provided for @checkinPainStrong.
  ///
  /// In pt, this message translates to:
  /// **'Forte'**
  String get checkinPainStrong;

  /// No description provided for @checkinPainWhereLabel.
  ///
  /// In pt, this message translates to:
  /// **'Onde?'**
  String get checkinPainWhereLabel;

  /// No description provided for @checkinCommentLabel.
  ///
  /// In pt, this message translates to:
  /// **'Comentário (opcional)'**
  String get checkinCommentLabel;

  /// No description provided for @checkinSubmit.
  ///
  /// In pt, this message translates to:
  /// **'Enviar avaliação'**
  String get checkinSubmit;

  /// No description provided for @checkinSubmitted.
  ///
  /// In pt, this message translates to:
  /// **'Avaliação enviada ao seu professor.'**
  String get checkinSubmitted;

  /// No description provided for @checkinQueuedOffline.
  ///
  /// In pt, this message translates to:
  /// **'Sem conexão — a avaliação será enviada assim que você reconectar.'**
  String get checkinQueuedOffline;

  /// No description provided for @checkinListEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma avaliação de treino ainda.'**
  String get checkinListEmpty;

  /// Cabeçalho do card de check-in com as duas notas (1 a 5) que o aluno deu.
  ///
  /// In pt, this message translates to:
  /// **'Nota {rating} · Dificuldade {difficulty}'**
  String checkinCardScores(int rating, int difficulty);

  /// No description provided for @checkinCardPainWhere.
  ///
  /// In pt, this message translates to:
  /// **'Dor em: {where}'**
  String checkinCardPainWhere(String where);

  /// No description provided for @checkinReviewed.
  ///
  /// In pt, this message translates to:
  /// **'Visto'**
  String get checkinReviewed;

  /// No description provided for @checkinMarkReviewed.
  ///
  /// In pt, this message translates to:
  /// **'Marcar como visto'**
  String get checkinMarkReviewed;

  /// No description provided for @agendaLoadError.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível carregar sua agenda.'**
  String get agendaLoadError;

  /// Streak simples da agenda: semanas consecutivas em que o aluno treinou pelo menos tantas vezes quanto os dias do rodízio (A/B/C).
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =1{1 semana seguida batendo a meta de treinos} other{{count} semanas seguidas batendo a meta de treinos}}'**
  String agendaStreakWeeks(int count);

  /// Intervalo da semana visível na agenda, já formatado pelo intl (ex.: '7 de set – 13 de set').
  ///
  /// In pt, this message translates to:
  /// **'{start} – {end}'**
  String agendaWeekRange(String start, String end);

  /// No description provided for @agendaPreviousWeek.
  ///
  /// In pt, this message translates to:
  /// **'Semana anterior'**
  String get agendaPreviousWeek;

  /// No description provided for @agendaNextWeek.
  ///
  /// In pt, this message translates to:
  /// **'Próxima semana'**
  String get agendaNextWeek;

  /// No description provided for @agendaExpandMonth.
  ///
  /// In pt, this message translates to:
  /// **'Ver mês'**
  String get agendaExpandMonth;

  /// No description provided for @agendaCollapseMonth.
  ///
  /// In pt, this message translates to:
  /// **'Ver semana'**
  String get agendaCollapseMonth;

  /// No description provided for @agendaStateDone.
  ///
  /// In pt, this message translates to:
  /// **'Treino feito'**
  String get agendaStateDone;

  /// No description provided for @agendaStatePredicted.
  ///
  /// In pt, this message translates to:
  /// **'Treino previsto'**
  String get agendaStatePredicted;

  /// No description provided for @agendaStateRest.
  ///
  /// In pt, this message translates to:
  /// **'Descanso'**
  String get agendaStateRest;

  /// Título do detalhe de um dia com treino sincronizado.
  ///
  /// In pt, this message translates to:
  /// **'Treino {label}'**
  String agendaSessionTitle(String label);

  /// Título do detalhe de um dia futuro projetado pela rotação.
  ///
  /// In pt, this message translates to:
  /// **'Treino previsto: {label}'**
  String agendaPredictedTitle(String label);

  /// No description provided for @agendaPredictedHint.
  ///
  /// In pt, this message translates to:
  /// **'Projeção com base no seu rodízio atual — pode mudar conforme você treina.'**
  String get agendaPredictedHint;

  /// No description provided for @agendaRestTitle.
  ///
  /// In pt, this message translates to:
  /// **'Dia de descanso'**
  String get agendaRestTitle;

  /// No description provided for @agendaRestHint.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum treino registrado neste dia.'**
  String get agendaRestHint;

  /// No description provided for @consentTitle.
  ///
  /// In pt, this message translates to:
  /// **'Antes de continuar'**
  String get consentTitle;

  /// No description provided for @consentSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Para usar o Lyfta precisamos do seu consentimento. Você decide sobre cada item e pode mudar de ideia depois, em Conta.'**
  String get consentSubtitle;

  /// No description provided for @consentTermsAccept.
  ///
  /// In pt, this message translates to:
  /// **'Li e aceito os Termos de Uso e a Política de Privacidade'**
  String get consentTermsAccept;

  /// No description provided for @consentReadTerms.
  ///
  /// In pt, this message translates to:
  /// **'Ler os Termos de Uso'**
  String get consentReadTerms;

  /// No description provided for @consentReadPrivacy.
  ///
  /// In pt, this message translates to:
  /// **'Ler a Política de Privacidade'**
  String get consentReadPrivacy;

  /// No description provided for @consentHealthDataTitle.
  ///
  /// In pt, this message translates to:
  /// **'Dados de saúde (obrigatório)'**
  String get consentHealthDataTitle;

  /// No description provided for @consentHealthDataBody.
  ///
  /// In pt, this message translates to:
  /// **'Autorizo o tratamento dos meus dados de saúde — treinos, cargas, medidas e bioimpedância — para a prescrição e o acompanhamento do meu treino.'**
  String get consentHealthDataBody;

  /// No description provided for @consentPhotosTitle.
  ///
  /// In pt, this message translates to:
  /// **'Fotos de evolução (opcional)'**
  String get consentPhotosTitle;

  /// No description provided for @consentPhotosBody.
  ///
  /// In pt, this message translates to:
  /// **'Autorizo guardar minhas fotos de evolução e mostrá-las ao meu professor. Sem isso o app funciona normalmente, só não envia fotos.'**
  String get consentPhotosBody;

  /// No description provided for @consentSubmit.
  ///
  /// In pt, this message translates to:
  /// **'Continuar'**
  String get consentSubmit;

  /// No description provided for @consentRequiredHint.
  ///
  /// In pt, this message translates to:
  /// **'Aceite os itens obrigatórios para continuar.'**
  String get consentRequiredHint;

  /// No description provided for @consentSignOut.
  ///
  /// In pt, this message translates to:
  /// **'Sair'**
  String get consentSignOut;

  /// No description provided for @legalClose.
  ///
  /// In pt, this message translates to:
  /// **'Fechar'**
  String get legalClose;

  /// No description provided for @legalLoadError.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível carregar o documento.'**
  String get legalLoadError;

  /// No description provided for @accountTooltip.
  ///
  /// In pt, this message translates to:
  /// **'Conta'**
  String get accountTooltip;

  /// No description provided for @accountTitle.
  ///
  /// In pt, this message translates to:
  /// **'Conta'**
  String get accountTitle;

  /// No description provided for @accountPrivacySection.
  ///
  /// In pt, this message translates to:
  /// **'Privacidade'**
  String get accountPrivacySection;

  /// No description provided for @accountPhotosTitle.
  ///
  /// In pt, this message translates to:
  /// **'Fotos de evolução'**
  String get accountPhotosTitle;

  /// No description provided for @accountPhotosSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Permite guardar suas fotos e mostrá-las ao seu professor. Ao desligar, o envio de fotos é bloqueado e seu professor deixa de ver as que já enviou.'**
  String get accountPhotosSubtitle;

  /// No description provided for @accountLegalSection.
  ///
  /// In pt, this message translates to:
  /// **'Documentos'**
  String get accountLegalSection;

  /// No description provided for @accountSignOut.
  ///
  /// In pt, this message translates to:
  /// **'Sair da conta'**
  String get accountSignOut;

  /// No description provided for @accountDeleteSection.
  ///
  /// In pt, this message translates to:
  /// **'Excluir conta'**
  String get accountDeleteSection;

  /// No description provided for @accountDeleteTitle.
  ///
  /// In pt, this message translates to:
  /// **'Excluir minha conta'**
  String get accountDeleteTitle;

  /// No description provided for @accountDeleteSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Apaga seus dados de saúde e suas fotos, anonimiza seus treinos e mensagens e encerra seu acesso. Não dá para desfazer.'**
  String get accountDeleteSubtitle;

  /// No description provided for @accountDeleteDialogTitle.
  ///
  /// In pt, this message translates to:
  /// **'Excluir a conta definitivamente?'**
  String get accountDeleteDialogTitle;

  /// No description provided for @accountDeleteDialogBody.
  ///
  /// In pt, this message translates to:
  /// **'Serão apagados: medidas, bioimpedância e fotos de evolução, inclusive os arquivos. Serão anonimizados: seus treinos executados e suas mensagens, que ficam sem o seu nome. Seu acesso será encerrado e isso não pode ser desfeito.'**
  String get accountDeleteDialogBody;

  /// No description provided for @accountDeletePasswordLabel.
  ///
  /// In pt, this message translates to:
  /// **'Confirme sua senha'**
  String get accountDeletePasswordLabel;

  /// No description provided for @accountDeleteConfirm.
  ///
  /// In pt, this message translates to:
  /// **'Excluir definitivamente'**
  String get accountDeleteConfirm;

  /// No description provided for @organizationSection.
  ///
  /// In pt, this message translates to:
  /// **'Organização'**
  String get organizationSection;

  /// No description provided for @organizationNameLabel.
  ///
  /// In pt, this message translates to:
  /// **'Nome da organização'**
  String get organizationNameLabel;

  /// No description provided for @organizationTimezoneLabel.
  ///
  /// In pt, this message translates to:
  /// **'Fuso horário'**
  String get organizationTimezoneLabel;

  /// No description provided for @organizationTimezoneHelp.
  ///
  /// In pt, this message translates to:
  /// **'Define o “hoje” e os horários dos lembretes dos seus alunos.'**
  String get organizationTimezoneHelp;

  /// No description provided for @organizationTimezoneSearchHint.
  ///
  /// In pt, this message translates to:
  /// **'Buscar fuso'**
  String get organizationTimezoneSearchHint;

  /// No description provided for @organizationTimezoneOther.
  ///
  /// In pt, this message translates to:
  /// **'Outro fuso…'**
  String get organizationTimezoneOther;

  /// No description provided for @organizationTimezoneOtherLabel.
  ///
  /// In pt, this message translates to:
  /// **'Nome do fuso (ex.: America/Sao_Paulo)'**
  String get organizationTimezoneOtherLabel;

  /// No description provided for @organizationSaved.
  ///
  /// In pt, this message translates to:
  /// **'Organização atualizada.'**
  String get organizationSaved;

  /// No description provided for @organizationLoadError.
  ///
  /// In pt, this message translates to:
  /// **'Não conseguimos carregar a organização.'**
  String get organizationLoadError;

  /// No description provided for @errorInvalidTimezone.
  ///
  /// In pt, this message translates to:
  /// **'Esse fuso horário não existe. Escolha um da lista ou use um nome como America/Sao_Paulo.'**
  String get errorInvalidTimezone;

  /// No description provided for @errorConsentRequired.
  ///
  /// In pt, this message translates to:
  /// **'Você não autorizou esse uso dos seus dados. Ajuste em Conta > Privacidade.'**
  String get errorConsentRequired;

  /// No description provided for @errorStudentConsentRequired.
  ///
  /// In pt, this message translates to:
  /// **'O aluno não autorizou o uso dos dados de saúde. Só ele pode mudar isso, em Conta > Privacidade.'**
  String get errorStudentConsentRequired;

  /// No description provided for @errorTermsVersionMismatch.
  ///
  /// In pt, this message translates to:
  /// **'Os termos foram atualizados. Reabra o app para ler a nova versão.'**
  String get errorTermsVersionMismatch;

  /// No description provided for @errorInvalidPassword.
  ///
  /// In pt, this message translates to:
  /// **'Senha incorreta.'**
  String get errorInvalidPassword;

  /// No description provided for @errorOwnerCannotDelete.
  ///
  /// In pt, this message translates to:
  /// **'O dono da conta não pode excluí-la por aqui. Encerrar a academia é outro processo — fale com o suporte.'**
  String get errorOwnerCannotDelete;

  /// No description provided for @errorErasureFailed.
  ///
  /// In pt, this message translates to:
  /// **'Não conseguimos concluir a exclusão agora. Tente de novo em instantes.'**
  String get errorErasureFailed;

  /// Limite de tentativas atingido (429): login, recuperação de senha, convite. `minutes` = tempo até liberar, arredondado para cima.
  ///
  /// In pt, this message translates to:
  /// **'Muitas tentativas. Aguarde {minutes, plural, =1{1 minuto} other{{minutes} minutos}} e tente de novo.'**
  String errorTooManyRequests(int minutes);

  /// No description provided for @errorStudentNotFound.
  ///
  /// In pt, this message translates to:
  /// **'Este aluno não está na sua lista de alunos.'**
  String get errorStudentNotFound;

  /// Professor responsável pelo aluno, mostrado ao dono da academia no cartão do aluno.
  ///
  /// In pt, this message translates to:
  /// **'Professor: {name}'**
  String studentsCoachLabel(String name);

  /// Ação do dono da academia no cartão do aluno: reatribuir o professor.
  ///
  /// In pt, this message translates to:
  /// **'Trocar professor'**
  String get studentsChangeCoach;

  /// Título do seletor de professor; `student` = nome do aluno.
  ///
  /// In pt, this message translates to:
  /// **'Professor de {student}'**
  String studentsChangeCoachTitle(String student);

  /// Confirmação após reatribuir o professor do aluno.
  ///
  /// In pt, this message translates to:
  /// **'Professor trocado para {name}.'**
  String studentsCoachChanged(String name);

  /// Seletor de professor sem opções.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum professor disponível.'**
  String get studentsCoachesEmpty;

  /// 409 no_coach: aluno sem professor vinculado tentou abrir conversa.
  ///
  /// In pt, this message translates to:
  /// **'Você ainda não tem um professor responsável. Fale com a sua academia.'**
  String get errorNoCoach;

  /// Aviso na tela de convite quando já há outra conta logada.
  ///
  /// In pt, this message translates to:
  /// **'Você está conectado com outra conta neste aparelho. Ativar este convite sai dela e entra na conta nova.'**
  String get inviteSwitchAccountNotice;

  /// Hoje, sem rede, depois de concluir o treino do cache.
  ///
  /// In pt, this message translates to:
  /// **'Treino de hoje concluído'**
  String get todayDoneOfflineTitle;

  /// Explica que o treino concluído offline sincroniza depois.
  ///
  /// In pt, this message translates to:
  /// **'Ele fica salvo no aparelho e sincroniza sozinho quando a conexão voltar. O próximo treino aparece em seguida.'**
  String get todayDoneOfflineBody;
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
