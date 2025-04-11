#
# Module 'Previder-Powershell-Module'
#

$Annexus = @{
    BaseUri = "https://portal.previder.nl";
    Uri = "https://portal.previder.nl/api";
    Headers = @{ };
    LastResponseHeaders = @{ };
    WaitForRateLimitReset = $true;
    RateLimitWaitThreshold = 100;
}

Add-Type -TypeDefinition @"
  public enum VirtualMachineControlAction {
    POWERON, RESTART, RESET, POWEROFF, SHUTDOWN, SUSPEND, INSTALL_GUEST_TOOLS,
    UPGRADE_GUEST_TOOLS, POWERON_BIOS, RESTART_BIOS, RESET_BIOS
  }
"@

Add-Type -TypeDefinition @"
  public enum ProvisioningType {
    NONE, CLOUD_INIT_OVF, SYSPREP, SYSPREP_TEXT, CONFIG_DRIVE_2, KICKSTART, CLOUD_INIT_OVF2, CLOUD_INIT_GUEST_INFO
  }
"@

function New-AnnexusWebRequest
{
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $TRUE)]
        [string] $Uri,
        [string] $RequestMethod = "GET",
        $Body
    )

    $DefaultRequestMethod = "application/json"

    if ($Annexus.LastResponseHeaders -and $Annexus.LastResponseHeaders['X-Rate-Limit-Remaining'] -and $Annexus['WaitForRateLimitReset'])
    {
        $RateLimitRequestsRemaining = $Annexus.LastResponseHeaders['X-Rate-Limit-Remaining'] -as [int]
        $RateLimitResetTimeUnix = $Annexus.LastResponseHeaders['X-Rate-Limit-Reset'] -As [int]

        if ($null -ne $RateLimitRequestsRemaining -and $null -ne $RateLimitResetTimeUnix)
        {
            $RateLimitResetTime = (Get-Date "01.01.1970").AddSeconds($RateLimitResetTimeUnix)
            $RateLimitResetTime = $RateLimitResetTime.AddSeconds((get-timezone).GetUtcOffset($RateLimitResetTime).TotalSeconds)

            $RateLimitSecondsUntilReset = (New-TimeSpan -Start (get-date) -End $RateLimitResetTime).TotalSeconds

            if ([int]$RateLimitRequestsRemaining -lt $Annexus['RateLimitWaitThreshold'])
            {
                write-warning "Waiting for rate limit expiry. Requests remaining: $RateLimitRequestsRemaining. Time remaining $RateLimitSecondsUntilReset seconds"
                Start-Sleep -Seconds ($RateLimitSecondsUntilReset + 10)
            }
        }
    }

    if ($Body)
    {
        $Res = Invoke-WebRequest -WebSession $Annexus.Session -Headers $Annexus.Headers -Method $RequestMethod -Uri $Uri -ContentType $DefaultRequestMethod -Body $Body
    }
    else
    {
        $Res = Invoke-WebRequest -WebSession $Annexus.Session -Headers $Annexus.Headers -Method $RequestMethod -Uri $Uri -ContentType $DefaultRequestMethod
    }


    $Annexus.LastResponseHeaders = $Res.Headers

    if ($Res.Content)
    {
        return $( $Res.Content | convertfrom-json )
    }

}

