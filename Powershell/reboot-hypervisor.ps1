# Can be added in SSM Doc it will rerun script after reboot
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('False', 'True')][string]$AllowReboot = "True",

    [Parameter()]
    [ValidateRange(1, [int]::MaxValue)]$VMOffTimeout = 15,

    [Parameter()]
    [string]$RegistryPath = "HKLM:\SOFTWARE\SSMReboot\"
)
function Set-RebootRegistryKey() {
    param(
        [int][ValidateRange(0, 1)]$Reboot 
    )
    Set-ItemProperty -Path $RegistryPath -Name "RebootFlag" -Value $Reboot
}
function Start-VMShutdown() {
    param(
        [Parameter(Mandatory)][Object]$VMObject,
        [Parameter(Mandatory)][ValidateSet("Shutdown", "TurnOff")][string]$Mode,
        [Parameter()][ValidateRange(1, [int]::MaxValue)]$Timeout = 15
    )
    $vmStateTurnedOff = 3
    $currentTime = (Get-Date)
    $timer = $currentTime.AddMinutes($Timeout)
    switch ($Mode) {
        "Shutdown" {
            Stop-VM -ComputerName $VMObject.ComputerName -Name $VMObject.Name -Force
        }
        "TurnOff" {
            Stop-VM -ComputerName $VMObject.ComputerName -Name $VMObject.Name -Force -TurnOff
        }
    }
    Start-Sleep -Seconds 1
    do {
        $State = ((Get-WmiObject -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem -ComputerName $VMObject.ComputerName -Filter "Name = '$($VMObject.VMId.Guid.ToString().ToUpper())'").EnabledState -eq $VMStateTurnedOff)
    }until($State -or ($timer -lt (Get-date)))
    if ($timer -lt (Get-date)) {
        return $false
    }
    return $true
}

[int]$Yes = 1
[int]$No = 0
[System.Object]$VMRunning = $(Get-VM | Where-Object { $_.State -eq "Running" })
[System.Collections.ArrayList]$obj = @()

if (-not ((Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V).State -eq "Enabled")) {
    Write-Output "[!] System is not a Hypervisor or does not have the Hyper-V role installed."
    Write-Output "Exiting..."
    Exit -1
}

if (!(Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
    Set-RebootRegistryKey -Reboot $No
}
else {
    $SystemRebooted = (Get-ItemProperty -Path $RegistryPath).RebootFlag
}
if ($SystemRebooted -eq $Yes) {
    Set-RebootRegistryKey -Reboot $No
    $BootTime = (Get-WmiObject win32_operatingsystem | Select-Object @{Name = "LastBoot"; Expression = { $_.ConvertToDateTime($_.LastBootUpTime) } }).LastBoot
    Write-Host "Virtual Machines were gracefully shutdown before the system rebooted."
    Write-Host "System rebooted: $($BootTime)"
    Exit 0
}

if ($null -ne $VMRunning) {
    $counter = 0
    foreach ($VirtualMachine in $VMRunning) {
        if (Start-VMShutdown -VMObject $VirtualMachine -Mode "Shutdown" -Timeout $VMOffTimeout) {
            $null = $obj.Add([PSCustomObject]@{
                    VirtualMachine = $VirtualMachine.Name
                    Shutdown       = "Success"
                })
        }
        else {
            $null = $obj.Add([PSCustomObject]@{
                    VirtualMachine = $VirtualMachine.Name
                    Shutdown       = "ShutdownTimeout"
                })
            $counter++
        }
    }
    if ($counter -gt 0) {
        Write-Output "[!] One or more Virtual Machines were not shutdown within the given time '${$VMOffTimeout}min', check hypervisor and reboot accordingly."
        Write-Output $obj | Format-Table
        Exit -1
    }
}
if ($AllowReboot -ieq 'False') {
    Write-Host "Virtual Mahines were gracefully shutdown, System can be manually rebooted."
    Write-Output $obj | Format-Table
    Exit 0
}
if ($AllowReboot -ieq 'True') {
    #ssm reboot(Exit301)
    Set-RebootRegistryKey -Reboot $Yes
    Exit 3010
}
