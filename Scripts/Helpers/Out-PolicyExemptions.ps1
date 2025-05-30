function Out-PolicyExemptions {
    [CmdletBinding()]
    param (
        $Exemptions,
        $Assignments,
        $PacEnvironment,
        $PolicyExemptionsFolder,
        [switch] $OutputJson,
        [switch] $OutputCsv,
        [string] $FileExtension = "json",
        [switch] $ActiveExemptionsOnly
    )

    $numberOfExemptions = $Exemptions.Count
    Write-Information "==================================================================================================="
    Write-Information "Output Exemption list ($numberOfExemptions)"
    Write-Information "==================================================================================================="

    $pacSelector = $PacEnvironment.pacSelector
    $outputPath = "$PolicyExemptionsFolder/$pacSelector"
    if (-not (Test-Path $outputPath)) {
        $null = New-Item $outputPath -Force -ItemType directory
    }

    
    #region Sort Metadata and epacMetaData
    $exemptionskeys = $Exemptions.Keys
    foreach ($key in $exemptionskeys) {
        # Create a new ordered hash table
        $orderedMetadata = [ordered]@{}
        # Get the properties of the original object and sort them alphabetically
        $metadataKeys = $Exemptions.$($key).metadata.Keys | Sort-Object
        # Add the sorted properties to the new ordered hash table
        foreach ($metadataKey in $metadataKeys) {
            $orderedMetadata.$metadataKey = $Exemptions.$($key).metadata.$metadataKey
        }
        $Exemptions.$($key).metadata = $orderedMetadata
    }

    $exemptionskeys = $Exemptions.Keys
    foreach ($key in $exemptionskeys) {
        # Create a new ordered hash table
        $orderedEpacMetadata = [ordered]@{}
        # Get the properties of the original object and sort them alphabetically
        $epacMetadataKeys = $Exemptions.$($key).metadata.epacMetadata.Keys | Sort-Object
        # Add the sorted properties to the new ordered hash table
        foreach ($epacMetadataKey in $epacMetadataKeys) {
            $orderedEpacMetadata.$epacMetadataKey = $Exemptions.$($key).metadata.epacMetadata.$epacMetadataKey
        }
        $Exemptions.$($key).metadata.epacMetadata = $orderedEpacMetadata
    }

    #region Transformations

    $policyDefinitionReferenceIdsTransform = @{
        label      = "policyDefinitionReferenceIds"
        expression = {
            if ($_.policyDefinitionReferenceIds) {
            ($_.policyDefinitionReferenceIds -join "&").ToString()
            }
            else {
                ''
            }
        }
    }
    $metadataTransformCsv = @{
        label      = "metadata"
        expression = {
            if ($_.metadata) {
                $step1 = Get-CustomMetadata -Metadata $_.metadata -Remove "pacOwnerId"
                $temp = (ConvertTo-Json $step1 -Depth 100 -Compress).ToString()
                if ($temp -eq "{}") {
                    ''
                }
                else {
                    $temp
                }
            }
            else {
                ''
            }
        }
    }
    $metadataTransformJson = @{
        label      = "metadata"
        expression = {
            if ($_.metadata) {
                $temp = Get-CustomMetadata -Metadata $_.metadata -Remove "pacOwnerId"
                $temp
            }
            else {
                $null
            }
        }
    }
    $resourceSelectorsTransform = @{
        label      = "resourceSelectors"
        expression = {
            if ($_.resourceSelectors) {
                (ConvertTo-Json $_.resourceSelectors -Depth 100 -Compress).ToString()
            }
            else {
                ''
            }
        }
    }
    $expiresInDaysTransform = @{
        label      = "expiresInDays"
        expression = {
            if ($_.expiresInDays -eq [Int32]::MaxValue) {
                'n/a'
            }
            else {
                $_.expiresInDays
            }
        }
    }
    $assignmentScopeValidationTransform = @{
        label      = "assignmentScopeValidation"
        expression = {
            if ($_.assignmentScopeValidation) {
                $_.assignmentScopeValidation
            }
            else {
                ''
            }
        }
    }

    #endregion Transformations

    Write-Information ""
    $selectedExemptions = $Exemptions.Values
    $numberOfExemptions = $selectedExemptions.Count
    if ($ActiveExemptionsOnly) {

        #region Active Exemptions

        $stem = "$outputPath/active-exemptions"
        Write-Information "==================================================================================================="
        Write-Information "Output $numberOfExemptions active (not expired or orphaned) Exemptions for epac environment '$pacSelector'"
        Write-Information "==================================================================================================="
        if ($OutputJson) {
            $selectedArray = $selectedExemptions | Where-Object status -in @("active", "active-expiring-within-15-days") | Select-Object -Property name, `
                displayName, `
                description, `
                exemptionCategory, `
                expiresOn, `
                scope, `
                policyAssignmentId, `
                policyDefinitionReferenceIds, `
                resourceSelectors, `
                $metadataTransformJson, `
                assignmentScopeValidation
            $jsonArray = @()
            if ($selectedArray -and $selectedArray.Count -gt 0) {
                $jsonArray += $selectedArray
            }
            # Logic to force the order of the Metadata property (DeployedBy first, then epacMetadata)
            foreach ($array in $jsonArray) {
                if ($null -ne $array.Metadata) {
                    $meta = $array.Metadata
                    $orderedMeta = [ordered]@{
                        deployedBy   = $meta['deployedBy']
                        epacMetadata = $meta['epacMetadata']
                    }
                    $array.Metadata = $orderedMeta
                }
            }
            $jsonFile = "$stem.$FileExtension"
            if (Test-Path $jsonFile) {
                Remove-Item $jsonFile
            }
            $outputJsonObj = [ordered]@{
                '$schema'  = "https://raw.githubusercontent.com/Azure/enterprise-azure-policy-as-code/main/Schemas/policy-exemption-schema.json"
                exemptions = $jsonArray
            }
            ConvertTo-Json $outputJsonObj -Depth 100 | Out-File $jsonFile -Force
        }
        if ($OutputCsv) {
            $selectedArray = $selectedExemptions | Where-Object status -in @("active", "active-expiring-within-15-days") | Select-Object -Property name, `
                displayName, `
                description, `
                exemptionCategory, `
                expiresOn, `
                scope, `
                policyAssignmentId, `
                $policyDefinitionReferenceIdsTransform, `
                $resourceSelectorsTransform, `
                $metadataTransformCsv, `
                $assignmentScopeValidationTransform
            $excelArray = @()
            if ($null -ne $selectedArray -and $selectedArray.Count -gt 0) {
                $excelArray += $selectedArray
            }
            # Logic to force the order of the Metadata property (DeployedBy first, then epacMetadata)
            foreach ($array in $excelArray) {
                if ($null -ne $array.Metadata) {
                    $metaString = $array.Metadata
                    $meta = $metaString | ConvertFrom-Json -Depth 100
                    $orderedMeta = [ordered]@{
                        deployedBy   = $meta.deployedBy
                        epacMetadata = $meta.epacMetadata
                    }
                    $orderedMetadata = (ConvertTo-Json $orderedMeta -Depth 100 -Compress).ToString()
                    $array.Metadata = $orderedMetadata
                }
            }
            $csvFile = "$stem.csv"
            if (Test-Path $csvFile) {
                Remove-Item $csvFile
            }
            if ($excelArray.Count -gt 0) {
                $excelArray | ConvertTo-Csv -UseQuotes AsNeeded | Out-File $csvFile -Force
            }
            else {
                $columnHeaders = "name,displayName,description,exemptionCategory,expiresOn,scope,policyAssignmentId,policyDefinitionReferenceIds,metadata,assignmentScopeValidation"
                $columnHeaders | Out-File $csvFile -Force
            }
        }

        #endregion Active Exemptions

    }
    else {

        #region All Exemptions

        $stem = "$outputPath/all-exemptions"
        Write-Information "==================================================================================================="
        Write-Information "Output $numberOfExemptions Exemptions (all) for epac environment '$pacSelector'"
        Write-Information "==================================================================================================="
        if ($OutputJson) {
            $selectedArray = $selectedExemptions | Select-Object -Property name, `
                displayName, `
                description, `
                exemptionCategory, `
                expiresOn, `
                status, `
                $expiresInDaysTransform, `
                scope, `
                policyAssignmentId, `
                policyDefinitionReferenceIds, `
                resourceSelectors, `
                $metadataTransformJson, `
                assignmentScopeValidation
            $jsonArray = @()
            if ($selectedArray -and $selectedArray.Count -gt 0) {
                $jsonArray += $selectedArray
            }
            # Logic to force the order of the Metadata property (DeployedBy first, then epacMetadata)
            foreach ($array in $jsonArray) {
                if ($null -ne $array.Metadata) {
                    $meta = $array.Metadata
                    $orderedMeta = [ordered]@{
                        deployedBy   = $meta['deployedBy']
                        epacMetadata = $meta['epacMetadata']
                    }
                    $array.Metadata = $orderedMeta
                }
            }
            $jsonFile = "$stem.$FileExtension"
            if (Test-Path $jsonFile) {
                Remove-Item $jsonFile
            }
            $outputJsonObj = [ordered]@{
                '$schema'  = "https://raw.githubusercontent.com/Azure/enterprise-azure-policy-as-code/main/Schemas/policy-exemption-schema.json"
                exemptions = $jsonArray
            }
            ConvertTo-Json $outputJsonObj -Depth 100 | Out-File $jsonFile -Force
        }
        if ($OutputCsv) {
            $selectedArray = $selectedExemptions | Select-Object -Property name, `
                displayName, `
                description, `
                exemptionCategory, `
                expiresOn, `
                status, `
                $expiresInDaysTransform, `
                scope, `
                policyAssignmentId, `
                $policyDefinitionReferenceIdsTransform, `
                $resourceSelectorsTransform, `
                $metadataTransformCsv, `
                $assignmentScopeValidationTransform
            $excelArray = @()
            if ($null -ne $selectedArray -and $selectedArray.Count -gt 0) {
                $excelArray += $selectedArray
            }
            # Logic to force the order of the Metadata property (DeployedBy first, then epacMetadata)
            foreach ($array in $excelArray) {
                if ($null -ne $array.Metadata) {
                    $metaString = $array.Metadata
                    $meta = $metaString | ConvertFrom-Json -Depth 100
                    $orderedMeta = [ordered]@{
                        deployedBy   = $meta.deployedBy
                        epacMetadata = $meta.epacMetadata
                    }
                    $orderedMetadata = (ConvertTo-Json $orderedMeta -Depth 100 -Compress).ToString()
                    $array.Metadata = $orderedMetadata
                }
            }
            $csvFile = "$stem.csv"
            if (Test-Path $csvFile) {
                Remove-Item $csvFile
            }
            if ($excelArray.Count -gt 0) {
                $excelArray | ConvertTo-Csv -UseQuotes AsNeeded | Out-File $csvFile -Force
            }
            else {
                $columnHeaders = "name,displayName,description,exemptionCategory,expiresOn,status,expiresInDays,scope,policyAssignmentId,policyDefinitionReferenceIds,metadata,assignmentScopeValidation"
                $columnHeaders | Out-File $csvFile -Force
            }

        }

        #endregion All Exemptions

    }
}