function Connect-Annexus
{
    [CmdletBinding(DefaultParameterSetName = "credSet")]
    param(
        [parameter(ParameterSetName = "tokenSet", Mandatory = $TRUE)]
        [string] $Token,
        [parameter(ParameterSetName = "credSet", Mandatory = $TRUE)]
        [string] $Accountname,
        [parameter(ParameterSetName = "credSet", Mandatory = $TRUE)]
        [string] $Username,
        [parameter(ParameterSetName = "credSet", Mandatory = $TRUE)]
        [Security.SecureString] $Password,
        [parameter(ParameterSetName = "credSet", Mandatory = $FALSE)]
        [string] $OTP,
        [switch] $UseOTP,
        [string] $Uri
    )

    If ($UseOTP -and !$OTP)
    {
        $OTP = Read-Host 'OTP'
    }

    If ($Uri)
    {
        $Annexus.Uri = $Uri
    }

    If ($Token)
    {
        $Annexus.Headers.Add("X-Auth-Token", $Token)
    }
    Else
    {

        $UnmanagedString = [System.IntPtr]::Zero
        try
        {
            $UnmanagedString = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($Password);
            $UnsecurePassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($UnmanagedString);
        }
        finally
        {
            [Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($UnmanagedString);
        }

        $Credentials = @{
            "username" = "$( $Username )@$( $Accountname )";
            "password" = $UnsecurePassword;
            "otp" = $OTP;
        }

        $Res = Invoke-WebRequest -SessionVariable AnnexusSession -Method GET -Uri "$( $Annexus.Uri )/" -ContentType "application/json"

        $Annexus.Session = $AnnexusSession
        $Annexus.Session.Headers.Add("X-CSRF-Token", $Res.Headers["X-CSRF-Token"])

        try
        {
            $Res = Invoke-WebRequest -WebSession $Annexus.Session -Method POST -Uri "$( $Annexus.BaseUri )/logincheck" -Body $Credentials -ContentType "application/x-www-form-urlencoded"
        }
        catch
        {
            Write-Host "Error logging in"
            return
        }

        $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/session"
        $Annexus.Session.Headers.Set_Item("X-CSRF-Token", $Res.Headers["X-CSRF-Token"])

        Write-Host "Logged in successfully"
        $Res
    }
}

Function Set-AnnexusRateLimitHandling
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Boolean]$WaitForRateLimitReset = $null,
        [Parameter(Mandatory = $false)]
        [int]$RateLimitWaitThreshold = $null
    )
    if ($WaitForRateLimitReset -ne $null)
    {
        $Annexus['WaitForRateLimitReset'] = $WaitForRateLimitReset
    }

    if ($RateLimitWaitThreshold -ne $null)
    {
        $Annexus['RateLimitWaitThreshold'] = $RateLimitWaitThreshold
    }
}

function Disconnect-Annexus
{
    [CmdletBinding()]
    param()
    if ($Annexus.Session -and $Annexus.Session.Headers.ContainsKey("X-CSRF-Token"))
    {
        Invoke-WebRequest -WebSession $Annexus.Session -Method POST -Uri "$( $Annexus.BaseUri )/logout" -ContentType "application/json"
    }

    $Annexus.Headers.Remove("X-Auth-Token")
    Write-Host "Logged out"
}

function Set-HandleByCustomer
{
    [CmdletBinding()]
    param(
        [string] $Id
    )

    if ( $Annexus.Headers.ContainsKey("X-CustomerId"))
    {
        Write-Host "Clearing handle by customer"
        $Annexus.Headers.Remove("X-CustomerId")
    }

    if ($Id)
    {
        $Customer = Get-Customer -Id $Id
        Write-Host "Handle by customer $( $Customer.name )"
        $Annexus.Headers.Add("X-CustomerId", $Customer.id)
    }
}

function Get-CustomerList
{
    [CmdletBinding()]
    param()

    $Res = @()
    $Page = 0
    do
    {
        $PageRes = Get-CustomerPage -Page $Page
        $Res += $PageRes.content
        $Page++
    } until ($PageRes.totalPages -eq $Page -or $PageRes.content.Count -eq 0)

    $Res
}

