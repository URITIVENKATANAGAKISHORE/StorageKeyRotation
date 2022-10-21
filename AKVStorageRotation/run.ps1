param($eventGridEvent, $TriggerMetadata)

function RegenerateKey($keyId, $providerAddress){
    Write-Host "Regenerating key. Id: $keyId Resource Id: $providerAddress"
    
    $storageAccountName = ($providerAddress -split '/')[8]
    $resourceGroupName = ($providerAddress -split '/')[4]
    
    #Regenerate key 
    New-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName -KeyName $keyId
    $newKeyValue = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $storageAccountName|where KeyName -eq $keyId).value

    return $newKeyValue
}

function AddSecretToKeyVault($keyVaultName,$secretName,$newAccessKeyValue,$exprityDate,$tags){
    
    $secretvalue = ConvertTo-SecureString "$newAccessKeyValue" -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -SecretValue $secretvalue -Tag $tags -Expires $expiryDate

}

function GetAlternateCredentialId($keyId){
    $validCredentialIdsRegEx = 'key[1-2]'
    
    If($keyId -NotMatch $validCredentialIdsRegEx){
        throw "Invalid credential id: $keyId. Credential id must follow this pattern:$validCredentialIdsRegEx"
    }
    If($keyId -eq 'key1'){
        return "key2"
    }
    Else{
        return "key1"
    }
}

function RoatateSecret($keyVaultName,$secretName, $StorageName ,$resourcegroupName){
    #Retrieve Secret
    $secret = (Get-AzKeyVaultSecret --VaultName $keyVaultName -Name $secretName)
    Write-Host "Secret Retrieved"
    
    if ( ($null -eq $secret ) -or ( $secret -eq "") ) {
        Write-Host "secert is empty , Now Creating New secert"
        $StorageresourceId = $(Get-AzStorageAccount -ResourceGroupName $resourcegroupName -Name $StorageName).id

        $Tags = @{ ValidityPeriodDays = 60 ; CredentialId = 'key1' ; ProviderAddress = $StorageresourceId  }
        #Add new access key to Key Vault
        $validityPeriodDays = $Tags.$validityPeriodDays
        $credentialId =$alternateCredentialId
        $providerAddress = $providerAddress

        Write-Host "Secret Info Retrieved"
        Write-Host "Validity Period: " $validityPeriodDays
        Write-Host "Credential Id: " $credentialId
        Write-Host "Provider Address: "$providerAddress

        #Regenerate alternate access key in provider
        $newAccessKeyValue = (RegenerateKey $alternateCredentialId $providerAddress)[-1]
        Write-Host "Access key regenerated. Access Key Id: " $alternateCredentialId " Resource Id: " $providerAddress

        #Add new access key to Key Vault
        $newSecretVersionTags = @{}
        $newSecretVersionTags.ValidityPeriodDays = $validityPeriodDays
        $newSecretVersionTags.CredentialId=$alternateCredentialId
        $newSecretVersionTags.ProviderAddress = $providerAddress

        $expiryDate = (Get-Date).AddDays([int]$validityPeriodDays).ToUniversalTime()
        AddSecretToKeyVault $keyVaultName $secretName $newAccessKeyValue $expiryDate $newSecretVersionTags

        Write-Host "New access key added to Key Vault. Secret Name: " $secretName

    }
    else {
        #Retrieve Secret Info
        $validityPeriodDays = $secret.Tags["ValidityPeriodDays"]
        $credentialId=  $secret.Tags["CredentialId"]
        $providerAddress = $secret.Tags["ProviderAddress"]
        
        Write-Host "Secret Info Retrieved"
        Write-Host "Validity Period: " $validityPeriodDays
        Write-Host "Credential Id: " $credentialId
        Write-Host "Provider Address: " $providerAddress

        #Get Credential Id to rotate - alternate credential
        $alternateCredentialId = GetAlternateCredentialId $credentialId
        Write-Host "Alternate credential id: " $alternateCredentialId

        #Regenerate alternate access key in provider
        $newAccessKeyValue = (RegenerateKey $alternateCredentialId $providerAddress)[-1]
        Write-Host "Access key regenerated. Access Key Id: " $alternateCredentialId " Resource Id: " $providerAddress

        #Add new access key to Key Vault
        $newSecretVersionTags = @{}
        $newSecretVersionTags.ValidityPeriodDays = $validityPeriodDays
        $newSecretVersionTags.CredentialId=$alternateCredentialId
        $newSecretVersionTags.ProviderAddress = $providerAddress

        $expiryDate = (Get-Date).AddDays([int]$validityPeriodDays).ToUniversalTime()
        AddSecretToKeyVault $keyVaultName $secretName $newAccessKeyValue $expiryDate $newSecretVersionTags

        Write-Host "New access key added to Key Vault. Secret Name: " $secretName
    }
}

# Make sure to pass hashtables to Out-String so they're logged correctly
$eventGridEvent = @{
    subject = 'rotekey1'
    data = @{
        VaultName = 'vaultrotation-kvs'
        storageAccName = 'vaultrotationstorages'
        resourcegroup = 'vaultrotation'
    } 
}

$eventGridEvent | ConvertTo-Json | Write-Host

$secretName = $eventGridEvent.subject
$keyVaultName = $eventGridEvent.data.VaultName
$StorageName = $eventGridEvent.data.storageAccName
$resourcegroupName = $eventGridEvent.data.resourcegroup

Write-Host "Key Vault Name: " $keyVaultName
Write-Host "Secret Name: " $secretName
Write-Host "Storage Account Name: " $StorageName
Write-Host "Resource Group Name: " $resourcegroup

#Rotate secret
Write-Host "Rotation started."
RoatateSecret $keyVaultName $secretName $StorageName $resourcegroup
Write-Host "Secret Rotated Successfully"

