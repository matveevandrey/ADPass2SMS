function Normalize-Phone {
    param([string]$Phone)

    if ([string]::IsNullOrWhiteSpace($Phone)) { return $null }

    # оставляем только цифры
    $clean = ($Phone -replace '[^\d]', '')

    # заменяем первую 8 на 7
    if ($clean.StartsWith("8")) {
        $clean = "7" + $clean.Substring(1)
    }

    # проверяем длину
    if ($clean.Length -ne 11) {
        Write-Log "Invalid phone format after normalization: $Phone -> $clean" "WARN" -Channel Main
        return $null
    }

    return $clean
}

function Get-ADTargetUsers {
    param($ADConfig)

    Write-Log "Get-ADTargetUsers: SearchBase=$($ADConfig.SearchBase)" "DEBUG" -Channel Main
    Write-Log "Get-ADTargetUsers: LDAPFilter=$($ADConfig.LDAPFilter)" "DEBUG" -Channel Main
    Write-Log "Get-ADTargetUsers: EnabledOnly=$($ADConfig.EnabledOnly), RequirePhone=$($ADConfig.RequirePhone), Group=$($ADConfig.GroupName)" "DEBUG" -Channel Main

    $props  = @("SamAccountName","DistinguishedName",$ADConfig.PhoneAttribute,"Enabled")

    # Получаем пользователей по LDAP-фильтру
    $rawUsers = Get-ADUser -LDAPFilter $ADConfig.LDAPFilter -SearchBase $ADConfig.SearchBase -Properties $props -ResultSetSize $ADConfig.MaxUsersPerRun
    Write-Log "AD returned raw users: $($rawUsers.Count)" "DEBUG" -Channel Main

    # Фильтрация по Enabled и наличию телефона
    $users = $rawUsers | Where-Object {
        ($ADConfig.EnabledOnly -eq $false -or $_.Enabled) -and
        (-not $ADConfig.RequirePhone -or $_.$($ADConfig.PhoneAttribute))
    }
    Write-Log "After Enabled/Phone filter: $($users.Count)" "DEBUG" -Channel Main

    # Фильтрация по группе (если указана)
    if ($ADConfig.GroupName -and $ADConfig.GroupName -ne "") {
        $groupMembers = Get-ADGroupMember -Identity $ADConfig.GroupName -Recursive | Select-Object -ExpandProperty DistinguishedName
        $users = $users | Where-Object { $groupMembers -contains $_.DistinguishedName }
        Write-Log "After Group '$($ADConfig.GroupName)' filter: $($users.Count)" "DEBUG" -Channel Main
    }

    # Приводим к выходному формату
    $out = @()
    foreach ($u in $users) {
        $normPhone = Normalize-Phone $u.$($ADConfig.PhoneAttribute)

        # если телефон обязателен, а нормализация не удалась → пропускаем
        if ($ADConfig.RequirePhone -and -not $normPhone) { continue }

        $out += [PSCustomObject]@{
            SamAccountName    = $u.SamAccountName
            Phone             = $normPhone
            DistinguishedName = $u.DistinguishedName
        }
    }

    Write-Log "Found users: $($out.Count)" "DEBUG" -Channel Main
    foreach ($x in $out) {
        Write-Log "  $($x.SamAccountName) ($($x.Phone))" "DEBUG" -Channel Main
    }

    return $out
}

# ---------------------------
# Экспорт только нужных функций
# ---------------------------
Export-ModuleMember -Function Get-ADTargetUsers