function Get-CustomerPage
{
    [CmdletBinding()]
    param(
        [Int16] $Page = 0,
        [Int16] $Size = 10,
        [string] $Query = "",
        [string] $Sort = "name,asc"
    )

    $QueryParams = @{
        "page" = $Page
        "size" = $Size
        "query" = $Query
        "sort" = $Sort
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/core/customer" -Body $QueryParams
    $Res
}

function Get-Customer
{
    [CmdletBinding(DefaultParameterSetName = "nameSet")]
    param(
        [parameter(ParameterSetName = "idSet", Mandatory = $TRUE)]
        [string] $Id,
        [parameter(ParameterSetName = "nameSet", Mandatory = $TRUE)]
        [string] $Name
    )

    If ($Name)
    {
        $CustomerPage = Get-CustomerPage -Query $Name -Size 1
        if ($CustomerPage.totalElements -eq 0)
        {
            throw "Customer not found by name"
        }
        $Customer = $CustomerPage.content[0]
        if (!$Customer)
        {
            throw "Virtualmachine not found by name"
        }
        $Id = $Customer.id
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/core/customer/$( $Id )"
    $Res
}

function Get-VmPage
{
    [CmdletBinding()]
    param(
        [Int16] $Page = 0,
        [Int16] $Size = 10,
        [string] $Query = "",
        [string] $Sort = "name,asc",
        [string] $Tags
    )

    $QueryParams = @{
        "page" = $Page
        "size" = $Size
        "query" = $Query
        "sort" = $Sort
    }

    if ($Tags) {
        $QueryParams.Add("tags", $tags)
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/" -Body $QueryParams
    $Res

}

function Get-VmList
{
    [CmdletBinding()]
    param(
        [string] $Tags = ""
    )

    $Res = @()
    $Page = 0

    do
    {
        $PageRes = Get-VmPage -Page $Page -Tags $Tags
        $Res += $PageRes.content
        $Page++
    } until ($PageRes.totalPages -eq $Page -or $PageRes.content.Count -eq 0)
    $Res
}

function Get-VmNetworkPage
{
    [CmdletBinding()]
    param(
        [Int16] $Page = 0,
        [Int16] $Size = 10,
        [string] $Query = "",
        [string] $Sort = "name,asc"
    )

    $QueryParams = @{
        "page" = $Page
        "size" = $Size
        "query" = $Query
        "sort" = $Sort
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualnetwork/" -Body $QueryParams
    $Res
}

function Get-VmNetworkList
{
    [CmdletBinding()]
    param()

    $Res = @()
    $Page = 0
    do
    {
        $PageRes = Get-VmNetworkPage -Page $Page
        $Res += $PageRes.content
        $Page++
    } until ($PageRes.totalPages -eq $Page -or $PageRes.content.Count -eq 0)
    $Res
}

function Get-VmClusterList
{
    [CmdletBinding()]
    param()

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/computecluster"
    $Res
}


function Get-VmBackupProfileList
{
    [CmdletBinding()]
    param()
    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/backupprofile"
    $Res
}

function Get-VmBackup
{
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $TRUE)]
        [string] $Id
    )

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )/backup"
    $Res
}

function Get-VMBackupOverview
{
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $FALSE)]
        [int] $limit_backups = 5
    )

    $QueryParams = @{
        "limit-backups" = $limit_backups
    }
    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/backupoverview" -Body $QueryParams
    $Res
}

function Get-VmTemplateList
{
    [CmdletBinding()]
    param()

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/template"
    $Res
}

function Get-VmGroupPage
{
    [CmdletBinding()]
    param(
        [Int16] $Page = 0,
        [Int16] $Size = 10,
        [string] $Query = "",
        [string] $Sort = "name,asc"
    )

    $QueryParams = @{
        "page" = $Page
        "size" = $Size
        "query" = $Query
        "sort" = $Sort
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/core/group/" -Body $QueryParams
    $Res
}

function Get-VmGroupList
{
    [CmdletBinding()]
    param()

    $Res = @()
    $Page = 0
    do
    {
        $PageRes = Get-VmGroupPage -Page $Page
        $Res += $PageRes.content
        $Page++
    } until ($PageRes.totalPages -eq $Page -or $PageRes.content.Count -eq 0)
    $Res
}

function Get-Vm
{
    [CmdletBinding(DefaultParameterSetName = "nameSet")]
    param(
        [parameter(ParameterSetName = "idSet", Mandatory = $TRUE)]
        [string] $Id,
        [parameter(ParameterSetName = "nameSet", Mandatory = $TRUE)]
        [string] $Name
    )

    If ($Name)
    {
        $VmPage = Get-VmPage -Query $Name -Size 1
        if ($VmPage.totalElements -eq 0)
        {
            throw "Virtualmachine not found by name"
        }
        $Vm = $VmPage.content[0]
        if (!$Vm)
        {
            throw "Virtualmachine not found by name"
        }
        $Id = $Vm.id
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )"
    $Res
}

function Update-VmHardware
{
    [CmdletBinding(DefaultParameterSetName = "nameSet")]
    param(
        [parameter(ParameterSetName = "idSet", Mandatory = $TRUE)]
        [string] $Id
    )

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )/upgradehardware" -RequestMethod PUT
    $Res
}


