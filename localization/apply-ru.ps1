param(
  [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
  [string]$Mapping = (Join-Path $PSScriptRoot 'mapping.json')
)
# Применяет карту русской локализации к репозиторию dsh-outlook.
# Скрипт идемпотентен: если строка уже переведена — пропускает, если не найдена — падает,
# ничего не записав (защита от порчи файлов после обновления upstream).
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Mapping)) { throw "mapping not found: $Mapping" }
$map = Get-Content -LiteralPath $Mapping -Raw -Encoding UTF8 | ConvertFrom-Json

$plan = @()
$problems = @()

foreach ($f in $map.files) {
  $path = Join-Path $RepoRoot ($f.file -replace '/', '\')
  if (-not (Test-Path -LiteralPath $path)) { throw "missing file: $path" }

  $text = [System.IO.File]::ReadAllText($path)
  $applied = 0
  $already = 0

  foreach ($pair in $f.pairs) {
    $from = [string]$pair[0]
    $to = [string]$pair[1]
    $hit = $false

    if ($text.Contains($from)) {
      $text = $text.Replace($from, $to)
      $applied++
      $hit = $true
    }
    elseif ($text.Contains($to)) {
      $already++
      $hit = $true
    }
    else {
      # Разные окончания строк: JS в репозитории с LF, .ps1 — с CRLF.
      $fromCrlf = $from.Replace("`n", "`r`n")
      $toCrlf = $to.Replace("`n", "`r`n")
      if ($text.Contains($fromCrlf)) {
        $text = $text.Replace($fromCrlf, $toCrlf)
        $applied++
        $hit = $true
      }
      elseif ($text.Contains($toCrlf)) {
        $already++
        $hit = $true
      }
    }

    if (-not $hit) {
      $short = $from.Substring(0, [Math]::Min(70, $from.Length))
      $problems += "$($f.file): не найдено -> $short"
    }
  }

  $enc = if ($f.encoding -eq 'utf8bom') { New-Object System.Text.UTF8Encoding($true) } else { New-Object System.Text.UTF8Encoding($false) }
  $plan += [pscustomobject]@{ Path = $path; Text = $text; Encoding = $enc; Applied = $applied; Already = $already; File = $f.file }
}

if ($problems.Count -gt 0) {
  'ЗАМЕНЫ НЕ ПРИМЕНЕНЫ, файлы не тронуты. Не найдено:'
  $problems | ForEach-Object { '  - ' + $_ }
  exit 2
}

foreach ($p in $plan) {
  if ($p.Applied -gt 0) {
    [System.IO.File]::WriteAllText($p.Path, $p.Text, $p.Encoding)
    'OK  {0,-12} замен: {1,3}  уже было: {2}' -f $p.File, $p.Applied, $p.Already
  }
  else {
    '--  {0,-12} уже переведено (совпадений перевода: {1})' -f $p.File, $p.Already
  }
}
