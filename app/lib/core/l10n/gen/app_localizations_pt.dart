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
  String appVersion(String version) {
    return 'v$version';
  }

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
  String get commonLoadMore => 'Carregar mais';

  @override
  String get commonShowPassword => 'Mostrar senha';

  @override
  String get commonHidePassword => 'Ocultar senha';

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
      'Nenhuma conversa ainda. Fale com seu professor por aqui.';

  @override
  String get chatStudentStart => 'Falar com meu professor';

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

  @override
  String get agendaLoadError => 'Não foi possível carregar sua agenda.';

  @override
  String agendaStreakWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count semanas seguidas batendo a meta de treinos',
      one: '1 semana seguida batendo a meta de treinos',
    );
    return '$_temp0';
  }

  @override
  String agendaWeekRange(String start, String end) {
    return '$start – $end';
  }

  @override
  String get agendaPreviousWeek => 'Semana anterior';

  @override
  String get agendaNextWeek => 'Próxima semana';

  @override
  String get agendaExpandMonth => 'Ver mês';

  @override
  String get agendaCollapseMonth => 'Ver semana';

  @override
  String get agendaStateDone => 'Treino feito';

  @override
  String get agendaStatePredicted => 'Treino previsto';

  @override
  String get agendaStateRest => 'Descanso';

  @override
  String agendaSessionTitle(String label) {
    return 'Treino $label';
  }

  @override
  String agendaPredictedTitle(String label) {
    return 'Treino previsto: $label';
  }

  @override
  String get agendaPredictedHint =>
      'Projeção com base no seu rodízio atual — pode mudar conforme você treina.';

  @override
  String get agendaRestTitle => 'Dia de descanso';

  @override
  String get agendaRestHint => 'Nenhum treino registrado neste dia.';

  @override
  String get consentTitle => 'Antes de continuar';

  @override
  String get consentSubtitle =>
      'Para usar o Lyfta precisamos do seu consentimento. Você decide sobre cada item e pode mudar de ideia depois, em Conta.';

  @override
  String get consentTermsAccept =>
      'Li e aceito os Termos de Uso e a Política de Privacidade';

  @override
  String get consentReadTerms => 'Ler os Termos de Uso';

  @override
  String get consentReadPrivacy => 'Ler a Política de Privacidade';

  @override
  String get consentHealthDataTitle => 'Dados de saúde (obrigatório)';

  @override
  String get consentHealthDataBody =>
      'Autorizo o tratamento dos meus dados de saúde — treinos, cargas, medidas e bioimpedância — para a prescrição e o acompanhamento do meu treino.';

  @override
  String get consentPhotosTitle => 'Fotos de evolução (opcional)';

  @override
  String get consentPhotosBody =>
      'Autorizo guardar minhas fotos de evolução e mostrá-las ao meu professor. Sem isso o app funciona normalmente, só não envia fotos.';

  @override
  String get consentSubmit => 'Continuar';

  @override
  String get consentRequiredHint =>
      'Aceite os itens obrigatórios para continuar.';

  @override
  String get consentSignOut => 'Sair';

  @override
  String get legalClose => 'Fechar';

  @override
  String get legalLoadError => 'Não foi possível carregar o documento.';

  @override
  String get accountTooltip => 'Conta';

  @override
  String get accountTitle => 'Conta';

  @override
  String get accountPrivacySection => 'Privacidade';

  @override
  String get accountPhotosTitle => 'Fotos de evolução';

  @override
  String get accountPhotosSubtitle =>
      'Permite guardar suas fotos e mostrá-las ao seu professor. Ao desligar, o envio de fotos é bloqueado e seu professor deixa de ver as que já enviou.';

  @override
  String get accountLegalSection => 'Documentos';

  @override
  String get accountSignOut => 'Sair da conta';

  @override
  String get accountDeleteSection => 'Excluir conta';

  @override
  String get accountDeleteTitle => 'Excluir minha conta';

  @override
  String get accountDeleteSubtitle =>
      'Apaga seus dados de saúde e suas fotos, anonimiza seus treinos e mensagens e encerra seu acesso. Não dá para desfazer.';

  @override
  String get accountDeleteDialogTitle => 'Excluir a conta definitivamente?';

  @override
  String get accountDeleteDialogBody =>
      'Serão apagados: medidas, bioimpedância e fotos de evolução, inclusive os arquivos. Serão anonimizados: seus treinos executados e suas mensagens, que ficam sem o seu nome. Seu acesso será encerrado e isso não pode ser desfeito.';

  @override
  String get accountDeletePasswordLabel => 'Confirme sua senha';

  @override
  String get accountDeleteConfirm => 'Excluir definitivamente';

  @override
  String get organizationSection => 'Organização';

  @override
  String get organizationNameLabel => 'Nome da organização';

  @override
  String get organizationTimezoneLabel => 'Fuso horário';

  @override
  String get organizationTimezoneHelp =>
      'Define o “hoje” e os horários dos lembretes dos seus alunos.';

  @override
  String get organizationTimezoneSearchHint => 'Buscar fuso';

  @override
  String get organizationTimezoneOther => 'Outro fuso…';

  @override
  String get organizationTimezoneOtherLabel =>
      'Nome do fuso (ex.: America/Sao_Paulo)';

  @override
  String get organizationSaved => 'Organização atualizada.';

  @override
  String get organizationLoadError => 'Não conseguimos carregar a organização.';

  @override
  String get errorInvalidTimezone =>
      'Esse fuso horário não existe. Escolha um da lista ou use um nome como America/Sao_Paulo.';

  @override
  String get errorConsentRequired =>
      'Você não autorizou esse uso dos seus dados. Ajuste em Conta > Privacidade.';

  @override
  String get errorInvitationNotFound =>
      'Esse convite não existe mais. Atualize a ficha do aluno.';

  @override
  String get errorInvitationAlreadyAccepted =>
      'Esse convite já foi aceito — o aluno já tem acesso.';

  @override
  String get errorStudentConsentRequired =>
      'O aluno não autorizou o uso dos dados de saúde. Só ele pode mudar isso, em Conta > Privacidade.';

  @override
  String get errorTermsVersionMismatch =>
      'Os termos foram atualizados. Reabra o app para ler a nova versão.';

  @override
  String get errorInvalidPassword => 'Senha incorreta.';

  @override
  String get errorOwnerCannotDelete =>
      'O dono da conta não pode excluí-la por aqui. Encerrar a academia é outro processo — fale com o suporte.';

  @override
  String get errorErasureFailed =>
      'Não conseguimos concluir a exclusão agora. Tente de novo em instantes.';

  @override
  String errorTooManyRequests(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutos',
      one: '1 minuto',
    );
    return 'Muitas tentativas. Aguarde $_temp0 e tente de novo.';
  }

  @override
  String get errorStudentNotFound =>
      'Este aluno não está na sua lista de alunos.';

  @override
  String studentsCoachLabel(String name) {
    return 'Professor: $name';
  }

  @override
  String get studentsChangeCoach => 'Trocar professor';

  @override
  String studentsChangeCoachTitle(String student) {
    return 'Professor de $student';
  }

  @override
  String studentsCoachChanged(String name) {
    return 'Professor trocado para $name.';
  }

  @override
  String get studentsCoachesEmpty => 'Nenhum professor disponível.';

  @override
  String get errorNoCoach =>
      'Você ainda não tem um professor responsável. Fale com a sua academia.';

  @override
  String get inviteSwitchAccountNotice =>
      'Você está conectado com outra conta neste aparelho. Ativar este convite sai dela e entra na conta nova.';

  @override
  String get todayDoneOfflineTitle => 'Treino de hoje concluído';

  @override
  String get todayDoneOfflineBody =>
      'Ele fica salvo no aparelho e sincroniza sozinho quando a conexão voltar. O próximo treino aparece em seguida.';

  @override
  String get studentsFilterActive => 'Ativos';

  @override
  String get studentsFilterInactive => 'Inativos';

  @override
  String get studentsFilterInvited => 'Convites pendentes';

  @override
  String get studentsFilterCoachLabel => 'Professor';

  @override
  String get studentsFilterCoachAll => 'Todos os professores';

  @override
  String get studentsEmptyFiltered =>
      'Nenhum aluno encontrado com esses filtros.';

  @override
  String get studentsLoadMoreError => 'Não foi possível carregar mais alunos.';

  @override
  String get studentsColName => 'Aluno';

  @override
  String get studentsColCoach => 'Professor';

  @override
  String get studentsColPlan => 'Plano';

  @override
  String get studentsColLastWorkout => 'Último treino';

  @override
  String get studentsLastWorkoutNever => 'Nunca treinou';

  @override
  String get studentsLastWorkoutToday => 'Hoje';

  @override
  String get studentsLastWorkoutYesterday => 'Ontem';

  @override
  String studentsLastWorkoutDaysAgo(int days) {
    return 'Há $days dias';
  }

  @override
  String get studentsColStatus => 'Status';

  @override
  String get studentStatusActive => 'Ativo';

  @override
  String get studentStatusInactive => 'Inativo';

  @override
  String get studentStatusInvited => 'Convite pendente';

  @override
  String get studentStatusDisabled => 'Bloqueado';

  @override
  String get studentDetailTitle => 'Aluno';

  @override
  String get studentTabData => 'Dados';

  @override
  String get studentTabWorkout => 'Treino';

  @override
  String get studentTabEvolution => 'Evolução';

  @override
  String get studentTabCheckins => 'Check-ins';

  @override
  String get studentDataSectionRegistry => 'Cadastro';

  @override
  String get studentDataNameLabel => 'Nome';

  @override
  String get studentDataEmailLabel => 'E-mail';

  @override
  String get studentDataSaved => 'Dados salvos.';

  @override
  String get profilePhoneLabel => 'Telefone';

  @override
  String get profileBirthLabel => 'Nascimento';

  @override
  String get profileBirthEmpty => 'Não informado';

  @override
  String get profileBirthClear => 'Limpar data';

  @override
  String get accountProfileSection => 'Meus dados';

  @override
  String get accountProfileSaved => 'Dados salvos.';

  @override
  String get studentStatusSection => 'Situação';

  @override
  String get studentDeactivate => 'Inativar aluno';

  @override
  String studentDeactivateTitle(String name) {
    return 'Inativar $name?';
  }

  @override
  String get studentDeactivateBody =>
      'O aluno perde o acesso ao app e sai da lista padrão. Treinos, medidas e conversas ficam guardados, e você pode reativar quando quiser.';

  @override
  String get studentDeactivateConfirm => 'Inativar';

  @override
  String get studentDeactivated => 'Aluno inativado.';

  @override
  String get studentReactivate => 'Reativar aluno';

  @override
  String studentReactivateTitle(String name) {
    return 'Reativar $name?';
  }

  @override
  String get studentReactivateBody => 'O aluno volta a poder entrar no app.';

  @override
  String get studentReactivateConfirm => 'Reativar';

  @override
  String get studentReactivated => 'Aluno reativado.';

  @override
  String get studentReasonLabel => 'Motivo (opcional)';

  @override
  String get studentInvitePending => 'Convite enviado, ainda não aceito.';

  @override
  String get studentInviteExpired =>
      'O convite expirou. Reenvie para o aluno poder entrar.';

  @override
  String get studentInviteResend => 'Reenviar convite';

  @override
  String get studentInviteResent => 'Convite reenviado.';

  @override
  String get studentCoachSection => 'Professor';

  @override
  String get studentCoachNone => 'Sem professor';

  @override
  String get studentHistorySection => 'Histórico de status';

  @override
  String get studentHistoryEmpty => 'Nenhuma mudança de status.';

  @override
  String studentHistoryEntry(String from, String to) {
    return '$from → $to';
  }

  @override
  String studentHistoryBy(String name) {
    return 'por $name';
  }

  @override
  String get studentWorkoutEmpty => 'Nenhum plano ainda. Crie o primeiro.';

  @override
  String get errorAlreadyInactive => 'Este aluno já está inativo.';

  @override
  String get errorAlreadyActive => 'Este aluno já está ativo.';

  @override
  String get errorInvalidStatusTransition =>
      'Este aluno ainda não aceitou o convite ou está bloqueado, então o status não pode ser mudado.';

  @override
  String get studentWorkoutDraft => 'Rascunho';

  @override
  String studentWorkoutVersion(int version) {
    return 'v$version';
  }

  @override
  String get studentWorkoutInUse => 'Em uso';

  @override
  String get profileHealthSection => 'Objetivo e saúde';

  @override
  String get profileGoalLabel => 'Objetivo';

  @override
  String get profileUnset => 'Não informado';

  @override
  String get goalHypertrophy => 'Hipertrofia';

  @override
  String get goalWeightLoss => 'Emagrecimento';

  @override
  String get goalStrength => 'Força';

  @override
  String get goalConditioning => 'Condicionamento';

  @override
  String get goalHealth => 'Saúde e bem-estar';

  @override
  String get goalRehab => 'Reabilitação';

  @override
  String get goalOther => 'Outro';

  @override
  String get profileGoalNotesLabel => 'Detalhes do objetivo';

  @override
  String get profileExperienceLabel => 'Experiência com treino';

  @override
  String get experienceBeginner => 'Iniciante';

  @override
  String get experienceIntermediate => 'Intermediário';

  @override
  String get experienceAdvanced => 'Avançado';

  @override
  String get profileWeeklyTargetLabel => 'Meta semanal de treinos';

  @override
  String get profileWeeklyTargetCoachOnly => 'Definida pelo seu professor.';

  @override
  String profileWeeklyTargetOption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count treinos por semana',
      one: '1 treino por semana',
    );
    return '$_temp0';
  }

  @override
  String get profileMedicalNotesLabel => 'Observações médicas';

  @override
  String get profileMedicalNotesHint => 'Condições, medicamentos, restrições';

  @override
  String get profileCoachNotesLabel => 'Notas privadas do professor';

  @override
  String get profileCoachNotesHint => 'O aluno não vê estas notas.';

  @override
  String get profileHealthSaved => 'Objetivo e saúde salvos.';

  @override
  String get injuriesSection => 'Lesões e restrições';

  @override
  String get injuriesEmpty => 'Nenhuma lesão registrada.';

  @override
  String get injuriesAdd => 'Adicionar lesão';

  @override
  String get injuriesResolvedHeader => 'Resolvidas';

  @override
  String get injuryFormTitle => 'Nova lesão';

  @override
  String get injuryRegionLabel => 'Região do corpo';

  @override
  String get injuryDescriptionLabel => 'Descrição';

  @override
  String get injurySinceLabel => 'Desde quando';

  @override
  String get injurySinceEmpty => 'Não informado';

  @override
  String get injurySinceClear => 'Limpar data';

  @override
  String injurySinceOn(String date) {
    return 'Desde $date';
  }

  @override
  String injuryResolvedOn(String date) {
    return 'Resolvida em $date';
  }

  @override
  String get injuryResolve => 'Marcar como resolvida';

  @override
  String get injuryReopen => 'Reabrir';

  @override
  String get injuryDeleteTitle => 'Remover lesão?';

  @override
  String get injuryDeleteBody => 'O registro será apagado.';

  @override
  String get bodyRegionNeck => 'Pescoço';

  @override
  String get bodyRegionShoulder => 'Ombro';

  @override
  String get bodyRegionElbow => 'Cotovelo';

  @override
  String get bodyRegionWristHand => 'Punho e mão';

  @override
  String get bodyRegionUpperBack => 'Costas (parte alta)';

  @override
  String get bodyRegionLowerBack => 'Lombar';

  @override
  String get bodyRegionChest => 'Peito';

  @override
  String get bodyRegionHip => 'Quadril';

  @override
  String get bodyRegionKnee => 'Joelho';

  @override
  String get bodyRegionAnkleFoot => 'Tornozelo e pé';

  @override
  String get bodyRegionOther => 'Outra';

  @override
  String get myGoalTitle => 'Meu objetivo';

  @override
  String get myGoalIntro =>
      'Seu professor usa isto para montar o seu treino. As observações médicas só você e ele veem.';

  @override
  String get accountGoalSubtitle => 'Objetivo, experiência e saúde';

  @override
  String get goalPromptTitle => 'Qual é o seu objetivo?';

  @override
  String get goalPromptBody =>
      'Conte ao seu professor o que você quer alcançar e se tem alguma lesão. Leva um minuto e dá para mudar depois, em Conta.';

  @override
  String get goalPromptNow => 'Preencher agora';

  @override
  String get goalPromptLater => 'Agora não';

  @override
  String get evolutionSummaryGoalUnset => 'Objetivo não informado';

  @override
  String get evolutionSummaryNoInjuries => 'Sem lesões ativas';

  @override
  String get homeCoachTabTemplates => 'Modelos';

  @override
  String get templatesSearchLabel => 'Buscar modelo';

  @override
  String get templatesSearchHint => 'título do modelo';

  @override
  String get templatesFilterActive => 'Ativos';

  @override
  String get templatesFilterArchived => 'Arquivados';

  @override
  String get templatesNew => 'Novo modelo';

  @override
  String get templatesNewTitle => 'Novo modelo';

  @override
  String get templatesTitleLabel => 'Título';

  @override
  String get templatesDescriptionLabel => 'Descrição (opcional)';

  @override
  String get templatesEmpty =>
      'Nenhum modelo ainda. Monte um treino uma vez e aplique a vários alunos.';

  @override
  String get templatesEmptyFiltered => 'Nenhum modelo encontrado.';

  @override
  String get templatesEmptyArchived => 'Nenhum modelo arquivado.';

  @override
  String templatesDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dias',
      one: '1 dia',
    );
    return '$_temp0';
  }

  @override
  String templatesExercises(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercícios',
      one: '1 exercício',
    );
    return '$_temp0';
  }

  @override
  String templatesAssignedTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'aplicado a $count alunos',
      one: 'aplicado a 1 aluno',
    );
    return '$_temp0';
  }

  @override
  String get templatesNotAssigned => 'ainda não aplicado';

  @override
  String get templatesUnpublishedChanges => 'alterações não publicadas';

  @override
  String get templatesMenuEdit => 'Editar';

  @override
  String get templatesMenuAssign => 'Aplicar a alunos';

  @override
  String get templatesMenuRecipients => 'Quem recebeu';

  @override
  String get templatesMenuArchive => 'Arquivar';

  @override
  String get templatesMenuUnarchive => 'Desarquivar';

  @override
  String get templatesArchivedToast => 'Modelo arquivado.';

  @override
  String get templatesUnarchivedToast => 'Modelo desarquivado.';

  @override
  String get assignTitle => 'Aplicar a alunos';

  @override
  String assignTemplateName(String title) {
    return 'Modelo: $title';
  }

  @override
  String assignSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alunos selecionados',
      one: '1 aluno selecionado',
      zero: 'Nenhum aluno selecionado',
    );
    return '$_temp0';
  }

  @override
  String assignLimitReached(int max) {
    return 'Limite de $max alunos por vez atingido.';
  }

  @override
  String get assignPublishNow => 'Publicar já';

  @override
  String get assignPublishNowHint =>
      'O treino entra na rotação do aluno agora. Desligado, cada aluno recebe um rascunho para você ajustar antes.';

  @override
  String get assignSubmit => 'Aplicar';

  @override
  String get batchResultTitle => 'Resultado';

  @override
  String batchResultSummary(int ok, int total) {
    return '$ok de $total com sucesso.';
  }

  @override
  String get batchItemOk => 'Plano criado';

  @override
  String batchItemReapplied(int version) {
    return 'Versão $version publicada';
  }

  @override
  String get batchBackToSelection => 'Tentar de novo os que falharam';

  @override
  String get batchDone => 'Concluir';

  @override
  String get recipientsTitle => 'Quem recebeu';

  @override
  String get recipientsEmpty =>
      'Este modelo ainda não foi aplicado a nenhum aluno.';

  @override
  String recipientsCurrentVersion(int version) {
    return 'versão atual v$version';
  }

  @override
  String get recipientsUpToDate => 'Na versão atual';

  @override
  String recipientsOutdated(int version) {
    return 'Na v$version do modelo';
  }

  @override
  String get recipientsEdited => 'Editado depois de aplicado';

  @override
  String get recipientsArchived => 'Plano arquivado';

  @override
  String get recipientsSelectOutdated => 'Selecionar desatualizados';

  @override
  String get recipientsSubmit => 'Reaplicar';

  @override
  String get recipientsConfirmTitle => 'Reaplicar o modelo?';

  @override
  String recipientsConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alunos será substituído',
      one: '1 aluno será substituído',
    );
    return 'O treino de $_temp0 pela versão atual do modelo e uma versão nova será publicada. Os ajustes individuais feitos nesses planos serão perdidos.';
  }

  @override
  String recipientsConfirmEdited(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count deles foram editados depois de aplicados.',
      one: '1 deles foi editado depois de aplicado.',
    );
    return '$_temp0';
  }

  @override
  String get applyModelTitle => 'Aplicar modelo';

  @override
  String get applyModelEmpty =>
      'Nenhum modelo publicado. Publique um na aba Modelos.';

  @override
  String get applyModelApplied => 'Modelo aplicado e em uso.';

  @override
  String get applyModelAppliedDraft => 'Modelo aplicado como rascunho.';

  @override
  String get planApplyTemplate => 'Aplicar modelo';

  @override
  String get planActivate => 'Ativar';

  @override
  String get planActivateTitle => 'Ativar este plano?';

  @override
  String get planActivateBody =>
      'O aluno passa a treinar por este plano e o plano em uso é arquivado. A rotação recomeça no primeiro dia.';

  @override
  String get planActivated => 'Plano ativado.';

  @override
  String get planDuplicate => 'Duplicar';

  @override
  String get planDuplicated => 'Cópia criada em rascunho.';

  @override
  String get planArchive => 'Arquivar';

  @override
  String get planArchiveTitle => 'Arquivar este plano?';

  @override
  String get planArchiveBody =>
      'O plano fica somente leitura. O histórico de treinos continua nos gráficos e dá para ativá-lo de novo depois.';

  @override
  String get planArchived => 'Plano arquivado.';

  @override
  String get planView => 'Ver';

  @override
  String get planEdit => 'Editar';

  @override
  String get studentWorkoutArchived => 'Arquivado';

  @override
  String get studentWorkoutFromTemplate => 'De modelo';

  @override
  String builderPublishTemplateBody(int version) {
    return 'Publicar congela a versão $version do modelo. Aplicar a alunos copia sempre a última versão publicada; planos já aplicados não mudam.';
  }

  @override
  String get builderSaveAsTemplate => 'Salvar como modelo';

  @override
  String get builderSaveAsTemplateTitle => 'Salvar como modelo';

  @override
  String get builderSavedAsTemplate =>
      'Modelo criado em rascunho. Revise e publique para aplicar.';

  @override
  String get builderOpenTemplate => 'Abrir';

  @override
  String get builderReadOnlyPlan =>
      'Plano arquivado: somente leitura. Ative para voltar a editar ou duplique para criar uma cópia.';

  @override
  String get builderReadOnlyPlanNeverPublished =>
      'Plano arquivado sem versão publicada: somente leitura. Só dá para aproveitá-lo duplicando.';

  @override
  String get builderReadOnlyTemplate =>
      'Modelo arquivado: somente leitura. Desarquive para voltar a editar.';

  @override
  String get errorPlanArchived =>
      'Este plano está arquivado e não pode ser editado nem publicado. Ative-o ou duplique-o para continuar.';

  @override
  String get errorTemplateArchived =>
      'Este modelo está arquivado. Desarquive-o para editar ou publicar.';

  @override
  String get errorTemplateNotOwned =>
      'Só o autor do modelo ou o dono da academia pode alterá-lo.';

  @override
  String get errorTemplateNotPublished =>
      'Publique o modelo antes de aplicá-lo.';

  @override
  String get errorPlanNotFromTemplate => 'Este plano não veio de um modelo.';

  @override
  String get errorPlanIsActive =>
      'O plano em uso não pode ser arquivado. Ative outro plano antes.';

  @override
  String get errorPlanNotPublished => 'Publique o plano antes de ativá-lo.';
}

