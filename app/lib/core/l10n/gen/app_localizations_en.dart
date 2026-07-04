// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Lyfta';

  @override
  String get appVersion => 'v0.1.0';

  @override
  String get loginWelcomeBack => 'Welcome back';

  @override
  String get loginSubtitle => 'Sign in to track your workouts and progress.';

  @override
  String get loginEmailLabel => 'Email';

  @override
  String get loginEmailHint => 'you@example.com';

  @override
  String get loginPasswordLabel => 'Password';

  @override
  String get loginPasswordHint => '••••••••';

  @override
  String get loginForgotPassword => 'Forgot my password';

  @override
  String get loginSubmit => 'Sign in';

  @override
  String get loginOrDivider => 'or';

  @override
  String get loginContinueWithGoogle => 'Continue with Google';

  @override
  String get loginNewHerePrefix => 'New here? ';

  @override
  String get loginNewHereSuffix => 'Your coach or gym sends the invite.';

  @override
  String get forgotPasswordTitle => 'Reset password';

  @override
  String get forgotPasswordSubtitle =>
      'Enter your email to receive the reset link.';

  @override
  String get forgotPasswordSubmit => 'Send link';

  @override
  String get forgotPasswordBackToLogin => 'Back to login';

  @override
  String get inviteTitle => 'Accept invite';

  @override
  String get inviteSubtitle => 'Set your password to activate your account.';

  @override
  String get inviteNewPasswordLabel => 'New password';

  @override
  String get inviteSubmit => 'Activate account';

  @override
  String get homeStudentTitle => 'Today';

  @override
  String get homeStudentTabToday => 'Today';

  @override
  String get homeStudentTabEvolution => 'Progress';

  @override
  String get homeStudentTabChat => 'Chat';

  @override
  String get homeStudentTabAgenda => 'Schedule';

  @override
  String get homeCoachTitle => 'Students';

  @override
  String get homeCoachTabStudents => 'Students';

  @override
  String get homeCoachTabWorkouts => 'Workouts';

  @override
  String get homeCoachTabChat => 'Chat';

  @override
  String get homePlaceholderBody => 'Under construction.';

  @override
  String get roleSwitcherCoach => 'Coach';

  @override
  String get roleSwitcherStudent => 'Student';

  @override
  String get errorInvalidCredentials => 'Invalid email or password.';

  @override
  String get errorMultipleTenants =>
      'This email belongs to more than one account. Choose one to continue.';

  @override
  String errorValidation(String field) {
    return 'Check the \"$field\" field.';
  }

  @override
  String get errorEmailTaken => 'This email is already in use.';

  @override
  String get errorInvalidToken => 'Invalid or expired link.';

  @override
  String get errorUnauthenticated =>
      'Your session has expired. Please sign in again.';

  @override
  String get errorForbidden => 'You don\'t have permission for this action.';

  @override
  String get errorSlugTaken => 'This identifier is already in use.';

  @override
  String get errorInternal => 'Something went wrong. Please try again.';

  @override
  String get errorNetwork =>
      'Could not connect to the server. Check your internet connection.';
}
