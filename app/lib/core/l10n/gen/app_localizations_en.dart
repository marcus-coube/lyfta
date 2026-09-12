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
  String studentsPlanDraft(String title) {
    return '$title · draft';
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
  String get evolutionStudentTitle => 'Progress';

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
      'Your coach hasn\'t started a conversation with you yet.';

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
}
