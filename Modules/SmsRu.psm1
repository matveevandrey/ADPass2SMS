# =========================
# Module: SmsRu.psm1
# =========================

function Test-SmsRuAuth {
    param(
        [hashtable]$SmsConfig
    )
    $uri = "$($SmsConfig.AuthCheckUrl)?api_id=$($SmsConfig.ApiId)&json=1"
    try {
        $resp = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec $SmsConfig.TimeoutSec
        if ($resp.status -eq "OK") {
            Write-Log "SMS.ru auth OK. Balance: $($resp.balance)" "INFO" -Channel "Sms"
            return $true
        } else {
            Write-Log "SMS.ru auth failed: $($resp.status_code)" "ERROR" -Channel "Sms"
            return $false
        }
    }
    catch {
        Write-Log "SMS.ru auth exception: $($_.Exception.Message)" "ERROR" -Channel "Sms"
        return $false
    }
}

function Send-SmsRuMessage {
    param(
        [hashtable]$SmsConfig,
        [string]$Phone,
        [string]$Message
    )

    $q = @{
        api_id = $SmsConfig.ApiId
        to     = $Phone
        msg    = $Message
        json   = 1
    }
    if ($SmsConfig.From -and $SmsConfig.From.Trim() -ne "") {
        $q.from = $SmsConfig.From
    }
    if ($SmsConfig.TestMode) {
        $q.test = 1
    }

    # правильная сборка query-string
    $pairs = @()
    foreach ($kv in $q.GetEnumerator()) {
        $k = [string]$kv.Key
        $v = [string]$kv.Value
        $pairs += ("{0}={1}" -f $k, [uri]::EscapeDataString($v))
    }
    $uri = $SmsConfig.BaseUrl + "?" + ($pairs -join "&")

    try {
        Write-Log "SMS URI: $uri" "DEBUG" -Channel "Sms"
        $resp = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec $SmsConfig.TimeoutSec
        Write-Log "RAW SMS response: $($resp | ConvertTo-Json -Depth 5 -Compress)" "DEBUG" -Channel "Sms"

        if ($resp.status -eq "OK") {
            $smsInfo = $resp.sms.$Phone
            if ($smsInfo.status -eq "OK") {
                Write-Log "SMS accepted, id=$($smsInfo.sms_id)" "INFO" -Channel "Sms"
                return @{ Ok = $true; SmsId = $smsInfo.sms_id; Raw = $resp }
            } else {
                $msg = "$($smsInfo.status_text) (code=$($smsInfo.status_code))"
                Write-Log "SMS send failed for ${Phone}: $msg" "ERROR" -Channel "Sms"
                return @{ Ok = $false; Error = $msg; Raw = $resp }
            }
        } else {
            $msg = "Gateway error: $($resp.status_code)"
            Write-Log "SMS gateway error: $msg" "ERROR" -Channel "Sms"
            return @{ Ok = $false; Error = $msg; Raw = $resp }
        }
    }
    catch {
        Write-Log "SMS.ru send exception: $($_.Exception.Message)" "ERROR" -Channel "Sms"
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}

Export-ModuleMember -Function Test-SmsRuAuth,Send-SmsRuMessage