function Remove-Vm
{
    [CmdletBinding(DefaultParameterSetName = "nameSet")]
    param(
        [parameter(ParameterSetName = "idSet", Mandatory = $TRUE)]
        [string] $Id,
        [parameter(ParameterSetName = "nameSet", Mandatory = $TRUE)]
        [string] $Name
    )

    if ($Name)
    {
        $Vm = Get-Vm -Name $Name
        $Id = $Vm.id
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )" -RequestMethod DELETE
    $Res
}

function Set-Vm
{
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $TRUE)]
        [string] $Id,
        [string] $BackupProfile,
        [string] $Name,
        [string] $Group,
        [string] $Cluster,
        [Object[]] $NetworkInterfaces,
        [Object[]] $Disks,
        [int] $CpuCores,
        [int] $CpuSockets,
        [int] $MemoryMb,
        [string[]] $Tags,
        [boolean] $TerminationProtection,
        [boolean] $SecureBoot,
        [boolean] $TPM,
        [boolean] $AutoUpdateVmWareTools
    )

    if ( $PSBoundParameters.ContainsKey("Group"))
    {
        $groupRes = Get-VmGroupPage -Query $Group
        if ($groupRes.totalElements -eq 0)
        {
            Throw "group not found: " + $Group
        }
        $groupObj = $groupRes.content[0]
    }

    if ( $PSBoundParameters.ContainsKey("Cluster"))
    {
        $computeClusterObj = Get-VmClusterList | Where-Object {
            $_.name -eq $Cluster
        }
        if (!$computeClusterObj)
        {
            Throw "cluster not found: " + $Cluster
        }
    }

    $vm = Get-Vm -Id $Id
    if ( $PSBoundParameters.ContainsKey("Name"))
    {
        $vm.name = $Name
    }
    if ( $PSBoundParameters.ContainsKey("NetworkInterfaces"))
    {
        $vm.networkInterfaces = $NetworkInterfaces
    }
    if ( $PSBoundParameters.ContainsKey("Disks"))
    {
        $vm.disks = $Disks
    }

    if ( $PSBoundParameters.ContainsKey("CpuCores"))
    {
        $vm.cpuCores = $CpuCores
    }

    if ( $PSBoundParameters.ContainsKey("MemoryMb"))
    {
        $vm.memory = $MemoryMb
    }

    if ( $PSBoundParameters.ContainsKey("computeClusterObj"))
    {
        $vm.computeCluster = $computeClusterObj.name
    }

    if ( $PSBoundParameters.ContainsKey("Tags"))
    {
        $vm.tags = $Tags
    }

    if ($CpuSockets)
    {

        if ($CpuCores)
        {
            if ($CpuCores % $CpuSockets -gt 0)
            {
                throw "Invalid number of cpu sockets, cpu cores must be divisible by cpu sockets with no remainders"
            }
        }
        else
        {
            if ($vm.CpuCores % $CpuSockets -gt 0)
            {
                throw "Invalid number of cpu sockets, cpu cores must be divisible by cpu sockets with no remainders"
            }
        }


        $vm.cpuSockets = $CpuSockets
    }

    if ( $PSBoundParameters.ContainsKey("groupObj"))
    {
        $vm.group = $groupObj.name
    }
    if ( $PSBoundParameters.ContainsKey("BackupProfile"))
    {
        $vm.backupProfile = $BackupProfile
    }

    If ( $PSBoundParameters.ContainsKey("TerminationProtection"))
    {
        $Vm.terminationProtectionEnabled = $TerminationProtection
    }
   
    if ( $PSBoundParameters.ContainsKey("TPM"))
    {
        $vm | Add-Member -NotePropertyName tpm -NotePropertyValue $TPM
    }

    if ( $PSBoundParameters.ContainsKey("AutoUpdateVmWareTools"))
    {
        $vm | Add-Member -NotePropertyName autoUpdateVmWareTools -NotePropertyValue $AutoUpdateVmWareTools
    }

    if ( $PSBoundParameters.ContainsKey("SecureBoot"))
    {
        $vm | Add-Member -NotePropertyName secureBoot -NotePropertyValue $SecureBoot
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )" -RequestMethod PUT -Body ($Vm | ConvertTo-Json -Depth 10)
    $Res
}

