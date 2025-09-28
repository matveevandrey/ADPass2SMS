<#
.SYNOPSIS
  ADPass2SMS — основной исполняемый скрипт
.DESCRIPTION
  Загружает конфиг, модули, получает пользователей, генерирует пароль
  (с опциональной солью), отправляет SMS (обфусцированную версию + спеки)
  и меняет реальный пароль в AD только при успешной приёмке шлюзом.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath
)

# ---------------------------
# Root и относительные пути
# ---------------------------
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $ScriptRoot "config.psd1"
}

if (-not (Test-Path $ConfigPath)) {
    throw "Config not found: $ConfigPath"
}
$config = Import-PowerShellDataFile $ConfigPath

$ModulesPath = Join-Path $ScriptRoot "Modules"
$LogsPath    = Join-Path $ScriptRoot $config.Runtime.LogDir

# ---------------------------
# Подключаем модули
# ---------------------------
Import-Module (Join-Path $ModulesPath "PasswordGenerator.psm1") -Force
Import-Module (Join-Path $ModulesPath "Logging.psm1") -Force
Import-Module (Join-Path $ModulesPath "ADUsers.psm1") -Force
Import-Module (Join-Path $ModulesPath "SmsRu.psm1") -Force
Import-Module ActiveDirectory -ErrorAction Stop

# ---------------------------
# Инициализация логирования
# ---------------------------
Initialize-Logger -LogDir $LogsPath -DebugModeMain $config.Runtime.DebugModeMain -DebugModeSms $config.Runtime.DebugModeSms

Write-Log "=== ADPass2SMS run started ===" "INFO" -Channel Main

# ---------------------------
# Получаем пользователей
# ---------------------------
$users = Get-ADTargetUsers -ADConfig $config.AD
Write-Log "Users to process: $($users.Count)" "INFO" -Channel Main

foreach ($u in $users) {
    $sam = $u.SamAccountName
    $dn  = $u.DistinguishedName
    $phone = $u.Phone

    $smsId = ''
    $smsStatus = ''
    $adChanged = $false
    $errorMessage = ''

    try {
        Write-Log "Processing ${sam} (${phone})" "INFO" -Channel Main

        # Вызов генератора с солью из конфига
        $pwObj = New-PasswordWithSalt `
            -MinLength $config.PasswordPolicy.MinLength `
            -MaxLength $config.PasswordPolicy.MaxLength `
            -AllowedSpecials $config.PasswordPolicy.AllowedSpecials `
            -SaltEnabled $config.PasswordPolicy.Salt.Enabled `
            -AllowedOps $config.PasswordPolicy.Salt.AllowedOps `
            -MaxSalt $config.PasswordPolicy.Salt.MaxSalt `
            -NumberWidth $config.PasswordPolicy.Salt.NumberWidth

        $realPwd  = $pwObj.Real
        $obscured = $pwObj.Obscured
        $saltSpec = $pwObj.SaltSpec

        # Логируем обфусцированную версию; реальный пароль НЕ пишем в файл.
        if ($saltSpec) {
            Write-Log "Generated password for ${sam}: ${obscured} ${saltSpec} (real=**masked**)" "DEBUG" -Channel Main -Sensitive
        } else {
            Write-Log "Generated password for ${sam}: ${obscured} (no salt)" "DEBUG" -Channel Main -Sensitive
        }

        # Формируем текст SMS
        if ($saltSpec) {
            $smsPwdText = "${obscured} ${saltSpec}"
        } else {
            $smsPwdText = $realPwd
        }
        $msg = $config.SMS.TextTemplate.Replace("{{UserName}}",${sam}).Replace("{{Password}}",$smsPwdText)

        # Отправляем SMS
        $smsResp = Send-SmsRuMessage -SmsConfig $config.SMS -Phone $phone -Message $msg
        if (-not $smsResp.Ok) { throw "SMS send failed: $($smsResp.Error)" }
        $smsId = $smsResp.SmsId
        Write-Log "SMS accepted by gateway, id=${smsId}" "INFO" -Channel Sms

        # Мы считаем доставкой на уровне шлюза (ACCEPTED)
        $smsStatus = "ACCEPTED"

        # Смена пароля в AD — только после успешной приёмки шлюзом
        try {
            $securePwd = ConvertTo-SecureString $realPwd -AsPlainText -Force
            Set-ADAccountPassword -Identity $dn -NewPassword $securePwd -Reset -ErrorAction Stop
            $adChanged = $true
            Write-Log "AD password changed for ${sam}" "INFO" -Channel Main
        }
        catch {
            throw "AD password change failed: $($_.Exception.Message)"
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Error processing ${sam}: ${errorMessage}" "ERROR" -Channel Main
    }
    finally {
        # CSV запись: не включаем реальный пароль
        $csvLine = "{0},{1},{2},{3},{4},{5},{6}" -f ${sam}, $dn, $phone, $smsId, $smsStatus, $adChanged, ($errorMessage -replace ',', ';')
        Add-Content -Path $global:LogCsv -Value $csvLine
    }
}

Write-Log "=== ADPass2SMS run complete ===" "INFO" -Channel Main
