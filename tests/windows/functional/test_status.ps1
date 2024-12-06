# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

function setUp {
    Write-Host "Ensuring reg key present: " -NoNewline
    New-ItemProperty -Path $vmtools_base_reg `
                     -Name $vmtools_salt_minion_status_name `
                     -Value 0 `
                     -Force | Out-Null
    Write-Done
}

function tearDownScript {
    Write-Host "Removing reg key: " -NoNewline
    Remove-ItemProperty -Path $vmtools_base_reg `
                        -Name $vmtools_salt_minion_status_name `
                        -ErrorAction SilentlyContinue
    Write-Done
}

function test_Get-Status_notInstalled {
    Remove-ItemProperty -Path $vmtools_base_reg `
                        -Name $vmtools_salt_minion_status_name `
                        -ErrorAction SilentlyContinue
    $result = Get-Status
    if ($result -eq $STATUS_CODES["notInstalled"]) { return 0 }
    return 1
}

function test_Get-Status_installed {
    $reg_value = $STATUS_CODES["installed"]
    Set-ItemProperty -Path $vmtools_base_reg `
                     -Name $vmtools_salt_minion_status_name `
                     -Value $reg_value
    function Get-ServiceStatus { return "Running" }
    $result = Get-Status
    if ($result -eq $STATUS_CODES["installed"]) { return 0 }
    return 1
}

function test_Get-Status_installedStopped {
    $reg_value = $STATUS_CODES["installed"]
    Set-ItemProperty -Path $vmtools_base_reg `
                     -Name $vmtools_salt_minion_status_name `
                     -Value $reg_value
    function Get-ServiceStatus { return "Stopped" }
    $result = Get-Status
    # We'll set this back once VM Tools adds support for this code
    #if ($result -eq $STATUS_CODES["installedStopped"]) { return 0 }
    if ($result -eq $STATUS_CODES["installed"]) { return 0 }
    return 1
}

function test_Get-Status_installing
{
    $reg_value = $STATUS_CODES["installing"]
    Set-ItemProperty -Path $vmtools_base_reg `
                     -Name $vmtools_salt_minion_status_name `
                     -Value $reg_value
    function Get-ScriptRunningStatus { return $true }
    $result = Get-Status
    if ($result -eq $STATUS_CODES["installing"]) { return 0 }
    return 1
}

function test_Get-Status_installing_failed
{
    $reg_value = $STATUS_CODES["installing"]
    Set-ItemProperty -Path $vmtools_base_reg `
                     -Name $vmtools_salt_minion_status_name `
                     -Value $reg_value
    function Get-ScriptRunningStatus { return $false }
    $result = Get-Status
    if ($result -eq $STATUS_CODES["installFailed"]) { return 0 }
    return 1
}

function test_Get-Status_installFailed {
    $reg_value = $STATUS_CODES["installFailed"]
    Set-ItemProperty -Path $vmtools_base_reg `
                     -Name $vmtools_salt_minion_status_name `
                     -Value $reg_value
    $result = Get-Status
    if ($result -eq $STATUS_CODES["installFailed"]) { return 0 }
    return 1
}

function test_Get-Status_removing {
    $reg_value = $STATUS_CODES["removing"]
    Set-ItemProperty -Path $vmtools_base_reg `
                     -Name $vmtools_salt_minion_status_name `
                     -Value $reg_value
    function Get-ScriptRunningStatus { return $true }
    $result = Get-Status
    if ($result -eq $STATUS_CODES["removing"]) { return 0 }
    return 1
}

function test_Get-Status_removing_failed {
    $reg_value = $STATUS_CODES["removing"]
    Set-ItemProperty -Path $vmtools_base_reg `
                     -Name $vmtools_salt_minion_status_name `
                     -Value $reg_value
    function Get-ScriptRunningStatus { return $false }
    $result = Get-Status
    if ($result -eq $STATUS_CODES["removeFailed"]) { return 0 }
    return 1
}

function test_Get-Status_removeFailed {
    $reg_value = $STATUS_CODES["removeFailed"]
    Set-ItemProperty -Path $vmtools_base_reg `
                     -Name $vmtools_salt_minion_status_name `
                     -Value $reg_value
    $result = Get-Status
    if ($result -eq $STATUS_CODES["removeFailed"]) { return 0 }
    return 1
}

function test_Get-Status_unknownStatus {
    Set-ItemProperty -Path $vmtools_base_reg `
                     -Name $vmtools_salt_minion_status_name `
                     -Value 7
    $result = Get-Status
    if ($result -eq 7) { return 0 }
    return 1
}

function test_Set-Status_installed {
    Set-Status -NewStatus installed
    $result = Get-ItemProperty -Path $vmtools_base_reg `
                               -Name $vmtools_salt_minion_status_name
    if ($result.SaltMinionStatus -eq $STATUS_CODES["installed"]) { return 0 }
    return 1
}

function test_Set-Status_installing {
    Set-Status -NewStatus installing
    $result = Get-ItemProperty -Path $vmtools_base_reg `
                               -Name $vmtools_salt_minion_status_name
    if ($result.SaltMinionStatus -eq $STATUS_CODES["installing"]) { return 0 }
    return 1
}

function test_Set-Status_notInstalled {
    Set-Status -NewStatus notInstalled
    $result = Get-Status
    if ($result -eq $STATUS_CODES["notInstalled"]) { return 0 }
    return 1
}

function test_Set-Status-notInstalled_key_not_present {
    Remove-ItemProperty -Path $vmtools_base_reg `
                        -Name $vmtools_salt_minion_status_name `
                        -ErrorAction SilentlyContinue
    Set-Status -NewStatus notInstalled
    $result = Get-Status
    if ($result -eq $STATUS_CODES["notInstalled"]) { return 0 }
    return 1
}

function test_Set-Status_installFailed {
    Set-Status -NewStatus installFailed
    $result = Get-ItemProperty -Path $vmtools_base_reg `
                               -Name $vmtools_salt_minion_status_name
    if ($result.SaltMinionStatus -eq $STATUS_CODES["installFailed"]) { return 0 }
    return 1
}

function test_Set-Status_removing {
    Set-Status -NewStatus removing
    $result = Get-ItemProperty -Path $vmtools_base_reg `
                               -Name $vmtools_salt_minion_status_name
    if ($result.SaltMinionStatus -eq $STATUS_CODES["removing"]) { return 0 }
    return 1
}

function test_Set-Status_removeFailed {
    Set-Status -NewStatus removeFailed
    $result = Get-ItemProperty -Path $vmtools_base_reg `
                               -Name $vmtools_salt_minion_status_name
    if ($result.SaltMinionStatus -eq $STATUS_CODES["removeFailed"]) { return 0 }
    return 1
}

function test_Set-FailedStatus_installFailed {
    $Action = "install"
    Set-FailedStatus
    $result = Get-ItemProperty -Path $vmtools_base_reg `
                               -Name $vmtools_salt_minion_status_name
    if ($result.SaltMinionStatus -eq $STATUS_CODES["installFailed"]) { return 0 }
    return 1
}

function test_Set-FailedStatus_removeFailed {
    $Action = "remove"
    Set-FailedStatus
    $result = Get-ItemProperty -Path $vmtools_base_reg `
                               -Name $vmtools_salt_minion_status_name
    if ($result.SaltMinionStatus -eq $STATUS_CODES["removeFailed"]) { return 0 }
    return 1
}
