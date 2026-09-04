import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/progress_photo.dart';

/// Rótulo traduzido da pose da foto de evolução (`front|side|back`,
/// ADR-011 §5 — código estável, o app traduz). Fica na feature, não em
/// `shared/`: [Pose] é específico da tela Evolução (P2.4/P2.5), diferente
/// de `Plan`/`Exercise`, que atravessam features (builder × workout) e por
/// isso moram em `shared/domain`.
String poseLabel(AppLocalizations l10n, Pose pose) => switch (pose) {
      Pose.front => l10n.evolutionPoseFront,
      Pose.side => l10n.evolutionPoseSide,
      Pose.back => l10n.evolutionPoseBack,
    };
