import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import '../domain/session_media.dart';

/// Escolhe (câmera/galeria) e prepara a mídia do treino (P12.2 §3). Fica atrás
/// de uma interface para o widget test não tocar em câmera nem em plugin.
abstract class MediaPreparer {
  /// `null` = o aluno desistiu do seletor. Erro de leitura/compressão lança.
  Future<PreparedMedia?> pick({
    required bool video,
    required ImageSource source,
  });
}

final mediaPreparerProvider = Provider<MediaPreparer>((ref) {
  return DeviceMediaPreparer();
});

/// Vídeo: `pickVideo` com 60 s e, no celular, compressão para MP4
/// (`video_compress`, D4). Foto: a mesma compressão JPEG das fotos de
/// progresso. Web: sem compressão de vídeo — só a validação de tamanho que o
/// chamador faz.
class DeviceMediaPreparer implements MediaPreparer {
  static const _maxDuration = Duration(seconds: 60);

  @override
  Future<PreparedMedia?> pick({
    required bool video,
    required ImageSource source,
  }) {
    return video ? _pickVideo(source) : _pickPhoto(source);
  }

  Future<PreparedMedia?> _pickPhoto(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 92);
    if (file == null) return null;
    final raw = await file.readAsBytes();
    final compressed = await FlutterImageCompress.compressWithList(
      raw,
      minWidth: 1280,
      minHeight: 1280,
      quality: 82,
      format: CompressFormat.jpeg,
    );
    return PreparedMedia(
      bytes: compressed,
      contentType: 'image/jpeg',
      isVideo: false,
      name: file.name,
    );
  }

  Future<PreparedMedia?> _pickVideo(ImageSource source) async {
    final file = await ImagePicker().pickVideo(
      source: source,
      maxDuration: _maxDuration,
    );
    if (file == null) return null;

    if (kIsWeb) {
      return PreparedMedia(
        bytes: await file.readAsBytes(),
        contentType: videoContentTypeFor(file.name, mime: file.mimeType),
        isVideo: true,
        name: file.name,
      );
    }

    Uint8List bytes;
    var contentType = 'video/mp4';
    final info = await VideoCompress.compressVideo(
      file.path,
      quality: VideoQuality.MediumQuality,
      deleteOrigin: false,
      includeAudio: true,
    );
    final compressed = info?.file;
    if (compressed != null) {
      bytes = await compressed.readAsBytes();
    } else {
      // Sem compressão (plugin falhou): segue com o original e o tamanho
      // decide — se passar de 20 MB o chamador recusa com a mensagem.
      bytes = await File(file.path).readAsBytes();
      contentType = videoContentTypeFor(file.name, mime: file.mimeType);
    }
    await VideoCompress.deleteAllCache().catchError((_) => null);
    return PreparedMedia(
      bytes: bytes,
      contentType: contentType,
      isVideo: true,
      name: file.name,
    );
  }
}

/// Tipo aceito pelo servidor a partir do nome/MIME do arquivo escolhido.
String videoContentTypeFor(String name, {String? mime}) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.mov') || mime == 'video/quicktime') {
    return 'video/quicktime';
  }
  if (lower.endsWith('.webm') || mime == 'video/webm') return 'video/webm';
  return 'video/mp4';
}
