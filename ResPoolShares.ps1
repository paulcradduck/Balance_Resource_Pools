
#######################################################################################
# Copyright Andrew Mitchell 2009
#
# You may freely use and redistribute this script as long as this 
# copyright notice remains intact 
#
#
# DISCLAIMER. THIS SCRIPT IS PROVIDED TO YOU "AS IS" WITHOUT WARRANTIES OR CONDITIONS 
# OF ANY KIND, WHETHER ORAL OR WRITTEN, EXPRESS OR IMPLIED. THE AUTHOR SPECIFICALLY 
# DISCLAIMS ANY IMPLIED WARRANTIES OR CONDITIONS OF MERCHANTABILITY, SATISFACTORY 
# QUALITY, NON-INFRINGEMENT AND FITNESS FOR A PARTICULAR PURPOSE. 
#
#
# Note : I know the script could have been made shorter by using pipes more extensively,
# but the aim was to make the script functionality and methodology clear so I have 
# left loops etc. fully exposed and not obfuscated within pipes.


#######################################################################################
############## Modify the following variables to suit your environment  ###############

$vCenterServer = "vcenter.fqdn.com"
$User = "vCenter_User"
$Password = "vCenter_Password"

# We need to specify the cluster name as the same Resource Pool names might exist within
# multiple clusters
$Cluster = "cluster_name"

# IMPORTANT NOTE
# Only specify resource pools that are in the same level within the resource pool heirarchy.
# Do not specify a combination of parent and child pools.
# These resource pools must already exist within the cluster specified above.
# Specify a comma seperated collection of resource pools
$ResourcePools = @("ResPool1", "ResPool2", "ResPool3")


#The share values you specify below will be used to determine the weighting of resources available
#to each pool, but will not be the actual share values applied.
$PoolCPUShares = @(80, 15, 5)
$PoolMemShares = @(80, 15, 5)


#Specify the maximum share value we want to apply. The highest priority resource pool will be set 
#to this value. Other pools will be proportionally lower, based on the $PoolCPUShares, $PoolMemshares
#and workloads present within the resource pools
$SharesUpperLimit = 8000

#Specify the minimum share value you want applied to each resource pool. This will ensure that empty 
#resource pools will not end up with zero shares.

$MinPoolCPUshares = 100
$MinPoolMemShares = 100


#Do we want the CPU share weighting based on the number of virtual machines within the resource pool, or the number of vCPUs?
#(vCPUs is the default method used by vSphere when specifying Low, Medium or High shares on a per-VM basis)
$CountvCPUs = $true


#######################################################################################
############## Do not modify anything beyond this point  ##############################
#######################################################################################


Connect-VIServer $vCenterServer -User $User -Password $Password
$ArrayIndex = 0
$NumvCPUs = new-object object[] $ResourcePools.length
$NumVMs = new-object object[] $ResourcePools.length
$TotalMemory = new-Object object[] $ResourcePools.length
$ArrayIndex = 0

Foreach ($ResourcePool in $ResourcePools)
{
	$NumvCPUs[$arrayindex] =0
	$NumVMs[$ArrayIndex] =0
	$TotalMemory[$ArrayIndex] = 0
	$pool = Get-ResourcePool -Name $ResourcePool -location $Cluster
		
			Foreach ($VM in ($pool |Get-VM | where {$_.PowerState -eq "PoweredOn"})) #We only care about running VMs
			{
				#Count the number of allocated vCPUs within the Resource Pool
				$NumvCPUs[$arrayindex] += ($VM).NumCpu
				#Count the number of VMs
				$NumVMs[$arrayindex] += 1
				# Count the total memory allocated within the Resource Pool
				$TotalMemory[$ArrayIndex] += ($VM).MemoryMB 
			}
	Write-Host "Discovered " $NumvCPUs[$arrayindex] "running vCPUs in resource pool " $ResourcePool
	Write-Host "Discovered " $NumVMs[$arrayindex] "running virtual machines in resource pool " $ResourcePool
	Write-Host $TotalMemory[$arrayIndex] "MB of memory allocated in resource pool"
	$ArrayIndex += 1		
		
}


#Calculate memory shares
for ($i=0; $i -lt ($PoolMemShares.length); $i++)
{
	$PoolMemShares[$i] = [int]$PoolMemShares[$i] * [int]$TotalMemory[$i]	
}

