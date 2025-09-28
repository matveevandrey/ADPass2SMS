function Initialize-Logger {
    param(
        [string]$LogDir,
        [bool]$DebugModeMain,
        [bool]$DebugModeSms
    )

    if (-not (Test-Path $LogDir)) { 
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null 
    }
    $DateTag = (Get-Date).ToString("yyyyMMdd-HHmmss")

    $global:LogTxt = Join-Path $LogDir "rotate-$DateTag.log"
    $global:LogCsv = Join-Path $LogDir "rotate-$DateTag.csv"

    $global:DebugModeMain = $DebugModeMain
    $global:DebugModeSms  = $DebugModeSms

    "User,DN,Phone,SMS_Id,SMS_Status,AD_Changed,Error" | Out-File -FilePath $LogCsv -Encoding UTF8
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')] [string]$Level = 'INFO',
        [ValidateSet('Main','Sms')] [string]$Channel = 'Main',
        [switch]$Sensitive
    )

    # проверка включённости отладки
    if ($Level -eq 'DEBUG') {
        if ($Channel -eq 'Main' -and -not $global:DebugModeMain) { return }
        if ($Channel -eq 'Sms'  -and -not $global:DebugModeSms)  { return }
    }

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $safeMessage = if ($Sensitive) { $Message -replace '(: ).+', '$1***' } else { $Message }

    $lineConsole = "[$ts] [$Level][$Channel] $Message"
    $lineFile    = "[$ts] [$Level][$Channel] $safeMessage"

    Write-Host $lineConsole
    Add-Content -Path $global:LogTxt -Value $lineFile
}
