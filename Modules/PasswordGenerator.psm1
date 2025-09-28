# -------- Слоговые словари --------
$Script:WordParts2 = @(
  "ba","be","bi","bo","bu",
  "da","de","di","do","du",
  "fa","fe","fi","fo","fu",
  "ga","ge","gi","go","gu",
  "ha","he","hi","ho","hu",
  "ka","ke","ki","ko","ku",
  "la","le","li","lo","lu",
  "ma","me","mi","mo","mu",
  "na","ne","ni","no","nu",
  "pa","pe","pi","po","pu",
  "ra","re","ri","ro","ru",
  "sa","se","si","so","su",
  "ta","te","ti","to","tu",
  "va","ve","vi","vo","vu",
  "za","ze","zi","zo","zu"
)

$Script:WordParts3 = @(
  "kra","kre","kri","kro","kru"
)

# -------- Выбор случайного слога --------
function _Get-RandomSyllable {
    # 80% шанс на 2-буквенный, 20% на 3-буквенный
    $roll = Get-Random -Minimum 1 -Maximum 101
    if ($roll -le 80 -or $Script:WordParts3.Count -eq 0) {
        return $Script:WordParts2 | Get-Random
    } else {
        return $Script:WordParts3 | Get-Random
    }
}

# -------- Вспомогательные функции --------
function _Normalize-Specials {
  param([object]$AllowedSpecials)
  if ($AllowedSpecials -is [string]) {
    return ($AllowedSpecials.ToCharArray() | ForEach-Object { $_.ToString() }) | Where-Object { $_ -ne ' ' }
  }
  elseif ($AllowedSpecials -is [array]) {
    return $AllowedSpecials
  }
  else {
    return @('!','@','#','$','%','&','*','+','=')
  }
}

function _BuildPrefix {
  param(
    [int]$TargetLength
  )
  $prefix = ""
  while ($prefix.Length -lt $TargetLength) {
    $partsInWord = Get-Random -Minimum 2 -Maximum 4
    $word = ""
    for ($p=1; $p -le $partsInWord; $p++) {
      $part = _Get-RandomSyllable
      $word += $part
    }
    $word = $word.Substring(0,1).ToUpper() + $word.Substring(1)
    $prefix += $word
  }
  if ($prefix.Length -gt $TargetLength) {
    $prefix = $prefix.Substring(0, $TargetLength)
  }
  return $prefix
}

function _Format-Num {
  param([int]$Value, [int]$Width)
  return ("{0:D$($Width)}" -f [int]$Value)
}

# -------- Генерация пароля --------
function New-PronounceablePassword {
  param(
    [int]$MinLength = 8,
    [int]$MaxLength = 12,
    [object]$AllowedSpecials = "!@#$%^&*_-+=",
    [int]$NumberWidth = 2
  )

  if ($MinLength -gt $MaxLength) { throw "MinLength must be <= MaxLength" }
  [int]$numWidth = [int]$NumberWidth
  if ($numWidth -lt 1) { $numWidth = 2 }

  $specials = _Normalize-Specials $AllowedSpecials
  if (($specials | Measure-Object).Count -eq 0) { $specials = @('!') }

  $targetTotal = Get-Random -Minimum $MinLength -Maximum ($MaxLength + 1)
  $prefixLen   = [math]::Max(1, $targetTotal - $numWidth - 1)

  $prefix = _BuildPrefix -TargetLength $prefixLen
  $maxNum = [math]::Pow(10, $numWidth) - 1
  $r = Get-Random -Minimum 0 -Maximum ($maxNum + 1)
  $rStr = _Format-Num -Value $r -Width $numWidth

  $spec = $specials | Get-Random
  return "$prefix$rStr$spec"
}

function New-PasswordWithSalt {
  param(
    [int]$MinLength = 8,
    [int]$MaxLength = 12,
    [object]$AllowedSpecials = "!@#$%^&*_-+=",
    [bool]$SaltEnabled = $false,
    [string[]]$AllowedOps = @('p','m'),
    [int]$MaxSalt = 30,
    [int]$NumberWidth = 2
  )

  $real = New-PronounceablePassword -MinLength $MinLength -MaxLength $MaxLength -AllowedSpecials $AllowedSpecials -NumberWidth $NumberWidth
  [int]$numWidth = [int]$NumberWidth
  $prefix = $real.Substring(0, $real.Length - $numWidth - 1)
  $spec   = $real[-1]
  $Rstr   = $real.Substring($real.Length - $numWidth - 1, $numWidth)
  [int]$R = [int]$Rstr

  if (-not $SaltEnabled) {
    return @{
      Real     = $real
      Obscured = $real
      SaltSpec = $null
      Op       = $null
      Salt     = $null
    }
  }

  $ops = @()
  foreach ($o in $AllowedOps) { if ($o -in @('p','m')) { $ops += $o } }
  if ($ops.Count -eq 0) { $ops = @('p') }

  $maxNum = [math]::Pow(10, $numWidth) - 1
  $valid = $false
  do {
    $op = $ops | Get-Random
    if ($op -eq 'p') {
      $maxS = [math]::Min($R, $MaxSalt)
      if ($maxS -ge 1) {
        $S = Get-Random -Minimum 1 -Maximum ($maxS + 1)
        $O = $R - $S
        $valid = $true
      }
    } else {
      $maxS = [math]::Min($MaxSalt, [int]($maxNum - $R))
      if ($maxS -ge 1) {
        $S = Get-Random -Minimum 1 -Maximum ($maxS + 1)
        $O = $R + $S
        $valid = $true
      }
    }
  } while (-not $valid)

  $Ostr = _Format-Num -Value $O -Width $numWidth
  $RstrF = _Format-Num -Value $R -Width $numWidth

  $obscured = "$prefix$Ostr$spec"
  $saltSpec = "($op$S)"

  return @{
    Real     = "$prefix$RstrF$spec"
    Obscured = $obscured
    SaltSpec = $saltSpec
    Op       = $op
    Salt     = $S
  }
}

Export-ModuleMember -Function New-PronounceablePassword, New-PasswordWithSalt
