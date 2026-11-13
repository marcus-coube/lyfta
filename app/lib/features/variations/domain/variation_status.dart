/// Filtro de status do `GET /v1/variations` (ADR-019).
enum VariationStatus {
  active,
  archived,
  all;

  String get code => name;
}
