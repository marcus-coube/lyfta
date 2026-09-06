import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/evolution_repository.dart';
import '../domain/evolution_scope.dart';
import '../domain/progress_photo.dart';

class PhotoListState {
  const PhotoListState({this.items = const [], this.hasMore = false});

  final List<ProgressPhoto> items;
  final bool hasMore;
}

/// Lista paginada de fotos de evolução — alimenta a grade por data/pose e o
/// comparador antes/depois (P2.4 §3), nos dois escopos (P2.5).
class PhotosController
    extends AutoDisposeFamilyAsyncNotifier<PhotoListState, EvolutionScope> {
  String? _cursor;

  @override
  Future<PhotoListState> build(EvolutionScope scope) async {
    final page = await ref
        .watch(evolutionRepositoryProvider)
        .listPhotos(scope, limit: 60);
    _cursor = page.nextCursor;
    return PhotoListState(items: page.items, hasMore: page.hasMore);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;

    final page = await ref
        .read(evolutionRepositoryProvider)
        .listPhotos(arg, cursor: _cursor, limit: 60);
    _cursor = page.nextCursor;
    state = AsyncData(
      PhotoListState(
        items: [...current.items, ...page.items],
        hasMore: page.hasMore,
      ),
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> delete(String id) async {
    await ref.read(evolutionRepositoryProvider).deletePhoto(arg, id);
    ref.invalidateSelf();
    await future;
  }

  /// As três etapas do upload de uma foto nova (presign → PUT no storage →
  /// cadastro, P2.3) seguidas de recarregar a lista — a tela de captura só
  /// entrega bytes já comprimidos e os metadados. No escopo do coach o
  /// presign devolve a pasta do aluno da ficha, não a de quem está logado.
  Future<void> upload({
    required Uint8List bytes,
    required String contentType,
    required DateTime takenAt,
    required Pose pose,
    String notes = '',
  }) async {
    final repository = ref.read(evolutionRepositoryProvider);
    final target = await repository.presignPhoto(
      arg,
      contentType: contentType,
      sizeBytes: bytes.length,
    );
    await repository.uploadPhotoBytes(target, bytes);
    await repository.createPhoto(
      arg,
      takenAt: takenAt,
      pose: pose,
      mediaKey: target.key,
      notes: notes,
    );
    ref.invalidateSelf();
    await future;
  }
}

final photosProvider = AsyncNotifierProvider.autoDispose
    .family<PhotosController, PhotoListState, EvolutionScope>(
  PhotosController.new,
);
