#
# Module 'Previder-Powershell-Module'
#

$Annexus = @{
    BaseUri = "https://portal.previder.nl";
    Uri = "https://portal.previder.nl/api";
    Headers = @{ };
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

    if ($Body)
    {
        $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method $RequestMethod -Uri $Uri -ContentType $DefaultRequestMethod -Body $Body
    }
    else
    {
        $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method $RequestMethod -Uri $Uri -ContentType $DefaultRequestMethod
    }

    $Res

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
        [string] $Sort = "name,asc"
    )

    $QueryParams = @{
        "page" = $Page
        "size" = $Size
        "query" = $Query
        "sort" = $Sort
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/" -Body $QueryParams
    $Res

}

function Get-VmList
{
    [CmdletBinding()]
    param()

    $Res = @()
    $Page = 0
    do
    {
        $PageRes = Get-VmPage -Page $Page
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

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/computecluster/"
    $Res
}

function Get-VmTemplateList
{
    [CmdletBinding()]
    param()

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/template/"
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
        [string] $Name,
        [string] $Group,
        [string] $Cluster,
        [string[]] $DeleteNetworkInterface,
        [string[]] $DeleteDisk,
        [int] $CpuCores,
        [int] $MemoryMb,
        [string[]] $Tags,
        [boolean] $TerminationProtection
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

    if ($Cluster)
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
    if ($Name)
    {
        $vm.name = $Name
    }
    if ($DeleteNetworkInterface)
    {
        [System.Collections.ArrayList]$currentNetworkInterfaces = $vm.networkInterfaces
        ForEach ($deleteId in $DeleteNetworkInterface)
        {
            $interfaceToDelete = $currentNetworkInterfaces | Where-Object {
                $_.id -eq $deleteId
            }
            $currentNetworkInterfaces.Remove($interfaceToDelete)
        }
        $vm.networkInterfaces = $currentNetworkInterfaces
    }
    if ($DeleteDisk)
    {
        [System.Collections.ArrayList]$currentDisks = $vm.disks
        ForEach ($deleteId in $DeleteDisk)
        {
            $diskToDelete = $currentDisks | Where-Object {
                $_.id -eq $deleteId
            }
            $diskToDelete | Add-Member -NotePropertyName delete -NotePropertyValue true
        }
    }

    if ($CpuCores)
    {
        $vm.cpuCores = $CpuCores
    }

    if ($MemoryMb)
    {
        $vm.memory = $MemoryMb
    }

    if ($computeClusterObj)
    {
        $vm.computeCluster = $computeClusterObj.name
    }

    if ($Tags)
    {
        $vm.tags = $Tags
    }

    if ($groupObj)
    {
        $vm.group = $groupObj.name
    }

    If ($TerminationProtection)
    {
        $Vm.terminationProtectionEnabled = $TerminationProtection
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )" -RequestMethod PUT -Body ($Vm | ConvertTo-Json -Depth 10)
    $Res
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
        [int] $CpuCores = 1,
        [int] $MemoryMb = 1024,
        [ProvisioningType] $ProvisioningType,
        [string] $UserData,
        [parameter(Mandatory = $TRUE)]
        [string[]] $Nics,
        [parameter(Mandatory = $TRUE)]
        [int[]] $Disks,
        [string[]] $Tags,
        [boolean] $TerminationProtection
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
        "memory" = $MemoryMb;
        "networkInterfaces" = $networkInterfaces;
        "disks" = $virtualDisks;
        "userData" = $UserData;
        "computeCluster" = $computeClusterObj.name;
        "provisioningType" = $ProvisioningType;
        "tags" = $Tags
    }

    if ($groupObj)
    {
        $vm.group = $groupObj.name
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

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/" -RequestMethod POST -Body ($Vm | ConvertTo-Json -Depth 10)
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

    $Snapshot = @{
        "removeChildren" = $RemoveChildren.IsPresent;
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/iaas/virtualmachine/$( $Id )/snapshot/$( $SnapshotId )" -RequestMethod DELETE -Body ($Snapshot | ConvertTo-Json)
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
    while (!$State -eq "POWEREDON" -and !$State -eq "POWEREDOFF" -and $Sw.Elapsed -lt $Timespan)
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