function Set-VmComment
{
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $TRUE)]
        [string] $Id,
        [string] $Comment

    )

    $Body = @{
        "comment" = $Comment
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )/comments" -RequestMethod PUT -Body ($Body | ConvertTo-Json -Depth 10)
}

function New-Vm
{
    [CmdletBinding(DefaultParameterSetName = "newSet")]
    param(
        [parameter(Mandatory = $TRUE)]
        [string] $Name,
        [string] $Group,
        [string] $Cluster = "express",
        [parameter(ParameterSetName = "newSet", Mandatory = $TRUE)]
        [string] $Template,
        [parameter(ParameterSetName = "copySet", Mandatory = $TRUE)]
        [string] $SourceVmId,
        [parameter(ParameterSetName = "guestIdSet", Mandatory = $TRUE)]
        [string] $GuestId,
        [int] $CpuCores = 1,
        [int] $CpuSockets = 1,
        [int] $MemoryMb = 1024,
        [ProvisioningType] $ProvisioningType,
        [string] $UserData,
        [parameter(Mandatory = $TRUE)]
        [string[]] $Nics,
        [parameter(Mandatory = $TRUE)]
        [int[]] $Disks,
        [string[]] $Tags,
        [boolean] $TerminationProtection,
        [string] $BackupProfile,
        [boolean] $FirmwareEfi,
        [boolean] $SecureBoot,
        [boolean] $TPM
        
	    [boolean] $PowerOnAfterClone
    )

    if ($Group)
    {
        $groupRes = Get-VmGroupPage -Query $Group
        if ($groupRes.totalElements -eq 0)
        {
            Throw "group not found: " + $Group
        }
        $groupObj = $groupRes.content[0]
    }

    If ($Template)
    {
        $templateObj = Get-VmTemplateList | Where-Object {
            $_.name -eq $Template
        }
        if (!$templateObj)
        {
            Throw "template not found: " + $Template
        }
    }
    ElseIf ($SourceVmId)
    {
        $sourceVmObj = Get-Vm -Id $SourceVmId
        if (!$sourceVmObj)
        {
            Throw "source vm not found: " + $SourceVmId
        }
    }
    $computeClusterObj = Get-VmClusterList | Where-Object {
        $_.name -eq $Cluster
    }

    if (!$computeClusterObj)
    {
        Throw "cluster not found: " + $Cluster
    }

    $virtualDisks = [System.Collections.ArrayList]@()
    ForEach ($diskSize in $Disks)
    {
        [void]$virtualDisks.Add(@{
            "size" = $diskSize;
        })
    }

    $networkInterfaces = [System.Collections.ArrayList]@()
    ForEach ($networkName in $Nics)
    {
        $network = Get-VmNetworkList | Where-Object {
            $_.name -eq $networkName
        }
        if (!$network)
        {
            Throw "network not found: " + $networkName
        }
        [void]$networkInterfaces.Add(@{
            "network" = $network.id
            "connected" = $TRUE
        })
    }

    $vm = @{
        "name" = $Name;
        "cpuCores" = $CpuCores;
        "cpuSockets" = $CpuSockets;
        "memory" = $MemoryMb;
        "networkInterfaces" = $networkInterfaces;
        "disks" = $virtualDisks;
        "userData" = $UserData;
        "computeCluster" = $computeClusterObj.name;
        "provisioningType" = $ProvisioningType;
        "tags" = $Tags;
    }

    if ($GuestId)
    {
        $vm.guestId = $GuestId
    }

    if ($CpuSockets)
    {
        if (!$PSBoundParameters.ContainsKey("CpuCores"))
        {
            throw "Cpu cores need to be defined when assigning cpu sockets"
        }

        if ($CpuCores % $CpuSockets -gt 0)
        {
            throw "Invalid number of cpu sockets, cpu cores must be divisible by cpu sockets with no remainders"
        }
    }

    if ($FirmwareEfi)
    {
        if (!$PSBoundParameters.ContainsKey("GuestId"))
        {
            throw "A guest id is nessecary to enable EFI"
        }
        $vm.firmwareEfi = $FirmwareEfi
    }

    if ($SecureBoot)
    {
        if (!$FirmwareEfi)
        {
            Throw "FirmwareEfi needs to be true in order to enable secure boot"
        }
        $vm.secureBoot = $SecureBoot;
    }

    if ($TPM)
    {
        if (!$FirmwareEfi)
        {
            Throw "FirmwareEfi needs to be true in order to include TPM"
        }
        $vm.tpm = $TPM;
    }

    if ($PowerOnAfterClone) 
    {
	    $vm.powerOnAfterClone = $PowerOnAfterClone
    }

    if ($groupObj)
    {
        $vm.group = $groupObj.name
    }

    if ($BackupProfile)
    {
        $vm.backupProfile = $BackupProfile
    }

    if ($templateObj)
    {
        $vm.template = $templateObj.name
    }

    If ($TerminationProtection)
    {
        $Vm.terminationProtectionEnabled = $TerminationProtection
    }

    if ($sourceVmObj)
    {
        $vm.sourceVirtualMachine = $SourceVmId
        For ($diskIndex = 0; $diskIndex -lt $sourceVmObj.disks.Length; $diskIndex++)
        {
            $CloneDisk = $sourceVmObj.disks[$diskIndex]
            if ($vm.disks.Length -gt $diskIndex)
            {
                $vm.disks[$diskIndex].id = $CloneDisk.id
            }
        }
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine" -RequestMethod POST -Body ($Vm | ConvertTo-Json -Depth 10)
    $Res
}

function Invoke-Vm
{
    [CmdletBinding(DefaultParameterSetName = "nameSet")]
    param(
        [parameter(ParameterSetName = "idSet", Mandatory = $TRUE)]
        [string] $Id,
        [parameter(ParameterSetName = "nameSet", Mandatory = $TRUE)]
        [string] $Name,
        [parameter(Mandatory = $TRUE)]
        [VirtualMachineControlAction] $Action
    )

    if ($Name)
    {
        $Vm = Get-Vm -Name $Name
        $Id = $Vm.id
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )/action/$( $Action )" -RequestMethod POST
    $Res
}

function Invoke-VmConsole
{
    [CmdletBinding(DefaultParameterSetName = "nameSet")]
    param(
        [parameter(ParameterSetName = "idSet", Mandatory = $TRUE)]
        [string] $Id,
        [parameter(ParameterSetName = "nameSet", Mandatory = $TRUE)]
        [string] $Name
    )

    if ($Name)
    {
        $Vm = Get-Vm -Name $Name
        $Id = $Vm.id
    }

    New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )/console" -RequestMethod POST
    Start-Process $Res.result
    $Res
}

