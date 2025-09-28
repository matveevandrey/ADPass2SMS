function Get-SmsRuStatusText {
    param([int]$Code)

    switch ($Code) {
        100 { return "Сообщение принято" }
        101 { return "В очереди" }
        102 { return "Передается оператору" }
        103 { return "Отправлено (в пути)" }
        104 { return "Доставлено" }
        105 { return "Не доставлено" }
        106 { return "Время жизни истекло" }
        107 { return "Удалено оператором" }
        108 { return "Неизвестная ошибка доставки" }
        200 { return "Неправильный api_id" }
        201 { return "Недостаточно средств" }
        202 { return "Неправильный номер" }
        203 { return "Нет текста сообщения" }
        204 { return "Имя отправителя не согласовано" }
        205 { return "Сообщение слишком длинное" }
        default { return "Неизвестный код" }
    }
}

function Test-SmsRuAuth {
    param($SmsConfig)

    $uri = "$($SmsConfig.AuthCheckUrl)?api_id=$($SmsConfig.ApiId)&json=1"
    Write-Log "AUTH URI: $uri" "DEBUG" -Channel Sms

    try {
        $resp = Invoke-RestMethod -Uri $uri -Method GET -TimeoutSec $SmsConfig.TimeoutSec
        Write-Log ("AUTH RAW: " + ($resp | ConvertTo-Json -Depth 5)) "DEBUG" -Channel Sms

        if ($resp.status -eq "OK") {
            Write-Log "SMS.ru auth OK. Balance: $($resp.balance)" "INFO" -Channel Sms
            return $true
        } else {
            $msg = Get-SmsRuStatusText $resp.status_code
            Write-Log "SMS.ru auth failed: $($resp.status_code) ($msg)" "ERROR" -Channel Sms
            return $false
        }
    }
    catch {
        Write-Log "SMS.ru auth error: $($_.Exception.Message)" "ERROR" -Channel Sms
        return $false
    }
}

function Send-SmsRuMessage {
    param(
        $SmsConfig,
        [string]$Phone,
        [string]$Message
    )

    $cleanPhone = ($Phone -replace '[^\d]', '')
    if ($cleanPhone.StartsWith("8")) {
        $cleanPhone = "7" + $cleanPhone.Substring(1)
    }

    $params = @{
        api_id = $SmsConfig.ApiId
        to     = $cleanPhone
        msg    = $Message
        json   = 1
    }
    if ($SmsConfig.TestMode) { $params.test = 1 }

    $query = ($params.GetEnumerator() | ForEach-Object {
        "$($_.Key)=$([uri]::EscapeDataString($_.Value))"
    }) -join "&"

    $uri = "$($SmsConfig.BaseUrl)?$query"
    Write-Log "SMS URI: $uri" "DEBUG" -Channel Sms

    try {
        $raw = Invoke-WebRequest -Uri $uri -Method GET -TimeoutSec $SmsConfig.TimeoutSec
        Write-Log "RAW SMS response: $($raw.Content)" "DEBUG" -Channel Sms

        $resp = $raw.Content | ConvertFrom-Json -ErrorAction Stop

        if ($resp.status -ne "OK") {
            $msg = Get-SmsRuStatusText $resp.status_code
            Write-Log "SMS.ru general error: $($resp.status_code) ($msg)" "ERROR" -Channel Sms
            return @{ Ok = $false; Error = $msg }
        }

        # Проверяем конкретный номер
        $phoneResp = $resp.sms.$cleanPhone
        if ($phoneResp.status -eq "OK" -and $phoneResp.sms_id) {
            $smsId = $phoneResp.sms_id
            Write-Log "SMS accepted for $($cleanPhone), id=$smsId" "INFO" -Channel Sms
            return @{ Ok = $true; SmsId = $smsId }
        } else {
            $msg = "$($phoneResp.status_code) $($phoneResp.status_text)"
            Write-Log "SMS send failed for $($cleanPhone): $msg" "ERROR" -Channel Sms
            return @{ Ok = $false; Error = $msg }
        }
    }
    catch {
        Write-Log "SMS.ru send error: $($_.Exception.Message)" "ERROR" -Channel Sms
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}

function Get-SmsRuStatus {
    param(
        $SmsConfig,
        [string]$SmsId
    )

    $uri = "$($SmsConfig.StatusUrl)?api_id=$($SmsConfig.ApiId)&id=$SmsId&json=1"
    Write-Log "STATUS URI: $uri" "DEBUG" -Channel Sms

    try {
        $raw = Invoke-WebRequest -Uri $uri -Method GET -TimeoutSec $SmsConfig.TimeoutSec
        Write-Log "RAW STATUS response: $($raw.Content)" "DEBUG" -Channel Sms

        $resp = $raw.Content | ConvertFrom-Json -ErrorAction Stop
        $status = $resp.${SmsId}.status
        $statusText = Get-SmsRuStatusText $status

        Write-Log "SMS.ru status for ${SmsId}: $status ($statusText)" "INFO" -Channel Sms
        return $status
    }
    catch {
        Write-Log "SMS.ru status error: $($_.Exception.Message)" "ERROR" -Channel Sms
        return "ERROR"
    }
}