/// The translations for Portuguese, as used in Portugal (`pt_PT`).
class AppLocalizationsPtPt extends AppLocalizationsPt {
  AppLocalizationsPtPt() : super('pt_PT');

  @override
  String get appTitle => 'Lyfta';

  @override
  String appVersion(String version) {
    return 'v$version';
  }

  @override
  String get loginWelcomeBack => 'Bem-vindo de volta';

  @override
  String get loginSubtitle =>
      'Entra para acompanhares os teus treinos e a tua evolução.';

  @override
  String get loginEmailLabel => 'E-mail';

  @override
  String get loginEmailHint => 'nome@exemplo.com';

  @override
  String get loginPasswordLabel => 'Palavra-passe';

  @override
  String get loginPasswordHint => '••••••••';

  @override
  String get loginForgotPassword => 'Esqueci-me da palavra-passe';

  @override
  String get loginSubmit => 'Entrar';

  @override
  String get loginOrDivider => 'ou';

  @override
  String get loginContinueWithGoogle => 'Continuar com Google';

  @override
  String get loginNewHerePrefix => 'Novo por aqui? ';

  @override
  String get loginNewHereSuffix => 'Cria a conta do teu ginásio.';

  @override
  String get loginTenantSheetTitle => 'Escolhe uma conta';