function Get-VmSnapshots
{
    [CmdletBinding(DefaultParameterSetName = "nameSet")]
    param(
        [parameter(ParameterSetName = "idSet", Mandatory = $TRUE)]
        [string] $Id,
        [parameter(ParameterSetName = "nameSet", Mandatory = $TRUE)]
        [string] $Name
    )

    if ($Name)
    {
        $Vm = Get-Vm -Name $Name
        $Id = $Vm.id
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )/snapshot"
    $Res
}

function New-VmSnapshot
{
    [CmdletBinding(DefaultParameterSetName = "nameSet")]
    param(
        [parameter(ParameterSetName = "idSet", Mandatory = $TRUE)]
        [string] $Id,
        [parameter(ParameterSetName = "nameSet", Mandatory = $TRUE)]
        [string] $Name,
        [parameter(Mandatory = $TRUE)]
        [string] $Description,
        [switch] $Memory,
        [switch] $Quiesce
    )

    if ($Name)
    {
        $Vm = Get-Vm -Name $Name
        $Id = $Vm.id
    }

    $Snapshot = @{
        "name" = $Description
        "memory" = $Memory.IsPresent
        "quiesce" = $Quiesce.IsPresent
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )/snapshot" -RequestMethod POST -Body ($Snapshot | ConvertTo-Json)
    $Res
}

