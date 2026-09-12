// Guard de CI (P4.3, ADR-011 §1): nenhuma chave de tradução pode faltar em
// pt-PT/en em relação ao ARB fonte (pt-BR). Compara também os placeholders
// declarados na metadata `@chave` do template contra o texto de cada
// tradução — um placeholder que sumiu na tradução (ex. `{count}` virou texto
// solto) quebra a interpolação em runtime sem o `flutter analyze` acusar
// nada, porque o gerador de l10n só falha se o placeholder sumir do
// template, não das traduções.
//
// Uso: dart run tool/check_arb_parity.dart (rodar a partir de app/, ou de
// qualquer lugar — o script resolve o próprio diretório a partir de
// Platform.script).
//
// Sem dependência nova: só dart:io/dart:convert, iguais em qualquer SDK do
// Flutter (Mac/Windows/CI) — dispensa duplicar a lógica em .sh/.ps1 como o
// guard de strings hardcoded precisou fazer.
import 'dart:convert';
import 'dart:io';

/// Chave de metadata (`@@locale`, `@algumaChave`) — não é uma chave
/// traduzível, então fica fora da comparação de paridade.
bool _isMetaKey(String key) => key.startsWith('@');

/// Nomes de placeholder declarados em `@chave.placeholders` no template.
Set<String> _declaredPlaceholders(Map<String, dynamic> arb, String key) {
  final meta = arb['@$key'];
  if (meta is! Map<String, dynamic>) return const {};
  final placeholders = meta['placeholders'];
  if (placeholders is! Map<String, dynamic>) return const {};
  return placeholders.keys.toSet();
}

Map<String, dynamic> _loadArb(File file) {
  final content = file.readAsStringSync();
  return jsonDecode(content) as Map<String, dynamic>;
}

void main() {
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final appDir = scriptDir.parent;
  final arbDir = Directory('${appDir.path}/lib/core/l10n/arb');

  const templateName = 'app_pt.arb';
  const localeNames = ['app_pt_PT.arb', 'app_en.arb'];

  final templateFile = File('${arbDir.path}/$templateName');
  if (!templateFile.existsSync()) {
    stderr.writeln('ARB template não encontrado: ${templateFile.path}');
    exitCode = 1;
    return;
  }

  final template = _loadArb(templateFile);
  final templateKeys = template.keys.where((k) => !_isMetaKey(k)).toSet();

  var hasError = false;
  final warnings = <String>[];

  for (final localeName in localeNames) {
    final localeFile = File('${arbDir.path}/$localeName');
    if (!localeFile.existsSync()) {
      stderr.writeln('ARB de tradução não encontrado: ${localeFile.path}');
      hasError = true;
      continue;
    }

    final locale = _loadArb(localeFile);
    final localeKeys = locale.keys.where((k) => !_isMetaKey(k)).toSet();

    final missing = templateKeys.difference(localeKeys).toList()..sort();
    final extra = localeKeys.difference(templateKeys).toList()..sort();

    if (missing.isNotEmpty) {
      hasError = true;
      stderr.writeln('$localeName: ${missing.length} chave(s) faltando:');
      for (final key in missing) {
        stderr.writeln('  - $key');
      }
    }

    if (extra.isNotEmpty) {
      warnings.add(
        '$localeName: ${extra.length} chave(s) sobrando (não existem no '
        'template pt-BR) — ${extra.join(', ')}',
      );
    }

    // Placeholders: só faz sentido comparar chaves presentes nos dois lados.
    for (final key in templateKeys.intersection(localeKeys)) {
      final declared = _declaredPlaceholders(template, key);
      if (declared.isEmpty) continue;

      final value = locale[key];
      if (value is! String) continue;

      final missingPlaceholders = declared
          .where((name) => !value.contains('{$name'))
          .toList()
        ..sort();
      if (missingPlaceholders.isNotEmpty) {
        hasError = true;
        stderr.writeln(
          '$localeName: chave "$key" perdeu o(s) placeholder(s) '
          '${missingPlaceholders.join(', ')} na tradução: $value',
        );
      }
    }
  }

  for (final warning in warnings) {
    stdout.writeln('AVISO: $warning');
  }

  if (hasError) {
    stderr.writeln();
    stderr.writeln(
      'Paridade de ARB falhou (ADR-011 §1). Traduza as chaves faltando em '
      'lib/core/l10n/arb/ antes de prosseguir.',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'OK: paridade de chaves e placeholders entre pt-BR/pt-PT/en '
    '(${templateKeys.length} chaves).',
  );
}
