import 'package:dio/dio.dart';
import 'package:duo/core/http/api_exception.dart';
import 'package:duo/features/variations/data/variation_repository.dart';
import 'package:duo/features/variations/domain/variation_status.dart';
import 'package:duo/shared/domain/plan.dart';

/// Repositório em memória: nome repetido entre as ativas = 409.
class FakeVariations extends VariationRepository {
  FakeVariations([List<SetVariation>? seed])
      : items = [...?seed],
        super(Dio());

  final List<SetVariation> items;
  var _next = 1;

  @override
  Future<List<SetVariation>> list({
    String query = '',
    VariationStatus status = VariationStatus.active,
  }) async =>
      items
          .where((v) => v.name.toLowerCase().contains(query.toLowerCase()))
          .where(
            (v) => switch (status) {
              VariationStatus.active => !v.archived,
              VariationStatus.archived => v.archived,
              VariationStatus.all => true,
            },
          )
          .toList();

  @override
  Future<SetVariation> create({
    required String name,
    required String description,
  }) async {
    if (items.any((v) => !v.archived && v.name.toLowerCase() == name.toLowerCase())) {
      throw const ApiException(code: 'variation_name_taken', statusCode: 409);
    }
    final v = SetVariation(id: 'v${_next++}', name: name, description: description);
    items.add(v);
    return v;
  }

  @override
  Future<SetVariation> update(
    String id, {
    required String name,
    required String description,
  }) async {
    final i = items.indexWhere((v) => v.id == id);
    items[i] = SetVariation(
      id: id,
      name: name,
      description: description,
      archived: items[i].archived,
    );
    return items[i];
  }

  @override
  Future<SetVariation> setArchived(String id, {required bool archived}) async {
    final i = items.indexWhere((v) => v.id == id);
    final old = items[i];
    items[i] = SetVariation(
      id: id,
      name: old.name,
      description: old.description,
      archived: archived,
    );
    return items[i];
  }
}
