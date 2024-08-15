$Servers = Get-ADComputer -Filter * | Where-Object { $_.Name -match "HPV" }
$Csv = [System.Collections.ArrayList]@()
$Customer = (Get-ADDomain).Name
$Date = (Get-Date -Format "MMddyyyy")
$Tmp = "C:\tmp\"


function Get-VMNetInfo() {
    [CmdletBinding()]
    param()
    $vmAdapters = @()
    $csv = @()
    $vms = Get-VM
    foreach ($vm in $vms) {

        $Hypervisor = ($env:COMPUTERNAME)

        #$vmAdapters = get-vm $vm.Name | Select-Object -ExpandProperty NetworkAdapters | Select-Object VMName, @{n = 'Switch'; e = { $_.SwitchName } }, IPAddresses, MacAddress, @{n = 'VLANID'; e = { ($_.VlanSetting).AccessVlanId } }, @{n = 'SwitchType'; e = { ($_.SwitchId | Get-VMSWitch).SwitchType } }, @{n = 'VMNetworkAdapter'; e = { ($_.SwitchId | Get-VMSwitch).NetAdapterInterfaceDescription } }
        $vmAdapters = get-vm $vm.Name | Select-Object -ExpandProperty NetworkAdapters `
        | Select-Object VMName, @{n='Switch'; e={ $_.SwitchName}}, IPAddresses, `
        MacAddress, @{n='VLANID'; e={($_.VlanSetting).AccessVlanId}}, @{n='SwitchType'; e={($_.SwitchId `
        | Get-VMSWitch -ErrorAction SilentlyContinue).SwitchType}}, @{n='VMNetworkAdapter'; e={($_.SwitchId `
        | Get-VMSwitch -ErrorAction SilentlyContinue).NetAdapterInterfaceDescription }}

        foreach ($adapter in $vmAdapters) {
            $HostAdapterName = Get-NetAdapter | Where-Object {$_.InterfaceDescription -eq "$($adapter.VMNetworkAdapter)"}
            if($null -eq $HostAdapterName){
                continue
            }
            $IsTeamMember = Get-NetLbfoTeamMember -Team $($HostAdapterName.Name) -ErrorAction SilentlyContinue
            if ($IsTeamMember) {
                foreach ($interface in $IsTeamMember) {
                    $csv += [PSCustomObject]@{
                        Hypervisor            = $Hypervisor
                        VMName                = $adapter.VMName
                        Switch                = $adapter.Switch
                        IPAddresses           = ([string]($adapter.IPAddresses))
                        VMMacAddress          = $adapter.MacAddress
                        VLANID                = $adapter.VLANID
                        SwitchType            = $adapter.SwitchType
                        VMNetworkAdapterName  = $adapter.VMNetworkAdapter
                        Team                  = $interface.Team
                        PhysicalInterfaceName = $interface.Name 
                        InterfaceDescription  = $interface.InterfaceDescription
                        MacAddressValue       = (Get-NetAdapter -Name $interface.Name).MacAddress
                        Status                = (Get-NetAdapter -Name $interface.Name).Status
                        LinkSpeed             = (Get-NetAdapter -Name $interface.Name).LinkSpeed
                    }
                }
            }
            else {
                $csv += [PSCustomObject]@{
                    Hypervisor            = $Hypervisor
                    VMName                = $adapter.VMName
                    Switch                = $adapter.Switch
                    IPAddresses           = ([string]($adapter.IPAddresses))
                    VMMacAddress          = $adapter.MacAddress
                    VLANID                = $adapter.VLANID
                    SwitchType            = $adapter.SwitchType
                    VMNetworkAdapterName  = $adapter.VMNetworkAdapter
                    Team                  = "Not Team"
                    PhysicalInterfaceName = (Get-NetAdapter -InterfaceDescription $adapter.VMNetworkAdapter).Name
                    InterfaceDescription  = (Get-NetAdapter -InterfaceDescription $adapter.VMNetworkAdapter).InterfaceDescription
                    MacAddressValue       = (Get-NetAdapter -InterfaceDescription $adapter.VMNetworkAdapter).MacAddress
                    Status                = (Get-NetAdapter -InterfaceDescription $adapter.VMNetworkAdapter).Status
                    LinkSpeed             = (Get-NetAdapter -InterfaceDescription $adapter.VMNetworkAdapter).LinkSpeed
                }   
            }
        }
    }

    return $csv
}
function Get-HostNetInfo() {
    [CmdletBinding()]
    param()
    $Hypervisor = ($env:COMPUTERNAME)
    $csv = @()
    $AllAdapters = @()
    Get-NetAdapter | ForEach-Object { $AllAdapters += $_.Name }
    foreach ($adapter in $AllAdapters) {
        $nic = (Get-NetAdapter $adapter | Select-Object *)
        $csv += [PSCustomObject]@{
            Hypervisor            = $Hypervisor
            VMName                = ""
            Switch                = ""
            IPAddresses           = ""
            VMMacAddress          = ""
            VLANID                = ""
            SwitchType            = ""
            VMNetworkAdapterName  = ""
            Team                  = if (Get-NetLbfoTeamMember -Team $($nic.Name) -ErrorAction SilentlyContinue) { $nic.Name }elseif (Get-NetLbfoTeamMember -Name $($nic.Name) -ErrorAction SilentlyContinue) { (Get-NetLbfoTeamMember -Name $($nic.Name)).Team }else { $null }
            PhysicalInterfaceName = $nic.Name 
            InterfaceDescription  = $nic.InterfaceDescription
            MacAddressValue       = $nic.MacAddress
            Status                = $nic.Status
            LinkSpeed             = $nic.LinkSpeed
        } 
    }
    return $csv
}

if (!(Test-Path $Tmp)) {
    Write-Host "Creating local \tmp\ Folder ..."
    New-Item -ItemType Directory -Path $tmp > $null
    Write-Host "Done"
}

foreach ($Hypervisor in $Servers) {
    try {
        Write-Host "[*] Retrieving NetInfo from Hypervisor - " -NoNewline; Write-Host "$($Hypervisor.Name.ToUpper())" -ForegroundColor Yellow
        $Csv += Invoke-Command -ComputerName $Hypervisor.Name -ScriptBlock ${Function:Get-VMNetInfo} -ErrorAction Stop
        $Csv += Invoke-Command -ComputerName $Hypervisor.Name -ScriptBlock ${Function:Get-HostNetInfo} -ErrorAction Stop
    }
    catch {
        $Csv += [PSCustomObject]@{
            Hypervisor            = $Hypervisor.Name
            VMName                = "<unable to connect>"
            Switch                = "<unable to connect>"
            IPAddresses           = "<unable to connect>"
            VMMacAddress          = "<unable to connect>"
            VLANID                = "<unable to connect>"
            SwitchType            = "<unable to connect>"
            VMNetworkAdapterName  = "<unable to connect>"
            Team                  = "<unable to connect>"
            PhysicalInterfaceName = "<unable to connect>" 
            InterfaceDescription  = "<unable to connect>"
            MacAddressValue       = "<unable to connect>"
            Status                = "<unable to connect>"
            LinkSpeed             = "<unable to connect>"
        }
    }
}

$csv | Export-Csv "C:\tmp\$($date)-hpv-$($customer)-netinfo.csv" -NoTypeInformation