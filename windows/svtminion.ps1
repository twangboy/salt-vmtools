# Copyright 2021-2024 Broadcom, Inc.
# SPDX-License-Identifier: Apache-2

<#
.SYNOPSIS
VMware Tools script for managing the Salt minion on a Windows guest.

.DESCRIPTION
This script provides comprehensive management of the Salt minion on a Windows
guest. The minion is a OneDir build available at:

https://packages.broadcom.com/artifactory/saltproject-generic/onedir

With this script, you can install, remove, check dependencies, retrieve
installation status, and reset the Salt minion configuration.

When run without parameters, the script checks for an action in `guestVars`. If
no action is found, it exits with a `scriptFailed` (126) code.

If an action is passed via the CLI or found in `guestVars`, the script gathers
minion configuration options (e.g., `master=198.51.100.1`) from `guestVars`.
Additional configuration options are obtained from `tools.conf`, which overrides
any conflicting options from `guestVars`. CLI options take the highest
precedence, followed by `tools.conf`, and finally `guestVars`.

The script returns the following exit codes to indicate its status:
- 0 - `scriptSuccess`
- 126 - `scriptFailed`
- 130 - `scriptTerminated`

If the `-Status` option is passed, the exit code signals the Salt minion’s
installation status as follows:
- 100 - Installed (and running)
- 101 - Installing
- 102 - Not installed
- 103 - Installation failed
- 104 - Removing
- 105 - Removal failed
- 106 - External installation detected
- 107 - Installed but stopped (future support, returns 100 for now)

NOTE: This script must be executed with Administrator privileges.

.EXAMPLE
PS> svtminion.ps1 -Install

.EXAMPLE
PS> svtminion.ps1 -Install -MinionVersion 3006.2 master=192.168.10.10 id=dev_box

.EXAMPLE
PS> svtminion.ps1 -Install -Source https://my.domain.com/vmtools/salt

.EXAMPLE
PS> svtminion.ps1 -Install -MinionVersion 3006.8 -Upgrade

.EXAMPLE
PS> svtminion.ps1 -Clear

.EXAMPLE
PS> svtminion.ps1 -Status

.EXAMPLE
PS> svtminion.ps1 -Depend

.EXAMPLE
PS> svtminion.ps1 -Remove -LogLevel debug

#>

[CmdletBinding(DefaultParameterSetName = "Install")]
param(

    [Parameter(Mandatory=$false, ParameterSetName="Install")]
    [Alias("i")]
    # The Install action downloads, installs, and starts the salt-minion
    # service.
    #
    # It exits with the `scriptFailed` exit code (126) under any of the
    # following conditions:
    # - Existing Standard Salt Installation detected
    # - Unknown status found
    # - Installation in progress
    # - Removal in progress
    # - Installation failed
    # - Missing script dependencies
    #
    # It exits with the `scriptSuccess` exit code (0) under the following
    # conditions:
    # - Installed successfully
    # - Already installed
    [Switch] $Install,

    [Parameter(Mandatory=$false, ParameterSetName="Install")]
    [Alias("u")]
    # The Upgrade parameter upgrades an existing Salt installation in place,
    # leaving the minion configuration unchanged. guestVars and CLI values
    # are ignored during the upgrade. Use this option to switch between
    # different Salt versions.
    #
    # Pass the Upgrade parameter with the Install action to upgrade to the
    # specified version. If Upgrade is not passed and Salt is already installed,
    # the script will exit with a `scriptSuccess` code (0) and a message
    # indicating that the minion is already installed.
    [Switch] $Upgrade,

    [Parameter(Mandatory=$false, ParameterSetName="Install")]
    [Alias("m")]
    # The MinionVersion parameter specifies the version of the Salt minion to
    # install. Use "latest" to install the most recent version available
    # (default is "latest"). Alternatively, you can specify a major version
    # number to install the latest release within that version series. For
    # example, to install the latest release in the 3006 series, pass "3006".
    [String] $MinionVersion="latest",

    [Parameter(Mandatory=$false, ParameterSetName="Install")]
    [Alias("j")]
    # The Source parameter specifies the URL or path to a repository containing
    # directories named after different Salt versions. Each directory should
    # include a zip file corresponding to the version indicated by the directory
    # name.
    #
    # The directory structure should follow a layout similar to the default
    # repository:
    #
    # https://packages.broadcom.com/artifactory/saltproject-generic/onedir
    #
    # The Source parameter supports common protocols such as HTTP, HTTPS, FTP,
    # UNC paths, and local file paths.
    [String] $Source=(
        "https://packages.broadcom.com/artifactory/saltproject-generic/onedir"
    ),

    [Parameter(Mandatory=$false, ParameterSetName="Reconfig")]
    [Alias("n")]
    # The Reconfig action updates the Salt minion configuration using settings
    # provided via the command-line, `guestVars`, or `tools.conf`. After
    # updating, the minion will be restarted to apply the new configuration.
    #
    # The following exit codes may occur:
    # - 102 - Salt minion not installed
    # - 106 - External installation of the Salt minion detected
    [Switch] $Reconfig,

    [Parameter(Position=0, ValueFromRemainingArguments=$true,
            Mandatory=$false, ParameterSetName="Install")]
    [Parameter(Position=0, ValueFromRemainingArguments=$true,
            Mandatory=$false, ParameterSetName="Reconfig")]
    # This parameter accepts any number of minion configuration options,
    # specified as key/value pairs in the format `key=value`, as documented in
    # the Salt documentation. For example: master=localhost.
    #
    # All keys will be automatically converted to lowercase and written to the
    # minion configuration.
    [String[]] $ConfigOptions,

    [Parameter(Mandatory=$false, ParameterSetName="Remove")]
    [Alias("r")]
    # The Remove action stops and uninstalls the salt-minion service. It exits
    # with the `scriptFailed` exit code (126) under the following conditions:
    # - Unknown status found
    # - Installation in progress
    # - Removal in progress
    # - Installation failed
    # - Missing script dependencies
    #
    # It exits with the `scriptSuccess` exit code (0) under the following
    # conditions:
    # - Successfully removed
    # - Already removed
    [Switch] $Remove,

    [Parameter(Mandatory=$false, ParameterSetName="Clear")]
    [Alias("c")]
    # The Clear action resets the salt-minion by randomizing its minion ID and
    # removing the minion keys. The new minion ID will be the old minion ID
    # followed by an underscore and five random digits.
    #
    # Exits with the `scriptFailed` exit code (126) under the following
    # conditions:
    # - Unknown status found
    # - Missing script dependencies
    #
    # Exits with the `scriptSuccess` exit code (0) under the following
    # conditions:
    # - Successfully cleared
    # - Minion was not installed
    [Switch] $Clear,

    [Parameter(Mandatory=$false, ParameterSetName="Status")]
    [Alias("s")]
    # The Status action retrieves the current status of the Salt minion
    # installation. The exit code will correspond to one of the following status
    # codes:
    #
    # 100 - Installed (and running)
    # 101 - Installing
    # 102 - Not installed
    # 103 - Installation failed
    # 104 - Removing
    # 105 - Removal failed
    # 106 - External installation detected
    # 107 - Installed but stopped (future support, returns 100 for now)
    #
    # Exits with the `scriptFailed` exit code (126) under the following
    # conditions:
    # - Unknown status found
    # - Missing script dependencies
    [Switch] $Status,

    [Parameter(Mandatory=$false, ParameterSetName="Depend")]
    [Alias("d")]
    # The Depend action checks that all required dependencies are available.
    #
    # It exits with the `scriptFailed` exit code (126) if any dependencies are
    # missing.
    #
    # It exits with the `scriptSuccess` exit code (0) if all dependencies are
    # present.
    [Switch] $Depend,

    [Parameter(Mandatory=$false)]
    [Alias("l")]
    [ValidateSet(
            "silent",
            "error",
            "warning",
            "info",
            "debug",
            IgnoreCase=$true)]
    # Sets the log level for display and logging. The default is "warning". The
    # "silent" level suppresses all logging output. Available options are:
    #
    # - silent
    # - error
    # - warning
    # - info
    # - debug
    #
    # Logs are stored in `C:\Windows\temp` and named according to the action the
    # script is performing, along with a timestamp. For example:
    # `vmware-svtminion-<action>-<timestamp>.log`
    [String] $LogLevel = "warning",

    [Parameter(Mandatory=$false)]
    [Alias("q")]
    # Stops the salt-minion service.
    #
    # The following exit codes may occur:
    # 102 - Salt minion not installed
    # 106 - External installation of the Salt minion detected
    [Switch] $Stop,

    [Parameter(Mandatory=$false)]
    [Alias("p")]
    # Starts or restarts the salt-minion service.
    #
    # The following exit codes may occur:
    # 102 - Salt minion not installed
    # 106 - External install of the Salt minion found
    [Switch] $Start,

    [Parameter(Mandatory=$false)]
    [Alias("h")]
    # Displays help information for this script.
    [Switch] $Help,

    [Parameter(Mandatory=$false)]
    [Alias("v")]
    # Displays the current version of this script.
    [Switch] $Version
)

# Set TLS1.2 as default
[System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.SecurityProtocolType]'Tls12'

################################ HELP/VERSION ##################################
# We'll put these functions first because they don't require administrator
# privileges to run

# Check for help switch
if ($help) {
    # Get the full script name
    $this_script = & {$myInvocation.ScriptName}
    Get-Help $this_script -Detailed
    exit 0
}

# This value is populated via CICD during build
$SCRIPT_VERSION = "SCRIPT_VERSION_REPLACE"
if ($Version) {
    Write-Host $SCRIPT_VERSION
    exit 0
}

# Only run on 64-bit architecture
if ( [System.IntPtr]::Size -eq 4 ) {
    Write-Host "This script only supports 64-bit architecture"
    exit 0
}

