#check if the IT Glue API is provided
If($ITG_API -eq $null){
    $ITG_API = $ITG_API = Read-Host "Enter your API key" #Ask for the IT Glue API  Key
}
else{
    Write-Host "Using existing API:" $ITG_API
}
#Find the encrypted disk
$blinfo = Get-BitLockerVolume
Foreach ($item in $blinfo){
    if($item.ProtectionStatus -eq 'On'-and $item.EncryptionPercentage -eq '100'){
        $MountPoint = $item.MountPoint
        Write-Host "Encrypted MountPoint: "$MountPoint
    }
}
#Fetch the BitLocker key and Find the configuration in IT Glue
#===============================================================
Foreach($MP in $MountPoint){
try{
$bitlocker = (Get-BitLockerVolume -MountPoint $MP).KeyProtector | ? {$_.KeyProtectorType -eq "RecoveryPassword"}
$username = $bitlocker.KeyProtectorId.trim('{}')
$password = $bitlocker.RecoveryPassword
$hostname = hostname
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "application/vnd.api+json")
$headers.Add("x-api-key", "$ITG_API")
$configdetail = Invoke-RestMethod "https://api.itglue.com/configurations?page[size]=1000&filter[name]=$hostname" -Method 'GET' -Headers $headers
$configID = $configdetail.data.id
$organization_id = $configdetail.data.attributes.'organization-id'
If (!$configID){
    Write-Host "Configuration with name " $hostname "does not exist in IT Glue! Make sure that a configuration exists"
    break
}
else{
    Write-Host "Configuration with name " $hostname "exist in IT Glue!"
    Write-Host "Configuration ID: "$configID
}
}
catch [System.Management.Automation.CommandNotFoundException],[System.Net.WebException],[System.IO.IOException] {
Write-Host $_.Exception.Message
}
#Check if the password exist already, update if exist and create new one if missing!
#======================================================================================
$checkpass = Invoke-RestMethod "https://api.itglue.com/passwords?filter[name]=$hostname - Bitlocker Key&filter[organization_id]=$organization_id" -Method 'GET' -Headers $headers
if($checkpass.data.attributes.name -eq "$hostname - Bitlocker Key" ){
    $passwordID = $checkpass.data.id
    Write-Host "Updating existing bitlocker key credentials with password ID" $passwordID "under organization "$checkpass.data.attributes.'organization-name'
    $body = @"
{
  `"data`": {
    `"type`": `"passwords`",
    `"attributes`": {
      `"username`": `"$username`",
      `"password`": `"$password`",
      `"resource-id`": `"$configID`",
      `"resource-type`": `"Configuration`"
    }
  }
}
"@
    $updatingpassword = Invoke-RestMethod "https://api.itglue.com/passwords/$passwordID" -Method 'PATCH' -Headers $headers -Body $body
}
else{
Write-Host "Creating a new bitlocker key record for the configuration" $hostname
$body = @"
{
  `"data`": {
    `"type`": `"passwords`",
    `"attributes`": {
      `"name`": `"$hostname - Bitlocker Key`",
      `"username`": `"$username`",
      `"password`": `"$password`",
      `"resource-id`": `"$configID`",
      `"resource-type`": `"Configuration`"
    }
  }
}
"@
Invoke-RestMethod "https://api.itglue.com/organizations/$organization_id/relationships/passwords" -Method 'POST' -Headers $headers -Body $body
}
}
