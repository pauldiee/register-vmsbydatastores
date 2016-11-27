<#
.SYNOPSIS
   Register .vmx files to vCenter
.DESCRIPTION
   Register .vmx files to vCenter
.EXAMPLE
    One or more examples for how to use this script
.NOTES
    File Name          : register-VMsByDatastores.ps1
    Author             : Bart Lievers
    version            : release/v0.1.0
    Prerequisite       : Powershell >= v 3.0
                         PowerCLI >= 5.8
    Copyright 2015 - CAM IT Solutions
#>

[CmdletBinding()]

Param(
)

Begin{
    #-- initialize environment
    $DebugPreference="SilentlyContinue"
    $VerbosePreference="SilentlyContinue"
    $ErrorActionPreference="Continue"
    $WarningPreference="Continue"
    clear-host #-- clear CLi
    $ts_start=get-date #-- note start time of script
    if ($finished_normal) {Remove-Variable -Name finished_normal -Confirm:$false }

	#-- determine script location and name
	$scriptpath=get-item (Split-Path -parent $MyInvocation.MyCommand.Definition)
	$scriptname=(Split-Path -Leaf $MyInvocation.mycommand.path).Split(".")[0]

    #-- Load Parameterfile
    if (!(test-path -Path $scriptpath\parameters.ps1 -IsValid)) {
        write-warning "parameters.ps1 niet gevonden. Script kan niet verder."
        exit
    } 
    $P = & $scriptpath\parameters.ps1


#region for Private script functions
    #-- note: place any specific function in this region

    function exit-script 
    {
        <#
        .DESCRIPTION
            Clean up actions before we exit the script.
        .PARAMETER unloadCcModule
            [switch] Unload the CC-function module
        .PARAMETER defaultcleanupcode
            [scriptblock] Unique code to invoke when exiting script.
        #>
        [CmdletBinding()]
        param()

        #-- check why script is called and react apropiatly
        if ($finished_normal) {
            $msg= "Hooray.... finished without any bugs....."
            if ($log) {$log.verbose($msg)} else {Write-Verbose $msg}
        } else {
            $msg= "(1) Script ended with errors."
            if ($log) {$log.error($msg)} else {Write-Error $msg}
        }

        #-- General cleanup actions
        #-- disconnect vCenter connections if they exist
        if ((Get-Variable -Scope global -Name DefaultVIServers -ErrorAction SilentlyContinue) -and $P.DisconnectviServerOnExit  ) {
            Disconnect-VIServer -server * -Confirm:$false
        }
        #-- Output runtime and say greetings
        $ts_end=get-date
        $msg="Runtime script: {0:hh}:{0:mm}:{0:ss}" -f ($ts_end- $ts_start)  
        write-host $msg
        read-host "The End <press Enter to close window>."
        exit
    }

    function Send-SyslogMessage
    {
    <#
    .SYNOPSIS
    Sends a SYSLOG message to a server running the SYSLOG daemon
 
    .DESCRIPTION
    Sends a message to a SYSLOG server as defined in RFC 5424. A SYSLOG message contains not only raw message text,
    but also a severity level and application/system within the host that has generated the message.
 
    .PARAMETER Server
    Destination SYSLOG server that message is to be sent to
 
    .PARAMETER Message
    Our message
 
    .PARAMETER Severity
    Severity level as defined in SYSLOG specification, must be of ENUM type Syslog_Severity
 
    .PARAMETER Facility
    Facility of message as defined in SYSLOG specification, must be of ENUM type Syslog_Facility
 
    .PARAMETER Hostname
    Hostname of machine the mssage is about, if not specified, local hostname will be used
 
    .PARAMETER Timestamp
    Timestamp, myst be of format, "yyyy:MM:dd:-HH:mm:ss zzz", if not specified, current date & time will be used
 
    .PARAMETER UDPPort
    SYSLOG UDP port to send message to
 
    .INPUTS
    Nothing can be piped directly into this function
 
    .OUTPUTS
    Nothing is output
 
    .EXAMPLE
    Send-SyslogMessage mySyslogserver "The server is down!" Emergency Mail
    Sends a syslog message to mysyslogserver, saying "server is down", severity emergency and facility is mail
 
    .NOTES
    NAME: Send-SyslogMessage
    AUTHOR: Kieran Jacobsen
    LASTEDIT: 2014 07 01
    KEYWORDS: syslog, messaging, notifications
 
    .LINK
    https://github.com/kjacobsen/PowershellSyslog
 
    .LINK
    http://aperturescience.su
 
    #>
    [CMDLetBinding()]
    Param
    (
            [Parameter(mandatory=$true)] [String] $Server,
            [Parameter(mandatory=$true)] [String] $Message,
            [Parameter(mandatory=$true)] [Syslog_Severity] $Severity,
            [Parameter(mandatory=$true)] [Syslog_Facility] $Facility,
            [String] $Hostname,
            [String] $Timestamp,
            [int] $UDPPort = 514
    )
 
    # Create a UDP Client Object
    $UDPCLient = New-Object System.Net.Sockets.UdpClient
    try {$UDPCLient.Connect($Server, $UDPPort)}

    catch {
        write-host "No connection to syslog server"
        return
    }
 
    # Evaluate the facility and severity based on the enum types
    $Facility_Number = $Facility.value__
    $Severity_Number = $Severity.value__
    Write-Verbose "Syslog Facility, $Facility_Number, Severity is $Severity_Number"
 
    # Calculate the priority
    $Priority = ($Facility_Number * 8) + $Severity_Number
    Write-Verbose "Priority is $Priority"
 
    # If no hostname parameter specified, then set it
    if (($Hostname -eq "") -or ($Hostname -eq $null))
    {
            $Hostname = Hostname
    }
 
    # I the hostname hasn't been specified, then we will use the current date and time
    if (($Timestamp -eq "") -or ($Timestamp -eq $null))
    {
            $Timestamp = Get-Date -Format "yyyy:MM:dd:-HH:mm:ss zzz"
    }
 
    # Assemble the full syslog formatted message
    $FullSyslogMessage = "<{0}>{1} {2} {3}" -f $Priority, $Timestamp, $Hostname, $Message
 
    # create an ASCII Encoding object
    $Encoding = [System.Text.Encoding]::ASCII
 
    # Convert into byte array representation
    $ByteSyslogMessage = $Encoding.GetBytes($FullSyslogMessage)
 
    # If the message is too long, shorten it
    if ($ByteSyslogMessage.Length -gt 1024)
    {
        $ByteSyslogMessage = $ByteSyslogMessage.SubString(0, 1024)
    }
 
    # Send the Message
    $UDPCLient.Send($ByteSyslogMessage, $ByteSyslogMessage.Length)
 
    }

    function import-powercli 
    {
        [CmdletBinding()]

        Param(
        )

        Begin{
 
        }

        Process{
            #-- make up inventory and check PowerCLI installation
            $RegisteredModules=Get-Module -Name vmware* -ListAvailable -ErrorAction ignore | % {$_.Name}
            $RegisteredSnapins=get-pssnapin -Registered vmware* -ErrorAction Ignore | %{$_.name}
            if (($RegisteredModules.Count -eq 0 ) -and ($RegisteredSnapins.count -eq 0 )) {
                #-- PowerCLI is not installed
                if ($log) {$log.warning("Cannot load PowerCLI, no VMware Powercli Modules and/or Snapins found.")}
                else {
                write-warning "Cannot load PowerCLI, no VMware Powercli Modules and/or Snapins found."}
                #-- exit function
                return $false
            } 
            #-- load modules
            #-- make inventory of already loaded VMware modules
            $loaded = Get-Module -Name vmware* -ErrorAction Ignore | % {$_.Name}
            #-- make inventory of available VMware modules
            $registered = Get-Module -Name vmware* -ListAvailable -ErrorAction Ignore | % {$_.Name}
            #-- determine which modules needs to be loaded, and import them.
            $notLoaded = $registered | ? {$loaded -notcontains $_}
   
            foreach ($module in $registered) {
                if ($loaded -notcontains $module) {
                    Import-Module $module
                }
            }

            #-- load Snapins
            #-- Exlude loaded modules from additional snappins to load
            $snapinList=Compare-Object -ReferenceObject $RegisteredModules -DifferenceObject $RegisteredSnapins | ?{$_.sideindicator -eq "=>"} | %{$_.inputobject}
            #-- Make inventory of loaded VMware Snapins
            $loaded = Get-PSSnapin -Name $snapinList -ErrorAction Ignore | % {$_.Name}
            #-- Make inventory of VMware Snapins that are registered
            $registered = Get-PSSnapin -Name $snapinList -Registered -ErrorAction Ignore  | % {$_.Name}
            #-- determine which snapins needs to loaded, and import them.
            $notLoaded = $registered | ? {$loaded -notcontains $_}
   
            foreach ($snapin in $registered) {
                if ($loaded -notcontains $snapin) {
                    Add-PSSnapin $snapin
                }
            }

            #-- show loaded vmware modules and snapins
            get-module -Name vmware* | select name,version,@{N="type";E={"module"}} | ft -AutoSize
            get-pssnapin -Name vmware* | select name,version,@{N="type";E={"snapin"}} | ft -AutoSize

        }

        End{

        }

    }
 

#endregion
}