################################# STATUS CODES #################################
$STATUS_CODES = @{
    "scriptSuccess" = 0;
    "installed" = 100;
    "installing" = 101;
    "notInstalled" = 102;
    "installFailed" = 103;
    "removing" = 104;
    "removeFailed" = 105;
    "externalInstall" = 106;
    # VM Tools currently doesn't support 107. We'll add this back
    # once they do. So, until then, we just return 100
    "installedStopped" = 100;
    "scriptFailed" = 126;
    "scriptTerminated" = 130;
    100 = "installed";
    101 = "installing";
    102 = "notInstalled";
    103 = "installFailed"
    104 = "removing";
    105 = "removeFailed";
    106 = "externalInstall";
    107 = "installedStopped";
}

################################ REQUIREMENTS ##################################
# Make sure the script is run as Administrator
$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
if (!($Principal.IsInRole(
        [System.Security.Principal.WindowsBuiltInRole]::Administrator
))) {
    Write-Host "This script must run as Administrator" -ForegroundColor Red
    exit $STATUS_CODES["scriptFailed"]
}


################################# LOGGING ######################################
$LOG_LEVELS = @{
    "silent" = 0;
    "error" = 1;
    "warning" = 2;
    "info" = 3;
    "debug" = 4
}
$log_level_value = $LOG_LEVELS[$LogLevel.ToLower()]

################################# SETTINGS #####################################
$global:ErrorActionPreference = "Stop"
$global:ProgressPreference = "SilentlyContinue"
$Script:log_cleared = $false
$download_retry_count = 5
$script_date = Get-Date -Format "yyyyMMddHHmmss"
$script_name = $MyInvocation.MyCommand.Name
$script_log_dir = "$env:SystemRoot\Temp"
# log file name: vmware-svtminion-{0}-20211019152012.log
$script_log_base_name = "vmware-$($script_name.Split(".")[0])-{0}"
$script_log_name = "$script_log_base_name-$script_date.log"
$script_log_file_count = 5
$action_list = @(
    "install",
    "reconfig",
    "remove",
    "depend",
    "clear",
    "status",
    "start",
    "stop"
)

################################# VARIABLES ####################################
# Repository locations and names
# An artifactory url will have "artifactory" in it
$domain_name, $target_path = $Source -split "/artifactory/"
# If $target_path is not empty, this is an artifactory url
if ( $target_path ) {
    # Create $base_url and $api_url
    $base_url = "$domain_name/artifactory/$target_path"
    $api_url = "$domain_name/artifactory/api/storage/$target_path"
} else {
    # This is a non-artifactory url, there is no api
    $base_url = $domain_name
    $api_url = ""
}

# Salt file and directory locations
$base_salt_install_location = "$env:ProgramFiles\Salt Project"
$salt_dir = "$base_salt_install_location\Salt"
$salt_minion_bin = "$salt_dir\salt-minion.exe"
$ssm_bin = "$salt_dir\ssm.exe"

$base_salt_config_location = "$env:ProgramData\Salt Project"
$salt_root_dir = "$base_salt_config_location\Salt"
$salt_config_dir = "$salt_root_dir\conf"
$salt_config_name = "minion"
$salt_config_file = "$salt_config_dir\$salt_config_name"
$salt_pki_dir = "$salt_config_dir\pki\$salt_config_name"
$salt_log_dir = "$salt_root_dir\var\log\salt"

# Files/Dirs to remove
$file_dirs_to_remove = New-Object System.Collections.Generic.List[String]
$file_dirs_to_remove.Add($base_salt_config_location) | Out-Null
$file_dirs_to_remove.Add($base_salt_install_location) | Out-Null
# Old Salt install location left behind by older versions of Salt
# Pre 3004
$file_dirs_to_remove.Add("C:\salt") | Out-Null

## VMware registry locations
$salt_base_reg = "HKLM:\SOFTWARE\Salt Project\Salt"
$vmtools_base_reg = "HKLM:\SOFTWARE\VMware, Inc.\VMware Tools"

$vmtools_salt_minion_status_name = "SaltMinionStatus"

try{
    $reg_key = Get-ItemProperty $vmtools_base_reg
} catch {
    if (Test-Path $vmtools_base_reg) {
        $msg = "VMware Tools not installed: $_"
        Write-Host $msg
        exit $STATUS_CODES["scriptFailed"]
    }
}
if (!($reg_key.PSObject.Properties.Name -contains "InstallPath")) {
    if (Test-Path $vmtools_base_reg) {
        # Only error out on systems with VMware Tools installed
        $msg = "Unable to find VMware Tools installation"
        Write-Host $msg
        exit $STATUS_CODES["scriptFailed"]
    }
} else {
    ## VMware file and directory locations
    $vmtools_reg = Get-ItemProperty -Path $vmtools_base_reg -Name "InstallPath"
    $vmtools_base_dir = $vmtools_reg.InstallPath
    $vmtools_conf_dir = "$env:ProgramData\VMware\VMware Tools"
    $vmtools_conf_file = "$vmtools_conf_dir\tools.conf"
    $vmtoolsd_bin = "$vmtools_base_dir\vmtoolsd.exe"
}

# If VMTools reg path exists, then we're on a VMTools system
if ( Test-Path $vmtools_base_reg ) {
    $reg_path = $vmtools_base_reg
} else {
    $reg_path = $salt_base_reg
    if ( !(Test-Path $salt_base_reg) ) {
        New-Item -Path "$salt_base_reg" -Force
    }
}

## VMware guestVars file and directory locations
$guestvars_base = "guestinfo./vmware.components"
$guestvars_section = "salt_minion"
$guestvars_salt = "$guestvars_base.$guestvars_section"
$guestvars_salt_args = "$guestvars_salt.args"
$guestvars_salt_desired_state = "$guestvars_salt.desiredstate"


################################ TEST FUNCTIONS ################################


function Get-Version {
    return $SCRIPT_VERSION
}


############################### HELPER FUNCTIONS ###############################