function Remove-VmSnapshot
{
    [CmdletBinding(DefaultParameterSetName = "nameSet")]
    param(
        [parameter(ParameterSetName = "idSet", Mandatory = $TRUE)]
        [string] $Id,
        [parameter(ParameterSetName = "nameSet", Mandatory = $TRUE)]
        [string] $Name,
        [parameter(Mandatory = $TRUE)]
        [int] $SnapshotId,
        [switch] $RemoveChildren
    )

    if ($Name)
    {
        $Vm = Get-Vm -Name $Name
        $Id = $Vm.id
    }

    if ($RemoveChildren.IsPresent)
    {
        $Parameters = "?removeChildren=true"
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )/snapshot/$( $SnapshotId )$( $Parameters )" -RequestMethod DELETE
    $Res
}

function Reset-VmSnapshot
{
    [CmdletBinding(DefaultParameterSetName = "nameSet")]
    param(
        [parameter(ParameterSetName = "idSet", Mandatory = $TRUE)]
        [string] $Id,
        [parameter(ParameterSetName = "nameSet", Mandatory = $TRUE)]
        [string] $Name,
        [parameter(Mandatory = $TRUE)]
        [int] $SnapshotId
    )

    if ($Name)
    {
        $Vm = Get-Vm -Name $Name
        $Id = $Vm.id
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )/snapshot/$( $SnapshotId )" -RequestMethod PUT
    $Res
}

function Get-VmTask
{
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $TRUE)]
        [string] $Id
    )

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/task/$( $Id )"
    $Res
}

function Wait-VmDeploy
{
    [CmdletBinding(DefaultParameterSetName = "nameSet")]
    param(
        [parameter(ParameterSetName = "idSet", Mandatory = $TRUE)]
        [string] $Id,
        [parameter(ParameterSetName = "nameSet", Mandatory = $TRUE)]
        [string] $Name,
        [int] $Timeout = 3600
    )

    if ($Name)
    {
        $Vm = Get-Vm -Name $Name
        $Id = $Vm.id
    }

    $Timespan = New-TimeSpan -Seconds $Timeout
    $State = ""

    $Sw = [Diagnostics.Stopwatch]::StartNew()
    while ($State -ne "POWEREDON" -and $State -ne "POWEREDOFF" -and $Sw.Elapsed -lt $Timespan)
    {
        $Vm = Get-Vm -Id $Id
        $State = $Vm.state
        Start-Sleep -Seconds 3
    }

    $Vm
}

function Wait-VmTask
{
    [CmdletBinding(DefaultParameterSetName = "taskSet")]
    param(
        [parameter(ParameterSetName = "taskSet", Mandatory = $TRUE, ValueFromPipeline = $TRUE)]
        $Task,
        [parameter(ParameterSetName = "idSet", Mandatory = $TRUE)]
        [string] $Id,
        [int] $Timeout = 60
    )

    $Timespan = New-TimeSpan -Seconds $Timeout
    $Completed = $FALSE

    if ($Task)
    {
        $Id = $Task.id
    }

    $Sw = [Diagnostics.Stopwatch]::StartNew()
    while (!$Completed -and $Sw.Elapsed -lt $Timespan)
    {
        $Task = Get-VmTask -Id $Id
        $Completed = $Task.completed
        Start-Sleep -Seconds 1
    }

    $Task
}