  @override
  String get loginTenantSheetSubtitle =>
      'Este e-mail está em mais do que uma conta. Escolhe com qual entrar.';

  @override
  String get forgotPasswordTitle => 'Recuperar palavra-passe';

  @override
  String get forgotPasswordSubtitle =>
      'Indica o teu e-mail para receberes o link de redefinição.';

  @override
  String get forgotPasswordSubmit => 'Enviar link';

  @override
  String get forgotPasswordBackToLogin => 'Voltar ao início de sessão';

  @override
  String get forgotPasswordSuccess =>
      'Se este e-mail tiver conta, enviámos um link de redefinição.';

  @override
  String get resetPasswordTitle => 'Definir nova palavra-passe';

  @override
  String get resetPasswordSubtitle =>
      'Escolhe uma nova palavra-passe para a tua conta.';

  @override
  String get resetPasswordNewLabel => 'Nova palavra-passe';

  @override
  String get resetPasswordSubmit => 'Guardar nova palavra-passe';

  @override
  String get resetPasswordSuccess =>
      'Palavra-passe redefinida. Entra com a nova palavra-passe.';

  @override
  String get resetPasswordInvalidLink =>
      'Link inválido. Pede uma nova recuperação de palavra-passe.';

  @override
  String get signupTitle => 'Cria a conta do teu ginásio';

