[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("enableall","disableall")][string]$Ipv6Component = "disableall"
)
function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
    { Write-Output $true }
    else
    { Write-Output $false }
}
function Set-ItemProp {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [ValidateSet("DWord", "QWord", "String", "ExpandedString", "Binary", "MultiString", "Unknown")]$PropertyType = "DWord"
    )

    if ((Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue)) {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force -Confirm:$false | Out-Null
    }
    else {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force -Confirm:$false | Out-Null
    }
}
function Disable-Ipv6ProtocolComponents {
    [CmdletBinding()]
    param(
        [ValidateSet("Net6to4", "NetTeredo", "ISATAP")][string]$Config,
        [ValidateSet("enable", "disable")][string]$State 
    )
    try {
        switch ($Config) {
            "Net6to4" {
                if ((Get-Net6to4Configuration).State -ne $State) {
                    Set-Net6to4Configuration –State $State
                }
            }
            "NetTeredo" {
                if ((Get-NetTeredoConfiguration).Type -ne $State) {
                    Set-NetTeredoConfiguration –Type $State
                }
            }
            "ISATAP" {
                if ((Get-NetIsatapConfiguration).State -ne $State) {
                    Set-NetIsatapConfiguration –State $State
                }
            }
        }
    }
    catch {
        Write-Error "Failed  - Set adapter ipv6 configuration to disable $_"
    }
}
function Disable-Ipv6AllInterfaces {
    [CmdletBinding()]
    param(
        [ValidateSet("ms_tcpip6")][string]$ComponentId
    )
    try {
        Disable-NetAdapterBinding -Name "*" -ComponentID $ComponentId
    }
    catch {
        Write-Error "Failed - to disable ipv6 on one or more interfaces $_"
    }
}

if (-not (Test-IsElevated)) {
    Write-Error -Message "Access Denied - Please run with Administrator privileges."
    exit 1
}
switch ($Ipv6Component) {
    "disableall" {
        $Disableall = 0xFF
        $State = "disable"
        $msipv6 = "ms_tcpip6"
        $Path = "HKLM:SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\"
        $Name = "DisabledComponents"
        $Value = $Disableall 
        $ProtocolComponents = @("Net6to4", "NetTeredo", "ISATAP")
    }
    default {
        Write-Error -Message "Invalid Option - Script can only disable ipv6 components parameters allowed (disableall)."
        exit 1
    }
}

Disable-Ipv6AllInterfaces -ComponentId $msipv6
foreach ($protocol in $ProtocolComponents) {
    Disable-Ipv6ProtocolComponents -Config $protocol -State $State
}
try {
    Set-ItemProp -Path $Path -Name $Name -Value $Value
}
catch {
    Write-Error "Failed - to add registry key to disable ipv6. $_"
    exit 1
}