// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Lyfta';

  @override
  String get appVersion => 'v0.1.0';

  @override
  String get loginWelcomeBack => 'Bem-vindo de volta';

  @override
  String get loginSubtitle =>
      'Entre para acompanhar seus treinos e sua evolução.';

  @override
  String get loginEmailLabel => 'E-mail';

  @override
  String get loginEmailHint => 'voce@exemplo.com';

  @override
  String get loginPasswordLabel => 'Senha';

  @override
  String get loginPasswordHint => '••••••••';

  @override
  String get loginForgotPassword => 'Esqueci minha senha';

  @override
  String get loginSubmit => 'Entrar';

  @override
  String get loginOrDivider => 'ou';

  @override
  String get loginContinueWithGoogle => 'Continuar com Google';

  @override
  String get loginNewHerePrefix => 'Novo por aqui? ';

  @override
  String get loginNewHereSuffix => 'Seu coach ou academia envia o convite.';

  @override
  String get forgotPasswordTitle => 'Recuperar senha';

  @override
  String get forgotPasswordSubtitle =>
      'Informe seu e-mail para receber o link de redefinição.';

  @override
  String get forgotPasswordSubmit => 'Enviar link';

  @override
  String get forgotPasswordBackToLogin => 'Voltar para o login';

  @override
  String get inviteTitle => 'Aceitar convite';

  @override
  String get inviteSubtitle => 'Defina sua senha para ativar sua conta.';

  @override
  String get inviteNewPasswordLabel => 'Nova senha';

  @override
  String get inviteSubmit => 'Ativar conta';

  @override
  String get homeStudentTitle => 'Hoje';

  @override
  String get homeStudentTabToday => 'Hoje';

  @override
  String get homeStudentTabEvolution => 'Evolução';

  @override
  String get homeStudentTabChat => 'Chat';

  @override
  String get homeStudentTabAgenda => 'Agenda';

  @override
  String get homeCoachTitle => 'Alunos';

  @override
  String get homeCoachTabStudents => 'Alunos';

  @override
  String get homeCoachTabWorkouts => 'Treinos';

  @override
  String get homeCoachTabChat => 'Chat';

  @override
  String get homePlaceholderBody => 'Em construção.';

  @override
  String get roleSwitcherCoach => 'Professor';

  @override
  String get roleSwitcherStudent => 'Aluno';

  @override
  String get errorInvalidCredentials => 'E-mail ou senha inválidos.';

  @override
  String get errorMultipleTenants =>
      'Este e-mail está em mais de uma conta. Escolha uma para continuar.';

  @override
  String errorValidation(String field) {
    return 'Verifique o campo \"$field\".';
  }

  @override
  String get errorEmailTaken => 'Este e-mail já está em uso.';

  @override
  String get errorInvalidToken => 'Link inválido ou expirado.';

  @override
  String get errorUnauthenticated => 'Sua sessão expirou. Entre novamente.';

  @override
  String get errorForbidden => 'Você não tem permissão para essa ação.';

  @override
  String get errorSlugTaken => 'Este identificador já está em uso.';

  @override
  String get errorInternal => 'Algo deu errado. Tente novamente.';

  @override
  String get errorNetwork =>
      'Sem conexão com o servidor. Verifique sua internet.';
}

/// The translations for Portuguese, as used in Portugal (`pt_PT`).
class AppLocalizationsPtPt extends AppLocalizationsPt {
  AppLocalizationsPtPt() : super('pt_PT');

  @override
  String get loginSubtitle =>
      'Entra para acompanhares os teus treinos e a tua evolução.';

  @override
  String get loginNewHerePrefix => 'Novo por aqui? ';

  @override
  String get loginNewHereSuffix =>
      'O teu treinador ou ginásio envia o convite.';

  @override
  String get forgotPasswordSubtitle =>
      'Indica o teu e-mail para receberes o link de redefinição.';

  @override
  String get inviteSubtitle => 'Define a tua senha para ativares a tua conta.';

  @override
  String get errorInvalidCredentials => 'E-mail ou palavra-passe inválidos.';

  @override
  String get errorMultipleTenants =>
      'Este e-mail está em mais do que uma conta. Escolhe uma para continuar.';

  @override
  String errorValidation(String field) {
    return 'Verifica o campo \"$field\".';
  }

  @override
  String get errorEmailTaken => 'Este e-mail já está a ser utilizado.';

  @override
  String get errorUnauthenticated => 'A tua sessão expirou. Entra novamente.';

  @override
  String get errorForbidden => 'Não tens permissão para essa ação.';

  @override
  String get errorNetwork =>
      'Sem ligação ao servidor. Verifica a tua internet.';
}
