<#
In this scenario AutomatedLab builds a lab inside a lab. Thanks to nested virtualization in Hyper-V and Azure,
this can be done on a Windows Server 2016 or Windows 10 host machine.
This lab contains:
    -	ADDC1 with the role root domain controller. This machine also has the routing role to enable
        internet access for the whole lab.
    -	AL1, the virtualized host machine on Windows Server Core 1709.
    -	ADClient1 gives you graphical management access to the virtualized host.

Note: The domain controller and client are not required. These machines are just add another level of comfort to have
graphical management of the virtual host machine and the lab inside.

After AutomatedLab has created the machines, it enables nested virtualization on machine AL1 and installs the Hyper-V roles
on AL1 and ALClient1. Then the AutomatedLab PowerShell modules are downloaded and installed on AL1. The only part missing are the
ISOs on AL1 in order to deploy a lab on the virtualized host so AL copied some files to the virtual host. Finally, the
deployment script calls the sample script "04 Single domain-joined server.ps1" on AL1 and deploys a lab in a lab.
#>

$labName = 'ALTestLab1'

New-LabDefinition -Name $labName -DefaultVirtualizationEngine HyperV

Add-LabVirtualNetworkDefinition -Name $labName
Add-LabVirtualNetworkDefinition -Name External -HyperVProperties @{ SwitchType = 'External'; AdapterName = 'Ethernet' }

$PSDefaultParameterValues = @{
    'Add-LabMachineDefinition:Network' = $labName
    'Add-LabMachineDefinition:ToolsPath'= "$labSources\Tools"
    'Add-LabMachineDefinition:OperatingSystem'= 'Windows Server 2016 Datacenter (Desktop Experience)'
    'Add-LabMachineDefinition:Memory'= 1GB
    'Add-LabMachineDefinition:DomainName'= 'contoso.com'
}

$netAdapter = @()
$netAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch $labName
$netAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch External -UseDhcp
Add-LabMachineDefinition -Name ALDC1 -Roles RootDC, Routing -NetworkAdapter $netAdapter

Add-LabMachineDefinition -Name AL1 -Memory 12GB -OperatingSystem 'Windows Server Standard'

Add-LabMachineDefinition -Name ALClient1 -OperatingSystem 'Windows 10 Pro'

Install-Lab

Checkpoint-LabVM -All -SnapshotName 1

$alServers = Get-LabVM -ComputerName AL1
$alClients = Get-LabVM -ComputerName ALCient1

Stop-LabVM -ComputerName $alServers -Wait
Get-VM $alServers | Set-VMProcessor -ExposeVirtualizationExtensions $true
Start-LabVM -ComputerName $alServers -Wait

Install-LabWindowsFeature -ComputerName $alServers -FeatureName Hyper-V, Hyper-V-PowerShell -IncludeAllSubFeature
Restart-LabVM -ComputerName $alServers -Wait #A restart is required by the Hyper-V installer
Wait-LabVMRestart -ComputerName $alServers #As the Hyper-V installation does another restart

Install-LabWindowsFeature -ComputerName ALClient1 -FeatureName Microsoft-Hyper-V-All
Restart-LabVM -ComputerName ALClient1 -Wait

Checkpoint-LabVM -All -SnapshotName 2

Invoke-LabCommand -ActivityName 'Install AutomatedLab and create LabSources folder' -ComputerName $alServers -ScriptBlock {

    #Add the AutomatedLab Telemetry setting to default to allow collection, otherwise will prompt during installation
    [System.Environment]::SetEnvironmentVariable('AUTOMATEDLAB_TELEMETRY_OPTOUT', '0')
    Install-PackageProvider -Name Nuget -ForceBootstrap -Force -ErrorAction Stop | Out-Null
    Install-Module -Name AutomatedLab -AllowClobber -Force -ErrorAction Stop

    Import-Module -Name AutomatedLab -ErrorAction Stop

    New-LabSourcesFolder -ErrorAction Stop
}

Copy-LabFileItem -ComputerName $alServers -DestinationFolderPath "C:\LabSources\ISOs" -Path `
$labSources\ISOs\en_windows_10_multiple_editions_version_1703_updated_march_2017_x64_dvd_10189288.iso,
$labSources\ISOs\en_windows_server_2012_r2_with_update_x64_dvd_4065220.iso 

Invoke-LabCommand -ActivityName 'Deploy Test Lab' -ComputerName $alServers -ScriptBlock {

    & "$(Get-LabSourcesLocation)\SampleScripts\Introduction\04 Single domain-joined server.ps1"

}

Show-LabDeploymentSummary -Detailed