function Clear-OldLogs {

    $filter = "*$script_log_base_name*.log" -f $Action.ToLower()
    $files = Get-ChildItem $script_log_dir -Filter $filter | Sort-Object
    $total_files = $files.Count
    try {
        foreach ($file in $files) {
            if ($total_files -ge $script_log_file_count) {
                # Remove the file/dir/synlink/junction
                $file_obj = Get-Item -Path $file.FullName
                if ($file_obj -is [System.IO.DirectoryInfo]) {
                    [System.IO.Directory]::Delete(`
                        $file.FullName, $true) | Out-Null
                } else {
                    [System.IO.File]::Delete($file.FullName) | Out-Null
                }
                $total_files -= 1
            } else {
                break
            }
        }
    } finally {
        $Script:log_cleared = $true
    }
}


function Write-Log {
    # Function for writing logs to the screen and to the log file
    #
    # Args:
    #     Message (string): The log message
    #     Level (string):
    #         The log level. Must be one of error, info, warning, debug. Default
    #         is info
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [String] $Message,

        [Parameter()]
        [ValidateSet("error", "info", "warning", "debug", IgnoreCase=$true)]
        [String] $Level = "info"
    )

    $Level = $Level.ToUpper()
    $level_text = $Level + " " * (7 - $Level.Length)
    $script_pid = $PID + " " * (5 - $PID.Length)

    if ( $LOG_LEVELS[$Level.ToLower()] -le $log_level_value ) {
        $date_time = Get-Date -Format "yyyy-MM-dd:HH:mm:ss.ffff"
        $timestamp = Get-Date -Format "HH:mm:ss.ffff"
        $log_message = "[$timestamp] [$level_text] $Message"
        $log_file_message = "[$date_time] [$script_pid] [$level_text] $Message"
        if (!(Test-Path($script_log_dir))) {
            Write-Host "[$timestamp] [INFO   ] : Creating log file directory"
            New-Item -Path $script_log_dir -Type Directory | Out-Null
        }
        if (!($action_list -contains $Action)) { $Action = "Default" }

        if (!$Script:log_cleared) {
            Clear-OldLogs
        }

        $log_path = "$script_log_dir\$script_log_name" -f $Action
        Add-Content -Path $log_path.ToLower() -Value $log_file_message
        switch ($Level) {
            "ERROR" { $color = "Red" }
            "WARNING" { $color = "Yellow" }
            default { $color = "White"}
        }
        Write-Host $log_message -ForegroundColor $color
    }
}


function Get-ScriptRunningStatus {
    # Try to detect if this script is already running under another process
    #
    # Returns True if running, otherwise False

    Write-Log "Checking for a running instance of this script" -Level info

    #Get all running powershell processes
    $filter = "Name='powershell.exe' AND CommandLine LIKE '%$script_name%'"
    $processes = Get-WmiObject Win32_Process -Filter $filter | `
                 Select-Object CommandLine,ProcessId

    $process_found = $false
    foreach ($process in $processes) {
        [Int32]$process_pid = $process.ProcessId
        [String]$process_cmd = $process.commandline
        #Are other instances of this script already running?
        if (($process_cmd -match $script_name) -And ($process_pid -ne $PID)) {
            $process_found = $true
        }
    }
    if ($process_found) {
        Write-Log "Found running instance in PID: $process_pid" -Level debug
        return $true
    } else {
        Write-Log "Running instance not detected" -Level debug
        return $false
    }
}


function Get-Status {
    # Read the status out of the registry. If the key is missing that means
    # notInstalled
    #
    # Returns the error level number
    $script_running_status = Get-ScriptRunningStatus

    Write-Log "Getting status" -Level info
    try {
        $current_status = Get-ItemProperty `
                            -Path $reg_path `
                            -Name $vmtools_salt_minion_status_name
        $current_status = $current_status.($vmtools_salt_minion_status_name)
        Write-Log "Found status code: $current_status" -Level debug
    } catch {
        Write-Log "Key not set, not installed : $_" -Level debug
        $current_status = $STATUS_CODES["notInstalled"]
    }

    # If status is 101 or 104 (installing or removing) but there isn't another
    # script running, then the status is installFailed or removeFailed
    $list_ing = @($STATUS_CODES["installing"], $STATUS_CODES["removing"])
    if (($list_ing -contains $current_status) -and !($script_running_status)) {
        switch ($current_status) {
            $STATUS_CODES["installing"] {
                Write-Log "Found failed install" -Level debug
                $current_status = $STATUS_CODES["installFailed"]
            }
            $STATUS_CODES["removing"] {
                Write-Log "Found failed remove" -Level debug
                $current_status = $STATUS_CODES["removeFailed"]
            }
        }
    }

    # If status 100 (installed) but the service isn't running, then the status
    # is installedStopped
    if ( $current_status -eq $STATUS_CODES["installed"] ) {
        $service_status = Get-ServiceStatus
        if ( [String]::IsNullOrEmpty($service_status) ) {
            Write-Log "Service not installed" -Level debug
            $current_status = $STATUS_CODES["notInstalled"]
        } elseif ( $service_status -ne "Running" ) {
            Write-Log "Service not running" -Level debug
            $current_status = $STATUS_CODES["installedStopped"]
        }
    }

    if ($STATUS_CODES.keys -contains $current_status) {
        $status_lookup = $STATUS_CODES[$current_status]
        Write-Log "Found status: $status_lookup" -Level debug
    } else {
        Write-Log "Unknown status code: $current_status" -Level debug
    }
    return $current_status
}


function Set-Status {
    # Set the numeric value of the status in the registry. notInstalled means to
    # remove the key
    #
    # Args:
    #     NewStatus (string):
    #         The status to set. Must be one of the following:
    #             - installed
    #             - installing
    #             - notInstalled
    #             - installFailed
    #             - removing
    #             - removeFailed
    #             - externalInstall
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet(
                "installed",
                "installing",
                "notInstalled",
                "installFailed",
                "removing",
                "removeFailed",
                "externalInstall"
        )]
        [String] $NewStatus
    )

    Write-Log "Setting status: $NewStatus" -Level info
    $status_code = $STATUS_CODES[$NewStatus]
    # If it's notInstalled, just remove the property name
    if ($status_code -eq $STATUS_CODES["notInstalled"]) {
        try {
            Remove-ItemProperty -Path "$reg_path"`
                                -Name $vmtools_salt_minion_status_name
            $key = "$reg_path\$vmtools_salt_minion_status_name"
            Write-Log "Removed reg key: $key" -Level debug
            Write-Log "Set status to $NewStatus" -Level debug
        } catch [System.Management.Automation.PSArgumentException] {
            Write-Log "Reg key not present: $key" -Level debug
            Write-Log "Status already set to: $NewStatus" -Level debug
        } catch {
            Write-Log "Error removing reg key: $_" -Level error
            exit $STATUS_CODES["scriptFailed"]
        }
    } else {
        try {
            New-ItemProperty -Path "$reg_path"`
                             -Name $vmtools_salt_minion_status_name `
                             -Value $status_code `
                             -Force | Out-Null
            Write-Log "Set status to $NewStatus" -Level debug
        } catch {
            if (Test-Path $vmtools_base_reg) {
                Write-Log "Error writing status: $_" -Level error
                exit $STATUS_CODES["scriptFailed"]
            } else {
                Write-Log "Error writing status: $_" -Level warning
            }
        }
    }
}


function Set-FailedStatus {
    # Sets the status if either add or remove fails, each sets a different
    # status if it fails
    switch ($Action.ToLower()) {
        "install" { Set-Status installFailed }
        "remove" { Set-Status removeFailed }
    }
}


function Get-WebFile{
    # Downloads a file from the web. Enables the TLS1.2 protocol. If the
    # download times out, wait 10 seconds and try again. Continues retrying
    # until the download retry count max is reached
    #
    # Used by:
    # - Get-SaltFromWeb
    #
    # Args:
    #     Url (string): The url for the file to download
    #     OutFile (string): The location to put the downloaded file
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Url,

        [Parameter(Mandatory=$true)]
        [String] $OutFile
    )
    $parent_dir = Split-Path $OutFile
    if ( !( Test-Path $parent_dir )) {
        New-Item $parent_dir -Type Directory | Out-Null
    }
    $url_name = $Url.SubString($Url.LastIndexOf('/'))

    $tries = 1
    $success = $false
    while (!$success){
        try {
            # Download the file
            $msg = "Downloading (try: $tries/$download_retry_count): $url_name"
            Write-Log $msg -Level debug
            Invoke-WebRequest -Uri $Url -OutFile $OutFile
        } catch {
            Write-Log "Error downloading: $Url" -Level warning
            Write-Log "Error message: $_" -Level warning
        } finally {
            $tries++
            if ((Test-Path -Path "$OutFile") `
                -and `
                ((Get-Item "$OutFile").Length -gt 0kb
            )) {
                Write-Log "Finished downloading: $url_name" -Level debug
                $success = $true
            } else {
                if ($tries -gt $download_retry_count) {
                    Write-Log "Retry count exceeded" -Level error
                    Set-FailedStatus
                    exit $STATUS_CODES["scriptFailed"]
                }
                Write-Log "Trying again after 10 seconds" -Level warning
                Start-Sleep -Seconds 10
            }
        }
    }
}


function Get-HashFromFile {
    # Gets the hash for the file from the hash file which contains a list of
    # hashes and their files
    #
    # Used by:
    # - Get-SaltFromWeb
    #
    # Args:
    #     HashFile (string): The file containing the hashes
    #     FileName (string): The name of the file to search for in the hash file
    #
    # Returns:
    #     Returns the hash for the specified file
    # Errors:
    #     If there is an error, set the failed status and exit with an error
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $HashFile,

        [Parameter(Mandatory=$true)]
        [String] $FileName
    )
    Write-Log "Loading hashfile: $HashFile" -Level debug
    $lines = Get-Content -Path $HashFile
    Write-Log "Searching for hash for: $FileName" -Level debug
    foreach ($line in $lines) {
        $file_hash, $file_name = $line -split "\s+"
        if ($FileName -eq $file_name) {
            Write-Log "Found hash: $file_hash" -Level debug
            return $file_hash
        }
    }
    Write-Log "No hash found for: $FileName" -Level error
    Set-FailedStatus
    exit $STATUS_CODES["scriptFailed"]
}


function Expand-ZipFile {
    # Extract a zip file
    #
    # Used by:
    # - Install-SaltMinion
    #
    # Args:
    #     ZipFile (string): The file to extract
    #     Destination (string): The location to extract to
    #
    # Error:
    #     Sets the failed status and exits with a scriptFailed exit code
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ZipFile,

        [Parameter(Mandatory = $true)]
        [string] $Destination
    )

    if (!(Test-Path -Path $Destination)) {
        Write-Log "Creating missing directory: $Destination" -Level debug
        New-Item -ItemType directory -Path $Destination
    }
    Write-Log "Unzipping '$ZipFile' to '$Destination'" -Level debug
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        # PowerShell 5 introduced Expand-Archive
        Write-Log "Using Expand-Archive to unzip"
        try{
            Expand-Archive -Path $ZipFile -DestinationPath $Destination -Force
        } catch {
            Write-Log "Failed to unzip $ZipFile : $_" -Level error
            Set-FailedStatus
            exit $STATUS_CODES["scriptFailed"]
        }
    } else {
        # This method will work with older versions of powershell, but it is
        # slow
        Write-Log "Using Shell.Application to unzip"
        $objShell = New-Object -Com Shell.Application
        $objZip = $objShell.NameSpace($ZipFile)
        try{
            foreach ($item in $objZip.Items()) {
                $objShell.Namespace($Destination).CopyHere($item, 0x14)
            }
        } catch {
            Write-Log "Failed to unzip $ZipFile : $_" -Level error
            Set-FailedStatus
            exit $STATUS_CODES["scriptFailed"]
        }
    }
    Write-Log "Finished unzipping '$ZipFile' to '$Destination'" -Level debug
}


