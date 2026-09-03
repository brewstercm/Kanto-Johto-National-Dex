param(
  [Parameter(Mandatory = $true)][string]$SpeciesCsv,
  [Parameter(Mandatory = $true)][string]$EvolutionCsv,
  [Parameter(Mandatory = $true)][string]$ItemsCsv,
  [Parameter(Mandatory = $true)][string]$NationalLua,
  [Parameter(Mandatory = $true)][string]$OutputLua,
  [Parameter(Mandatory = $true)][string]$OutputDisplayDir,
  [Parameter(Mandatory = $true)][string]$OutputQa
)

$ErrorActionPreference = 'Stop'
$cutoff = 1025

function SpeciesId([string]$identifier) {
  return $identifier.ToUpperInvariant().Replace('-', '_').Replace("'", '')
}

$species = @(Import-Csv -LiteralPath $SpeciesCsv | Where-Object { [int]$_.id -le $cutoff })
$byDex = @{}
$idForDex = @{}
foreach ($row in $species) {
  $dex = [int]$row.id
  $byDex[$dex] = $row
  $idForDex[$dex] = SpeciesId $row.identifier
}

# The payload is authoritative for engine spellings (MR_MIME, MIME_JR,
# JANGMO_O, and so on). Pull those names from it instead of guessing.
$national = Get-Content -Raw -LiteralPath $NationalLua
$recordPattern = '(?ms)^    ([A-Z0-9_]+) = \{\r?\n      id = "([^"]+)",\r?\n      name = [^\r\n]+\r?\n      dex = (\d+),'
foreach ($match in [regex]::Matches($national, $recordPattern)) {
  $idForDex[[int]$match.Groups[3].Value] = $match.Groups[2].Value
}

$items = @{}
foreach ($row in (Import-Csv -LiteralPath $ItemsCsv)) {
  $items[[int]$row.id] = $row.identifier
}

$itemMap = @{
  'fire-stone' = 'FIRE_STONE'
  'water-stone' = 'WATER_STONE'
  'thunder-stone' = 'THUNDER_STONE'
  'leaf-stone' = 'LEAF_STONE'
  'moon-stone' = 'MOON_STONE'
}
$itemApprox = @{
  'sun-stone' = 'LEAF_STONE'
  'shiny-stone' = 'MOON_STONE'
  'dusk-stone' = 'MOON_STONE'
  'dawn-stone' = 'MOON_STONE'
  'ice-stone' = 'WATER_STONE'
  'oval-stone' = 'MOON_STONE'
}

$evolutionRows = @(Import-Csv -LiteralPath $EvolutionCsv | Where-Object {
  $target = [int]$_.evolved_species_id
  $target -le $cutoff -and $byDex.ContainsKey($target)
})