Process{
#-- note: area to write script code.....

    import-powercli
    connect-viserver $P.vcenter -ErrorAction SilentlyContinue -ErrorVariable Err1
    if ($err1) {
        write-warning "Geen verbinding kunnen maken met $vCenter."
        exit-script
    }

    # Select datastore and VM Folder interactivly
    $Datastore = get-datastore | sort-object name | Out-GridView -Title "Selecteer de datastore." -OutputMode Single
    if ($datastore.length -le 0) {
        write-warning "Geen datastore geselecteerd."
        exit-script
    }
    $VMFolder = get-folder | ? {$_.Type -imatch "VM"} | select name,parent | sort-object name | Out-GridView -Title "Select Folder" -OutputMode Single | select -ExpandProperty name
    if ($vmFolder.length -le 0) {
        Write-Warning "Geen VM Folder geselecteerd."
        exit-script
    }

    #-- select vSphere ESXi host where datastore is mounted to register VMs on
    $ESXhost = Get-Datastore $datastore | get-vmhost | select -first 1 -ExpandProperty name
    write-host "Selected $ESXhost to register VMs on."
    #build table containing all registed VMs
    $knownVMTable = get-vm | select name | Group-Object -AsHashTable -Property name

 
    $tasklist=@{}

    foreach($Datastore in $Datastore) {
        # Searches for .VMX Files in datastore variable
        $ds = Get-Datastore -Name $Datastore | %{Get-View $_.Id}
        $SearchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
        $SearchSpec.matchpattern = "*.vmx"
        $dsBrowser = Get-View $ds.browser
        $DatastorePath = "[" + $ds.Summary.Name + "]"
        $vms=@{}
        foreach ($vmImpl in $ds.Vm){
        $vm=get-view $vmImpl
        $vms.add($vm.config.files.VmPathName,$ds.name)
        }
 
        # Find all .VMX file paths in Datastore variable and filters out .snapshot
        $SearchResult = $dsBrowser.SearchDatastoreSubFolders($DatastorePath, $SearchSpec) | where {$_.FolderPath -notmatch ".snapshot"} | %{$_.FolderPath + ($_.File | select Path).Path}
        write-host ("Found "+ $SearchResult.Count + " VMX files in datastore.")
 
        # Register .VMX files with vCenter, check if VM is already registered
        $VMXRegisterActions=0
        $VMXfilesSkipped=0
        foreach($VMXFile in $SearchResult) {
            #if ($knownVMTable.Contains((split-path $VMXFile -leaf).split(".")[0] )) {
            if ($vms.ContainsKey($VMXFile)){
                $VMXfilesSkipped++
                write-host "VMXfile $vmxfile already registered. Skipping"
            } else {
                $VMXRegisterActions++
                write-host $VMXFile
                New-VM -VMFilePath $VMXFile -VMHost $ESXHost -Location $VMFolder -RunAsync | out-null
            }
         }
    }
    write-host "VMs registered: $VMXRegisterActions, skipped: $VMXfilesSkipped"
}

End{
    #-- we made it, exit script.
    $finished_normal=$true
    exit-script
}