function Add-SystemPathValue{
    # Add a new entry to the system path environment variable. Only adds the new
    # path if it does not already exist.
    #
    # Used by:
    # - Install-SaltMinion
    #
    # Args:
    #     Path (string): The target path to add
    #
    # Warning:
    #     Logs a warning if the target path does not exist
    [Cmdletbinding()]
    param (
        [parameter(Mandatory=$True)]
        [String]$Path
    )

    $key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"

    # Make sure the target folder exists
    Write-Log "Ensuring target path exists" -Level debug
    if (!(Test-Path $Path)) {
        Write-Log "Target path does not exist: $Path" -Level warning
    }

    Write-Log "Getting current system path" -Level debug
    $current_path = (Get-ItemProperty -Path $key -Name Path).Path
    $new_path_list = New-Object System.Collections.Generic.List[String]

    Write-Log "Verifying the target path is not already present" -Level debug
    $regex_path = $Path.Replace("\", "\\")
    foreach ($item in $current_path.Split(";")) {
        # Bail if we find the new path in the current path
        if ($item -imatch "^$regex_path(\\)?$") {
            Write-Log "Target path already exists: $Path" -Level warning
            return
        } else {
            # Add the item to our new path array
            $new_path_list.Add($item) | Out-Null
        }
    }

    # Add the new path to the array
    Write-Log "Adding target path: $Path" -Level debug
    $new_path_list.Add($Path) | Out-Null

    $new_path = $new_path_list -join ";"
    try{
        Write-Log "Updating system path" -Level debug
        Set-ItemProperty -Path $key -Name Path -Value $new_path
    } catch {
        Write-Log "Failed to add $Path the system path" -Level warning
        Write-Log "Tried to write: $new_path" -Level warning
        Write-Log "Error message: $_" -Level warning
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")
}


function Remove-SystemPathValue {
    # Removes the specified target path from the system path environment
    # variable
    #
    # Used by:
    # - Remove-SaltMinion
    #
    # Args
    #     Path (string): The target path to remove
    [Cmdletbinding()]
    param (
        [parameter(Mandatory=$True)]
        [String]$Path
    )

    Write-Log "Removing from system path: $Path" -Level info

    $key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"

    Write-Log "Getting current system path" -Level debug
    $current_path = (Get-ItemProperty -Path $key -Name Path).Path
    $new_path_list = New-Object System.Collections.Generic.List[String]

    Write-Log "Searching for $Path" -Level debug
    $regex_path = $Path.Replace("\", "\\")
    $removed = 0
    foreach ($item in $current_path.Split(";")) {
        # Don't add if we find the new path
        if ($item -imatch "^$regex_path(\\)?$") {
            Write-Log "Removing target path: $Path" -Level debug
            $removed = 1
        } else {
            # Add the item to our new path array
            $new_path_list.Add($item) | Out-Null
        }
    }

    if ($removed) {
        $new_path = $new_path_list -join ";"
        try {
            Write-Log "Updating system path" -Level debug
            Set-ItemProperty -Path $key -Name Path -Value $new_path
        } catch {
            $msg = "Failed to remove $Path from the system path: $new_path"
            Write-Log $msg -Level warning
            Write-Log "Tried to write: $new_path" -Level warning
            Write-Log "Error message: $_" -level warning
        }
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")
}


function Remove-FileOrFolder {
    # Removes a file or a folder recursively from the system. Takes ownership of
    # the file or directory before removing
    #
    # Used by:
    # - Remove-SaltMinion
    # - Reset-SaltMinion
    #
    # Args:
    #     Path (string): The file or folder to remove
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path
    )

    if (!(Test-Path -Path $Path)) {
        Write-Log "Path not found: $Path" -Level debug
        return
    }

    $tries = 1
    $max_tries = 5
    $success = $false
    while (!$success) {
        $msg = "Removing (try: $tries/$max_tries): $Path"
        Write-Log $msg -Level debug
        try {
            # Remove the file/dir/symlink/junction
            if ((Get-Item -Path $Path) -is [System.IO.DirectoryInfo]) {
                if (Get-IsReparsePoint -Path $Path) {
                    Write-Log "Removing reparse point" -Level debug
                    [System.IO.Directory]::Delete($Path, $true) | Out-Null
                } else {
                    Write-Log "Removing directory" -Level debug
                    # Handles nested readonly files
                    Remove-Item -Path $Path -Force -Recurse
                }
            } else {
                Write-Log "Removing file" -Level debug
                [System.IO.File]::Delete($Path) | Out-Null
            }
        } catch {
            Write-Log "Error removing: $Path" -Level warning
            Write-Log "Error message: $_" -Level warning
        } finally {
            $tries++
            if (!(Test-Path -Path $Path)) {
                Write-Log "Finished removing $Path" -Level debug
                $success = $true
            } else {
                if ($tries -gt $max_tries) {
                    Write-Log "Retry count exceeded" -Level error
                    Set-FailedStatus
                    exit $STATUS_CODES["scriptFailed"]
                }

                if ((Get-Item -Path $Path) -is [System.IO.DirectoryInfo]) {
                    Write-Log "Taking ownership: $Path" -Level debug
                    takeown /a /r /d Y /f $Path *> $null
                    if ($LASTEXITCODE) {
                        Write-Log "Directory does not exist" -Level debug
                    }
                }

                Write-Log "Trying again after 5 seconds" -Level warning
                Start-Sleep -Seconds 5
            }
        }
    }
}


function Get-GuestVars {
    # Get guestvars data using vmtoolsd.exe
    # They can be set on the host using vmrun.exe
    #
    # vmrun writeVariable "d:\VMWare\Windows Server 2019\Windows Server
    #       2019.vmx" guestVar /vmware.components.salt_minion.args
    #       "master=192.168.0.12 id=test_id"
    #
    # Used by:
    # - Get-ConfigGuestVars
    #
    # Args:
    #     GuestVarsPath (string):
    #         The option to get from the guestvars repository. Likely one of the
    #         following:
    #         - Action: guestinfo.vmware.components.salt_minion
    #         - Minion Config: guestinfo.vmware.components.salt_minion.args
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $GuestVarsPath
    )

    If ( !$vmtoolsd_bin -or !(Test-Path $vmtoolsd_bin) ) {
        $msg = "vmtoolsd.exe not found. GuestVars data will not be available"
        Write-Log $msg -Level warning
        return ""
    }

    $arguments = "--cmd `"info-get $GuestVarsPath`""

    try {
        $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
        $ProcessInfo.FileName = $vmtoolsd_bin
        $ProcessInfo.Arguments = $arguments
        $ProcessInfo.RedirectStandardError = $true
        $ProcessInfo.RedirectStandardOutput = $true
        $ProcessInfo.UseShellExecute = $false
        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $ProcessInfo
        $Process.Start() | Out-Null
        $Process.WaitForExit()
        $stdout = $Process.StandardOutput.ReadToEnd()
        $exitcode = $Process.ExitCode
    } catch {
        $msg = "vmtoolsd.exe encountered an error. " +
               "GuestVars data will not be available"
        Write-Log $msg -Level warning
        return ""
    }

    if ($exitcode -eq 0) {
        return $stdout.Trim()
    } else {
        return ""
    }
}


function _parse_config {
    # Parse config options that are in the format key=value. These can be passed
    # on the cli, guestvars, or tools.conf
    #
    # Used by:
    # - Get-ConfigCLI
    # - Get-ConfigGuestVars
    # - Get-ConfigToolsConf
    #
    # Args:
    #     KeyValues (string[])
    #         A list of string values in the key=value format
    #
    # Returns:
    #     A hash table containing the config options and their values
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String[]] $KeyValues
    )

    $config_options = @{}
    foreach ($key_value in $KeyValues.Split()) {
        if ($key_value -like "*=*") {
            Write-Log "Found config: $key_value" -Level debug
            $key, $value = $key_value -split "="
            if ($value) {
                $config_options[$key.ToLower()] = $value.ToLower()
            } else {
                Write-Log "No config value specified: $key_value" -Level warning
            }
        } else {
            Write-Log "Invalid config format ignored: $key_value" -Level warning
        }
    }
    $count = $config_options.Count
    Write-Log "Found $count config options" -Level debug
    return $config_options
}


function Get-ConfigCLI {
    # Get salt-minion configuration options from arguments passed on the
    # command line. These key/value pairs are already in the ConfigOptions
    # variable populated by the powershell cli parser. They should be a space
    # delimited list of options in the key=value format.
    #
    # Used by:
    # - Get-MinionConfig
    #
    # Return hashtable
    Write-Log "Checking for CLI config options" -Level debug
    if ($ConfigOptions) {
        return _parse_config $ConfigOptions
    } else {
        Write-Log "Minion config not passed on CLI" -Level debug
    }
}


function Get-ConfigGuestVars {
    # Get salt-minion configuration options defined in the guestvars. That
    # should be a space delimited list of options in the key=value format.
    #
    # Used by:
    # - Get-MinionConfig
    #
    # Return hashtable
    Write-Log "Checking for GuestVars config options" -Level debug
    $config_options = Get-GuestVars -GuestVarsPath $guestvars_salt_args
    if ($config_options) {
        return _parse_config $config_options
    } else {
        Write-Log "Minion config not defined in guestvars" -Level debug
    }
}


function Read-IniContent {
    # Create a hash table with values from an ini file. Each section will
    # contain a sub hash table with key/value pairs
    #
    # Used by:
    # - Get-ConfigToolsConf
    #
    # Args:
    #     FilePath (string): The location of the ini file to read
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $FilePath
    )

    if (!(Test-Path -Path $FilePath)) {
        Write-Log "File not found: $FilePath" -Level warning
        return @{}
    }

    $ini = @{}

    switch -regex -file $FilePath {
        # [Section]
        "^(?![#,;])\[(.+)\]$" {
            $section = $matches[1]
            $ini[$section.Trim()] = @{}
        }
        # key=value
        "^(?![#,;])(.+?)\s*=(.*)$" {
            $key,$value = $matches[1..2]
            $ini[$section.Trim()][$key.Trim()] = $value.Trim()
        }
    }
    return $ini
}


function Get-ConfigToolsConf {
    # Get salt-minion configuration options defined in tools.conf. That should
    # be all keys/value pairs under the [salt_minion] section of the tools.conf
    # ini file.
    #
    # Used by:
    # - Get-MinionConfig
    #
    # Return hashtable
    if ( !$vmtools_conf_file -or !(Test-Path $vmtools_conf_file) ) {
        Write-Log "tools.conf not found" -Level debug
        return @{}
    }
    $config_options = Read-IniContent -FilePath $vmtools_conf_file
    Write-Log "Checking for tools.conf config options" -Level debug
    if ($config_options.ContainsKey($guestvars_section)) {
        $count = $config_options[$guestvars_section].Count
        Write-Log "Found $count config options" -Level debug
        return $config_options[$guestvars_section]
    } else {
        Write-Log "Minion config not defined in tools.conf" -Level debug
        return @{}
    }
}


function Get-MinionConfig {
    # Get the minion config values to be placed in the minion config file. The
    # Order of priority is as follows:
    # - Get config from GuestVars (defined by VMware Tools)
    # - Get config from tools.conf (defined by VMware Tools - older method),
    #   overwrites guestVars with the same name
    # - Get config from the CLI (options passed to the script), overwrites
    #   guestVars and tools.conf settings with the same name
    # - No config found, use Salt minion defaults (master: salt, id: hostname)
    #
    # Used by:
    # - Add-MinionConfig
    #
    # Returns a hash table of options or null if no options found
    Write-Log "Getting minion config" -Level info
    $config_options = @{}
    # Get guestVars config, conflicting values will be overwritten by guestvars
    $gv_config = Get-ConfigGuestVars
    if ($gv_config) {
        foreach ($row in $gv_config.GetEnumerator()) {
            if ($row.Value) {
                $config_options[$row.Name] = $row.Value
            }
        }
    }
    # Get tools.conf config first
    $tc_config = Get-ConfigToolsConf
    if ($tc_config) {
        foreach ($row in $tc_config.GetEnumerator()) {
            if ($row.Value) {
                $config_options[$row.Name] = $row.Value
            }
        }
    }
    # Get cli config, conflicting values will be overwritten by cli
    $cli_config = Get-ConfigCLI
    if ($cli_config) {
        foreach ($row in $cli_config.GetEnumerator()) {
            if ($row.Value) {
                $config_options[$row.Name] = $row.Value
            }
        }
    }
    return $config_options
}


function Get-IsReparsePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path
    )
    $fd_path = Get-Item -Path $Path
    return [bool]($fd_path.Attributes -band [IO.FileAttributes]::ReparsePoint)
}


function Get-IsSecureOwner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path
    )

    $acl = Get-Acl -Path $Path
    $owner = (($acl | Select-Object Owner).Owner).ToLower()
    if ($owner -eq "nt authority\system") {
        return $true
    }
    if ($owner -eq "builtin\administrators") {
        return $true
    }
    return $false
}


function Set-Security {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path,

        [Parameter(Mandatory=$false)]
        [String] $Owner = "BUILTIN\Administrators"
    )

    Write-Log "Setting Security: $Path" -Level info

    Write-Log "Getting ACL: $Path" -Level debug
    $path_acl = Get-Acl -Path $Path

    Write-Log "Setting Sddl" -Level debug
    $Sddl = 'D:PAI(A;OICI;0x1200a9;;;WD)(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
    $path_acl.SetSecurityDescriptorSddlForm($Sddl)

    Write-Log "Setting Owner" -Level debug
    $path_acl.SetOwner([System.Security.Principal.NTAccount]"$Owner")

    Write-Log "Writing New ACL" -Level debug
    Set-Acl -Path $Path -AclObject $path_acl
}


function New-SecureDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [String] $Path
    )
    if (Test-Path -Path $Path) {
        if (Get-IsReparsePoint -Path $Path) {
            Write-Log "Found reparse point: $Path" -Level warning
            Write-Log "Renaming reparse point (.insecure): $Path" -Level warning
            Move-item -Path $Path `
                    -Destination "$Path-$script_date.insecure" | Out-Null
            $msg = "Insecure reparse point renamed: $Path-$script_date.insecure"
            Write-Log $msg -Level debug
        }
    }

    if (Test-Path -Path $Path) {
        if (!(Get-IsSecureOwner -Path $Path)) {
            Write-Log "Found insecure owner: $Path" -Level warning
            Write-Log "Renaming file/dir (.insecure): $Path" -Level warning
            Move-Item -Path $Path `
                    -Destination "$Path-$script_date.insecure" | Out-Null
            $msg = "Insecure file/dir renamed: $Path-$script_date.insecure"
            Write-Log $msg -Level debug
        }
    }

    $tries = 1
    $max_tries = 5
    while ($true) {

        # Remove any existing file or directory if it exists
        if (Test-Path -Path $Path) {
            Write-Log "Removing existing file/directory: $Path" -Level debug
            Remove-FileOrFolder -Path $Path
        }

        $msg = "Creating secure directory (try: $tries/$max_tries): $Path"
        Write-Log $msg -Level debug
        try {
            New-Item -Path $Path -Type Directory | Out-Null
        } catch {
            if ($tries -le $max_tries) {
                $msg = "Failed to create directory: $Path. Trying again..."
                Write-Log $msg -Level warning
                $tries++
                continue
            } else {
                $msg = "Failed to create secure directory. Try limit exceeded."
                Write-Log $msg -Level error
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }

        Set-Security -Path $Path

        if((Get-ChildItem -Path $Path | Measure-Object).Count -ne 0) {
            # Someone is competing with us
            if ($tries -le $max_tries) {
                $msg = "Expected empty directory. Trying again..."
                Write-Log $msg -Level warning
                $tries += 1
                continue
            } else {
                $msg = "Expected empty directory. Try limit exceeded."
                Write-Log $msg -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
        Write-Log "Secure directory created successfully" -Level debug
        break
    }
}


function Add-MinionConfig {
    # Write minion config options to the minion config file

    # Child directories will inherit permissions from the parent
    if ( !( Test-Path -path $salt_root_dir ) ) {
        New-Item -Path $salt_root_dir -Type Directory | Out-Null
    }
    if ( !( Test-Path -path $salt_config_dir ) ) {
        New-Item -Path $salt_config_dir -Type Directory | Out-Null
    }
    if ( !( Test-Path -path $salt_pki_dir ) ) {
        New-Item -Path "$salt_pki_dir" -Type Directory | Out-Null
    }
    if ( !( Test-Path -path $salt_log_dir ) ) {
        New-Item -Path "$salt_log_dir" -Type Directory | Out-Null
    }

    # Create additional directories
    $cache_dir = "$salt_root_dir\var\cache\salt\minion"
    if ( !( Test-Path -path "$salt_config_dir\minion.d" ) ) {
        New-Item -Path "$salt_config_dir\minion.d" -Type Directory | Out-Null
    }
    if ( !( Test-Path -path "$cache_dir\extmods\grains" ) ) {
        New-Item -Path "$cache_dir\extmods\grains" -Type Directory | Out-Null
    }
    if ( !( Test-Path -path "$cache_dir\proc" ) ) {
        New-Item -Path "$cache_dir\proc" -Type Directory | Out-Null
    }
    if ( !( Test-Path -path "$salt_root_dir\var\run" ) ) {
        New-Item -Path "$salt_root_dir\var\run" -Type Directory | Out-Null
    }

    # Get the minion config
    $config_options = Get-MinionConfig

    if ($config_options.Count -eq 0) {
        Write-Log "No minion config found. Defaults will be used" -Level debug
    }

    # These settings are for pre 3004 versions of Salt
    # Add root_dir to point to ProgramData
    $config_options["root_dir"] = $salt_root_dir
    # Add log_file to point to ProgramData
    $config_options["log_file"] = "$salt_log_dir\minion"

    $new_content = New-Object System.Collections.Generic.List[String]
    $comment = "# Minion configuration file - created by VMTools Salt script"
    $new_content.Add($comment)
    foreach ($row in $config_options.GetEnumerator()) {
        $new_content.Add("$($row.Name): $($row.Value)") | Out-Null
    }
    $config_content = $new_content -join "`r`n"
    try {
        Write-Log "Writing minion config" -Level info
        Set-Content -Path $salt_config_file -Value $config_content
        Write-Log "Finished writing minion config" -Level debug
    } catch {
        $msg = "Failed to write minion config: $config_content : $_"
        Write-Log $msg -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }
}


function Start-MinionService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [String] $ServiceName = "salt-minion"
    )

    try {
        $service = Get-Service -Name $ServiceName
    } catch {
        switch ($_.FullyQualifiedErrorId.Split(",")[0]) {
            "NoServiceFoundForGivenName" {
                # We'll hard fail here because the service is not present
                Write-Log "$ServiceName is not installed" -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
            Default {
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
    }

    # Not sure this is needed as the Start-Service cmdlet seems to wait until
    # the service is started before returning
    $tries = 1
    $max_tries = 5
    while ($service.Status -ne "Running") {
        if ($service.Status -eq "Stopped") {
            # Start the minion service
            Write-Log "Starting the $ServiceName service" -Level info
            try {
                Start-Service -Name $ServiceName *> $null
            } catch {
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
        $service.Refresh()
        if ($service.Status -eq "Running") {
            Write-Log "Service started successfully" -Level debug
        } else {
            if ($tries -le $max_tries) {
                $msg = "Service not started. Waiting 1 second to try again..."
                Write-Log $msg -Level debug
                $tries += 1
                Start-Sleep -Seconds 1
            } else {
                $msg = "Failed to start the $ServiceName service. "
                $msg += "Exceeded max tries"
                Write-Log $msg -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
    }
}


function Get-ServiceStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [String] $ServiceName = "salt-minion"
    )

    try {
        $service = Get-Service -Name $ServiceName
    } catch {
        switch ($_.FullyQualifiedErrorId.Split(",")[0]) {
            "NoServiceFoundForGivenName" {
                # We'll return here because we don't need to stop a service that
                # isn't installed
                Write-Log "$ServiceName is not installed" -Level info
                return
            }
            Default {
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
    }
    return $service.Status
}


function Stop-MinionService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [String] $ServiceName = "salt-minion"
    )

    try {
        $service = Get-Service -Name $ServiceName
    } catch {
        switch ($_.FullyQualifiedErrorId.Split(",")[0]) {
            "NoServiceFoundForGivenName" {
                # We'll return here because we don't need to stop a service that
                # isn't installed
                Write-Log "$ServiceName is not installed" -Level info
                return
            }
            Default {
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
    }

    # Not sure this is needed as the Stop-Service cmdlet seems to wait until
    # the service is stopped before returning
    $tries = 1
    $max_tries = 5
    while ($service.Status -ne "Stopped") {
        if (($service.Status -eq "Running") -or `
                ($service.Status -eq "Paused")) {
            # Start the minion service
            Write-Log "Stop the $ServiceName service" -Level info
            try {
                Stop-Service -Name $ServiceName *> $null
            } catch {
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
        $service.Refresh()
        if ($service.Status -eq "Stopped") {
            Write-Log "Service stopped successfully" -Level debug
        } else {
            if ($tries -le $max_tries) {
                $msg = "Service not stopped. Waiting 1 second to try again..."
                Write-Log $msg -Level debug
                $tries += 1
                Start-Sleep -Seconds 1
            } else {
                $msg = "Failed to stop the $ServiceName service. "
                $msg += "Exceeded max tries"
                Write-Log $msg -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
    }
}


function Get-RandomizedMinionId {
    # Generate a randomized minion id
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [String] $Prefix = "minion",

        [Parameter(Mandatory=$false)]
        [String] $Length = 5
    )
    $chars = (0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A)
    $rand_chars = $chars | Get-Random -Count $Length
    $rand_string = -join ($rand_chars | ForEach-Object {[char]$_})
    return -join ($Prefix, "_", $rand_string)
}


############################### MAIN FUNCTIONS #################################


function Confirm-Dependencies {
    # Check that the required dependencies for this script are present on the
    # system
    #
    # Return:
    #     Bool: False if missing dependencies, otherwise True
    $deps_present = $true
    Write-Log "Checking dependencies" -Level info

    # Files required by this script
    $salt_dep_files = @{}
    # $salt_dep_files["dep_name.exe"] = "path\to\dep_name.exe"

    foreach ($file in $salt_dep_files.Keys) {
        Write-Log "Looking for $file in $($salt_dep_files[$file])" -Level debug
        if(!(Test-Path("$($salt_dep_files[$file])\$file"))) {
            $msg = "Unable to find $file in $($salt_dep_files[$file])"
            Write-Log $msg -Level error
            $deps_present = $false
        }
    }

    return $deps_present
}


function Get-SaltVersion {
    # This function is needed for unit testing
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path
    )

    if ( Test-Path -Path "$Path\salt-call.exe" ) {
        # 3006 and later packages
        Write-Log "Running: $Path\salt-call.exe" -Level debug
        $ver = . $Path\salt-call.exe --version
    } elseif ( Test-Path -Path "$Path\bin\python.exe" ) {
        # Pre 3006 Packages
        $python_bin = "$Path\bin\python.exe"
        Write-Log "Running: $python_bin" -Level debug
        $ver = . $python_bin -E -s $Path\bin\Scripts\salt-call --version
    } elseif ( Test-Path -Path "$Path\bin\salt.exe" ) {
        # Tiamat Packages
        Write-Log "Running: $Path\bin\salt.exe" -Level debug
        $ver = . $Path\bin\salt.exe --version
    }
    return $ver.Trim("salt-call ")
}


function Find-StandardSaltInstallation {
    # Find an existing standard Salt installation
    #
    # Return:
    #     Bool: True if standard installation found, otherwise False

    # First we'll look for the install_dir registry entry
    # If we find that, we'll use it to detect the version
    # This works for 3004 and newer versions of Salt
    try {
        $dir_path = (Get-Item -Path $salt_base_reg).GetValue("install_dir")
    } catch {}
    if ($null -ne $dir_path) {
        $dir_path = [System.Environment]::ExpandEnvironmentVariables($dir_path)
        if ( Test-Path -Path $dir_path ) {
            $version = Get-SaltVersion -Path $dir_path
            Write-Log "Standard Installation detected" -Level error
            Write-Log "Version: $version" -Level error
            Write-Log "Path: $dir_path" -Level error
            return $true
        }
    }

    # We'll look in the old C:\salt location for python.exe
    # This handles all older versions of Salt
    if (Test-Path -Path "C:\salt\bin\python.exe") {
        $version = Get-SaltVersion -Path "C:\salt"
        Write-Log "Standard Installation detected" -Level error
        Write-Log "Version: $version" -Level error
        Write-Log "Path: C:\salt" -Level error
        return $true
    }
    Write-Log "Standard Installation not detected" -Level debug
    return $false
}


function Get-MajorVersion {
    # Parses a version string and returns the major version
    #
    # Args:
    #     Version (string): The Version to parse
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [String] $Version
    )
    return ( $Version -split "\." )[0]
}


function Get-AvailableVersions {
    # Get available versions from a remote location specified in the Source
    # Parameter
    Write-Log "Getting version information from Source" -Level debug
    Write-Log "base_url: $base_url" -Level debug

    $available_versions = [System.Collections.ArrayList]@()

    if ( $base_url.StartsWith("http") -or $base_url.StartsWith("ftp") ) {
        # We're dealing with HTTP, HTTPS, or FTP
        $response = Invoke-WebRequest "$base_url" -UseBasicParsing
        try {
            $response = Invoke-WebRequest "$base_url" -UseBasicParsing
        } catch {
            Write-Log "Failed to get version information" -Level error
            Set-FailedStatus
            exit $STATUS_CODES["scriptFailed"]
        }

        if ( $response.StatusCode -ne 200 ) {
            Write-Log "There was an error getting version information" -Level error
            Write-Log "Error: $($response.StatusCode)" -Level error
            Set-FailedStatus
            exit $STATUS_CODES["scriptFailed"]
        }

        $response.links | ForEach-Object {
            if ( $_.href.Length -gt 8) {
                Write-Log "The content at this location is unexpected" -Level error
                Write-Log "Should be a list of directories where the" -Level error
                Write-Log "name is a version of Salt" -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }

        # Getting available versions from response
        Write-Log "Getting available versions from response" -Level debug
        $filtered = $response.Links | Where-Object -Property href -NE "../"
        $filtered | Select-Object -Property href | ForEach-Object {
            $available_versions.Add($_.href.Trim("/")) | Out-Null
        }
    } elseif ( $base_url.StartsWith("\\") -or $base_url -match "^[A-Za-z]:\\" ) {
        # We're dealing with a local directory or SMB source
        Get-ChildItem -Path $base_url -Directory | ForEach-Object {
            $available_versions.Add($_.Name) | Out-Null
        }
    } else {
        Write-Log "Unknown Source Type" -Level error
        $msg = "Must be one of HTTP, HTTPS, FTP, SMB Share, Local Directory"
        Write-Log $msg -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }

    Write-Log "Available versions:" -Level debug
    $available_versions | ForEach-Object {
        Write-Log "- $_" -Level debug
    }

    # Get the latest version, should be the last in the list
    Write-Log "Getting latest available version" -Level debug
    $latest = $available_versions | Select-Object -Last 1
    Write-Log "Latest available version: $latest" -Level debug

    # Create a versions table
    # This will have the latest version available, the latest version available
    # for each major version, and every version available. This makes the
    # version lookup logic easier. The contents of the versions table can be
    # found in the log or by passing -LogLevel debug
    Write-Log "Populating the versions table" -Level debug
    $versions_table = [ordered]@{"latest"=$latest}
    $available_versions | ForEach-Object {
        $versions_table[$(Get-MajorVersion $_)] = $_
        $versions_table[$_.ToLower()] = $_.ToLower()
    }

    Write-Log "Versions Table:" -Level debug
    $versions_table | Sort-Object Name | Out-String | ForEach-Object {
        Write-Log "$_" -Level debug
    }

    # Validate passed version
    Write-Log "Looking up version: $MinionVersion" -Level debug
    if ( $versions_table.Contains($MinionVersion.ToLower()) ) {
        $MinionVersion = $versions_table[$MinionVersion.ToLower()]
        Write-Log "Found version: $MinionVersion" -Level debug
    } else {
        Write-Log "Version $MinionVersion is not available" -Level error
        Write-Log "Available versions are:" -Level error
        $available_versions | ForEach-Object { Write-Log "- $_" -Level debug }
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }

    return $versions_table
}


function Get-HashFromArtifactory {
    # This function uses the artifactory API to get the SHA265 Hash for the file
    # If Source is NOT artifactory, the sha will not be checked
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $SaltVersion,

        [Parameter(Mandatory=$true)]
        [String] $SaltFileName
    )
    #
    if ( $api_url ) {
        $full_url = "$api_url/$SaltVersion/$SaltFileName"
        Write-Log "Querying Artifactory API for hash:" -Level debug
        Write-Log $full_url
        try {
            $response = Invoke-RestMethod $full_url -UseBasicParsing
            return $response.checksums.sha256
        } catch {
            Write-Log "Artifactory API Not available or file not" -Level debug
            Write-Log "available at specified location" -Level debug
            Write-Log "Hash will not be checked"
            return ""
        }
        Write-Log "No hash found for this file: $SaltFileName" -Level debug
        Write-Log "Hash will not be checked"
        return ""
    }
    Write-Log "No artifactory API defined" -Level debug
    Write-Log "Hash will not be checked"
    return ""
}


function Get-SaltPackageInfo {
    # We don't get repo.json anymore, now we parse the html at the Source.
    # Need to get the available versions and then check if hash is available
    # using the artifactory api. We'll use it if available, otherwise we'll
    # log that the hash isn't available and continue
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $MinionVersion
    )

    # Getting available versions from Source
    $versions = Get-AvailableVersions

    # Make sure the passed version is available
    $salt_file_name = ""
    $salt_sha256 = ""
    $salt_version = ""
    $salt_url = ""
    if ( $versions.Contains($MinionVersion.ToLower()) ) {
        $salt_version = $versions[$MinionVersion.ToLower()]
        # Since we only support 64 bit we don't need the arch
        $salt_file_name = "salt-$salt_version-onedir-windows-amd64.zip"
        $salt_url = "$base_url/$salt_version/$salt_file_name"
        Write-Log "File Name: $salt_file_name" -Level debug
        Write-Log "Salt Vers: $salt_version" -Level debug
        Write-Log "Salt url : $salt_url" -Level debug
        $salt_sha256 = Get-HashFromArtifactory -SaltVersion $salt_version `
                                               -SaltFileName $salt_file_name
        Write-Log "Salt hash: $salt_sha256" -Level debug
    } else {
        Write-Log "Version $MinionVersion is not available" -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }
    return @{
        url = $salt_url;
        hash = $salt_sha256;
        file_name = $salt_file_name;
        version = $salt_version
    }
}


function Get-FileHash {
    # Get-FileHash is a built-in cmdlet in powershell 5+ but we need to support
    # powershell 3. This will overwrite the powershell 5 commandlet only for
    # this script. But it will provide the missing cmdlet for powershell 3
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path,

        [Parameter(Mandatory=$false)]
        [ValidateSet(
                "SHA1",
                "SHA256",
                "SHA384",
                "SHA512",
                # https://serverfault.com/questions/820300/
                # why-isnt-mactripledes-algorithm-output-in-powershell-stable
                "MACTripleDES", # don't use
                "MD5",
                "RIPEMD160",
                IgnoreCase=$true)]
        [String] $Algorithm = "SHA256"
    )

    if ( !(Test-Path $Path) ) {
        Write-Log "Invalid path for hashing: $Path" -Level debug
        return @{}
    }

    if ( (Get-Item -Path $Path) -isnot [System.IO.FileInfo]) {
        Write-Log "Not a file for hashing: $Path" -Level debug
        return @{}
    }

    $Path = Resolve-Path -Path $Path

    Switch ($Algorithm) {
        SHA1 {
            # We're doing this in 2 lines to comply with the 80 char limit
            $hasher = [System.Security.Cryptography.SHA1CryptoServiceProvider]
            $hasher = $hasher::Create()
        }
        SHA256 {
            $hasher = [System.Security.Cryptography.SHA256]::Create()
        }
        SHA384 {
            $hasher = [System.Security.Cryptography.SHA384]::Create()
        }
        SHA512 {
            $hasher = [System.Security.Cryptography.SHA512]::Create()
        }
        MACTripleDES {
            $hasher = [System.Security.Cryptography.MACTripleDES]::Create()
        }
        MD5 {
            $hasher = [System.Security.Cryptography.MD5]::Create()
        }
        RIPEMD160 {
            $hasher = [System.Security.Cryptography.RIPEMD160]::Create()
        }
    }

    Write-Log "Hashing using $Algorithm algorithm" -Level debug
    try {
        $data = [System.IO.File]::OpenRead($Path)
        $hash = $hasher.ComputeHash($data)
        $hash = [System.BitConverter]::ToString($hash) -replace "-",""
        return @{
            Path = $Path;
            Algorithm = $Algorithm.ToUpper();
            Hash = $hash
        }
    } catch {
        Write-Log "Error hashing: $Path" -Level debug
        return @{}
    } finally {
        if ($null -ne $data) {
            $data.Close()
        }
    }
}


function Get-SaltFromWeb {
    # Download the Salt OneDir zip file from the web and verify the hash
    #
    # Error:
    #     Sets the failed status and exits with a scriptFailed exit code
    #
    # Make sure the download directory exists
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Url,

        [Parameter(Mandatory=$true)]
        [String] $Destination,

        [Parameter(Mandatory=$false)]
        [String] $Hash
    )

    # Download the Salt file
    Write-Log "Downloading Salt" -Level info
    Get-WebFile -Url $Url -OutFile $Destination

    # We only check the hash if we got a hash from Artifactory
    if ( $Hash ) {
        # Get the hash for the Salt file
        $file_hash = (Get-FileHash -Path $Destination -Algorithm SHA256).Hash

        Write-Log "Verifying hash" -Level info
        if ($file_hash -like $Hash) {
            Write-Log "Hash verified" -Level debug
        } else {
            Write-Log "Failed to verify hash:" -Level error
            Write-Log "  - $file_hash" -Level error
            Write-Log "  - $Hash" -Level error
            Set-FailedStatus
            exit $STATUS_CODES["scriptFailed"]
        }
    }
}


function Install-SaltMinion
{
    # Installs the Salt minion. Performs the following:
    # - Expands the zipfile into C:\Program Files\Salt Project
    # - Registers and configures the salt-minion service
    #
    # Error:
    #     Sets the failed status and exits with a scriptFailed exit code

    # 1. Unzip into Program Files
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path,

        [Parameter(Mandatory=$true)]
        [String] $Version
    )
    Write-Log "Unzipping Salt (this may take a few minutes)" -Level info
    Expand-ZipFile -ZipFile $Path -Destination $base_salt_install_location

    Write-Log "Removing zipfile: $Path" -Level debug
    Remove-Item -Path $Path

    # 2. Register the salt-minion service
    Write-Log "Registering the salt-minion service ($Version)" -Level info
    & $ssm_bin install salt-minion "$salt_minion_bin" `
                "-c """"$salt_config_dir"""" -l quiet" *> $null
    $description = "Salt Minion from VMware Tools ($Version)"
    & $ssm_bin set salt-minion Description $description *> $null

    # Common service settings
    Write-Log "Configuring the salt-minion service" -Level info
    & $ssm_bin set salt-minion Start SERVICE_AUTO_START *> $null
    & $ssm_bin set salt-minion AppStopMethodConsole 24000 *> $null
    & $ssm_bin set salt-minion AppStopMethodWindow 2000 *> $null
    & $ssm_bin set salt-minion AppRestartDelay 60000 *> $null

    # 3. Verify that the service is installed
    try {
        Get-Service -Name salt-minion
        Write-Log "salt-minion service installed successfully" -Level debug
    } catch {
        switch ($_.FullyQualifiedErrorId.Split(",")[0]) {
            "NoServiceFoundForGivenName" {
                $msg = "Failed to install salt-minion service"
                Write-Log $msg -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
            Default {
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
    }

    # 4. Modify the system path
    Write-Log "Adding Salt to the path" -Level info
    Add-SystemPathValue -Path $salt_dir
}


function Remove-SaltMinion {
    # Uninstall the Salt minion. Performs the following steps:
    # - Stop the salt-minion service
    # - Remove the salt-minion service
    # - Remove the directories in Program Files and ProgramData
    # - Remove the registry entries
    # - Remove the entry from the system path
    #
    # Error:
    #     Sets the failed status and exits with a scriptFailed exit code

    # Does the service exist

    try {
        # This command will throw an exception if the service is missing
        $service = Get-Service -Name salt-minion

        # Stop the minion service
        Stop-MinionService

        # Delete the service
        Write-Log "Uninstalling salt-minion service" -Level info
        $service = Get-WmiObject -Class Win32_Service `
                                 -Filter "Name='salt-minion'"
        $service.delete() *> $null

        try {
            # This command will throw an exception if the service is missing
            $service = Get-Service -Name salt-minion

            # If we were able to connect to the service, no exception thrown,
            # then we failed to remove the service
            Write-Log "Failed to uninstall salt-minion service" -Level error
            Set-FailedStatus
            exit $STATUS_CODES["scriptFailed"]
        } catch {
            # This would catch a missing service after the removal meaning the
            # service was removed successfully
            switch ($_.FullyQualifiedErrorId.Split(",")[0]) {
                "NoServiceFoundForGivenName" {
                    $msg = "Finished uninstalling salt-minion service"
                    Write-Log $msg -Level debug
                }
                Default {
                    Write-Log $_ -Level error
                    Set-FailedStatus
                    exit $STATUS_CODES["scriptFailed"]
                }
            }
        }
    } catch {
        # This would catch a missing service before trying to Stop and Remove it
        # That would mean the service is already removed
        switch ($_.FullyQualifiedErrorId.Split(",")[0]) {
            "NoServiceFoundForGivenName" {
                # We'll return here because we don't need to remove a service
                # that isn't installed
                Write-Log "salt-minion service not found" -Level debug
            }
            Default {
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
    }

    # 3. Remove the files
    if ($Upgrade) {
        # Just remove the program files on an upgrade
        Remove-FileOrFolder -Path $base_salt_install_location
    } else {
        # Do this in a for loop for logging
        foreach ($item in $file_dirs_to_remove) {
            Remove-FileOrFolder -Path $item
        }
    }

    # 4. Remove entry from the path
    Remove-SystemPathValue -Path $salt_dir
}


function Reset-SaltMinion {
    # Resets the salt-minion environment in preperation for imaging. Performs
    # the following steps:
    # - Remove minion_id file
    # - Randomize the minion id in the minion config
    # - Remove the minion public and private keys

    Write-Log "Resetting Salt minion" -Level info

    # Remove the minion_id file
    Remove-FileOrFolder "$salt_config_file\minion_id"

    # Remove the minion.d directory
    Remove-FileOrFolder "$salt_config_dir\minion.d"

    # Comment out id: in the minion config
    $new_content = New-Object System.Collections.Generic.List[String]
    if (Test-Path -Path "$salt_config_file") {
        Write-Log "Searching minion config file for id" -Level debug
        foreach ($line in Get-Content $salt_config_file) {
            if ($line -match "^id:.*$") {
                Write-Log "Commenting out the id" -Level debug
                $new_content.Add("#" + $line) | Out-Null
                $random_id = Get-RandomizedMinionId -Prefix $line.Split("")[1]
                $new_content.Add("id: $random_id") | Out-Null
            } else {
                $new_content.Add($line) | Out-Null
            }
        }
        $config_content = $new_content -join "`r`n"
        Write-Log "Writing new minion config"
        try {
            Set-Content -Path $salt_config_file -Value $config_content
        } catch {
            Write-Log "Failed to write new minion config : $_" -Level error
            exit $STATUS_CODES["scriptFailed"]
        }
    }

    # Remove minion keys (minion.pem and minion.pub"
    Remove-FileOrFolder -Path "$salt_pki_dir\minion.pem"
    Remove-FileOrFolder -Path "$salt_pki_dir\minion.pub"

    Write-Log "Salt minion reset successfully" -Level info
}


function Install {
    # Set status and update the log
    Write-Log "Installing Salt minion" -Level info
    Set-Status installing

    # Make sure the base install location exists
    if ( !( Test-Path -Path $base_salt_install_location) ) {
        Write-Log "Creating directory: $base_salt_install_location" -Level debug
        New-Item -Path $base_salt_install_location -Type Directory | Out-Null
    }

    # Get URL from Source
    $info = Get-SaltPackageInfo -MinionVersion $MinionVersion

    if ($info.Count -eq 0) {
        $msg = "Failed to get Package Info for Version: $MinionVersion"
        Write-Log $msg -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }

    # We need to remove the previous minion before we do anything else since
    # this will remove the Program Files directory
    Remove-SaltMinion

    $zip_file = "$base_salt_install_location\$($info.file_name)"

    # Download Salt from the Web
    Get-SaltFromWeb -Url $info.url -Destination $zip_file -Hash $info.hash

    # Install the Salt Package
    Install-SaltMinion -Path $zip_file -Version $info.version

    # If it is not an upgrade, add config
    # If it is an upgrade but the path doesn't exist, add config
    # Otherwise, don't touch the config
    if ( (! $Upgrade) -or ( ! (Test-Path -Path $base_salt_config_location) ) ) {

        # New-SecureDirectory will handle reparse points and ownership issues
        New-SecureDirectory -Path $base_salt_config_location

        # Generate and update the minion config
        Add-MinionConfig
    }

    # Start the Minion Service
    Start-MinionService

    # Update the Status and output the Log
    Set-Status installed
    Write-Log "Salt minion installed successfully" -Level info
}


function Reconfigure {
    # Set status and update the log
    Write-Log "Reconfiguring the Salt minion" -Level info

    # Generate and update the minion config
    Add-MinionConfig

    # Stop the Minion Service
    Stop-MinionService

    # Start the Minion Service
    Start-MinionService

    # Update the Status and output the Log
    Write-Log "Salt minion configured successfully" -Level info
}


function Remove {
    Write-Log "Removing Salt minion" -Level info
    Set-Status removing
    Remove-SaltMinion
    Set-Status notInstalled
    Write-Log "Salt minion removed successfully" -Level info
}


################################### MAIN #######################################
function Main {
    # Check for Action. If not specified on the command line, get it from
    # guestVars
    if ($Install) { $Action = "install" }
    if ($Reconfig) { $Action = "reconfig" }
    if ($Status) { $Action = "status" }
    if ($Depend) { $Action = "depend" }
    if ($Clear) { $Action = "clear" }
    if ($Remove) { $Action = "remove" }
    if ($Stop) { $Action = "stop" }
    if ($Start) { $Action = "start" }
    if (!$Action) {
        # We're not logging yet because we don't know the status
        $Action = Get-GuestVars -GuestVarsPath $guestvars_salt_desired_state
        if (!$Action) {
            $msg = "No action found in guestVars or specified on CLI"
            Write-Log $msg -Level error
            Write-Host $msg -ForegroundColor Red
            Write-Host "Please specify an action" -ForegroundColor Yellow
            return $STATUS_CODES["scriptFailed"]
        }
        switch ($Action.ToLower()) {
            "present" { $Action = "install" }
            "absent" { $Action = "remove" }
        }
    }

    if (!($action_list -contains $Action.ToLower())) {
        $msg = "Invalid action: $Action - Must be one of [$action_list]"
        Write-Log $msg -Level error
        Write-Host $msg -ForegroundColor Red
        Write-Host "Please specify a valid action" -ForegroundColor Yellow
        return $STATUS_CODES["scriptFailed"]
    }

    # Let's confirm dependencies
    if (!(Confirm-Dependencies)) {
        Write-Log "Missing script dependencies" -Level error
        Write-Host "Missing script dependencies" -ForegroundColor Red
        return $STATUS_CODES["scriptFailed"]
    }

    # Perform the action
    switch ($Action.ToLower()) {
        "stop" {
            # If not installed (0), bail out
            $current_status = Get-Status
            if ($STATUS_CODES.keys -notcontains $current_status) {
                $msg = "Unknown status code: $current_status"
                Write-Log $msg -Level error
                return $STATUS_CODES["scriptFailed"]
            }
            if ( $current_status -eq $STATUS_CODES["installedStopped"] ) {
                Write-Host "Service already stopped"
                return $STATUS_CODES["scriptSuccess"]
            }
            if ( $current_status -ne $STATUS_CODES["installed"] ) {
                Write-Host "Not installed. Stop will not continue"
                return $STATUS_CODES["scriptSuccess"]
            }
            Stop-MinionService
            Write-Host "Salt minion stopped successfully"
            return $STATUS_CODES["scriptSuccess"]
        }
        "start" {
            # If not installed (0), bail out
            $current_status = Get-Status
            if ($STATUS_CODES.keys -notcontains $current_status) {
                $msg = "Unknown status code: $current_status"
                Write-Host $msg -Level error
                return $STATUS_CODES["scriptFailed"]
            }
            $valid = @(
                $STATUS_CODES["installed"],
                $STATUS_CODES["installedStopped"]
            )
            if ( $valid -notcontains $current_status ) {
                Write-Host "Not installed. Start will not continue"
                return $STATUS_CODES["scriptSuccess"]
            }
            $service_status = Get-ServiceStatus
            $verb = "started"
            if ( $service_status -eq "Running" ) {
                $verb = "restarted"
            }
            Stop-MinionService
            Start-MinionService
            Write-Host "Salt minion $verb successfully"
            return $STATUS_CODES["scriptSuccess"]
        }
        "depend" {
            # If we've gotten this far, dependencies have been confirmed
            Write-Host "Found all dependencies"
            return $STATUS_CODES["scriptSuccess"]
        }
        "install" {
            # Let's make sure there's not already a standard Salt installation
            # on the system
            if (Find-StandardSaltInstallation) {
                $msg = "Found an existing Salt installation on the system."
                Write-Log $msg -Level error
                Write-Host $msg -ForegroundColor Red
                return $STATUS_CODES["externalInstall"]
            }
            $current_status = Get-Status
            if ($STATUS_CODES.keys -notcontains $current_status) {
                $msg = "Unknown status code: $current_status"
                Write-Log $msg -Level error
                Write-Host $msg -ForegroundColor Red
                return $STATUS_CODES["scriptFailed"]
            }
            # If status is "installed", "installing", or "removing", bail out
            switch ($current_status) {
                $STATUS_CODES["installed"] {
                    if (! $Upgrade) {
                        Write-Host "Already installed"
                        return $STATUS_CODES["scriptSuccess"]
                    }
                }
                $STATUS_CODES["installedStopped"] {
                    if (! $Upgrade) {
                        Write-Host "Already installed, but stopped"
                        return $STATUS_CODES["scriptSuccess"]
                    }
                }
                $STATUS_CODES["installing"] {
                    Write-Host "Installation in progress"
                    return $STATUS_CODES["scriptFailed"]
                }
                $STATUS_CODES["removing"] {
                    Write-Host "Removal in progress"
                    return $STATUS_CODES["scriptFailed"]
                }
                $STATUS_CODES["removeFailed"] {
                    # We want to clean up anything left behind by a failed
                    # remove
                    Remove
                }
                $STATUS_CODES["installFailed"] {
                    # We want to clean up anything left behind by a failed
                    # install
                    Remove
                }
            }
            Install
            Write-Host "Salt minion installed successfully"
            return $STATUS_CODES["scriptSuccess"]
        }
        "reconfig" {
            # Let's make sure there's not a standard Salt installation on the
            # system
            if (Find-StandardSaltInstallation) {
                $msg = "Found an existing Salt installation on the system."
                Write-Log $msg -Level error
                Write-Host $msg -ForegroundColor Red
                return $STATUS_CODES["externalInstall"]
            }
            $current_status = Get-Status
            if ($STATUS_CODES.keys -notcontains $current_status) {
                $msg = "Unknown status code: $current_status"
                Write-Log $msg -Level error
                Write-Host $msg -ForegroundColor Red
                return $STATUS_CODES["scriptFailed"]
            }
            # If status is not "installed", bail out
            $valid = @(
                $STATUS_CODES["installed"],
                $STATUS_CODES["installedStopped"]
            )
            if ( $valid -notcontains $current_status ) {
                Write-Host "Not installed. Reconfig will not continue"
                return $STATUS_CODES["scriptSuccess"]
            }
            Reconfigure
            Write-Host "Salt minion reconfigured successfully"
            return $STATUS_CODES["scriptSuccess"]
        }
        "remove" {
            # Let's make sure we're not trying to remove a standard Salt
            # installation on the system
            if (Find-StandardSaltInstallation) {
                $msg = "Found an existing Salt installation on the system."
                Write-Log $msg -Level error
                Write-Host $msg -ForegroundColor Red
                return $STATUS_CODES["externalInstall"]
            }
            # If status is installing, notInstalled, or removing, bail out
            $current_status = Get-Status
            if ($STATUS_CODES.keys -notcontains $current_status) {
                $msg = "Unknown status code: $current_status"
                Write-Host $msg -Level error
                return $STATUS_CODES["scriptFailed"]
            }
            switch ($current_status) {
                $STATUS_CODES["installing"] {
                    Write-Host "Installation in progress"
                    return $STATUS_CODES["scriptFailed"]
                }
                $STATUS_CODES["notInstalled"] {
                    Write-Host "Already uninstalled"
                    return $STATUS_CODES["scriptSuccess"]
                }
                $STATUS_CODES["removing"] {
                    Write-Host "Removal in progress"
                    return $STATUS_CODES["scriptFailed"]
                }
            }
            Remove
            Write-Host "Salt minion removed successfully"
            return $STATUS_CODES["scriptSuccess"]
        }
        "clear" {
            # If not installed (0), bail out
            $current_status = Get-Status
            if ($STATUS_CODES.keys -notcontains $current_status) {
                $msg = "Unknown status code: $current_status"
                Write-Host $msg -Level error
                return $STATUS_CODES["scriptFailed"]
            }
            $valid = @(
                $STATUS_CODES["installed"],
                $STATUS_CODES["installedStopped"]
            )
            if ( $valid -notcontains $current_status ) {
                Write-Host "Not installed. Reset will not continue"
                return $STATUS_CODES["scriptSuccess"]
            }
            Reset-SaltMinion
            Write-Host "Salt minion reset successfully"
            return $STATUS_CODES["scriptSuccess"]
        }
        "status" {
            # Let's check for a standard Salt installation first
            if (Find-StandardSaltInstallation) {
                $msg = "Found an existing Salt installation on the system."
                Write-Log $msg -Level error
                Write-Host $msg -ForegroundColor Red
                return $STATUS_CODES["externalInstall"]
            }
            $exit_code = Get-Status
            if ($STATUS_CODES.keys -notcontains $exit_code) {
                Write-Host "Unknown status code: $exit_code"
                return $STATUS_CODES["scriptFailed"]
            }
            Write-Host "Found status: $($STATUS_CODES[$exit_code])"
            return $exit_code
        }
    }
}

# Allow importing for testing
if (($Action) -and ($Action.ToLower() -eq "test")) {
    exit $STATUS_CODES["scriptSuccess"]
}

try {
    $exit_code = Main
    exit $exit_code
} finally {
    if ($null -eq $exit_code) {
        Write-Host "Script Terminated..."
        exit $STATUS_CODES["scriptTerminated"]
    }
}
