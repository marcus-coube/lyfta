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
  String get loginNewHereSuffix => 'Crie a conta da sua academia.';

  @override
  String get loginTenantSheetTitle => 'Escolha uma conta';

  @override
  String get loginTenantSheetSubtitle =>
      'Este e-mail está em mais de uma conta. Selecione com qual entrar.';

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
  String get forgotPasswordSuccess =>
      'Se este e-mail tiver conta, enviamos um link de redefinição.';

  @override
  String get resetPasswordTitle => 'Definir nova senha';

  @override
  String get resetPasswordSubtitle => 'Escolha uma nova senha para sua conta.';

  @override
  String get resetPasswordNewLabel => 'Nova senha';

  @override
  String get resetPasswordSubmit => 'Salvar nova senha';

  @override
  String get resetPasswordSuccess =>
      'Senha redefinida. Entre com a nova senha.';

  @override
  String get resetPasswordInvalidLink =>
      'Link inválido. Solicite uma nova recuperação de senha.';

  @override
  String get signupTitle => 'Crie a conta da sua academia';

  @override
  String get signupSubtitle =>
      'Cadastre seu negócio para começar a gerenciar alunos e treinos.';

  @override
  String get signupBusinessNameLabel => 'Nome do negócio';

  @override
  String get signupBusinessNameHint => 'Academia Exemplo';

  @override
  String get signupSlugLabel => 'Identificador';

  @override
  String get signupSlugHint => 'academia-exemplo';

  @override
  String get signupNameLabel => 'Seu nome';

  @override
  String get signupNameHint => 'Como você se chama';

  @override
  String get signupSubmit => 'Criar conta';

  @override
  String get signupBackToLogin => 'Já tenho conta';

  @override
  String get inviteTitle => 'Aceitar convite';

  @override
  String get inviteSubtitle => 'Defina sua senha para ativar sua conta.';

  @override
  String get inviteNewPasswordLabel => 'Nova senha';

  @override
  String get inviteSubmit => 'Ativar conta';

  @override
  String get inviteInvalidLink => 'Link de convite inválido ou expirado.';

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
  String get homeCoachTabStudents => 'Alunos';

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

  @override
  String get homeCoachTabLibrary => 'Biblioteca';

  @override
  String get commonRetry => 'Tentar de novo';

  @override
  String get commonSave => 'Salvar';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonCreate => 'Criar';

  @override
  String get commonRemove => 'Remover';

  @override
  String get libraryNewExercise => 'Novo exercício';

  @override
  String get librarySearchLabel => 'Buscar exercício';

  @override
  String get librarySearchHint => 'supino, agachamento…';

  @override
  String get libraryFilterMuscle => 'Músculo';

  @override
  String get libraryFilterEquipment => 'Equipamento';

  @override
  String get libraryFilterAll => 'Todos';

  @override
  String get libraryGlobalBadge => 'Lyfta';

  @override
  String get libraryEmpty => 'Nenhum exercício encontrado.';

  @override
  String get exerciseFormNewTitle => 'Novo exercício';

  @override
  String get exerciseFormEditTitle => 'Editar exercício';

  @override
  String get exerciseFormDuplicateTitle => 'Duplicar exercício';

  @override
  String get exerciseFormDuplicateHint =>
      'Exercícios da Lyfta não podem ser editados. Salvar cria uma cópia na biblioteca da sua academia.';

  @override
  String get exerciseFormNameLabel => 'Nome';

  @override
  String get exerciseFormNameHint => 'Supino reto com barra';

  @override
  String get exerciseFormNameRequired => 'Informe o nome do exercício.';

  @override
  String get exerciseFormMuscleLabel => 'Músculo principal';

  @override
  String get exerciseFormEquipmentLabel => 'Equipamento';

  @override
  String get exerciseFormLevelLabel => 'Nível';

  @override
  String get exerciseFormInstructionsLabel => 'Instruções';

  @override
  String get exerciseFormInstructionsHint => 'Como executar o movimento';

  @override
  String get exerciseFormMediaLabel => 'Mídia';

  @override
  String get exerciseFormMediaHint => 'GIF ou vídeo curto de até 50 MB.';

  @override
  String get exerciseFormMediaPick => 'Escolher arquivo';

  @override
  String get exerciseFormMediaReplace => 'Trocar arquivo';

  @override
  String get builderTitle => 'Montar treino';

  @override
  String get builderDayTitle => 'Título do dia';

  @override
  String get builderAddDay => 'Adicionar dia';

  @override
  String get builderNoDays =>
      'Este plano ainda não tem nenhum dia. Comece pelo treino A.';

  @override
  String get builderAddBlock => 'Adicionar bloco';

  @override
  String get builderAddExercise => 'Adicionar exercício';

  @override
  String get builderAddSet => 'Adicionar série';

  @override
  String get builderDuplicateSet => 'Duplicar série';

  @override
  String get builderPickExercise => 'Escolher exercício';

  @override
  String get builderUnknownExercise => 'Exercício removido da biblioteca';

  @override
  String get builderBlockRest => 'Descanso (s)';

  @override
  String get builderRepsMin => 'Reps mín.';

  @override
  String get builderRepsMax => 'Reps máx.';

  @override
  String get builderRestSeconds => 'Descanso (s)';

  @override
  String get builderTargetUnit => 'Unidade do alvo';

  @override
  String get builderTargetKg => 'Carga (kg)';

  @override
  String get builderTargetPercent1rm => '% de 1RM';

  @override
  String get builderTargetRpe => 'RPE';

  @override
  String get builderTargetRir => 'RIR';

  @override
  String get builderBlockStraight => 'Série simples';

  @override
  String get builderBlockSuperset => 'Bi-set';

  @override
  String get builderBlockDropset => 'Drop set';

  @override
  String get builderBlockRestPause => 'Rest-pause';

  @override
  String get builderBlockCircuit => 'Circuito';

  @override
  String get builderSaveDraft => 'Salvar rascunho';

  @override
  String get builderSaved => 'Rascunho salvo';

  @override
  String get builderDraftSaved => 'Rascunho salvo.';

  @override
  String get builderPublish => 'Publicar';

  @override
  String get builderMoveUp => 'Mover para cima';

  @override
  String get builderMoveDown => 'Mover para baixo';

  @override
  String get studentsSearchLabel => 'Buscar aluno';

  @override
  String get studentsSearchHint => 'nome ou e-mail';

  @override
  String get studentsEmpty => 'Nenhum aluno ainda. Convide o primeiro.';

  @override
  String get studentsNoPlan => 'Sem plano';

  @override
  String get studentsNewPlan => 'Novo plano';

  @override
  String get studentsOpenPlan => 'Abrir';

  @override
  String get studentsNewPlanTitle => 'Novo plano';

  @override
  String get studentsNewPlanDefaultTitle => 'Treino A/B';

  @override
  String get studentsPlanTitleLabel => 'Nome do plano';

  @override
  String get studentsPendingBadge => 'convite pendente';

  @override
  String get studentsInviteTitle => 'Convidar aluno';

  @override
  String get studentsInviteNameLabel => 'Nome';

  @override
  String get studentsInviteEmailLabel => 'E-mail';

  @override
  String get studentsInviteSubmit => 'Convidar';

  @override
  String get errorNotFound => 'Não encontramos o que você procurava.';

  @override
  String get errorInvalidCursor => 'A lista mudou. Recarregue a página.';

  @override
  String get errorExerciseIsGlobal =>
      'Exercícios da Lyfta não podem ser editados. Duplique para criar o seu.';

  @override
  String get errorUnsupportedMedia =>
      'Formato não aceito. Use GIF, MP4 ou WebM.';

  @override
  String get errorFileTooLarge => 'Arquivo grande demais. O limite é 50 MB.';

  @override
  String get errorPlanNoDays => 'Adicione ao menos um dia antes de publicar.';

  @override
  String get errorPlanDayWithoutBlock =>
      'Há um dia sem nenhum bloco. Complete antes de publicar.';

  @override
  String get errorPlanBlockWithoutExercise =>
      'Há um bloco sem exercício. Complete antes de publicar.';

  @override
  String get errorPlanExerciseWithoutSet =>
      'Há um exercício sem série prescrita. Complete antes de publicar.';

  @override
  String get errorNoDraftToPublish => 'Não há alterações novas para publicar.';

  @override
  String get errorUnknownExercise =>
      'Um dos exercícios não está mais disponível na biblioteca.';

  @override
  String get muscleChest => 'Peitoral';

  @override
  String get muscleBack => 'Costas';

  @override
  String get muscleLats => 'Dorsais';

  @override
  String get muscleTraps => 'Trapézio';

  @override
  String get muscleLowerBack => 'Lombar';

  @override
  String get muscleShoulders => 'Ombros';

  @override
  String get muscleBiceps => 'Bíceps';

  @override
  String get muscleTriceps => 'Tríceps';

  @override
  String get muscleForearms => 'Antebraço';

  @override
  String get muscleAbs => 'Abdômen';

  @override
  String get muscleObliques => 'Oblíquos';

  @override
  String get muscleQuadriceps => 'Quadríceps';

  @override
  String get muscleHamstrings => 'Posterior de coxa';

  @override
  String get muscleGlutes => 'Glúteos';

  @override
  String get muscleCalves => 'Panturrilha';

  @override
  String get muscleAdductors => 'Adutores';

  @override
  String get muscleAbductors => 'Abdutores';

  @override
  String get muscleFullBody => 'Corpo inteiro';

  @override
  String get equipmentBarbell => 'Barra';

  @override
  String get equipmentDumbbell => 'Halteres';

  @override
  String get equipmentMachine => 'Máquina';

  @override
  String get equipmentCable => 'Polia';

  @override
  String get equipmentSmith => 'Smith';

  @override
  String get equipmentBodyweight => 'Peso do corpo';

  @override
  String get equipmentKettlebell => 'Kettlebell';

  @override
  String get equipmentBand => 'Elástico';

  @override
  String get equipmentBench => 'Banco';

  @override
  String get equipmentOther => 'Outro';

  @override
  String get levelBeginner => 'Iniciante';

  @override
  String get levelIntermediate => 'Intermediário';

  @override
  String get levelAdvanced => 'Avançado';

  @override
  String builderDraftVersion(int version) {
    return 'rascunho v$version';
  }

  @override
  String builderPublishedVersion(int version) {
    return 'v$version publicada';
  }

  @override
  String builderPublishBody(int version) {
    return 'Publicar congela esta versão e envia o treino para o aluno. A versão $version não poderá mais ser editada.';
  }

  @override
  String builderPublished(int version) {
    return 'Versão $version publicada.';
  }

  @override
  String studentsPlanActive(String title, int version) {
    return '$title · v$version';
  }

  @override
  String studentsPlanDraft(String title) {
    return '$title · rascunho';
  }

  @override
  String get builderPublishTitle => 'Publicar treino?';

  @override
  String get todayNoPlanTitle => 'Seu professor ainda não montou seu treino';

  @override
  String get todayNoPlanBody =>
      'Assim que ele publicar o plano, o treino do dia aparece aqui.';

  @override
  String get todayRestTitle => 'Dia de descanso';

  @override
  String get todayRestBody =>
      'Nada programado para hoje. Descanso também faz parte do treino.';

  @override
  String get todayStart => 'Iniciar treino';

  @override
  String get todayResume => 'Continuar treino';

  @override
  String get todayOffline =>
      'Sem conexão — este é o treino baixado no aparelho.';

  @override
  String get todayLoadError => 'Não foi possível carregar o treino.';

  @override
  String get todayNoPreviousLoad => 'Primeira vez';

  @override
  String get todayRecentTitle => 'Últimos treinos';

  @override
  String get todaySyncing => 'Sincronizando…';

  @override
  String get todaySynced => 'Tudo sincronizado';

  @override
  String get todayEmptyDay => 'Este treino não tem exercícios.';

  @override
  String get sessionReps => 'Reps';

  @override
  String get sessionLoadKg => 'Carga (kg)';

  @override
  String get sessionMarkDone => 'Registrar série';

  @override
  String get sessionSetDone => 'Registrada';

  @override
  String get sessionRestTitle => 'Descanso';

  @override
  String get sessionRestSkip => 'Pular descanso';

  @override
  String get sessionRestOver => 'Descanso concluído';

  @override
  String get sessionRestNotificationTitle => 'Fim do descanso';

  @override
  String get sessionFinish => 'Finalizar treino';

  @override
  String get sessionFinishTitle => 'Finalizar treino?';

  @override
  String get sessionSummaryTitle => 'Treino concluído';

  @override
  String get sessionSummarySets => 'Séries';

  @override
  String get sessionSummaryVolume => 'Volume';

  @override
  String get sessionSummaryDuration => 'Duração';

  @override
  String get sessionSummaryClose => 'Fechar';

  @override
  String get sessionTargetFreeReps => 'reps livres';

  @override
  String todayDayHeading(String label) {
    return 'Treino $label';
  }

  @override
  String todayNextWorkout(String label) {
    return 'Próximo: treino $label';
  }

  @override
  String get todaySwitch => 'Trocar treino de hoje';

  @override
  String get todaySwitchTitle => 'Qual treino você quer fazer hoje?';

  @override
  String get todaySwitchCurrent => 'Hoje';

  @override
  String get todaySwitchOffline =>
      'Sem conexão — trocar o treino precisa de internet.';

  @override
  String get todaySwitchError => 'Não foi possível trocar o treino.';

  @override
  String todayPreviousLoad(String load) {
    return 'Anterior: $load kg';
  }

  @override
  String todaySetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count séries',
      one: '1 série',
    );
    return '$_temp0';
  }

  @override
  String todayRecentEntry(String label, int sets, String volume) {
    return 'Treino $label · $sets séries · $volume kg';
  }

  @override
  String todaySyncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count registros por enviar',
      one: '1 registro por enviar',
    );
    return '$_temp0';
  }

  @override
  String sessionTitle(String label) {
    return 'Treino $label';
  }

  @override
  String sessionSet(int number) {
    return 'Série $number';
  }

  @override
  String sessionEditSet(int number) {
    return 'Corrigir série $number';
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
    return 'Hora da próxima série de $exercise.';
  }

  @override
  String sessionFinishBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Você registrou $count séries. O treino de hoje será concluído.',
      one: 'Você registrou 1 série. O treino de hoje será concluído.',
      zero:
          'Você não registrou nenhuma série — o treino de hoje não será marcado como feito.',
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
  String get studentsOpenEvolution => 'Evolução';

  @override
  String get studentsOpenChat => 'Chat';

  @override
  String get evolutionTabSummary => 'Resumo';

  @override
  String get evolutionTabLoad => 'Carga';

  @override
  String get evolutionTabMeasurements => 'Medidas';

  @override
  String get evolutionTabPhotos => 'Fotos';

  @override
  String get evolutionTabCheckins => 'Check-ins';

  @override
  String get evolutionSummaryLatestMeasurement => 'Última medida';

  @override
  String get evolutionSummaryLatestBioimpedance => 'Última bioimpedância';

  @override
  String get evolutionSummaryPhotoCount => 'Fotos de evolução';

  @override
  String get evolutionStudentTitle => 'Evolução';

  @override
  String get evolutionMeasurementsSection => 'Medidas corporais';

  @override
  String get evolutionAddMeasurement => 'Nova medida';

  @override
  String get evolutionBioimpedanceSection => 'Bioimpedância';

  @override
  String get evolutionAddBioimpedance => 'Nova leitura';

  @override
  String get evolutionPhotosSection => 'Fotos de evolução';

  @override
  String get evolutionAddPhoto => 'Nova foto';

  @override
  String get evolutionDeleteTitle => 'Apagar registro?';

  @override
  String get evolutionDeleteBody => 'Essa ação não pode ser desfeita.';

  @override
  String get evolutionPhotosCompareTitle => 'Comparar antes/depois';

  @override
  String get evolutionDateLabel => 'Data';

  @override
  String get evolutionValueHint => '0';

  @override
  String get evolutionNotesLabel => 'Observações';

  @override
  String get measurementFormEmpty => 'Preencha ao menos uma medida.';

  @override
  String get evolutionMeasurementsEmpty => 'Nenhuma medida registrada ainda.';

  @override
  String get evolutionBioimpedanceEmpty =>
      'Nenhuma leitura de bioimpedância ainda.';

  @override
  String get evolutionMetricMaxLoad => 'Carga máxima';

  @override
  String get evolutionMetricVolume => 'Volume';

  @override
  String get evolutionRangeOneMonth => '1 mês';

  @override
  String get evolutionRangeThreeMonths => '3 meses';

  @override
  String get evolutionRangeSixMonths => '6 meses';

  @override
  String get evolutionRangeAll => 'Tudo';

  @override
  String get evolutionNoDataForRange => 'Sem registros neste período.';

  @override
  String get evolutionNoExercisesYet =>
      'Você ainda não registrou nenhuma série. Treine para ver o gráfico aqui.';

  @override
  String get evolutionPhotosEmpty => 'Nenhuma foto ainda.';

  @override
  String get evolutionPhotosCompareNeedTwo =>
      'Registre pelo menos duas fotos para comparar.';

  @override
  String get evolutionPoseFront => 'Frente';

  @override
  String get evolutionPoseSide => 'Lado';

  @override
  String get evolutionPoseBack => 'Costas';

  @override
  String get evolutionNewMeasurement => 'Nova medida';

  @override
  String get evolutionNewBioimpedance => 'Nova leitura de bioimpedância';

  @override
  String get evolutionNewPhoto => 'Nova foto';

  @override
  String get evolutionPhotoFromCamera => 'Câmera';

  @override
  String get evolutionPhotoFromGallery => 'Galeria';

  @override
  String get evolutionPhotoEmptyPreview => 'Escolha uma foto para continuar.';

  @override
  String get evolutionPhotoRequired => 'Escolha uma foto antes de salvar.';

  @override
  String get evolutionPhotoPickError =>
      'Não foi possível processar a foto. Tente outra.';

  @override
  String get measurementFieldWeightKg => 'Peso (kg)';

  @override
  String get measurementFieldHeightCm => 'Altura (cm)';

  @override
  String get measurementFieldNeckCm => 'Pescoço (cm)';

  @override
  String get measurementFieldShoulderCm => 'Ombro (cm)';

  @override
  String get measurementFieldChestCm => 'Peito (cm)';

  @override
  String get measurementFieldWaistCm => 'Cintura (cm)';

  @override
  String get measurementFieldAbdomenCm => 'Abdômen (cm)';

  @override
  String get measurementFieldHipCm => 'Quadril (cm)';

  @override
  String get measurementFieldArmLCm => 'Braço esq. (cm)';

  @override
  String get measurementFieldArmRCm => 'Braço dir. (cm)';

  @override
  String get measurementFieldThighLCm => 'Coxa esq. (cm)';

  @override
  String get measurementFieldThighRCm => 'Coxa dir. (cm)';

  @override
  String get measurementFieldCalfLCm => 'Panturrilha esq. (cm)';

  @override
  String get measurementFieldCalfRCm => 'Panturrilha dir. (cm)';

  @override
  String get bioimpedanceFieldBodyFatPct => '% de gordura';

  @override
  String get bioimpedanceFieldMuscleMassKg => 'Massa muscular (kg)';

  @override
  String get bioimpedanceFieldVisceralFat => 'Gordura visceral';

  @override
  String get bioimpedanceFieldBodyWaterPct => '% de água corporal';

  @override
  String get bioimpedanceFieldBoneMassKg => 'Massa óssea (kg)';

  @override
  String get bioimpedanceFieldBmrKcal => 'Taxa metabólica basal (kcal)';

  @override
  String get chatTitleFallback => 'Chat';

  @override
  String get chatEmpty => 'Nenhuma mensagem ainda. Diga oi!';

  @override
  String get chatConversationsEmpty => 'Nenhuma conversa ainda.';

  @override
  String get chatStudentNoConversation =>
      'Seu professor ainda não iniciou uma conversa com você.';

  @override
  String get chatNoMessagesYet => 'Nenhuma mensagem ainda';

  @override
  String get chatImagePreview => '📷 Foto';

  @override
  String get chatMessageHint => 'Escreva uma mensagem…';

  @override
  String get chatAttachImage => 'Anexar foto';

  @override
  String get chatSend => 'Enviar';

  @override
  String get chatMessageFailed => 'Não enviada.';

  @override
  String get chatMessageRetry => 'Tentar de novo';

  @override
  String get checkinTitle => 'Como foi o treino?';

  @override
  String get checkinSubtitle =>
      'Sua avaliação ajuda seu professor a ajustar o próximo treino.';

  @override
  String get checkinRatingLabel => 'Nota geral';

  @override
  String get checkinDifficultyLabel => 'Dificuldade';

  @override
  String get checkinPainLabel => 'Sentiu dor?';

  @override
  String get checkinPainNone => 'Nenhuma';

  @override
  String get checkinPainMild => 'Leve';

  @override
  String get checkinPainStrong => 'Forte';

  @override
  String get checkinPainWhereLabel => 'Onde?';

  @override
  String get checkinCommentLabel => 'Comentário (opcional)';

  @override
  String get checkinSubmit => 'Enviar avaliação';

  @override
  String get checkinSubmitted => 'Avaliação enviada ao seu professor.';

  @override
  String get checkinQueuedOffline =>
      'Sem conexão — a avaliação será enviada assim que você reconectar.';

  @override
  String get checkinListEmpty => 'Nenhuma avaliação de treino ainda.';

  @override
  String checkinCardScores(int rating, int difficulty) {
    return 'Nota $rating · Dificuldade $difficulty';
  }

  @override
  String checkinCardPainWhere(String where) {
    return 'Dor em: $where';
  }

  @override
  String get checkinReviewed => 'Visto';

  @override
  String get checkinMarkReviewed => 'Marcar como visto';
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
  String get loginNewHereSuffix => 'Cria a conta do teu ginásio.';

  @override
  String get loginTenantSheetSubtitle =>
      'Este e-mail está em mais do que uma conta. Escolhe com qual entrar.';

  @override
  String get forgotPasswordSubtitle =>
      'Indica o teu e-mail para receberes o link de redefinição.';

  @override
  String get resetPasswordSubtitle =>
      'Escolhe uma nova palavra-passe para a tua conta.';

  @override
  String get resetPasswordNewLabel => 'Nova palavra-passe';

  @override
  String get resetPasswordSuccess =>
      'Palavra-passe redefinida. Entra com a nova palavra-passe.';

  @override
  String get resetPasswordInvalidLink =>
      'Link inválido. Pede uma nova recuperação de palavra-passe.';

  @override
  String get signupSubtitle =>
      'Regista o teu negócio para começares a gerir alunos e treinos.';

  @override
  String get signupNameHint => 'Como te chamas';

  @override
  String get signupBackToLogin => 'Já tenho conta';

  @override
  String get inviteSubtitle => 'Define a tua senha para ativares a tua conta.';

  @override
  String get inviteInvalidLink => 'Link de convite inválido ou expirado.';

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

  @override
  String get commonSave => 'Guardar';

  @override
  String get librarySearchHint => 'supino, agachamento…';

  @override
  String get exerciseFormMediaHint => 'GIF ou vídeo curto até 50 MB.';

  @override
  String get builderSaveDraft => 'Guardar rascunho';

  @override
  String get builderSaved => 'Rascunho guardado';

  @override
  String get builderDraftSaved => 'Rascunho guardado.';

  @override
  String get studentsSearchHint => 'nome ou e-mail';

  @override
  String get errorUnsupportedMedia =>
      'Formato não aceite. Use GIF, MP4 ou WebM.';

  @override
  String get errorFileTooLarge =>
      'Ficheiro demasiado grande. O limite é 50 MB.';

  @override
  String get muscleTraps => 'Trapézio';

  @override
  String get muscleAbs => 'Abdominais';

  @override
  String get muscleQuadriceps => 'Quadricípite';

  @override
  String get muscleHamstrings => 'Isquiotibiais';

  @override
  String get muscleCalves => 'Gémeos';

  @override
  String get equipmentDumbbell => 'Halteres';

  @override
  String get equipmentBodyweight => 'Peso corporal';

  @override
  String get equipmentBand => 'Banda elástica';

  @override
  String get todayNoPlanTitle =>
      'O teu professor ainda não montou o teu treino';

  @override
  String get todayNoPlanBody =>
      'Assim que ele publicar o plano, o treino do dia aparece aqui.';

  @override
  String get todayOffline =>
      'Sem ligação — este é o treino descarregado no aparelho.';

  @override
  String get todayLoadError => 'Não foi possível carregar o teu treino.';

  @override
  String get sessionMarkDone => 'Registar série';

  @override
  String get sessionSetDone => 'Registada';

  @override
  String get todaySwitchTitle => 'Que treino queres fazer hoje?';

  @override
  String get todaySwitchOffline =>
      'Sem ligação — trocar o treino precisa de internet.';

  @override
  String todaySetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count séries',
      one: '1 série',
    );
    return '$_temp0';
  }

  @override
  String todaySyncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count registos por enviar',
      one: '1 registo por enviar',
    );
    return '$_temp0';
  }

  @override
  String sessionFinishBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Registaste $count séries. O treino de hoje será concluído.',
      one: 'Registaste 1 série. O treino de hoje será concluído.',
      zero:
          'Não registaste nenhuma série — o treino de hoje não será marcado como feito.',
    );
    return '$_temp0';
  }

  @override
  String get chatStudentNoConversation =>
      'O teu professor ainda não iniciou uma conversa contigo.';

  @override
  String get chatMessageHint => 'Escreve uma mensagem…';

  @override
  String get checkinSubtitle =>
      'A tua avaliação ajuda o teu professor a ajustar o próximo treino.';

  @override
  String get checkinSubmitted => 'Avaliação enviada ao teu professor.';

  @override
  String get checkinQueuedOffline =>
      'Sem ligação — a avaliação será enviada assim que reconectares.';
}