  @override
  String get signupSubtitle =>
      'Regista o teu negócio para começares a gerir alunos e treinos.';

  @override
  String get signupBusinessNameLabel => 'Nome do negócio';

  @override
  String get signupBusinessNameHint => 'Ginásio Exemplo';

  @override
  String get signupSlugLabel => 'Identificador';

  @override
  String get signupSlugHint => 'ginasio-exemplo';

  @override
  String get signupNameLabel => 'O teu nome';

  @override
  String get signupNameHint => 'Como te chamas';

  @override
  String get signupSubmit => 'Criar conta';

  @override
  String get signupBackToLogin => 'Já tenho conta';

  @override
  String get inviteTitle => 'Aceitar convite';

  @override
  String get inviteSubtitle =>
      'Define a tua palavra-passe para ativares a tua conta.';

  @override
  String get inviteNewPasswordLabel => 'Nova palavra-passe';

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
  String get errorInvalidToken => 'Link inválido ou expirado.';

  @override
  String get errorUnauthenticated => 'A tua sessão expirou. Entra novamente.';

  @override
  String get errorForbidden => 'Não tens permissão para essa ação.';

  @override
  String get errorSlugTaken => 'Este identificador já está a ser utilizado.';

  @override
  String get errorInternal => 'Algo correu mal. Tenta novamente.';

  @override
  String get errorNetwork =>
      'Sem ligação ao servidor. Verifica a tua Internet.';

  @override
  String get homeCoachTabLibrary => 'Biblioteca';

  @override
  String get commonRetry => 'Tentar novamente';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonCreate => 'Criar';

  @override
  String get commonRemove => 'Remover';

  @override
  String get commonLoadMore => 'Carregar mais';

  @override
  String get commonShowPassword => 'Mostrar palavra-passe';

  @override
  String get commonHidePassword => 'Ocultar palavra-passe';

  @override
  String get libraryNewExercise => 'Novo exercício';

  @override
  String get librarySearchLabel => 'Procurar exercício';

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
      'Os exercícios da Lyfta não podem ser editados. Guardar cria uma cópia na biblioteca do teu ginásio.';

  @override
  String get exerciseFormNameLabel => 'Nome';

  @override
  String get exerciseFormNameHint => 'Supino plano com barra';

  @override
  String get exerciseFormNameRequired => 'Indica o nome do exercício.';

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
  String get exerciseFormMediaLabel => 'Multimédia';

  @override
  String get exerciseFormMediaHint => 'GIF ou vídeo curto até 50 MB.';

  @override
  String get exerciseFormMediaPick => 'Escolher ficheiro';

  @override
  String get exerciseFormMediaReplace => 'Trocar ficheiro';

  @override
  String get builderTitle => 'Montar treino';

  @override
  String get builderDayTitle => 'Título do dia';

  @override
  String get builderAddDay => 'Adicionar dia';

  @override
  String get builderNoDays =>
      'Este plano ainda não tem qualquer dia. Começa pelo treino A.';

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
  String get builderSaveDraft => 'Guardar rascunho';

  @override
  String get builderSaved => 'Rascunho guardado';

  @override
  String get builderDraftSaved => 'Rascunho guardado.';

  @override
  String get builderPublish => 'Publicar';

  @override
  String get builderMoveUp => 'Mover para cima';

  @override
  String get builderMoveDown => 'Mover para baixo';

  @override
  String get studentsSearchLabel => 'Procurar aluno';

  @override
  String get studentsSearchHint => 'nome ou e-mail';

  @override
  String get studentsEmpty => 'Ainda não há alunos. Convida o primeiro.';

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
  String get errorNotFound => 'Não encontrámos o que procuravas.';

  @override
  String get errorInvalidCursor => 'A lista mudou. Recarrega a página.';

  @override
  String get errorExerciseIsGlobal =>
      'Os exercícios da Lyfta não podem ser editados. Duplica para criares o teu.';

  @override
  String get errorUnsupportedMedia =>
      'Formato não aceite. Usa GIF, MP4 ou WebM.';

  @override
  String get errorFileTooLarge =>
      'Ficheiro demasiado grande. O limite é 50 MB.';

  @override
  String get errorPlanNoDays =>
      'Adiciona pelo menos um dia antes de publicares.';

  @override
  String get errorPlanDayWithoutBlock =>
      'Há um dia sem qualquer bloco. Completa antes de publicares.';

  @override
  String get errorPlanBlockWithoutExercise =>
      'Há um bloco sem exercício. Completa antes de publicares.';

  @override
  String get errorPlanExerciseWithoutSet =>
      'Há um exercício sem série prescrita. Completa antes de publicares.';

  @override
  String get errorNoDraftToPublish => 'Não há alterações novas para publicar.';

  @override
  String get errorUnknownExercise =>
      'Um dos exercícios já não está disponível na biblioteca.';

  @override
  String get muscleChest => 'Peitoral';

  @override
  String get muscleBack => 'Costas';

  @override
  String get muscleLats => 'Grande dorsal';

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
  String get muscleAbs => 'Abdominais';

  @override
  String get muscleObliques => 'Oblíquos';

  @override
  String get muscleQuadriceps => 'Quadricípite';

  @override
  String get muscleHamstrings => 'Isquiotibiais';

  @override
  String get muscleGlutes => 'Glúteos';

  @override
  String get muscleCalves => 'Gémeos';

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
  String get equipmentBodyweight => 'Peso corporal';

