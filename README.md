# Previder Powershell Module
The Previder Powershell Module can be used to interact with resources on the Previder IaaS environment. 
The provider needs to be configured with an API token. This token can be acquired by loggin in and navigationg to your user setting page.

## Example Usage

```
Import-Module Previder-Powershell-Module
Connect-Annexus -Token <token>
Get-VmList
New-Vm -Name "Virtual Server 01" -Cluster "express" -Template "centos8" -CpuCores 2 -MemoryMb 4048 -Nics @("Public WAN") -Disks @(20480) -Tags @()
Wait-VmDeploy -Name "Virtual Server 01"
Invoke-VmConsole -Name "Virtual Server 01"
$vm = Get-Vm -Name "Virtual Server 01"
Invoke-Vm -Name "Virtual Server 01" -Action "POWEROFF"
$task = Set-Vm -Id $vm.id -cpuCores 4
Wait-VmTask -Task $task
$task = Invoke-Vm -Name "Virtual Server 01" -Action "POWERON"
Wait-VmTask -Task $task
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

### Get-VmList
Gets all the pages of virtualmachines

### Get-VmPage
- Page (optional) - Pagenumber starting at 0 for the first page
- Size (optional) - Page size, defaults to 10
- Sort (optional) - sort on fields, defaults to name,asc
- Query (optional) - Filter query

### Get-VmNetworkList
Gets all the pages of virtualnetworks

### Get-VmNetworkPage
- Page (optional) - Pagenumber starting at 0 for the first page
- Size (optional) - Page size, defaults to 10
- Sort (optional) - sort on fields, defaults to name,asc
- Query (optional) - Filter query

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
- Disks (optional) - List of disks that will be used by the server.
- NetworkInterfaces (optional) - List of network interfaces that will be used by the server. Interfaces not included in the list will be deleted.

#### Example: Edit a list of network interfaces
Set-Vm -Id "630f560b37cd6574d8fff3f3" -NetworkInterfaces @{
"id"="630f560cd56c7b4ef50ab6a0"                          
"network"="public-wan"      
"connected"= "true"
"label" = "example1" }, @{
"id"="630f560cd56c7b4ef50ab6a0"                          
"network"="public-wan"      
"connected"= "true"
"label" = "example2" }

#### Example: Deleting a disk
Set-Vm -Id "630f560b37cd6574d8fff3f3" -Disks @{             
"id" = "630f560cd56c7b4ef50ab69e"                        
"size" = "20480"            
"label" = "Example"
"delete" = "true"        
}  





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
- TerminationProtection (optional) - Boolean of the termination protection
- Tags (optional) - List of strings to set specific tags on the Virtual Server

### Invoke-Vm
- Id (optional) - Id of the Virtual Server to send the action to (Either Id or Name is required)
- Name (optional) - Name of the Virtual Server to send the action to (Either Id or Name is required)
- Action (required) - Action to send

### Invoke-VmConsole
- Id (optional) - Id of the Virtual Server to open the console of (Either Id or Name is required)
- Name (optional) - Name of the Virtual Server to open the console of (Either Id or Name is required)

### Get-VmSnapshots
- Id (optional) - Id of the Virtual Server for which you would like to list snapshots
- Name (Optional) - Name of the Virtual Server for which you would like to list snapshots

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

### Wait-VmTask
- Id (optional) - Id of the task to wait for completion
- Task (optional) - Task to wait for completion


## Motivation

As projects besides e.g. the Previder Portal, the development team at Previder develops and maintains multiple projects aiming to integrate the previder IaaS environment.

## Contributors

* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet
* Fork the project
* Start a feature/bugfix branch
* Commit and push until you are happy with your contribution
* Send a merge request describing your exact problem, what and how you fixed it
