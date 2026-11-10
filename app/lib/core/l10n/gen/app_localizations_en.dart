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
  String appVersion(String version) {
    return 'v$version';
  }

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
  String get loginNewHereSuffix => 'Create your gym\'s account.';

  @override
  String get loginTenantSheetTitle => 'Choose an account';

  @override
  String get loginTenantSheetSubtitle =>
      'This email belongs to more than one account. Pick which one to sign in to.';

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
  String get forgotPasswordSuccess =>
      'If this email has an account, we sent a reset link.';

  @override
  String get resetPasswordTitle => 'Set new password';

  @override
  String get resetPasswordSubtitle => 'Choose a new password for your account.';

  @override
  String get resetPasswordNewLabel => 'New password';

  @override
  String get resetPasswordSubmit => 'Save new password';

  @override
  String get resetPasswordSuccess =>
      'Password reset. Sign in with your new password.';

  @override
  String get resetPasswordInvalidLink =>
      'Invalid link. Request a new password reset.';

  @override
  String get signupTitle => 'Create your gym\'s account';

  @override
  String get signupSubtitle =>
      'Register your business to start managing students and workouts.';

  @override
  String get signupBusinessNameLabel => 'Business name';

  @override
  String get signupBusinessNameHint => 'Example Gym';

  @override
  String get signupSlugLabel => 'Identifier';

  @override
  String get signupSlugHint => 'example-gym';

  @override
  String get signupNameLabel => 'Your name';

  @override
  String get signupNameHint => 'What should we call you';

  @override
  String get signupSubmit => 'Create account';

  @override
  String get signupBackToLogin => 'I already have an account';

  @override
  String get inviteTitle => 'Accept invite';

  @override
  String get inviteSubtitle => 'Set your password to activate your account.';

  @override
  String get inviteNewPasswordLabel => 'New password';

  @override
  String get inviteSubmit => 'Activate account';

  @override
  String get inviteInvalidLink => 'Invalid or expired invite link.';

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
  String get homeCoachTabStudents => 'Students';

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

  @override
  String get homeCoachTabLibrary => 'Library';

  @override
  String get commonRetry => 'Try again';

  @override
  String get commonSave => 'Save';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonLoadMore => 'Load more';

  @override
  String get commonShowPassword => 'Show password';

  @override
  String get commonHidePassword => 'Hide password';

  @override
  String get libraryNewExercise => 'New exercise';

  @override
  String get librarySearchLabel => 'Search exercise';

  @override
  String get librarySearchHint => 'bench press, squat…';

  @override
  String get libraryFilterMuscle => 'Muscle';

  @override
  String get libraryFilterEquipment => 'Equipment';

  @override
  String get libraryFilterAll => 'All';

  @override
  String get libraryGlobalBadge => 'Lyfta';

  @override
  String get libraryEmpty => 'No exercise found.';

  @override
  String get exerciseFormNewTitle => 'New exercise';

  @override
  String get exerciseFormEditTitle => 'Edit exercise';

  @override
  String get exerciseFormDuplicateTitle => 'Duplicate exercise';

  @override
  String get exerciseFormDuplicateHint =>
      'Lyfta exercises can\'t be edited. Saving creates a copy in your gym\'s library.';

  @override
  String get exerciseFormNameLabel => 'Name';

  @override
  String get exerciseFormNameHint => 'Barbell bench press';

  @override
  String get exerciseFormNameRequired => 'Enter the exercise name.';

  @override
  String get exerciseFormMuscleLabel => 'Primary muscle';

  @override
  String get exerciseFormEquipmentLabel => 'Equipment';

  @override
  String get exerciseFormLevelLabel => 'Level';

  @override
  String get exerciseFormInstructionsLabel => 'Instructions';

  @override
  String get exerciseFormInstructionsHint => 'How to perform the movement';

  @override
  String get exerciseFormMediaLabel => 'Media';

  @override
  String get exerciseFormMediaHint => 'GIF or short video, up to 50 MB.';

  @override
  String get exerciseFormMediaPick => 'Choose file';

  @override
  String get exerciseFormMediaReplace => 'Replace file';

  @override
  String get builderTitle => 'Build workout';

  @override
  String get builderDayTitle => 'Day title';

  @override
  String get builderAddDay => 'Add day';

  @override
  String get builderNoDays =>
      'This plan has no days yet. Start with workout A.';

  @override
  String get builderAddBlock => 'Add block';

  @override
  String get builderAddExercise => 'Add exercise';

  @override
  String get builderAddSet => 'Add set';

  @override
  String get builderDuplicateSet => 'Duplicate set';

  @override
  String get builderPickExercise => 'Choose exercise';

  @override
  String get builderUnknownExercise => 'Exercise removed from the library';

  @override
  String get builderBlockRest => 'Rest (s)';

  @override
  String get builderRepsMin => 'Min reps';

  @override
  String get builderRepsMax => 'Max reps';

  @override
  String get builderRestSeconds => 'Rest (s)';

  @override
  String get builderTargetUnit => 'Target unit';

  @override
  String get builderTargetKg => 'Load (kg)';

  @override
  String get builderTargetPercent1rm => '% of 1RM';

  @override
  String get builderTargetRpe => 'RPE';

  @override
  String get builderTargetRir => 'RIR';

  @override
  String get builderBlockStraight => 'Straight set';

  @override
  String get builderBlockSuperset => 'Superset';

  @override
  String get builderBlockDropset => 'Drop set';

  @override
  String get builderBlockRestPause => 'Rest-pause';

  @override
  String get builderBlockCircuit => 'Circuit';

  @override
  String get builderSaveDraft => 'Save draft';

  @override
  String get builderSaved => 'Draft saved';

  @override
  String get builderDraftSaved => 'Draft saved.';

  @override
  String get builderPublish => 'Publish';

  @override
  String get builderMoveUp => 'Move up';

  @override
  String get builderMoveDown => 'Move down';

  @override
  String get studentsSearchLabel => 'Search student';

  @override
  String get studentsSearchHint => 'name or email';

  @override
  String get studentsEmpty => 'No students yet. Invite the first one.';

  @override
  String get studentsNoPlan => 'No plan';

  @override
  String get studentsNewPlan => 'New plan';

  @override
  String get studentsOpenPlan => 'Open';

  @override
  String get studentsNewPlanTitle => 'New plan';

  @override
  String get studentsNewPlanDefaultTitle => 'Workout A/B';

  @override
  String get studentsPlanTitleLabel => 'Plan name';

  @override
  String get studentsPendingBadge => 'invite pending';

  @override
  String get studentsInviteTitle => 'Invite student';

  @override
  String get studentsInviteNameLabel => 'Name';

  @override
  String get studentsInviteEmailLabel => 'Email';

  @override
  String get studentsInviteSubmit => 'Invite';

  @override
  String get errorNotFound => 'We couldn\'t find what you were looking for.';

  @override
  String get errorInvalidCursor => 'The list changed. Reload the page.';

  @override
  String get errorExerciseIsGlobal =>
      'Lyfta exercises can\'t be edited. Duplicate it to make your own.';

  @override
  String get errorUnsupportedMedia =>
      'Format not accepted. Use GIF, MP4 or WebM.';

  @override
  String get errorFileTooLarge => 'File too large. The limit is 50 MB.';

  @override
  String get errorPlanNoDays => 'Add at least one day before publishing.';

  @override
  String get errorPlanDayWithoutBlock =>
      'A day has no blocks. Complete it before publishing.';

  @override
  String get errorPlanBlockWithoutExercise =>
      'A block has no exercise. Complete it before publishing.';

  @override
  String get errorPlanExerciseWithoutSet =>
      'An exercise has no prescribed set. Complete it before publishing.';

  @override
  String get errorNoDraftToPublish => 'There are no new changes to publish.';

  @override
  String get errorUnknownExercise =>
      'One of the exercises is no longer available in the library.';

  @override
  String get muscleChest => 'Chest';

  @override
  String get muscleBack => 'Back';

  @override
  String get muscleLats => 'Lats';

  @override
  String get muscleTraps => 'Traps';

  @override
  String get muscleLowerBack => 'Lower back';

  @override
  String get muscleShoulders => 'Shoulders';

  @override
  String get muscleBiceps => 'Biceps';

  @override
  String get muscleTriceps => 'Triceps';

  @override
  String get muscleForearms => 'Forearms';

  @override
  String get muscleAbs => 'Abs';

  @override
  String get muscleObliques => 'Obliques';

  @override
  String get muscleQuadriceps => 'Quads';

  @override
  String get muscleHamstrings => 'Hamstrings';

  @override
  String get muscleGlutes => 'Glutes';

  @override
  String get muscleCalves => 'Calves';

  @override
  String get muscleAdductors => 'Adductors';

  @override
  String get muscleAbductors => 'Abductors';

  @override
  String get muscleFullBody => 'Full body';

  @override
  String get equipmentBarbell => 'Barbell';

  @override
  String get equipmentDumbbell => 'Dumbbell';

  @override
  String get equipmentMachine => 'Machine';

  @override
  String get equipmentCable => 'Cable';

  @override
  String get equipmentSmith => 'Smith machine';

  @override
  String get equipmentBodyweight => 'Bodyweight';

  @override
  String get equipmentKettlebell => 'Kettlebell';

  @override
  String get equipmentBand => 'Band';

  @override
  String get equipmentBench => 'Bench';

  @override
  String get equipmentOther => 'Other';

  @override
  String get levelBeginner => 'Beginner';

  @override
  String get levelIntermediate => 'Intermediate';

  @override
  String get levelAdvanced => 'Advanced';

  @override
  String builderDraftVersion(int version) {
    return 'draft v$version';
  }

  @override
  String builderPublishedVersion(int version) {
    return 'v$version published';
  }

  @override
  String builderPublishBody(int version) {
    return 'Publishing freezes this version and sends the workout to the student. Version $version won\'t be editable anymore.';
  }

  @override
  String builderPublished(int version) {
    return 'Version $version published.';
  }

  @override
  String studentsPlanActive(String title, int version) {
    return '$title · v$version';
  }

  @override
  String get builderPublishTitle => 'Publish workout?';

  @override
  String get todayNoPlanTitle => 'Your coach hasn\'t built your plan yet';

  @override
  String get todayNoPlanBody =>
      'As soon as the plan is published, today\'s workout shows up here.';

  @override
  String get todayRestTitle => 'Rest day';

  @override
  String get todayRestBody =>
      'Nothing scheduled for today. Recovery is part of training.';

  @override
  String get todayStart => 'Start workout';

  @override
  String get todayResume => 'Resume workout';

  @override
  String get todayOffline =>
      'No connection — this is the workout stored on your device.';

  @override
  String get todayLoadError => 'Couldn\'t load your workout.';

  @override
  String get todayNoPreviousLoad => 'First time';

  @override
  String get todayRecentTitle => 'Recent workouts';

  @override
  String get todaySyncing => 'Syncing…';

  @override
  String get todaySynced => 'All synced';

  @override
  String get todayEmptyDay => 'This workout has no exercises.';

  @override
  String get sessionReps => 'Reps';

  @override
  String get sessionLoadKg => 'Load (kg)';

  @override
  String get sessionMarkDone => 'Log set';

  @override
  String get sessionSetDone => 'Logged';

  @override
  String get sessionRestTitle => 'Rest';

  @override
  String get sessionRestSkip => 'Skip rest';

  @override
  String get sessionRestOver => 'Rest is over';

  @override
  String get sessionRestNotificationTitle => 'Rest is over';

  @override
  String get sessionFinish => 'Finish workout';

  @override
  String get sessionFinishTitle => 'Finish workout?';

  @override
  String get sessionSummaryTitle => 'Workout done';

  @override
  String get sessionSummarySets => 'Sets';

  @override
  String get sessionSummaryVolume => 'Volume';

  @override
  String get sessionSummaryDuration => 'Duration';

  @override
  String get sessionSummaryClose => 'Close';

  @override
  String get sessionTargetFreeReps => 'free reps';

  @override
  String todayDayHeading(String label) {
    return 'Workout $label';
  }

  @override
  String todayNextWorkout(String label) {
    return 'Next: workout $label';
  }

  @override
  String get todaySwitch => 'Switch today\'s workout';

  @override
  String get todaySwitchTitle => 'Which workout do you want today?';

  @override
  String get todaySwitchCurrent => 'Today';

  @override
  String get todaySwitchOffline =>
      'No connection — switching the workout needs internet.';

  @override
  String get todaySwitchError => 'Couldn\'t switch the workout.';

  @override
  String todayPreviousLoad(String load) {
    return 'Last time: $load kg';
  }

  @override
  String todaySetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sets',
      one: '1 set',
    );
    return '$_temp0';
  }

  @override
  String todayRecentEntry(String label, int sets, String volume) {
    return 'Workout $label · $sets sets · $volume kg';
  }

  @override
  String todaySyncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries to send',
      one: '1 entry to send',
    );
    return '$_temp0';
  }

  @override
  String sessionTitle(String label) {
    return 'Workout $label';
  }

  @override
  String sessionSet(int number) {
    return 'Set $number';
  }

  @override
  String sessionEditSet(int number) {
    return 'Fix set $number';
  }

  @override
  String sessionTargetRepsRange(int min, int max) {
    return '$min–$max reps';
  }

  @override
  String sessionTargetReps(int reps) {
    return '$reps reps';
  }

  @override
  String sessionTargetWithUnit(String value, String unit) {
    return '$value $unit';
  }

  @override
  String sessionRestNotificationBody(String exercise) {
    return 'Time for your next set of $exercise.';
  }

  @override
  String sessionFinishBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You logged $count sets. Today\'s workout will be completed.',
      one: 'You logged 1 set. Today\'s workout will be completed.',
      zero:
          'You haven\'t logged any set — today\'s workout won\'t be marked as done.',
    );
    return '$_temp0';
  }

  @override
  String sessionDurationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String sessionLoggedSet(String reps, String load) {
    return '$reps reps · $load kg';
  }

  @override
  String get sessionEmptyValue => '—';

  @override
  String get studentsOpenEvolution => 'Progress';

  @override
  String get studentsOpenChat => 'Chat';

  @override
  String get evolutionTabSummary => 'Overview';

  @override
  String get evolutionTabLoad => 'Load';

  @override
  String get evolutionTabMeasurements => 'Measurements';

  @override
  String get evolutionTabPhotos => 'Photos';

  @override
  String get evolutionTabCheckins => 'Check-ins';

  @override
  String get evolutionSummaryLatestMeasurement => 'Latest measurement';

  @override
  String get evolutionSummaryLatestBioimpedance => 'Latest bioimpedance';

  @override
  String get evolutionSummaryPhotoCount => 'Progress photos';

  @override
  String get evolutionMeasurementsSection => 'Body measurements';

  @override
  String get evolutionAddMeasurement => 'New measurement';

  @override
  String get evolutionBioimpedanceSection => 'Bioimpedance';

  @override
  String get evolutionAddBioimpedance => 'New reading';

  @override
  String get evolutionPhotosSection => 'Progress photos';

  @override
  String get evolutionAddPhoto => 'New photo';

  @override
  String get evolutionDeleteTitle => 'Delete record?';

  @override
  String get evolutionDeleteBody => 'This action can\'t be undone.';

  @override
  String get evolutionPhotosCompareTitle => 'Compare before/after';

  @override
  String get evolutionDateLabel => 'Date';

  @override
  String get evolutionValueHint => '0';

  @override
  String get evolutionNotesLabel => 'Notes';

  @override
  String get measurementFormEmpty => 'Fill in at least one measurement.';

  @override
  String get evolutionMeasurementsEmpty => 'No measurements logged yet.';

  @override
  String get evolutionBioimpedanceEmpty => 'No bioimpedance readings yet.';

  @override
  String get evolutionMetricMaxLoad => 'Max load';

  @override
  String get evolutionMetricVolume => 'Volume';

  @override
  String get evolutionRangeOneMonth => '1 month';

  @override
  String get evolutionRangeThreeMonths => '3 months';

  @override
  String get evolutionRangeSixMonths => '6 months';

  @override
  String get evolutionRangeAll => 'All';

  @override
  String get evolutionNoDataForRange => 'No entries in this period.';

  @override
  String get evolutionNoExercisesYet =>
      'You haven\'t logged any set yet. Train to see the chart here.';

  @override
  String get evolutionPhotosEmpty => 'No photos yet.';

  @override
  String get evolutionPhotosCompareNeedTwo =>
      'Log at least two photos to compare.';

  @override
  String get evolutionPoseFront => 'Front';

  @override
  String get evolutionPoseSide => 'Side';

  @override
  String get evolutionPoseBack => 'Back';

  @override
  String get evolutionNewMeasurement => 'New measurement';

  @override
  String get evolutionNewBioimpedance => 'New bioimpedance reading';

  @override
  String get evolutionNewPhoto => 'New photo';

  @override
  String get evolutionPhotoFromCamera => 'Camera';

  @override
  String get evolutionPhotoFromGallery => 'Gallery';

  @override
  String get evolutionPhotoEmptyPreview => 'Choose a photo to continue.';

  @override
  String get evolutionPhotoRequired => 'Choose a photo before saving.';

  @override
  String get evolutionPhotoPickError =>
      'Couldn\'t process the photo. Try another one.';

  @override
  String get measurementFieldWeightKg => 'Weight (kg)';

  @override
  String get measurementFieldHeightCm => 'Height (cm)';

  @override
  String get measurementFieldNeckCm => 'Neck (cm)';

  @override
  String get measurementFieldShoulderCm => 'Shoulder (cm)';

  @override
  String get measurementFieldChestCm => 'Chest (cm)';

  @override
  String get measurementFieldWaistCm => 'Waist (cm)';

  @override
  String get measurementFieldAbdomenCm => 'Abdomen (cm)';

  @override
  String get measurementFieldHipCm => 'Hip (cm)';

  @override
  String get measurementFieldArmLCm => 'Left arm (cm)';

  @override
  String get measurementFieldArmRCm => 'Right arm (cm)';

  @override
  String get measurementFieldThighLCm => 'Left thigh (cm)';

  @override
  String get measurementFieldThighRCm => 'Right thigh (cm)';

  @override
  String get measurementFieldCalfLCm => 'Left calf (cm)';

  @override
  String get measurementFieldCalfRCm => 'Right calf (cm)';

  @override
  String get bioimpedanceFieldBodyFatPct => 'Body fat %';

  @override
  String get bioimpedanceFieldMuscleMassKg => 'Muscle mass (kg)';

  @override
  String get bioimpedanceFieldVisceralFat => 'Visceral fat';

  @override
  String get bioimpedanceFieldBodyWaterPct => 'Body water %';

  @override
  String get bioimpedanceFieldBoneMassKg => 'Bone mass (kg)';

  @override
  String get bioimpedanceFieldBmrKcal => 'Basal metabolic rate (kcal)';

  @override
  String get chatTitleFallback => 'Chat';

  @override
  String get chatEmpty => 'No messages yet. Say hi!';

  @override
  String get chatConversationsEmpty => 'No conversations yet.';

  @override
  String get chatStudentNoConversation =>
      'No conversation yet. Talk to your coach here.';

  @override
  String get chatStudentStart => 'Message my coach';

  @override
  String get chatNoMessagesYet => 'No messages yet';

  @override
  String get chatImagePreview => '📷 Photo';

  @override
  String get chatMessageHint => 'Type a message…';

  @override
  String get chatAttachImage => 'Attach photo';

  @override
  String get chatSend => 'Send';

  @override
  String get chatMessageFailed => 'Not sent.';

  @override
  String get chatMessageRetry => 'Try again';

  @override
  String get checkinTitle => 'How was the workout?';

  @override
  String get checkinSubtitle =>
      'Your feedback helps your coach adjust the next workout.';

  @override
  String get checkinRatingLabel => 'Overall rating';

  @override
  String get checkinDifficultyLabel => 'Difficulty';

  @override
  String get checkinPainLabel => 'Any pain?';

  @override
  String get checkinPainNone => 'None';

  @override
  String get checkinPainMild => 'Mild';

  @override
  String get checkinPainStrong => 'Strong';

  @override
  String get checkinPainWhereLabel => 'Where?';

  @override
  String get checkinCommentLabel => 'Comment (optional)';

  @override
  String get checkinSubmit => 'Submit feedback';

  @override
  String get checkinSubmitted => 'Feedback sent to your coach.';

  @override
  String get checkinQueuedOffline =>
      'No connection — feedback will be sent once you reconnect.';

  @override
  String get checkinListEmpty => 'No workout feedback yet.';

  @override
  String checkinCardScores(int rating, int difficulty) {
    return 'Rating $rating · Difficulty $difficulty';
  }

  @override
  String checkinCardPainWhere(String where) {
    return 'Pain at: $where';
  }

  @override
  String get checkinReviewed => 'Seen';

  @override
  String get checkinMarkReviewed => 'Mark as seen';

  @override
  String get agendaLoadError => 'We couldn\'t load your schedule.';

  @override
  String agendaStreakWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weeks in a row hitting your workout goal',
      one: '1 week in a row hitting your workout goal',
    );
    return '$_temp0';
  }

  @override
  String agendaWeekRange(String start, String end) {
    return '$start – $end';
  }

  @override
  String get agendaPreviousWeek => 'Previous week';

  @override
  String get agendaNextWeek => 'Next week';

  @override
  String get agendaExpandMonth => 'View month';

  @override
  String get agendaCollapseMonth => 'View week';

  @override
  String get agendaStateDone => 'Workout done';

  @override
  String get agendaStatePredicted => 'Workout expected';

  @override
  String get agendaStateRest => 'Rest';

  @override
  String agendaSessionTitle(String label) {
    return '$label workout';
  }

  @override
  String agendaPredictedTitle(String label) {
    return 'Expected workout: $label';
  }

  @override
  String get agendaPredictedHint =>
      'Projection based on your current rotation — it can change as you train.';

  @override
  String get agendaRestTitle => 'Rest day';

  @override
  String get agendaRestHint => 'No workout logged on this day.';

  @override
  String get consentTitle => 'Before you continue';

  @override
  String get consentSubtitle =>
      'To use Lyfta we need your consent. You decide on each item and can change your mind later, under Account.';

  @override
  String get consentTermsAccept =>
      'I have read and accept the Terms of Use and the Privacy Policy';

  @override
  String get consentReadTerms => 'Read the Terms of Use';

  @override
  String get consentReadPrivacy => 'Read the Privacy Policy';

  @override
  String get consentHealthDataTitle => 'Health data (required)';

  @override
  String get consentHealthDataBody =>
      'I authorize the processing of my health data — workouts, loads, measurements and body composition — to prescribe and follow my training.';

  @override
  String get consentPhotosTitle => 'Progress photos (optional)';

  @override
  String get consentPhotosBody =>
      'I authorize storing my progress photos and showing them to my coach. Without this the app works normally, it just does not upload photos.';

  @override
  String get consentSubmit => 'Continue';

  @override
  String get consentRequiredHint => 'Accept the required items to continue.';

  @override
  String get consentSignOut => 'Sign out';

  @override
  String get legalClose => 'Close';

  @override
  String get legalLoadError => 'Could not load the document.';

  @override
  String get accountTooltip => 'Account';

  @override
  String get accountTitle => 'Account';

  @override
  String get accountPrivacySection => 'Privacy';

  @override
  String get accountPhotosTitle => 'Progress photos';

  @override
  String get accountPhotosSubtitle =>
      'Lets us store your photos and show them to your coach. Turning it off blocks photo uploads and your coach stops seeing the ones you already sent.';

  @override
  String get accountLegalSection => 'Documents';

  @override
  String get accountSignOut => 'Sign out';

  @override
  String get accountDeleteSection => 'Delete account';

  @override
  String get accountDeleteTitle => 'Delete my account';

  @override
  String get accountDeleteSubtitle =>
      'Erases your health data and photos, anonymizes your workouts and messages and ends your access. This cannot be undone.';

  @override
  String get accountDeleteDialogTitle => 'Delete the account for good?';

  @override
  String get accountDeleteDialogBody =>
      'Erased: measurements, body composition and progress photos, including the files. Anonymized: your completed workouts and your messages, which lose your name. Your access ends and this cannot be undone.';

  @override
  String get accountDeletePasswordLabel => 'Confirm your password';

  @override
  String get accountDeleteConfirm => 'Delete for good';

  @override
  String get organizationSection => 'Organization';

  @override
  String get organizationNameLabel => 'Organization name';

  @override
  String get organizationTimezoneLabel => 'Time zone';

  @override
  String get organizationTimezoneHelp =>
      'Sets “today” and the reminder times for your students.';

  @override
  String get organizationTimezoneSearchHint => 'Search time zone';

  @override
  String get organizationTimezoneOther => 'Other time zone…';

  @override
  String get organizationTimezoneOtherLabel =>
      'Time zone name (e.g. America/New_York)';

  @override
  String get organizationSaved => 'Organization updated.';

  @override
  String get organizationLoadError => 'We could not load the organization.';

  @override
  String get errorInvalidTimezone =>
      'That time zone does not exist. Pick one from the list or use a name like America/New_York.';

  @override
  String get errorConsentRequired =>
      'You have not authorized this use of your data. Change it under Account > Privacy.';

  @override
  String get errorInvitationNotFound =>
      'This invitation no longer exists. Refresh the student profile.';

  @override
  String get errorInvitationAlreadyAccepted =>
      'This invitation has already been accepted — the student already has access.';

  @override
  String get errorStudentConsentRequired =>
      'This student has not authorized the use of their health data. Only they can change this, under Account > Privacy.';

  @override
  String get errorTermsVersionMismatch =>
      'The terms were updated. Reopen the app to read the new version.';

  @override
  String get errorInvalidPassword => 'Wrong password.';

  @override
  String get errorOwnerCannotDelete =>
      'The account owner cannot delete the account here. Closing the gym is a separate process — contact support.';

  @override
  String get errorErasureFailed =>
      'We could not finish the deletion right now. Try again in a moment.';

  @override
  String errorTooManyRequests(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return 'Too many attempts. Wait $_temp0 and try again.';
  }

  @override
  String get errorStudentNotFound =>
      'This student is not on your student list.';

  @override
  String studentsCoachLabel(String name) {
    return 'Coach: $name';
  }

  @override
  String get studentsChangeCoach => 'Change coach';

  @override
  String studentsChangeCoachTitle(String student) {
    return 'Coach for $student';
  }

  @override
  String studentsCoachChanged(String name) {
    return 'Coach changed to $name.';
  }

  @override
  String get studentsCoachesEmpty => 'No coaches available.';

  @override
  String get errorNoCoach =>
      'You don\'t have an assigned coach yet. Contact your gym.';

  @override
  String get inviteSwitchAccountNotice =>
      'You are signed in with another account on this device. Activating this invite signs you out of it and into the new account.';

  @override
  String get todayDoneOfflineTitle => 'Today\'s workout done';

  @override
  String get todayDoneOfflineBody =>
      'It\'s saved on this device and syncs on its own when you\'re back online. Your next workout shows up right after.';

  @override
  String get studentsFilterActive => 'Active';

  @override
  String get studentsFilterInactive => 'Inactive';

  @override
  String get studentsFilterInvited => 'Pending invites';

  @override
  String get studentsFilterCoachLabel => 'Coach';

  @override
  String get studentsFilterCoachAll => 'All coaches';

  @override
  String get studentsEmptyFiltered => 'No students match these filters.';

  @override
  String get studentsLoadMoreError => 'Couldn\'t load more students.';

  @override
  String get studentsColName => 'Student';

  @override
  String get studentsColCoach => 'Coach';

  @override
  String get studentsColPlan => 'Plan';

  @override
  String get studentsColLastWorkout => 'Last workout';

  @override
  String get studentsLastWorkoutNever => 'Never trained';

  @override
  String get studentsLastWorkoutToday => 'Today';

  @override
  String get studentsLastWorkoutYesterday => 'Yesterday';

  @override
  String studentsLastWorkoutDaysAgo(int days) {
    return '$days days ago';
  }

  @override
  String get studentsColStatus => 'Status';

  @override
  String get studentStatusActive => 'Active';

  @override
  String get studentStatusInactive => 'Inactive';

  @override
  String get studentStatusInvited => 'Invite pending';

  @override
  String get studentStatusDisabled => 'Blocked';

  @override
  String get studentDetailTitle => 'Student';

  @override
  String get studentTabData => 'Details';

  @override
  String get studentTabWorkout => 'Workout';

  @override
  String get studentTabEvolution => 'Progress';

  @override
  String get studentTabCheckins => 'Check-ins';

  @override
  String get studentDataSectionRegistry => 'Profile';

  @override
  String get studentDataNameLabel => 'Name';

  @override
  String get studentDataEmailLabel => 'Email';

  @override
  String get studentDataSaved => 'Details saved.';

  @override
  String get profilePhoneLabel => 'Phone';

  @override
  String get profileBirthLabel => 'Date of birth';

  @override
  String get profileBirthEmpty => 'Not provided';

  @override
  String get profileBirthClear => 'Clear date';

  @override
  String get accountProfileSection => 'My details';

  @override
  String get accountProfileSaved => 'Details saved.';

  @override
  String get studentStatusSection => 'Status';

  @override
  String get studentDeactivate => 'Deactivate student';

  @override
  String studentDeactivateTitle(String name) {
    return 'Deactivate $name?';
  }

  @override
  String get studentDeactivateBody =>
      'The student loses access to the app and leaves the default list. Workouts, measurements and chats are kept, and you can reactivate any time.';

  @override
  String get studentDeactivateConfirm => 'Deactivate';

  @override
  String get studentDeactivated => 'Student deactivated.';

  @override
  String get studentReactivate => 'Reactivate student';

  @override
  String studentReactivateTitle(String name) {
    return 'Reactivate $name?';
  }

  @override
  String get studentReactivateBody =>
      'The student can sign in to the app again.';

  @override
  String get studentReactivateConfirm => 'Reactivate';

  @override
  String get studentReactivated => 'Student reactivated.';

  @override
  String get studentReasonLabel => 'Reason (optional)';

  @override
  String get studentInvitePending => 'Invite sent, not accepted yet.';

  @override
  String get studentInviteExpired =>
      'The invite expired. Resend it so the student can sign in.';

  @override
  String get studentInviteResend => 'Resend invite';

  @override
  String get studentInviteResent => 'Invite resent.';

  @override
  String get studentCoachSection => 'Coach';

  @override
  String get studentCoachNone => 'No coach';

  @override
  String get studentHistorySection => 'Status history';

  @override
  String get studentHistoryEmpty => 'No status changes.';

  @override
  String studentHistoryEntry(String from, String to) {
    return '$from → $to';
  }

  @override
  String studentHistoryBy(String name) {
    return 'by $name';
  }

  @override
  String get studentWorkoutEmpty => 'No plans yet. Create the first one.';

  @override
  String get errorAlreadyInactive => 'This student is already inactive.';

  @override
  String get errorAlreadyActive => 'This student is already active.';

  @override
  String get errorInvalidStatusTransition =>
      'This student hasn\'t accepted the invite yet or is blocked, so the status can\'t be changed.';

  @override
  String get studentWorkoutDraft => 'Draft';

  @override
  String studentWorkoutVersion(int version) {
    return 'v$version';
  }

  @override
  String get studentWorkoutInUse => 'In use';

  @override
  String get profileHealthSection => 'Goal and health';

  @override
  String get profileGoalLabel => 'Goal';

  @override
  String get profileUnset => 'Not set';

  @override
  String get goalHypertrophy => 'Muscle gain';

  @override
  String get goalWeightLoss => 'Weight loss';

  @override
  String get goalStrength => 'Strength';

  @override
  String get goalConditioning => 'Conditioning';

  @override
  String get goalHealth => 'Health and wellbeing';

  @override
  String get goalRehab => 'Rehab';

  @override
  String get goalOther => 'Other';

  @override
  String get profileGoalNotesLabel => 'Goal details';

  @override
  String get profileExperienceLabel => 'Training experience';

  @override
  String get experienceBeginner => 'Beginner';

  @override
  String get experienceIntermediate => 'Intermediate';

  @override
  String get experienceAdvanced => 'Advanced';

  @override
  String get profileWeeklyTargetLabel => 'Weekly workout goal';

  @override
  String get profileWeeklyTargetCoachOnly => 'Set by your coach.';

  @override
  String profileWeeklyTargetOption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count workouts per week',
      one: '1 workout per week',
    );
    return '$_temp0';
  }

  @override
  String get profileMedicalNotesLabel => 'Medical notes';

  @override
  String get profileMedicalNotesHint => 'Conditions, medication, restrictions';

  @override
  String get profileCoachNotesLabel => 'Coach private notes';

  @override
  String get profileCoachNotesHint => 'The student can\'t see these notes.';

  @override
  String get profileHealthSaved => 'Goal and health saved.';

  @override
  String get injuriesSection => 'Injuries and restrictions';

  @override
  String get injuriesEmpty => 'No injuries recorded.';

  @override
  String get injuriesAdd => 'Add injury';

  @override
  String get injuriesResolvedHeader => 'Resolved';

  @override
  String get injuryFormTitle => 'New injury';

  @override
  String get injuryRegionLabel => 'Body region';

  @override
  String get injuryDescriptionLabel => 'Description';

  @override
  String get injurySinceLabel => 'Since';

  @override
  String get injurySinceEmpty => 'Not set';

  @override
  String get injurySinceClear => 'Clear date';

  @override
  String injurySinceOn(String date) {
    return 'Since $date';
  }

  @override
  String injuryResolvedOn(String date) {
    return 'Resolved on $date';
  }

  @override
  String get injuryResolve => 'Mark as resolved';

  @override
  String get injuryReopen => 'Reopen';

  @override
  String get injuryDeleteTitle => 'Remove injury?';

  @override
  String get injuryDeleteBody => 'The record will be deleted.';

  @override
  String get bodyRegionNeck => 'Neck';

  @override
  String get bodyRegionShoulder => 'Shoulder';

  @override
  String get bodyRegionElbow => 'Elbow';

  @override
  String get bodyRegionWristHand => 'Wrist and hand';

  @override
  String get bodyRegionUpperBack => 'Upper back';

  @override
  String get bodyRegionLowerBack => 'Lower back';

  @override
  String get bodyRegionChest => 'Chest';

  @override
  String get bodyRegionHip => 'Hip';

  @override
  String get bodyRegionKnee => 'Knee';

  @override
  String get bodyRegionAnkleFoot => 'Ankle and foot';

  @override
  String get bodyRegionOther => 'Other';

  @override
  String get myGoalTitle => 'My goal';

  @override
  String get myGoalIntro =>
      'Your coach uses this to build your training. Only you and your coach can see the medical notes.';

  @override
  String get accountGoalSubtitle => 'Goal, experience and health';

  @override
  String get goalPromptTitle => 'What\'s your goal?';

  @override
  String get goalPromptBody =>
      'Tell your coach what you want to achieve and whether you have any injuries. It takes a minute and you can change it later in Account.';

  @override
  String get goalPromptNow => 'Fill in now';

  @override
  String get goalPromptLater => 'Not now';

  @override
  String get evolutionSummaryGoalUnset => 'Goal not set';

  @override
  String get evolutionSummaryNoInjuries => 'No active injuries';

  @override
  String get homeCoachTabTemplates => 'Templates';

  @override
  String get templatesSearchLabel => 'Search template';

  @override
  String get templatesSearchHint => 'template title';

  @override
  String get templatesFilterActive => 'Active';

  @override
  String get templatesFilterArchived => 'Archived';

  @override
  String get templatesNew => 'New template';

  @override
  String get templatesNewTitle => 'New template';

  @override
  String get templatesTitleLabel => 'Title';

  @override
  String get templatesDescriptionLabel => 'Description (optional)';

  @override
  String get templatesEmpty =>
      'No templates yet. Build a workout once and apply it to many students.';

  @override
  String get templatesEmptyFiltered => 'No templates found.';

  @override
  String get templatesEmptyArchived => 'No archived templates.';

  @override
  String templatesDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String templatesExercises(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercises',
      one: '1 exercise',
    );
    return '$_temp0';
  }

  @override
  String templatesAssignedTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'applied to $count students',
      one: 'applied to 1 student',
    );
    return '$_temp0';
  }

  @override
  String get templatesNotAssigned => 'not applied yet';

  @override
  String get templatesUnpublishedChanges => 'unpublished changes';

  @override
  String get templatesMenuEdit => 'Edit';

  @override
  String get templatesMenuAssign => 'Apply to students';

  @override
  String get templatesMenuRecipients => 'Who received it';

  @override
  String get templatesMenuArchive => 'Archive';

  @override
  String get templatesMenuUnarchive => 'Unarchive';

  @override
  String get templatesArchivedToast => 'Template archived.';

  @override
  String get templatesUnarchivedToast => 'Template unarchived.';

  @override
  String get assignTitle => 'Apply to students';

  @override
  String assignTemplateName(String title) {
    return 'Template: $title';
  }

  @override
  String assignSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count students selected',
      one: '1 student selected',
      zero: 'No students selected',
    );
    return '$_temp0';
  }

  @override
  String assignLimitReached(int max) {
    return 'Limit of $max students at a time reached.';
  }

  @override
  String get assignPublishNow => 'Publish now';

  @override
  String get assignPublishNowHint =>
      'The workout enters the student\'s rotation right away. Off, each student gets a draft for you to adjust first.';

  @override
  String get assignSubmit => 'Apply';

  @override
  String get batchResultTitle => 'Result';

  @override
  String batchResultSummary(int ok, int total) {
    return '$ok of $total succeeded.';
  }

  @override
  String get batchItemOk => 'Plan created';

  @override
  String batchItemReapplied(int version) {
    return 'Version $version published';
  }

  @override
  String get batchBackToSelection => 'Retry the failed ones';

  @override
  String get batchDone => 'Done';

  @override
  String get recipientsTitle => 'Who received it';

  @override
  String get recipientsEmpty =>
      'This template has not been applied to any student yet.';

  @override
  String recipientsCurrentVersion(int version) {
    return 'current version v$version';
  }

  @override
  String get recipientsUpToDate => 'On the current version';

  @override
  String recipientsOutdated(int version) {
    return 'On template v$version';
  }

  @override
  String get recipientsEdited => 'Edited after applying';

  @override
  String get recipientsArchived => 'Plan archived';

  @override
  String get recipientsSelectOutdated => 'Select outdated';

  @override
  String get recipientsSubmit => 'Reapply';

  @override
  String get recipientsConfirmTitle => 'Reapply the template?';

  @override
  String recipientsConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count students will be replaced',
      one: '1 student will be replaced',
    );
    return 'The workout of $_temp0 by the current template version and a new version will be published. Individual adjustments made to those plans will be lost.';
  }

  @override
  String recipientsConfirmEdited(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count of them were edited after applying.',
      one: '1 of them was edited after applying.',
    );
    return '$_temp0';
  }

  @override
  String get applyModelTitle => 'Apply template';

  @override
  String get applyModelEmpty =>
      'No published templates. Publish one in the Templates tab.';

  @override
  String get applyModelApplied => 'Template applied and in use.';

  @override
  String get applyModelAppliedDraft => 'Template applied as a draft.';

  @override
  String get planApplyTemplate => 'Apply template';

  @override
  String get planActivate => 'Activate';

  @override
  String get planActivateTitle => 'Activate this plan?';

  @override
  String get planActivateBody =>
      'The student will train with this plan and the plan in use is archived. The rotation restarts on the first day.';

  @override
  String get planActivated => 'Plan activated.';

  @override
  String get planDuplicate => 'Duplicate';

  @override
  String get planDuplicated => 'Copy created as a draft.';

  @override
  String get planArchive => 'Archive';

  @override
  String get planArchiveTitle => 'Archive this plan?';

  @override
  String get planArchiveBody =>
      'The plan becomes read-only. Workout history stays in the charts and you can activate it again later.';

  @override
  String get planArchiveDraftBody =>
      'This plan was never published: once archived it becomes read-only and can\'t be activated. Duplicate it to reuse it.';

  @override
  String get planArchived => 'Plan archived.';

  @override
  String get planView => 'View';

  @override
  String get planEdit => 'Edit';

  @override
  String get studentWorkoutArchived => 'Archived';

  @override
  String get studentWorkoutFromTemplate => 'From template';

  @override
  String builderPublishTemplateBody(int version) {
    return 'Publishing freezes version $version of the template. Applying to students always copies the latest published version; plans already applied do not change.';
  }

  @override
  String get builderSaveAsTemplate => 'Save as template';

  @override
  String get builderSaveAsTemplateTitle => 'Save as template';

  @override
  String get builderSavedAsTemplate =>
      'Template created as a draft. Review and publish it to apply.';

  @override
  String get builderOpenTemplate => 'Open';

  @override
  String get builderReadOnlyPlan =>
      'Archived plan: read-only. Activate it to edit again or duplicate it to make a copy.';

  @override
  String get builderReadOnlyPlanNeverPublished =>
      'Archived plan with no published version: read-only. The only way to reuse it is to duplicate it.';

  @override
  String get builderReadOnlyTemplate =>
      'Archived template: read-only. Unarchive it to edit again.';

  @override
  String get errorPlanArchived =>
      'This plan is archived and cannot be edited or published. Activate or duplicate it to continue.';

  @override
  String get errorTemplateArchived =>
      'This template is archived. Unarchive it to edit or publish.';

  @override
  String get errorTemplateNotOwned =>
      'Only the template author or the gym owner can change it.';

  @override
  String get errorTemplateNotPublished =>
      'Publish the template before applying it.';

  @override
  String get errorPlanNotFromTemplate =>
      'This plan did not come from a template.';

  @override
  String get errorPlanIsActive =>
      'The plan in use cannot be archived. Activate another plan first.';

  @override
  String get errorPlanNotPublished => 'Publish the plan before activating it.';

  @override
  String get builderDuplicateDay => 'Duplicate day';

  @override
  String get builderDuplicateBlock => 'Duplicate block';

  @override
  String get builderReorderHandle => 'Drag to reorder';

  @override
  String get builderCopyToNext => 'Copy to the next sets';

  @override
  String get builderUnpublishedChanges =>
      'Unpublished changes. The student still sees the last published version.';

  @override
  String get builderHistory => 'Version history';

  @override
  String get builderHistoryEmpty => 'No versions yet.';

  @override
  String builderHistoryBy(String name) {
    return 'by $name';
  }

  @override
  String builderHistoryCounts(int days, int exercises) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    String _temp1 = intl.Intl.pluralLogic(
      exercises,
      locale: localeName,
      other: '$exercises exercises',
      one: '1 exercise',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String builderViewingVersion(int version) {
    return 'You are viewing version $version, read-only.';
  }

  @override
  String get builderBackToCurrent => 'Back to current version';

  @override
  String builderInjuriesActive(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active injuries',
      one: '1 active injury',
    );
    return '$_temp0';
  }

  @override
  String get builderInjuriesToggle => 'Show or hide injuries';

  @override
  String get planNextDay => 'Next day';

  @override
  String get planNextDayTitle => 'Student\'s next workout';

  @override
  String get planNextDayCurrent => 'Next now';

  @override
  String planNextDaySet(String label) {
    return 'Next day: $label.';
  }

  @override
  String sessionBlockRound(int number, int total) {
    return 'Round $number of $total';
  }

  @override
  String get sessionBlockSuperset =>
      'Alternate the exercises without resting between them; rest only at the end of each round.';

  @override
  String get sessionBlockCircuit =>
      'Do the exercises back to back with no rest between them; rest at the end of each round.';

  @override
  String get sessionBlockDropset =>
      'When the set ends, lower the weight and keep going right away, with almost no rest.';

  @override
  String get sessionBlockRestPause =>
      'Take the set close to failure, rest a few seconds and continue with the same weight.';

  @override
  String get sessionBlockNow => 'Now';

  @override
  String get homeCoachTabBilling => 'Billing';

  @override
  String get billingTabInvoices => 'Invoices';

  @override
  String get billingTabPlans => 'Plans';

  @override
  String get studentTabBilling => 'Billing';

  @override
  String get billingDelinquent => 'Delinquent';

  @override
  String get invoiceStatusOpen => 'Open';

  @override
  String get invoiceStatusOverdue => 'Overdue';

  @override
  String get invoiceStatusPaid => 'Paid';

  @override
  String get invoiceStatusCanceled => 'Canceled';

  @override
  String get subscriptionStatusActive => 'Active';

  @override
  String get subscriptionStatusPaused => 'Paused';

  @override
  String get subscriptionStatusCanceled => 'Canceled';

  @override
  String get invoicesFilterAll => 'All';

  @override
  String get invoicesPeriodAll => 'All months';

  @override
  String get invoicesEmpty =>
      'No invoices yet. They show up once a student has a subscription.';

  @override
  String get invoicesEmptyFiltered => 'No invoices match these filters.';

  @override
  String get invoicesColStudent => 'Student';

  @override
  String get invoicesColDue => 'Due date';

  @override
  String get invoicesColAmount => 'Amount';

  @override
  String get invoicesColStatus => 'Status';

  @override
  String invoiceDueOn(String date) {
    return 'Due $date';
  }

  @override
  String invoicePaidOn(String date) {
    return 'Paid on $date';
  }

  @override
  String get invoiceAccountDeleted => 'account deleted';

  @override
  String get invoiceActionPay => 'Mark as paid';

  @override
  String get invoiceActionReverse => 'Reverse';

  @override
  String invoiceDetailTitle(String period) {
    return 'Invoice for $period';
  }

  @override
  String get invoicePaymentsTitle => 'Payments';

  @override
  String get invoicePaymentsEmpty => 'No payments recorded.';

  @override
  String get invoicePaymentManual => 'Manual payment';

  @override
  String get invoicePaymentReversed => 'Reversed payment';

  @override
  String get invoicePaymentReversal => 'Reversal';

  @override
  String get payDialogTitle => 'Mark as paid';

  @override
  String payDialogBody(String amount, String name) {
    return 'Confirm receiving $amount from $name? The invoice is settled in full.';
  }

  @override
  String get payDateLabel => 'Payment date';

  @override
  String get payDateToday => 'Today';

  @override
  String get payNoteLabel => 'Note (optional)';

  @override
  String get payConfirm => 'Confirm';

  @override
  String get payDone => 'Payment recorded.';

  @override
  String get reverseDialogTitle => 'Reverse payment';

  @override
  String reverseDialogBody(String amount, String name) {
    return 'Reverse $amount from $name? The invoice goes back to open or overdue.';
  }

  @override
  String get reverseReasonLabel => 'Reason for the reversal';

  @override
  String get reverseConfirm => 'Reverse';

  @override
  String get reverseDone => 'Payment reversed.';

  @override
  String get billingPlansEmpty =>
      'No membership plans yet. Create the first one to subscribe your students.';

  @override
  String get billingPlansArchivedSection => 'Archived';

  @override
  String get billingPlanNew => 'New plan';

  @override
  String get billingPlanEdit => 'Edit plan';

  @override
  String get billingPlanNameLabel => 'Plan name';

  @override
  String get billingPlanAmountLabel => 'Monthly amount';

  @override
  String get billingPlanEditHint =>
      'Existing subscriptions keep the amount they already have.';

  @override
  String billingPlanPerMonth(String amount) {
    return '$amount per month';
  }

  @override
  String get billingPlanArchive => 'Archive';

  @override
  String billingPlanArchiveTitle(String name) {
    return 'Archive $name?';
  }

  @override
  String get billingPlanArchiveBody =>
      'The plan stops being offered for new subscriptions. Existing subscriptions stay as they are.';

  @override
  String get billingPlanSaved => 'Plan saved.';

  @override
  String get billingPlanArchived => 'Plan archived.';

  @override
  String get subscriptionTitle => 'Subscription';

  @override
  String get subscriptionNone => 'This student has no subscription.';

  @override
  String get subscriptionCreate => 'Create subscription';

  @override
  String get subscriptionEdit => 'Edit';

  @override
  String get subscriptionPause => 'Pause';

  @override
  String get subscriptionResume => 'Resume';

  @override
  String get subscriptionCancel => 'Cancel subscription';

  @override
  String subscriptionSummary(int day) {
    return 'Due on day $day of every month';
  }

  @override
  String subscriptionStartsOn(String date) {
    return 'Since $date';
  }

  @override
  String get subscriptionPlanLabel => 'Membership plan';

  @override
  String get subscriptionPlanHint => 'Choose a plan';

  @override
  String get subscriptionAmountLabel => 'Amount';

  @override
  String get subscriptionDueDayLabel => 'Due day';

  @override
  String get subscriptionStartsOnLabel => 'Start';

  @override
  String get subscriptionEditHint =>
      'Amount and due day apply from the next invoice on.';

  @override
  String get subscriptionNoPlansOwner =>
      'Create a membership plan in the Billing tab before subscribing the student.';

  @override
  String get subscriptionNoPlansCoach =>
      'There is no active membership plan. Ask whoever runs the organization to create one.';

  @override
  String get subscriptionCreated => 'Subscription created.';

  @override
  String get subscriptionUpdated => 'Subscription updated.';

  @override
  String get subscriptionPaused => 'Subscription paused.';

  @override
  String get subscriptionResumed => 'Subscription resumed.';

  @override
  String get subscriptionCanceled => 'Subscription canceled.';

  @override
  String subscriptionCancelTitle(String name) {
    return 'Cancel $name\'s subscription?';
  }

  @override
  String get subscriptionCancelBody =>
      'Open invoices due in the future are canceled. Overdue ones remain to be collected.';

  @override
  String get studentInvoicesTitle => 'Invoices and payments';

  @override
  String get studentInvoicesEmpty => 'No invoices yet.';

  @override
  String get studentDeactivateSubscriptionTitle => 'Subscription still active';

  @override
  String studentDeactivateSubscriptionBody(String name) {
    return '$name was deactivated, but the subscription is still active and keeps generating invoices. Cancel it now?';
  }

  @override
  String get studentDeactivateSubscriptionKeep => 'Keep';

  @override
  String get organizationCoachBillingTitle =>
      'Coaches manage billing for their own students';

  @override
  String get organizationCoachBillingOn =>
      'On: the coach sees subscriptions and invoices of their own students, creates and edits subscriptions and marks payments. Plans, reversals and the organization\'s revenue stay with you only.';

  @override
  String get organizationCoachBillingOff =>
      'Off: the coach only sees the \"delinquent\" badge on their own students, with no amounts.';

  @override
  String get organizationCoachBillingSaved => 'Coach billing access updated.';

  @override
  String get accountInvoicesTitle => 'My payments';

  @override
  String get accountInvoicesSubtitle => 'Invoices and the status of each month';

  @override
  String get myInvoicesEmpty => 'You don\'t have any payments yet.';

  @override
  String get errorBillingAccessDenied =>
      'You don\'t have access to this part of billing.';

  @override
  String get errorInvoiceAlreadyPaid => 'This invoice is already paid.';

  @override
  String get errorInvoiceCanceled => 'This invoice is canceled.';

  @override
  String get errorPaymentAlreadyReversed =>
      'This payment was already reversed.';

  @override
  String get errorPaymentIsReversal => 'A reversal cannot be reversed.';

  @override
  String get errorIdempotencyConflict =>
      'That payment attempt was already used on another invoice. Close and try again.';

  @override
  String get errorBillingPlanArchived =>
      'This membership plan is archived. Pick another one.';

  @override
  String get errorSubscriptionExists =>
      'This student already has an active or paused subscription.';

  @override
  String get errorInvalidSubscriptionState =>
      'The subscription\'s current state doesn\'t allow this action.';
}