  @override
  String get equipmentKettlebell => 'Kettlebell';

  @override
  String get equipmentBand => 'Banda elástica';

  @override
  String get equipmentBench => 'Banco';

  @override
  String get equipmentOther => 'Outro';

  @override
  String get levelBeginner => 'Iniciante';

  @override
  String get levelIntermediate => 'Intermédio';

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
    return 'Publicar congela esta versão e envia o treino para o aluno. A versão $version não poderá voltar a ser editada.';
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
  String get builderPublishTitle => 'Publicar treino?';

  @override
  String get todayNoPlanTitle =>
      'O teu professor ainda não montou o teu treino';

  @override
  String get todayNoPlanBody =>
      'Assim que ele publicar o plano, o treino do dia aparece aqui.';

  @override
  String get todayRestTitle => 'Dia de descanso';

  @override
  String get todayRestBody =>
      'Nada programado para hoje. O descanso também faz parte do treino.';

  @override
  String get todayStart => 'Iniciar treino';

  @override
  String get todayResume => 'Continuar treino';

  @override
  String get todayOffline =>
      'Sem ligação — este é o treino transferido para o dispositivo.';

  @override
  String get todayLoadError => 'Não foi possível carregar o treino.';

  @override
  String get todayNoPreviousLoad => 'Primeira vez';

  @override
  String get todayRecentTitle => 'Últimos treinos';

  @override
  String get todaySyncing => 'A sincronizar…';

  @override
  String get todaySynced => 'Tudo sincronizado';

  @override
  String get todayEmptyDay => 'Este treino não tem exercícios.';

  @override
  String get sessionReps => 'Reps';

  @override
  String get sessionLoadKg => 'Carga (kg)';

  @override
  String get sessionMarkDone => 'Registar série';

  @override
  String get sessionSetDone => 'Registada';

  @override
  String get sessionRestTitle => 'Descanso';

  @override
  String get sessionRestSkip => 'Saltar descanso';

  @override
  String get sessionRestOver => 'Descanso concluído';

  @override
  String get sessionRestNotificationTitle => 'Fim do descanso';

  @override
  String get sessionFinish => 'Terminar treino';

  @override
  String get sessionFinishTitle => 'Terminar treino?';

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
  String get todaySwitch => 'Trocar o treino de hoje';

  @override
  String get todaySwitchTitle => 'Que treino queres fazer hoje?';

  @override
  String get todaySwitchCurrent => 'Hoje';

  @override
  String get todaySwitchOffline =>
      'Sem ligação — trocar o treino precisa de Internet.';

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
      other: '$count registos por enviar',
      one: '1 registo por enviar',
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
    return 'Corrigir a série $number';
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
      other: 'Registaste $count séries. O treino de hoje será concluído.',
      one: 'Registaste 1 série. O treino de hoje será concluído.',
      zero:
          'Não registaste qualquer série — o treino de hoje não será marcado como feito.',
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
  String get evolutionSummaryLatestMeasurement => 'Última medição';

  @override
  String get evolutionSummaryLatestBioimpedance => 'Última bioimpedância';

  @override
  String get evolutionSummaryPhotoCount => 'Fotografias de evolução';

  @override
  String get evolutionMeasurementsSection => 'Medidas corporais';

  @override
  String get evolutionAddMeasurement => 'Nova medição';

  @override
  String get evolutionBioimpedanceSection => 'Bioimpedância';

  @override
  String get evolutionAddBioimpedance => 'Nova leitura';

  @override
  String get evolutionPhotosSection => 'Fotografias de evolução';

  @override
  String get evolutionAddPhoto => 'Nova fotografia';

  @override
  String get evolutionDeleteTitle => 'Apagar registo?';

  @override
  String get evolutionDeleteBody => 'Esta ação não pode ser anulada.';

  @override
  String get evolutionPhotosCompareTitle => 'Comparar antes/depois';

  @override
  String get evolutionDateLabel => 'Data';

  @override
  String get evolutionValueHint => '0';

  @override
  String get evolutionNotesLabel => 'Observações';

  @override
  String get measurementFormEmpty => 'Preenche pelo menos uma medida.';

  @override
  String get evolutionMeasurementsEmpty => 'Ainda não há medições registadas.';

  @override
  String get evolutionBioimpedanceEmpty =>
      'Ainda não há leituras de bioimpedância.';

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
  String get evolutionNoDataForRange => 'Sem registos neste período.';

  @override
  String get evolutionNoExercisesYet =>
      'Ainda não registaste qualquer série. Treina para veres o gráfico aqui.';

  @override
  String get evolutionPhotosEmpty => 'Ainda não há fotografias.';

  @override
  String get evolutionPhotosCompareNeedTwo =>
      'Regista pelo menos duas fotografias para comparares.';

  @override
  String get evolutionPoseFront => 'Frente';

  @override
  String get evolutionPoseSide => 'Lado';

  @override
  String get evolutionPoseBack => 'Costas';

  @override
  String get evolutionNewMeasurement => 'Nova medição';

  @override
  String get evolutionNewBioimpedance => 'Nova leitura de bioimpedância';

  @override
  String get evolutionNewPhoto => 'Nova fotografia';

  @override
  String get evolutionPhotoFromCamera => 'Câmara';

  @override
  String get evolutionPhotoFromGallery => 'Galeria';

  @override
  String get evolutionPhotoEmptyPreview =>
      'Escolhe uma fotografia para continuares.';

  @override
  String get evolutionPhotoRequired =>
      'Escolhe uma fotografia antes de guardares.';

  @override
  String get evolutionPhotoPickError =>
      'Não foi possível processar a fotografia. Tenta outra.';

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
  String get measurementFieldAbdomenCm => 'Abdómen (cm)';

  @override
  String get measurementFieldHipCm => 'Anca (cm)';

  @override
  String get measurementFieldArmLCm => 'Braço esq. (cm)';

  @override
  String get measurementFieldArmRCm => 'Braço dir. (cm)';

  @override
  String get measurementFieldThighLCm => 'Coxa esq. (cm)';

  @override
  String get measurementFieldThighRCm => 'Coxa dir. (cm)';

  @override
  String get measurementFieldCalfLCm => 'Gémeo esq. (cm)';

  @override
  String get measurementFieldCalfRCm => 'Gémeo dir. (cm)';

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
  String get chatEmpty => 'Ainda não há mensagens. Diz olá!';

  @override
  String get chatConversationsEmpty => 'Ainda não há conversas.';

  @override
  String get chatStudentNoConversation =>
      'Ainda não há conversas. Fala com o teu professor por aqui.';

  @override
  String get chatStudentStart => 'Falar com o meu professor';

  @override
  String get chatNoMessagesYet => 'Ainda não há mensagens';

  @override
  String get chatImagePreview => '📷 Fotografia';

  @override
  String get chatMessageHint => 'Escreve uma mensagem…';

  @override
  String get chatAttachImage => 'Anexar fotografia';

  @override
  String get chatSend => 'Enviar';

  @override
  String get chatMessageFailed => 'Não enviada.';

  @override
  String get chatMessageRetry => 'Tentar novamente';

  @override
  String get checkinTitle => 'Como correu o treino?';

  @override
  String get checkinSubtitle =>
      'A tua avaliação ajuda o teu professor a ajustar o próximo treino.';

  @override
  String get checkinRatingLabel => 'Nota geral';

  @override
  String get checkinDifficultyLabel => 'Dificuldade';

  @override
  String get checkinPainLabel => 'Sentiste dor?';

  @override
  String get checkinPainNone => 'Nenhuma';

  @override
  String get checkinPainMild => 'Ligeira';

  @override
  String get checkinPainStrong => 'Forte';

  @override
  String get checkinPainWhereLabel => 'Onde?';

  @override
  String get checkinCommentLabel => 'Comentário (opcional)';

  @override
  String get checkinSubmit => 'Enviar avaliação';

  @override
  String get checkinSubmitted => 'Avaliação enviada ao teu professor.';

  @override
  String get checkinQueuedOffline =>
      'Sem ligação — a avaliação será enviada assim que voltares a ter rede.';

