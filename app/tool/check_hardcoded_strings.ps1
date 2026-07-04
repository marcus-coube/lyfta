# Guard de CI (ADR-011 §5): nenhuma string literal de UI fora do design
# system. Equivalente Windows de check_hardcoded_strings.sh — procura
# `Text('...')` / `Text("...")` literal em lib/, excluindo
# core/design_system/ e os arquivos gerados de l10n.
#
# Uso: powershell -File tool/check_hardcoded_strings.ps1

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$appDir = Split-Path -Parent $scriptDir
$libDir = Join-Path $appDir "lib"

$pattern = "Text\((['""])"

$matches = Get-ChildItem -Path $libDir -Recurse -Filter "*.dart" |
    Where-Object {
        $_.FullName -notmatch [regex]::Escape([IO.Path]::Combine("core", "design_system")) -and
        $_.FullName -notmatch [regex]::Escape([IO.Path]::Combine("core", "l10n", "gen"))
    } |
    Select-String -Pattern $pattern

if ($matches) {
    Write-Host "Strings literais de UI encontradas fora do design system (ADR-011):"
    $matches | ForEach-Object { Write-Host "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
    Write-Host ""
    Write-Host "Mova a string para os ARBs em lib/core/l10n/arb/ e use AppLocalizations.of(context)."
    exit 1
}

Write-Host "OK: nenhuma string literal de UI fora do design system."
exit 0