# PokeAPI contains parallel rows for regional forms. Pick one condition per
# target, preferring the base-form row, then the declared default, then the
# newest version group. The species-level graph still retains every distinct
# target, including branches.
$chosen = @()
foreach ($group in ($evolutionRows | Group-Object evolved_species_id)) {
  $targetDex = [int]$group.Name
  $sourceDex = [int]$byDex[$targetDex].evolves_from_species_id
  if ($sourceDex -lt 1 -or -not $idForDex.ContainsKey($sourceDex)) { continue }
  $ranked = @($group.Group | Sort-Object `
    @{ Expression = {
      if ([string]::IsNullOrWhiteSpace($_.base_form_id)) { 0 }
      elseif ([int]$_.base_form_id -eq $sourceDex) { 1 }
      else { 2 }
    } },
    @{ Expression = { if ($_.is_default -eq '1') { 0 } else { 1 } } },
    @{ Expression = { [int]$_.version_group_id }; Descending = $true })
  $chosen += [pscustomobject]@{
    SourceDex = $sourceDex
    TargetDex = $targetDex
    Row = $ranked[0]
  }
}

$stats = [ordered]@{
  source = 'PokeAPI official CSV tables'
  source_species = 0
  evolution_edges = 0
  display_records = 0
  canonical_level = 0
  canonical_stone = 0
  approximated_stone = 0
  approximated_level = 0
  trade_to_level = 0
}
$records = @{}

foreach ($entry in ($chosen | Sort-Object SourceDex,TargetDex)) {
  $sourceDex = $entry.SourceDex
  $targetDex = $entry.TargetDex
  $row = $entry.Row
  $method = $null
  $level = $null
  $item = $null

  switch ([int]$row.evolution_trigger_id) {
    1 {
      $method = 'LEVEL'
      if (-not [string]::IsNullOrWhiteSpace($row.minimum_level)) {
        $level = [int]$row.minimum_level
        $stats.canonical_level++
      } elseif (-not [string]::IsNullOrWhiteSpace($row.minimum_happiness) -or
                -not [string]::IsNullOrWhiteSpace($row.minimum_beauty) -or
                -not [string]::IsNullOrWhiteSpace($row.minimum_affection)) {
        $level = 30
        $stats.approximated_level++
      } else {
        $level = 32
        $stats.approximated_level++
      }
    }
    2 {
      $method = 'LEVEL'
      $level = if (-not [string]::IsNullOrWhiteSpace($row.held_item_id) -or
                    -not [string]::IsNullOrWhiteSpace($row.trade_species_id)) { 42 } else { 37 }
      $stats.trade_to_level++
    }
    3 {
      $slug = if ([string]::IsNullOrWhiteSpace($row.trigger_item_id)) { '' }
              else { $items[[int]$row.trigger_item_id] }
      if ($itemMap.ContainsKey($slug)) {
        $method = 'ITEM'; $item = $itemMap[$slug]; $stats.canonical_stone++
      } elseif ($itemApprox.ContainsKey($slug)) {
        $method = 'ITEM'; $item = $itemApprox[$slug]; $stats.approximated_stone++
      } else {
        $method = 'LEVEL'; $level = 36; $stats.approximated_level++
      }
    }
    default {
      $method = 'LEVEL'
      $level = if ([int]$row.evolution_trigger_id -in 6,7) { 42 } else { 32 }
      $stats.approximated_level++
    }
  }

  if (-not $records.ContainsKey($sourceDex)) { $records[$sourceDex] = @() }
  $records[$sourceDex] += [pscustomobject]@{
    method = $method
    level = $level
    item = $item
    targetDex = $targetDex
  }
  $stats.evolution_edges++
}

$stats.source_species = $records.Count
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('-- Generated from the official PokeAPI CSV evolution tables.')
$lines.Add('-- Modern-only conditions are reduced to Gen1Recomp-compatible level/stone methods.')
$lines.Add('return {')
$lines.Add('  records = {')
foreach ($sourceDex in @($records.Keys | Sort-Object)) {
  $sourceId = $idForDex[$sourceDex]
  $lines.Add(('    {0} = {{ dex = {1}, evolutions = {{' -f $sourceId,$sourceDex))
  foreach ($evo in $records[$sourceDex]) {
    $targetId = $idForDex[$evo.targetDex]
    $fields = @('method = "' + $evo.method + '"')
    if ($null -ne $evo.level) { $fields += 'level = ' + $evo.level }
    if ($null -ne $evo.item) { $fields += 'item = "' + $evo.item + '"' }
    $fields += 'species = "' + $targetId + '"'
    $fields += 'targetDex = ' + $evo.targetDex
    $lines.Add('      { ' + ($fields -join ', ') + ' },')
  }
  $lines.Add('    } },')
}
$lines.Add('  },')
$lines.Add('}')

$parent = Split-Path -Parent $OutputLua
New-Item -ItemType Directory -Force -Path $parent | Out-Null
[IO.File]::WriteAllLines($OutputLua, $lines, [Text.UTF8Encoding]::new($false))

# Build the lazy API/Dex-page payload from the same effective gameplay rows.
# It intentionally describes the compatible approximation the player can
# perform in this mod, rather than displaying an unavailable modern trigger.
$children = @{}
$parentEdge = @{}
$nodes = [System.Collections.Generic.HashSet[int]]::new()
foreach ($sourceDex in $records.Keys) {
  [void]$nodes.Add([int]$sourceDex)
  $children[[int]$sourceDex] = @()
  foreach ($evo in $records[$sourceDex]) {
    $edge = [pscustomobject]@{
      sourceDex = [int]$sourceDex
      targetDex = [int]$evo.targetDex
      method = $evo.method
      level = $evo.level
      item = $evo.item
    }
    $children[[int]$sourceDex] += $edge
    if (-not $parentEdge.ContainsKey([int]$evo.targetDex)) {
      $parentEdge[[int]$evo.targetDex] = $edge
    }
    [void]$nodes.Add([int]$evo.targetDex)
  }
}

function RootDex([int]$dex) {
  $seen = @{}
  while ($parentEdge.ContainsKey($dex) -and -not $seen.ContainsKey($dex)) {
    $seen[$dex] = $true
    $dex = [int]$parentEdge[$dex].sourceDex
  }
  return $dex
}

function Stage([int]$dex) {
  $stage = 1
  $seen = @{}
  while ($parentEdge.ContainsKey($dex) -and -not $seen.ContainsKey($dex)) {
    $seen[$dex] = $true
    $dex = [int]$parentEdge[$dex].sourceDex
    $stage++
  }
  return $stage
}

function EdgeLua($edge, [int]$shownDex) {
  $shownId = $idForDex[$shownDex]
  if ($edge.method -eq 'ITEM') {
    $slug = $edge.item.ToLowerInvariant().Replace('_', '-')
    $text = 'Use ' + $edge.item.Replace('_', ' ')
    $method = '{ text = "' + $text + '", trigger = "use-item", versionGroup = "gen1recomp", isDefault = true, item = "' + $slug + '" }'
  } else {
    $text = 'Level ' + $edge.level
    $method = '{ text = "' + $text + '", trigger = "level-up", versionGroup = "gen1recomp", isDefault = true, level = ' + $edge.level + ' }'
  }
  return '{ id = "' + $shownId + '", dex = ' + $shownDex + ', name = "' + $shownId + '", text = "' + $text + '", methods = { ' + $method + ' } }'
}

$families = @{}
foreach ($dex in $nodes) {
  $rootDex = RootDex $dex
  if (-not $families.ContainsKey($rootDex)) { $families[$rootDex] = @() }
  $families[$rootDex] += [int]$dex
}

New-Item -ItemType Directory -Force -Path $OutputDisplayDir | Out-Null
$indexLines = [System.Collections.Generic.List[string]]::new()
$indexLines.Add('return {')
$shardLines = [System.Collections.Generic.List[string]]::new()
$shardLines.Add('return {')
foreach ($dex in @($nodes | Sort-Object)) {
  $id = $idForDex[$dex]
  $rootDex = RootDex $dex
  $chainDex = @($families[$rootDex] | Sort-Object @{ Expression = { Stage $_ } }, @{ Expression = { $_ } })
  $chainIds = @($chainDex | ForEach-Object { '"' + $idForDex[$_] + '"' }) -join ', '
  $fromLua = 'nil'
  if ($parentEdge.ContainsKey($dex)) {
    $edge = $parentEdge[$dex]
    $fromLua = EdgeLua $edge ([int]$edge.sourceDex)
  }
  $into = @()
  if ($children.ContainsKey($dex)) {
    foreach ($edge in @($children[$dex])) {
      $into += EdgeLua $edge ([int]$edge.targetDex)
    }
  }
  $intoLua = if ($into.Count) { '{ ' + ($into -join ', ') + ' }' } else { '{}' }
  $shardLines.Add('  ' + $id + ' = {')
  $shardLines.Add('    id = "' + $id + '", dex = ' + $dex + ', name = "' + $id + '",')
  $shardLines.Add('    chainId = ' + $rootDex + ', chain = { ' + $chainIds + ' }, stage = ' + (Stage $dex) + ',')
  $shardLines.Add('    evolvesFrom = ' + $fromLua + ',')
  $shardLines.Add('    evolvesInto = ' + $intoLua + ',')
  $shardLines.Add('  },')
  $indexLines.Add('  ' + $id + ' = 1,')
}
$indexLines.Add('}')
$shardLines.Add('}')
[IO.File]::WriteAllLines((Join-Path $OutputDisplayDir 'index.lua'), $indexLines, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllLines((Join-Path $OutputDisplayDir '001.lua'), $shardLines, [Text.UTF8Encoding]::new($false))
$stats.display_records = $nodes.Count
$stats | ConvertTo-Json | Set-Content -LiteralPath $OutputQa -Encoding utf8
