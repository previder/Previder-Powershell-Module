#
# Module 'Previder-Powershell-Module'
#

$Annexus = @{
  BaseUri = "https://portal.previder.nl";
  Uri = "https://portal.previder.nl/api";
  Headers = @{};
}

Add-Type -TypeDefinition @"
  public enum VirtualMachineControlAction {
    POWERON, RESTART, RESET, POWEROFF, SHUTDOWN, SUSPEND, INSTALL_GUEST_TOOLS,
    UPGRADE_GUEST_TOOLS, POWERON_BIOS, RESTART_BIOS, RESET_BIOS, REFRESH_STATE
  }
"@

Add-Type -TypeDefinition @"
  public enum ProvisioningType {
    NONE, CLOUD_INIT_OVF, SYSPREP, SYSPREP_TEXT
  }
"@

function Connect-Annexus {
  [CmdletBinding(DefaultParameterSetName="credSet")]
  param(
    [parameter(ParameterSetName="tokenSet", Mandatory=$TRUE)]
    [string] $Token,
    [parameter(ParameterSetName="credSet", Mandatory=$TRUE)]
    [string] $Accountname,
    [parameter(ParameterSetName="credSet", Mandatory=$TRUE)]
    [string] $Username,
    [parameter(ParameterSetName="credSet", Mandatory=$TRUE)]
    [Security.SecureString] $Password,
    [parameter(ParameterSetName="credSet", Mandatory=$FALSE)]
    [string] $OTP,
    [switch] $UseOTP,
    [string] $Uri
  )

  If ($UseOTP -and !$OTP) {
    $OTP = Read-Host 'OTP'
  }
  
  If ($Uri) {
    $Annexus.Uri = $Uri
  }
  
  If ($Token) {
    $Annexus.Headers.Add("X-Auth-Token", $Token)
  } Else {

    $UnmanagedString = [System.IntPtr]::Zero
    try {
      $UnmanagedString = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($Password);
      $UnsecurePassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($UnmanagedString);
    } finally {
      [Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($UnmanagedString);
    }
        
    $Credentials = @{
      "username"="$($Username)@$($Accountname)";
      "password"=$UnsecurePassword;
      "otp"=$OTP;
    }

    $Res = Invoke-WebRequest -SessionVariable AnnexusSession -Method GET -Uri "$($Annexus.Uri)/"
	
    $Annexus.Session = $AnnexusSession
    $Annexus.Session.Headers.Add("X-CSRF-Token", $Res.Headers["X-CSRF-Token"])
	
	
    try {
      $Res = Invoke-WebRequest -WebSession $Annexus.Session -Method POST -Uri "$($Annexus.Uri)/logincheck" -Body $Credentials
    } catch {
      Write-Host "Error logging in"
      return
    }
	
	# Newly required block of code since release of 19/12/2017
    $Res = Invoke-WebRequest -WebSession $Annexus.Session -Headers $Annexus.Headers -Method GET -Uri "$($Annexus.Uri)/session"
	$Annexus.Session.Headers.Set_Item("X-CSRF-Token", $Res.Headers["X-CSRF-Token"])
	# End of newly required block of code since release of 19/12/2017
	
    Write-Host "Logged in successfully"
    $Res
  }
}

function Disconnect-Annexus {
  [CmdletBinding()]
  param()

  $Res = Invoke-WebRequest -WebSession $Annexus.Session -Method POST -Uri "$($Annexus.BaseUri)/logout"

  $Annexus.Headers.Remove("X-Auth-Token")
  if($Annexus.Session.Headers.ContainsKey('X-Auth-Token')){
     $Annexus.Session.Headers.Remove("X-Auth-Token")
  }
  Write-Host "Logged out"
}

function Set-HandleByCustomer {
  [CmdletBinding()]
  param(
    [parameter(Mandatory=$FALSE)]
    [string] $Id
  )
  
  if ($Id) {
    $Customer = Get-Customer -Id $Id
    Write-Host "Handle by customer $($Customer.name)"
    $Annexus.Headers.Add("X-CustomerId", $Customer.id)
  } else {
    Write-Host "Clear handle by customer"
    $Annexus.Headers.Remove("X-CustomerId")
    $Annexus.Session.Headers.Remove("X-CustomerId")
  }
}

function Get-CustomerList {
  [CmdletBinding()]
  param()
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method GET -Uri "$($Annexus.Uri)/customer"
  $Res
}

function Get-Customer {
  [CmdletBinding()]
  param(
    [parameter(Mandatory=$TRUE)]
    [string] $Id
  )
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method GET -Uri "$($Annexus.Uri)/customer/$($Id)"
  $Res
}


function Get-VmList {
  [CmdletBinding()]
  param()
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method GET -Uri "$($Annexus.Uri)/virtualmachine"
  $Res
}

function Get-VmNetworkList {
  [CmdletBinding()]
  param()
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method GET -Uri "$($Annexus.Uri)/virtualnetwork"
  $Res
}

function Get-VmClusterList {
  [CmdletBinding()]
  param()
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method GET -Uri "$($Annexus.Uri)/virtualmachine/cluster"
  $Res
}

function Get-VmTemplateList {
  [CmdletBinding()]
  param()
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method GET -Uri "$($Annexus.Uri)/virtualmachine/template"
  $Res
}

function Get-VmGroupList {
  [CmdletBinding()]
  param()
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method GET -Uri "$($Annexus.Uri)/configurationitem/group"
  $Res
}

function Get-Vm {
  [CmdletBinding(DefaultParameterSetName="nameSet")]
  param(
    [parameter(ParameterSetName="idSet", Mandatory=$TRUE)]
    [string] $Id,
    [parameter(ParameterSetName="nameSet", Mandatory=$TRUE)]
    [string] $Name,
    [parameter(ParameterSetName="vmIdSet", Mandatory=$TRUE)]
    [string] $VmId
  )

  If ($Id) {
    $Uri = "$($Annexus.Uri)/virtualmachine/$($Id)"
  } ElseIf ($Name) {
    $Uri = "$($Annexus.Uri)/virtualmachine/byname/$($Name)"
  } ElseIf ($VmId) {
    $Uri = "$($Annexus.Uri)/virtualmachine/byvmid/$($VmId)"
  }
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method GET -Uri $Uri
  $Res
}

function Remove-Vm {
  [CmdletBinding(DefaultParameterSetName="nameSet")]
  param(
    [parameter(ParameterSetName="idSet", Mandatory=$TRUE)]
    [string] $Id,
    [parameter(ParameterSetName="nameSet", Mandatory=$TRUE)]
    [string] $Name
  )
  
  if ($Name) {
    $Vm = Get-Vm -Name $Name
    $Id = $Vm.id
  }
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method DELETE -Uri "$($Annexus.Uri)/virtualmachine/$($Id)"
  $Res
}

function Set-Vm {
  [CmdletBinding()]
  param(
    [parameter(Mandatory=$TRUE)]
    [string] $Id,
    [string] $Name,
    [string] $Group,
    [int] $CpuCores,
    [int] $MemoryMb,
    [boolean] $TerminationProtection,
    [string[]] $Tags
  )
  
  $Vm = Get-Vm -Id $Id
  
  If ($Name) {
    $Vm.name = $Name
  }

  If ($CpuCores) {
    $Vm.cpuCores = $CpuCores
  }
  
  If ($MemoryMb) {
    $Vm.memoryMb = $MemoryMb
  }
  
  if ($Tags) {
	$Vm.tags = $Tags
  }
  
  If ($TerminationProtection) {
    $Vm.terminationProtection = $TerminationProtection
  }
  
  if ($Group) {
    $groupObj = VmGroupList | Where-Object {$_.name -eq $Group}
    if (!$groupObj) {
      Throw "group not found: " + $Group
    }
    $Vm.group = $groupObj
  }
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method PUT -Uri "$($Annexus.Uri)/virtualmachine/$($Id)" -Body ($Vm | ConvertTo-Json -Depth 10)
  $Res
}

function New-Vm {
  [CmdletBinding(DefaultParameterSetName="newSet")]
  param(
    [parameter(Mandatory=$TRUE)]
    [string] $Name,
    [string] $Group,
    [string] $Cluster = "Express",
    [parameter(ParameterSetName="newSet", Mandatory=$TRUE)]
    [string] $Template,
    [parameter(ParameterSetName="copySet", Mandatory=$TRUE)]
    [string] $SourceVmId,
    [int] $CpuCores = 1,
    [int] $MemoryMb = 1024,
    [ProvisioningType] $ProvisioningType,
    [string] $UserData,
    [parameter(Mandatory=$TRUE)]
    [string[]] $Nics,
    [parameter(Mandatory=$TRUE)]
    [int[]] $Disks,
    [string[]] $Tags
  )
  
  if ($Group) {
    $groupObj = Get-VmGroupList | Where-Object {$_.name -eq $Group}
    if (!$groupObj) {
      Throw "group not found: " + $Group
    }
  }

  If ($Template) {
    $templateObj = Get-VmTemplateList | Where-Object {$_.name -eq $Template}
    if (!$templateObj) {
      Throw "template not found: " + $Template
    }
  } ElseIf ($SourceVmId) {
    $sourceVmObj = Get-Vm -Id $SourceVmId
    if (!$sourceVmObj) {
      Throw "source vm not found: " + $SourceVmId
    }
  }

  $computeClusterObj = Get-VmClusterList | Where-Object {$_.name -eq $Cluster}
  if (!$computeClusterObj) {
    Throw "cluster not found: " + $Cluster
  }
  
  $virtualDisks = [System.Collections.ArrayList]@()
  ForEach ($diskSize in $Disks) {
    [void]$virtualDisks.Add(@{
      "diskSize"=$diskSize;
    })
  }

  $networkInterfaces = [System.Collections.ArrayList]@()
  ForEach ($networkName in $Nics) {
    $network = Get-VmNetworkList | Where-Object {$_.name -eq $networkName}
    if (!$network) {
      Throw "network not found: " + $networkName
    }
    [void]$networkInterfaces.Add(@{
      "network"=@{
        "id"=$network.id
      };
      "connected"=$TRUE;
    })
  }
  
  $vm = @{
    "name"=$Name;
    "cpuCores"=$CpuCores;
    "memoryMb"=$MemoryMb;
    "networkInterfaces"=$networkInterfaces;
    "virtualDisks"=$virtualDisks;
    "userData"=$UserData;
    "group"=$groupObj;
    "template"=$templateObj;
    "computeCluster"=$computeClusterObj;
    "provisioningType"=$ProvisioningType;
	"tags"=$Tags
  }
  
  if ($sourceVmObj) {
    $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method POST -Uri "$($Annexus.Uri)/virtualmachine/$($SourceVmId)/clone" -Body ($Vm | ConvertTo-Json -Depth 10) -ContentType "application/json"
  } else {
    $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method POST -Uri "$($Annexus.Uri)/virtualmachine" -Body ($Vm | ConvertTo-Json -Depth 10) -ContentType "application/json"
  }
  $Res
}

function Invoke-Vm {
  [CmdletBinding(DefaultParameterSetName="nameSet")]
  param(
    [parameter(ParameterSetName="idSet", Mandatory=$TRUE)]
    [string] $Id,
    [parameter(ParameterSetName="nameSet", Mandatory=$TRUE)]
    [string] $Name,
    [parameter(Mandatory=$TRUE)]
    [VirtualMachineControlAction] $Action
  )
  
  if ($Name) {
    $Vm = Get-Vm -Name $Name
    $Id = $Vm.id
  }
 
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method POST -Uri "$($Annexus.Uri)/virtualmachine/$($Id)/control/$($Action)" -ContentType "application/json"
  $Res
}

function Invoke-VmConsole {
  [CmdletBinding(DefaultParameterSetName="nameSet")]
  param(
    [parameter(ParameterSetName="idSet", Mandatory=$TRUE)]
    [string] $Id,
    [parameter(ParameterSetName="nameSet", Mandatory=$TRUE)]
    [string] $Name
  )
  
  if ($Name) {
    $Vm = Get-Vm -Name $Name
    $Id = $Vm.id
  }
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method POST -Uri "$($Annexus.Uri)/virtualmachine/$($Id)/console" -ContentType "application/json"
  Start-Process $Res.result
  $Res
}


function New-VmSnapshot {
  [CmdletBinding(DefaultParameterSetName="nameSet")]
  param(
    [parameter(ParameterSetName="idSet", Mandatory=$TRUE)]
    [string] $Id,
    [parameter(ParameterSetName="nameSet", Mandatory=$TRUE)]
    [string] $Name,
    [parameter(Mandatory=$TRUE)]
    [string] $Decription,
    [switch] $Memory,
    [switch] $Quiesce
  )
  
  if ($Name) {
    $Vm = Get-Vm -Name $Name
    $Id = $Vm.id
  }
  
  $Snapshot = @{
    "name"=$Description
    "memory"=$Memory;
    "quiesce"=$Quiesce;
  }
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method POST -Uri "$($Annexus.Uri)/virtualmachine/$($Id)/snapshot" -Body ($Snapshot | ConvertTo-Json) -ContentType "application/json"
  $Res
}

function Remove-VmSnapshot {
  [CmdletBinding(DefaultParameterSetName="nameSet")]
  param(
    [parameter(ParameterSetName="idSet", Mandatory=$TRUE)]
    [string] $Id,
    [parameter(ParameterSetName="nameSet", Mandatory=$TRUE)]
    [string] $Name,
    [parameter(Mandatory=$TRUE)]
    [int] $SnapshotId,
    [switch] $RemoveChildren
  )

  if ($Name) {
    $Vm = Get-Vm -Name $Name
    $Id = $Vm.id
  }
  
  $Snapshot = @{
    "removeChildren"=$RemoveChildren.IsPresent;
  }
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method PUT -Uri "$($Annexus.Uri)/virtualmachine/$($Id)/snapshot/$($SnapshotId)/remove" -Body ($Snapshot | ConvertTo-Json)
  $Res
}

function Reset-VmSnapshot {
  [CmdletBinding(DefaultParameterSetName="nameSet")]
  param(
    [parameter(ParameterSetName="idSet", Mandatory=$TRUE)]
    [string] $Id,
    [parameter(ParameterSetName="nameSet", Mandatory=$TRUE)]
    [string] $Name,
    [parameter(Mandatory=$TRUE)]
    [int] $SnapshotId
  )
  
  if ($Name) {
    $Vm = Get-Vm -Name $Name
    $Id = $Vm.id
  }
  
  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method PUT -Uri "$($Annexus.Uri)/virtualmachine/$($Id)/snapshot/$($SnapshotId)/revert"
  $Res
}

function Get-VmTask {
  [CmdletBinding()]
  param(
    [parameter(Mandatory=$FALSE)]
    [string] $Id
  )

  $Res = Invoke-RestMethod -WebSession $Annexus.Session -Headers $Annexus.Headers -Method GET -Uri "$($Annexus.Uri)/configurationitem/task/$($Id)"
  $Res
}

function Wait-VmDeploy {
  [CmdletBinding(DefaultParameterSetName="nameSet")]
  param(
    [parameter(ParameterSetName="idSet", Mandatory=$TRUE)]
    [string] $Id,
    [parameter(ParameterSetName="nameSet", Mandatory=$TRUE)]
    [string] $Name,
    [int] $Timeout = 3600
  )
  
  if ($Name) {
    $Vm = Get-Vm -Name $Name
    $Id = $Vm.id
  }
  
  $Timespan = New-TimeSpan -Seconds $Timeout
  $State = ""
   
  $Sw = [Diagnostics.Stopwatch]::StartNew()
  while (!$State -eq "POWEREDON" -and $Sw.Elapsed -lt $Timespan) {
    $Vm = Get-Vm -Id $Id
    $State = $Vm.state
    Start-Sleep -Seconds 3
  }
  
  $Vm
}

function Wait-VmTask {
  [CmdletBinding(DefaultParameterSetName="taskSet")]
  param(
    [parameter(ParameterSetName="taskSet", Mandatory=$TRUE, ValueFromPipeline=$TRUE)]
    $Task,
    [parameter(ParameterSetName="idSet", Mandatory=$TRUE)]
    [string] $Id,
    [int] $Timeout = 60
  )
  
  $Timespan = New-TimeSpan -Seconds $Timeout
  $Completed = $FALSE
  
  if ($Task){
    $Id = $Task.id
  }
  
  $Sw = [Diagnostics.Stopwatch]::StartNew()
  while (!$Completed -and $Sw.Elapsed -lt $Timespan) {
    $Task = Get-VmTask -Id $Id
    $Completed = $Task.completed
    Start-Sleep -Seconds 1
  }

  $Task
}
