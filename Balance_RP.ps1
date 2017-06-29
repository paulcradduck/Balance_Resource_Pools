# http://wahlnetwork.com/2012/02/01/understanding-resource-pools-in-vmware-vsphere/
# If you have 1 cluster with 100 VM, 90 Prod and 10 Dev and you want prod to get double the prioirty
# of the Dev the math is below and the script to do set it all is here as well.
#
# The Math: 
# If you have 90 Production VMs = [ 90 VMs ] * [ 100 shares/per VM ] = 9,000 shares of RAM and CPU
# If you have 10 Dev/Test would get [ 10 VMs ] * [ 50 shares/per VM ] = 500 shares of RAM and CPU
#
#

## Variables
$vcenter = $args[0]
$cluster = $args[1]

## Gather RPools
Connect-VIServer $vcenter
[array]$rpools = Get-ResourcePool -Location (Get-Cluster $cluster)
cls

## Enumerate Members of RPools
Foreach ($rpool in $rpools)
	{
	If ($rpool.name -ne "Resources")
		{
		[int]$pervmshares = Read-Host "How many shares per VM in the $($rpool.Name) resource pool?"
		$totalvms = $rpool.ExtensionData.Vm.count
		[int]$rpshares = $pervmshares * $totalvms
		Write-Host -ForegroundColor Green -BackgroundColor Black $rpool.name
		Write-Host "Found $totalvms in the $($rpool.name) resource pool. At $pervmshares each, this pool should be set to $rpshares shares."
		Set-ResourcePool -ResourcePool $rpool.Name -CpuSharesLevel:Custom -NumCpuShares $rpshares -MemSharesLevel:Custom -NumMemShares $rpshares -Confirm:$true | Out-Null
		}
	}
