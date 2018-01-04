# Previder Powershell Module
The Previder Powershell Module is used to interact with resources on the Previder IaaS environment. 
The provider needs to be configured with an API token that will be provided by Previder.

## Example Usage

```
Import-Module Previder-Powershell-Module
Connect-Annexus -Token <token>
Get-VmList
New-Vm -Name "Virtual Server 01" -Cluster "Express" -Template "Ubuntu 17.10" -CpuCores 2 -MemoryMb 2048 -Nics ["Public WAN"] -Disks [20480]
Wait-VmDeploy -Name "Virtual Server 01"
Invoke-VmConsole -Name "Virtual Server 01"
```

## Argument reference

The following arguments are supported

### Connect-Annexus

*(Either Token or Accountname and Username are required)*
- Token -  This is your personal API token for accessing resources in the Previder IaaS environment.
- Accountname - This is your accountname
- Username - Enter the username with which to login
- Password - Enter the plain-text password required for the account configure above
- OTP - If OTP is enabled on this account, use this field to send the challenge code
- UseOTP - Required when manually sending your OTP challenge code
- Uri - Only used when connecting to an alternative environment (defaults to https://portal.previder.nl/api)

### Set-HandleByCustomer
- Id (optional) - Id of the subcustomer which you loke to switch to (to clear this setting, only call base function)

### Get-Customer
- Id (required) - Id of the customer which you like to show

### Get-Vm
- Id (optional) - Id of the Virtual Server you would like to show
- Name (Optional) - Name of the Virtual Server you would like to show
- VmId (optional) - Backend Id of the Virtual Server you would like to show

### Remove-Vm
- Id (optional) - Id of the Virtual Server you would like to remove
- Name (optional) - Name of the Virtual Server you would like to remove

### Set-Vm
- Id (required) - Id of the Virtual Server you would like to edit
- Name (optional) - Name to set the Virtual Server to
- Group (optional) - Name of the group to set the Virtual Server to
- CpuCores (optional) - Integer of number of cpu cores
- MemoryMb (optional) - Integer of MBs of memory to set the VM to
- TerminationProtection (optional) - Boolean of the termination protection
- Tags (optional) - List of strings to set specific tags on the Virtual Server

### New-Vm
- Name (required) - Name to set the Virtual Server to
- Group (optional) - Name of the group to set the Virtual Server to
- Cluster (required) - Name of the compute cluster to deploy the Virtual Server to
- Template (optional) - Name of the template to deploy (Either Template or SourceVmId is required)
- SourceVmId (optional) - Id of the Virtual Server to clone (Either Template or SourceVmId is required)
- CpuCores (required) - Integer of number of cpu cores
- MemoryMb (required) - Integer of MBs of memory to set the VM to
- ProvisioningType (optional) - Provide your own provisioningtype, leave blank to copy it of the template
- UserData (optional) - Send custom userdata (leave blank if you do not know what to enter)
- Nics (required) - List of network names to link the Virtual Server to
- Disks (required) - List of integers for disk sizes
- Tags (optional) - List of strings to set specific tags on the Virtual Server

### Invoke-Vm
- Id (optional) - Id of the Virtual Server to send the action to (Either Id or Name is required)
- Name (optional) - Name of the Virtual Server to send the action to (Either Id or Name is required)
- Action (required) - Action to send

### Invoke-VmConsole
- Id (optional) - Id of the Virtual Server to open the console of (Either Id or Name is required)
- Name (optional) - Name of the Virtual Server to open the console of (Either Id or Name is required)

### New-VmSnapshot
- Id (optional) - Id of the Virtual Server to create a snapshot of (Either Id or Name is required)
- Name (optional) - Name of the Virtual Server to create a snapshot of (Either Id or Name is required)
- Description (required) - Description for this snapshot

### Remove-VmSnapshot
- Id (optional) - Id of the Virtual Server to remove a snapshot of (Either Id or Name is required)
- Name (optional) - Name of the Virtual Server to remove a snapshot of (Either Id or Name is required)
- SnapshotId (required) - Integer snapshot id
- RemoveChildren (optional) - Boolean if you wish to remove all snapshots embedded in the snapshot to remove

### Reset-VmSnapshot
- Id (optional) - Id of the Virtual Server to revert a snapshot of (Either Id or Name is required)
- Name (optional) - Name of the Virtual Server to revert a snapshot of (Either Id or Name is required)
- SnapshotId (required) - Integer snapshot id

### Get-VmTask
- Id (required) - Id of the task you wish to show

### Wait-VmDeploy
- Id (optional) - Id of the Virtual Server to wait until deployed (Either Id or Name is required)
- Name (optional) - Name of the Virtual Server to wait until deployed (Either Id or Name is required)
- Timeout (optional) - Integer in seconds for timeout (defaults to 3600 or 1 hour)


## Motivation

As projects besides e.g. the Previder Portal, the development team at Previder develops and maintains multiple projects aiming to integrate the previder IaaS environment.

## Contributors

* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet
* Fork the project
* Start a feature/bugfix branch
* Commit and push until you are happy with your contribution
* Send a merge request describing your exact problem, what and how you fixed it