#Calculate CPU shares
#
#If $CountvCPUs has been defined as true we will base the shares on the number of vCPUs we found in the resource pool. This
#is the standard mechanism used for CPU share values within VI3 and vSphere and is highly recommmended. Otherwise we will just count
#number of VMs and ignore the number of vCPUs

for ($i=0; $i -lt ($PoolCPUShares.length); $i++)
{	
	if ($CountvCPUs)
	{
		$PoolCPUShares[$i] = [int]$PoolCPUShares[$i] * [int]$numvCPUs[$i]
	}
	else
	{
		$PoolCPUShares[$i] = [int]$PoolCPUShares[$i] * [int]$numVMs[$i]	
	} 
}

# Find the largest array members so we can set the shares to a sensible value
$MaxMemShares = $PoolMemShares[0]
for ($i=0; $i -lt $PoolMemShares.length; $i++)
{
	if ($PoolMemShares[$i] -gt $MaxMemShares)
	{
		$MaxMemShares = $PoolMemShares[$i]
	}
}
	
$MaxCPUShares = $PoolCPUShares[0]
for ($i=0; $i -lt $PoolCPUShares.length; $i++)
{
	if ($PoolCPUShares[$i] -gt $MaxCPUShares)
	{
		$MaxCPUShares = $PoolCPUShares[$i]
	}
}


If ($MaxCPUShares -gt 0)
{
	#Set the highest share to a maximum of $SharesUpperLimit. All other shares will be a proprtional value of $SharesUpperLimit
	$CPUShareMultiplier = $SharesUpperLimit / $MaxCPUShares
		
	for ($i=0; $i -lt $PoolCPUShares.length; $i++)
	{
		$PoolCPUShares[$i] = [int]($PoolCPUShares[$i] * $CPUShareMultiplier)
		#If we're below the minimum, readjust
		if ($PoolCPUShares[$i] -lt $MinPoolCPUshares)  { $PoolCPUShares[$i] = $MinPoolCPUshares}
		Write-Host "Resource Pool " $ResourcePools[$i] " : " $PoolCPUShares[$i] " CPU shares"
	}

}
else
{
	Write-Host "Warning: No running VMs found within cluster or CPU shares have been defined as 0 (zero)"
	#Set it to the minimum specified by the user
	for ($i=0; $i -lt $PoolCPUShares.length; $i++)
	{
		$PoolCPUShares[$i] = $MinPoolCPUshares
		Write-Host "Resource Pool " $ResourcePools[$i] " : " $PoolCPUShares[$i] " CPU shares"
	}
}
	
if ($MaxMemShares -gt 0) 
{
	$MemShareMultiplier = $SharesUpperLimit / $MaxMemShares

	for ($i=0; $i -lt $PoolMemShares.length; $i++)
	{
		$PoolMemShares[$i] = [int]($PoolMemShares[$i] * $MemShareMultiplier)
		#If we're below the minimum, readjust
		if ($PoolMemShares[$i] -lt $MinPoolMemshares)  { $PoolMemShares[$i] = $MinPoolMemshares}
		
		Write-Host "Resource Pool " $ResourcePools[$i] " : " $PoolMemShares[$i] " memory shares"
	}
	
}
else
{
	Write-Host "Warning: No running VMs found or Memory shares have been defined as 0 (zero)"
	#Set it to the minimum specified by the user
	for ($i=0; $i -lt $PoolMemShares.length; $i++)
	{
		$PoolMemShares[$i] = $MinPoolMemshares
		Write-Host "Resource Pool " $ResourcePools[$i] " : " $PoolMemShares[$i] " memory shares"
	}
}



#Loop through each Resource Pool and set the CPU and memory shares that have been calculated
$ArrayIndex = 0

Foreach ($ResourcePool in $ResourcePools)
	{
		$pool = Get-ResourcePool -Name $ResourcePool -location $Cluster
		Set-Resourcepool -Resourcepool $Pool -CPUsharesLevel Custom -NumCpuShares $PoolCPUShares[$ArrayIndex] -MemSharesLevel Custom -NumMemShares $PoolMemShares[$ArrayIndex] 
		$ArrayIndex += 1		
		
	}
	

