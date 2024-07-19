# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

function setUpScript {

    Write-Host "Installing salt: " -NoNewline
    function Get-GuestVars { "master=gv_master id=gv_minion" }
    $MinionVersion = "3006.0"
    Install
    Write-Done
}

function tearDownScript {

    # Stop and remove the salt-minion service if it exists
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "Stopping the salt-minion service: " -NoNewline
        Stop-Service -Name salt-minion
        Write-Done

        Write-Host "Removing the salt-minion service: " -NoNewline
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='salt-minion'"
        $service.delete() *> $null
        Write-Done
    }

    # Remove Program Data directory
    if (Test-Path "$base_salt_config_location") {
        Write-Host "Removing config directory: " -NoNewline
        Remove-Item "$base_salt_config_location" -Force -Recurse
        Write-Done
    }

    # Remove Program Files directory
    if (Test-Path "$base_salt_install_location") {
        Write-Host "Removing install directory: " -NoNewline
        Remove-Item "$base_salt_install_location" -Force -Recurse
        Write-Done
    }

    # Removing from the path

    $path = "$salt_dir"
    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
    $new_path_list = [System.Collections.ArrayList]::new()
    $removed = 0
    foreach ($item in $current_path.Split(";")) {
        $regex_path = $path.Replace("\", "\\")
        # Bail if we find the new path in the current path
        if ($item -imatch "^$regex_path(\\)?$") {
            # Remove this one
            Write-Host "Removing salt from the system path: " -NoNewline
            $removed = 1
        } else {
            # Add the item to our new path array
            $new_path_list.Add($item) | Out-Null
        }
    }
    if ($removed) {
        $new_path = $new_path_list -join ";"
        Set-ItemProperty -Path $path_reg_key -Name Path -Value $new_path
        Write-Done
    }
}

function test_reconfig{
    # test reconfig
    function Get-GuestVars { "master=reconfig_master id=reconfig_minion_id" }
    Reconfigure

    $result = & "$salt_dir\salt-call.exe" --local config.get master
    if (!($result -like "local:*")) { return 1 }
    if (!($result -like "*reconfig_master")) { return 1 }

    $result = & "$salt_dir\salt-call.exe" --local config.get id
    if (!($result -like "local:*")) { return 1 }
    if (!($result -like "*reconfig_minion_id")) { return 1 }

    return 0
}

function test_stop {
    # test stop
    Stop-MinionService

    $service_status = Get-ServiceStatus
    if ( !($service_status -eq "Stopped") ) { return 1 }

    return 0
}

function test_start {
    # test start

    # let's stop it first...
    Stop-MinionService
    $service_status = Get-ServiceStatus
    if ( !($service_status -eq "Stopped") ) { return 1 }

    # now let's start it...
    Start-MinionService
    $service_status = Get-ServiceStatus
    if ( !($service_status -eq "Running") ) { return 1 }

    return 0
}