  @override
  String get checkinListEmpty => 'Ainda não há avaliações de treino.';

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

  @override
  String get agendaLoadError => 'Não foi possível carregar a tua agenda.';

  @override
  String agendaStreakWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count semanas seguidas a cumprir a meta de treinos',
      one: '1 semana seguida a cumprir a meta de treinos',
    );
    return '$_temp0';
  }

  @override
  String agendaWeekRange(String start, String end) {
    return '$start – $end';
  }

  @override
  String get agendaPreviousWeek => 'Semana anterior';

  @override
  String get agendaNextWeek => 'Semana seguinte';

  @override
  String get agendaExpandMonth => 'Ver mês';

  @override
  String get agendaCollapseMonth => 'Ver semana';

  @override
  String get agendaStateDone => 'Treino feito';

  @override
  String get agendaStatePredicted => 'Treino previsto';

  @override
  String get agendaStateRest => 'Descanso';

  @override
  String agendaSessionTitle(String label) {
    return 'Treino $label';
  }

  @override
  String agendaPredictedTitle(String label) {
    return 'Treino previsto: $label';
  }

  @override
  String get agendaPredictedHint =>
      'Projeção com base no teu rodízio atual — pode mudar conforme fores treinando.';

  @override
  String get agendaRestTitle => 'Dia de descanso';

  @override
  String get agendaRestHint => 'Nenhum treino registado neste dia.';

  @override
  String get consentTitle => 'Antes de continuar';

  @override
  String get consentSubtitle =>
      'Para utilizar o Lyfta precisamos do seu consentimento. Decide sobre cada item e pode mudar de ideias mais tarde, em Conta.';

  @override
  String get consentTermsAccept =>
      'Li e aceito os Termos de Utilização e a Política de Privacidade';

  @override
  String get consentReadTerms => 'Ler os Termos de Utilização';

  @override
  String get consentReadPrivacy => 'Ler a Política de Privacidade';

  @override
  String get consentHealthDataTitle => 'Dados de saúde (obrigatório)';

  @override
  String get consentHealthDataBody =>
      'Autorizo o tratamento dos meus dados de saúde — treinos, cargas, medidas e bioimpedância — para a prescrição e o acompanhamento do meu treino.';

  @override
  String get consentPhotosTitle => 'Fotografias de evolução (opcional)';

  @override
  String get consentPhotosBody =>
      'Autorizo guardar as minhas fotografias de evolução e mostrá-las ao meu treinador. Sem isto a app funciona normalmente, apenas não envia fotografias.';

  @override
  String get consentSubmit => 'Continuar';

  @override
  String get consentRequiredHint =>
      'Aceite os itens obrigatórios para continuar.';

  @override
  String get consentSignOut => 'Terminar sessão';

  @override
  String get legalClose => 'Fechar';

  @override
  String get legalLoadError => 'Não foi possível carregar o documento.';

  @override
  String get accountTooltip => 'Conta';

  @override
  String get accountTitle => 'Conta';

  @override
  String get accountPrivacySection => 'Privacidade';

  @override
  String get accountPhotosTitle => 'Fotografias de evolução';

  @override
  String get accountPhotosSubtitle =>
      'Permite guardar as suas fotografias e mostrá-las ao seu treinador. Ao desligar, o envio de fotografias fica bloqueado e o seu treinador deixa de ver as que já enviou.';

  @override
  String get accountLegalSection => 'Documentos';

  @override
  String get accountSignOut => 'Terminar sessão';

  @override
  String get accountDeleteSection => 'Eliminar conta';

  @override
  String get accountDeleteTitle => 'Eliminar a minha conta';

  @override
  String get accountDeleteSubtitle =>
      'Apaga os seus dados de saúde e as suas fotografias, anonimiza os seus treinos e mensagens e termina o seu acesso. Não é possível desfazer.';

  @override
  String get accountDeleteDialogTitle => 'Eliminar a conta definitivamente?';

  @override
  String get accountDeleteDialogBody =>
      'Serão apagados: medidas, bioimpedância e fotografias de evolução, incluindo os ficheiros. Serão anonimizados: os seus treinos executados e as suas mensagens, que ficam sem o seu nome. O seu acesso terminará e isto não pode ser desfeito.';

  @override
  String get accountDeletePasswordLabel => 'Confirme a sua palavra-passe';

  @override
  String get accountDeleteConfirm => 'Eliminar definitivamente';

  @override
  String get organizationSection => 'Organização';

  @override
  String get organizationNameLabel => 'Nome da organização';

  @override
  String get organizationTimezoneLabel => 'Fuso horário';

  @override
  String get organizationTimezoneHelp =>
      'Define o “hoje” e os horários dos lembretes dos seus alunos.';

  @override
  String get organizationTimezoneSearchHint => 'Pesquisar fuso';

  @override
  String get organizationTimezoneOther => 'Outro fuso…';

  @override
  String get organizationTimezoneOtherLabel =>
      'Nome do fuso (ex.: Europe/Lisbon)';

  @override
  String get organizationSaved => 'Organização atualizada.';

  @override
  String get organizationLoadError => 'Não conseguimos carregar a organização.';

  @override
  String get errorInvalidTimezone =>
      'Esse fuso horário não existe. Escolha um da lista ou use um nome como Europe/Lisbon.';

  @override
  String get errorConsentRequired =>
      'Não autorizou esta utilização dos seus dados. Ajuste em Conta > Privacidade.';

  @override
  String get errorInvitationNotFound =>
      'Este convite já não existe. Atualize a ficha do aluno.';

  @override
  String get errorInvitationAlreadyAccepted =>
      'Este convite já foi aceite — o aluno já tem acesso.';

  @override
  String get errorStudentConsentRequired =>
      'O aluno não autorizou a utilização dos dados de saúde. Só ele pode alterar isto, em Conta > Privacidade.';

  @override
  String get errorTermsVersionMismatch =>
      'Os termos foram atualizados. Reabra a app para ler a nova versão.';

  @override
  String get errorInvalidPassword => 'Palavra-passe incorreta.';

  @override
  String get errorOwnerCannotDelete =>
      'O dono da conta não a pode eliminar aqui. Encerrar o ginásio é outro processo — contacte o suporte.';

  @override
  String get errorErasureFailed =>
      'Não conseguimos concluir a eliminação agora. Tente novamente dentro de instantes.';

  @override
  String errorTooManyRequests(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutos',
      one: '1 minuto',
    );
    return 'Demasiadas tentativas. Aguarde $_temp0 e tente novamente.';
  }

  @override
  String get errorStudentNotFound =>
      'Este aluno não está na sua lista de alunos.';

  @override
  String studentsCoachLabel(String name) {
    return 'Professor: $name';
  }

  @override
  String get studentsChangeCoach => 'Trocar professor';

  @override
  String studentsChangeCoachTitle(String student) {
    return 'Professor de $student';
  }

  @override
  String studentsCoachChanged(String name) {
    return 'Professor alterado para $name.';
  }

  @override
  String get studentsCoachesEmpty => 'Nenhum professor disponível.';

  @override
  String get errorNoCoach =>
      'Ainda não tens um professor responsável. Fala com o teu ginásio.';

  @override
  String get inviteSwitchAccountNotice =>
      'Tens outra conta com sessão iniciada neste dispositivo. Ativar este convite termina essa sessão e entra na conta nova.';

  @override
  String get todayDoneOfflineTitle => 'Treino de hoje concluído';

  @override
  String get todayDoneOfflineBody =>
      'Fica guardado no dispositivo e sincroniza sozinho quando a ligação voltar. O próximo treino aparece a seguir.';

  @override
  String get studentsFilterActive => 'Ativos';

  @override
  String get studentsFilterInactive => 'Inativos';

  @override
  String get studentsFilterInvited => 'Convites pendentes';

  @override
  String get studentsFilterCoachLabel => 'Professor';

  @override
  String get studentsFilterCoachAll => 'Todos os professores';

  @override
  String get studentsEmptyFiltered =>
      'Nenhum aluno encontrado com esses filtros.';

  @override
  String get studentsLoadMoreError => 'Não foi possível carregar mais alunos.';

  @override
  String get studentsColName => 'Aluno';

  @override
  String get studentsColCoach => 'Professor';

  @override
  String get studentsColPlan => 'Plano';

  @override
  String get studentsColLastWorkout => 'Último treino';

  @override
  String get studentsLastWorkoutNever => 'Nunca treinou';

  @override
  String get studentsLastWorkoutToday => 'Hoje';

  @override
  String get studentsLastWorkoutYesterday => 'Ontem';

  @override
  String studentsLastWorkoutDaysAgo(int days) {
    return 'Há $days dias';
  }

  @override
  String get studentsColStatus => 'Estado';

  @override
  String get studentStatusActive => 'Ativo';

  @override
  String get studentStatusInactive => 'Inativo';

  @override
  String get studentStatusInvited => 'Convite pendente';

  @override
  String get studentStatusDisabled => 'Bloqueado';

  @override
  String get studentDetailTitle => 'Aluno';

  @override
  String get studentTabData => 'Dados';

  @override
  String get studentTabWorkout => 'Treino';

  @override
  String get studentTabEvolution => 'Evolução';

  @override
  String get studentTabCheckins => 'Check-ins';

  @override
  String get studentDataSectionRegistry => 'Cadastro';

  @override
  String get studentDataNameLabel => 'Nome';

  @override
  String get studentDataEmailLabel => 'E-mail';

  @override
  String get studentDataSaved => 'Dados guardados.';

  @override
  String get profilePhoneLabel => 'Telefone';

  @override
  String get profileBirthLabel => 'Nascimento';

  @override
  String get profileBirthEmpty => 'Não informado';

  @override
  String get profileBirthClear => 'Limpar data';

  @override
  String get accountProfileSection => 'Os meus dados';

  @override
  String get accountProfileSaved => 'Dados guardados.';

  @override
  String get studentStatusSection => 'Situação';

  @override
  String get studentDeactivate => 'Inativar aluno';

  @override
  String studentDeactivateTitle(String name) {
    return 'Inativar $name?';
  }

  @override
  String get studentDeactivateBody =>
      'O aluno perde o acesso à app e sai da lista padrão. Treinos, medidas e conversas ficam guardados, e podes reativar quando quiseres.';

  @override
  String get studentDeactivateConfirm => 'Inativar';

  @override
  String get studentDeactivated => 'Aluno inativado.';

  @override
  String get studentReactivate => 'Reativar aluno';

  @override
  String studentReactivateTitle(String name) {
    return 'Reativar $name?';
  }

  @override
  String get studentReactivateBody => 'O aluno volta a poder entrar na app.';

  @override
  String get studentReactivateConfirm => 'Reativar';

  @override
  String get studentReactivated => 'Aluno reativado.';

  @override
  String get studentReasonLabel => 'Motivo (opcional)';

  @override
  String get studentInvitePending => 'Convite enviado, ainda não aceito.';

  @override
  String get studentInviteExpired =>
      'O convite expirou. Reenvia para o aluno poder entrar.';

  @override
  String get studentInviteResend => 'Reenviar convite';

  @override
  String get studentInviteResent => 'Convite reenviado.';

  @override
  String get studentCoachSection => 'Professor';

  @override
  String get studentCoachNone => 'Sem professor';

  @override
  String get studentHistorySection => 'Histórico de status';

  @override
  String get studentHistoryEmpty => 'Nenhuma mudança de status.';

  @override
  String studentHistoryEntry(String from, String to) {
    return '$from → $to';
  }

  @override
  String studentHistoryBy(String name) {
    return 'por $name';
  }

  @override
  String get studentWorkoutEmpty => 'Ainda sem planos. Cria o primeiro.';

  @override
  String get errorAlreadyInactive => 'Este aluno já está inativo.';

  @override
  String get errorAlreadyActive => 'Este aluno já está ativo.';

  @override
  String get errorInvalidStatusTransition =>
      'Este aluno ainda não aceitou o convite ou está bloqueado, por isso o estado não pode ser alterado.';

  @override
  String get studentWorkoutDraft => 'Rascunho';

  @override
  String studentWorkoutVersion(int version) {
    return 'v$version';
  }

  @override
  String get studentWorkoutInUse => 'Em uso';

  @override
  String get profileHealthSection => 'Objetivo e saúde';

  @override
  String get profileGoalLabel => 'Objetivo';

  @override
  String get profileUnset => 'Não indicado';

  @override
  String get goalHypertrophy => 'Hipertrofia';

  @override
  String get goalWeightLoss => 'Emagrecimento';

  @override
  String get goalStrength => 'Força';

  @override
  String get goalConditioning => 'Condicionamento';

  @override
  String get goalHealth => 'Saúde e bem-estar';

  @override
  String get goalRehab => 'Reabilitação';

  @override
  String get goalOther => 'Outro';

  @override
  String get profileGoalNotesLabel => 'Detalhes do objetivo';

  @override
  String get profileExperienceLabel => 'Experiência com treino';

  @override
  String get experienceBeginner => 'Iniciante';

  @override
  String get experienceIntermediate => 'Intermédio';

  @override
  String get experienceAdvanced => 'Avançado';

  @override
  String get profileWeeklyTargetLabel => 'Meta semanal de treinos';

  @override
  String get profileWeeklyTargetCoachOnly => 'Definida pelo seu professor.';

  @override
  String profileWeeklyTargetOption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count treinos por semana',
      one: '1 treino por semana',
    );
    return '$_temp0';
  }

  @override
  String get profileMedicalNotesLabel => 'Observações médicas';

  @override
  String get profileMedicalNotesHint => 'Condições, medicamentos, restrições';

  @override
  String get profileCoachNotesLabel => 'Notas privadas do professor';

  @override
  String get profileCoachNotesHint => 'O aluno não vê estas notas.';

  @override
  String get profileHealthSaved => 'Objetivo e saúde guardados.';

  @override
  String get injuriesSection => 'Lesões e restrições';

  @override
  String get injuriesEmpty => 'Nenhuma lesão registada.';

  @override
  String get injuriesAdd => 'Adicionar lesão';

  @override
  String get injuriesResolvedHeader => 'Resolvidas';

  @override
  String get injuryFormTitle => 'Nova lesão';

  @override
  String get injuryRegionLabel => 'Região do corpo';

  @override
  String get injuryDescriptionLabel => 'Descrição';

  @override
  String get injurySinceLabel => 'Desde quando';

  @override
  String get injurySinceEmpty => 'Não indicado';

  @override
  String get injurySinceClear => 'Limpar data';

  @override
  String injurySinceOn(String date) {
    return 'Desde $date';
  }

  @override
  String injuryResolvedOn(String date) {
    return 'Resolvida em $date';
  }

  @override
  String get injuryResolve => 'Marcar como resolvida';

  @override
  String get injuryReopen => 'Reabrir';

  @override
  String get injuryDeleteTitle => 'Remover lesão?';

  @override
  String get injuryDeleteBody => 'O registo será apagado.';

  @override
  String get bodyRegionNeck => 'Pescoço';

  @override
  String get bodyRegionShoulder => 'Ombro';

  @override
  String get bodyRegionElbow => 'Cotovelo';

  @override
  String get bodyRegionWristHand => 'Pulso e mão';

  @override
  String get bodyRegionUpperBack => 'Costas (parte alta)';

  @override
  String get bodyRegionLowerBack => 'Lombar';

  @override
  String get bodyRegionChest => 'Peito';

  @override
  String get bodyRegionHip => 'Anca';

  @override
  String get bodyRegionKnee => 'Joelho';

  @override
  String get bodyRegionAnkleFoot => 'Tornozelo e pé';

  @override
  String get bodyRegionOther => 'Outra';

  @override
  String get myGoalTitle => 'O meu objetivo';

  @override
  String get myGoalIntro =>
      'O teu professor usa isto para montar o teu treino. As observações médicas só tu e ele veem.';

  @override
  String get accountGoalSubtitle => 'Objetivo, experiência e saúde';

  @override
  String get goalPromptTitle => 'Qual é o teu objetivo?';

  @override
  String get goalPromptBody =>
      'Conta ao teu professor o que queres alcançar e se tens alguma lesão. Leva um minuto e podes mudar depois, em Conta.';

  @override
  String get goalPromptNow => 'Preencher agora';

  @override
  String get goalPromptLater => 'Agora não';

  @override
  String get evolutionSummaryGoalUnset => 'Objetivo não indicado';

  @override
  String get evolutionSummaryNoInjuries => 'Sem lesões ativas';

  @override
  String get homeCoachTabTemplates => 'Modelos';

  @override
  String get templatesSearchLabel => 'Pesquisar modelo';

  @override
  String get templatesSearchHint => 'título do modelo';

  @override
  String get templatesFilterActive => 'Ativos';

  @override
  String get templatesFilterArchived => 'Arquivados';

  @override
  String get templatesNew => 'Novo modelo';

  @override
  String get templatesNewTitle => 'Novo modelo';

  @override
  String get templatesTitleLabel => 'Título';

  @override
  String get templatesDescriptionLabel => 'Descrição (opcional)';

  @override
  String get templatesEmpty =>
      'Ainda não há modelos. Monte um treino uma vez e aplique-o a vários alunos.';

  @override
  String get templatesEmptyFiltered => 'Nenhum modelo encontrado.';

  @override
  String get templatesEmptyArchived => 'Nenhum modelo arquivado.';

  @override
  String templatesDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dias',
      one: '1 dia',
    );
    return '$_temp0';
  }

  @override
  String templatesExercises(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercícios',
      one: '1 exercício',
    );
    return '$_temp0';
  }

  @override
  String templatesAssignedTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'aplicado a $count alunos',
      one: 'aplicado a 1 aluno',
    );
    return '$_temp0';
  }

  @override
  String get templatesNotAssigned => 'ainda não aplicado';

  @override
  String get templatesUnpublishedChanges => 'alterações não publicadas';

  @override
  String get templatesMenuEdit => 'Editar';

  @override
  String get templatesMenuAssign => 'Aplicar a alunos';

  @override
  String get templatesMenuRecipients => 'Quem recebeu';

  @override
  String get templatesMenuArchive => 'Arquivar';

  @override
  String get templatesMenuUnarchive => 'Desarquivar';

  @override
  String get templatesArchivedToast => 'Modelo arquivado.';

  @override
  String get templatesUnarchivedToast => 'Modelo desarquivado.';

  @override
  String get assignTitle => 'Aplicar a alunos';

  @override
  String assignTemplateName(String title) {
    return 'Modelo: $title';
  }

  @override
  String assignSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alunos selecionados',
      one: '1 aluno selecionado',
      zero: 'Nenhum aluno selecionado',
    );
    return '$_temp0';
  }

  @override
  String assignLimitReached(int max) {
    return 'Limite de $max alunos por vez atingido.';
  }

  @override
  String get assignPublishNow => 'Publicar já';

  @override
  String get assignPublishNowHint =>
      'O treino entra já na rotação do aluno. Desligado, cada aluno recebe um rascunho para ajustar antes.';

  @override
  String get assignSubmit => 'Aplicar';

  @override
  String get batchResultTitle => 'Resultado';

  @override
  String batchResultSummary(int ok, int total) {
    return '$ok de $total com sucesso.';
  }

  @override
  String get batchItemOk => 'Plano criado';

  @override
  String batchItemReapplied(int version) {
    return 'Versão $version publicada';
  }

  @override
  String get batchBackToSelection => 'Tentar de novo os que falharam';

  @override
  String get batchDone => 'Concluir';

  @override
  String get recipientsTitle => 'Quem recebeu';

  @override
  String get recipientsEmpty =>
      'Este modelo ainda não foi aplicado a nenhum aluno.';

  @override
  String recipientsCurrentVersion(int version) {
    return 'versão atual v$version';
  }

  @override
  String get recipientsUpToDate => 'Na versão atual';

  @override
  String recipientsOutdated(int version) {
    return 'Na v$version do modelo';
  }

  @override
  String get recipientsEdited => 'Editado depois de aplicado';

  @override
  String get recipientsArchived => 'Plano arquivado';

  @override
  String get recipientsSelectOutdated => 'Selecionar desatualizados';

  @override
  String get recipientsSubmit => 'Reaplicar';

  @override
  String get recipientsConfirmTitle => 'Reaplicar o modelo?';

  @override
  String recipientsConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alunos será substituído',
      one: '1 aluno será substituído',
    );
    return 'O treino de $_temp0 pela versão atual do modelo e será publicada uma versão nova. Os ajustes individuais feitos nesses planos serão perdidos.';
  }

  @override
  String recipientsConfirmEdited(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count deles foram editados depois de aplicados.',
      one: '1 deles foi editado depois de aplicado.',
    );
    return '$_temp0';
  }

  @override
  String get applyModelTitle => 'Aplicar modelo';

  @override
  String get applyModelEmpty =>
      'Nenhum modelo publicado. Publique um no separador Modelos.';

  @override
  String get applyModelApplied => 'Modelo aplicado e em uso.';

  @override
  String get applyModelAppliedDraft => 'Modelo aplicado como rascunho.';

  @override
  String get planApplyTemplate => 'Aplicar modelo';

  @override
  String get planActivate => 'Ativar';

  @override
  String get planActivateTitle => 'Ativar este plano?';

  @override
  String get planActivateBody =>
      'O aluno passa a treinar por este plano e o plano em uso é arquivado. A rotação recomeça no primeiro dia.';

  @override
  String get planActivated => 'Plano ativado.';

  @override
  String get planDuplicate => 'Duplicar';

  @override
  String get planDuplicated => 'Cópia criada em rascunho.';

  @override
  String get planArchive => 'Arquivar';

  @override
  String get planArchiveTitle => 'Arquivar este plano?';

  @override
  String get planArchiveBody =>
      'O plano fica só de leitura. O histórico de treinos continua nos gráficos e pode ser ativado de novo mais tarde.';

  @override
  String get planArchived => 'Plano arquivado.';

  @override
  String get planView => 'Ver';

  @override
  String get planEdit => 'Editar';

  @override
  String get studentWorkoutArchived => 'Arquivado';

  @override
  String get studentWorkoutFromTemplate => 'De modelo';

  @override
  String builderPublishTemplateBody(int version) {
    return 'Publicar congela a versão $version do modelo. Aplicar a alunos copia sempre a última versão publicada; os planos já aplicados não mudam.';
  }

  @override
  String get builderSaveAsTemplate => 'Guardar como modelo';

  @override
  String get builderSaveAsTemplateTitle => 'Guardar como modelo';

  @override
  String get builderSavedAsTemplate =>
      'Modelo criado em rascunho. Reveja e publique para aplicar.';

  @override
  String get builderOpenTemplate => 'Abrir';

  @override
  String get builderReadOnlyPlan =>
      'Plano arquivado: só de leitura. Ative-o para voltar a editar ou duplique para criar uma cópia.';

  @override
  String get builderReadOnlyPlanNeverPublished =>
      'Plano arquivado sem versão publicada: só de leitura. Só se aproveita duplicando.';

  @override
  String get builderReadOnlyTemplate =>
      'Modelo arquivado: só de leitura. Desarquive para voltar a editar.';

  @override
  String get errorPlanArchived =>
      'Este plano está arquivado e não pode ser editado nem publicado. Ative-o ou duplique-o para continuar.';

  @override
  String get errorTemplateArchived =>
      'Este modelo está arquivado. Desarquive-o para editar ou publicar.';

  @override
  String get errorTemplateNotOwned =>
      'Só o autor do modelo ou o dono do ginásio pode alterá-lo.';

  @override
  String get errorTemplateNotPublished =>
      'Publique o modelo antes de o aplicar.';

  @override
  String get errorPlanNotFromTemplate => 'Este plano não veio de um modelo.';

  @override
  String get errorPlanIsActive =>
      'O plano em uso não pode ser arquivado. Ative outro plano antes.';

  @override
  String get errorPlanNotPublished => 'Publique o plano antes de o ativar.';
}
