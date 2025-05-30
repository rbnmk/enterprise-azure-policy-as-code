function Confirm-ParametersUsageMatches {
    [CmdletBinding()]
    param(
        $ExistingParametersObj,
        $DefinedParametersObj,
        [switch] $CompareValueEntryForExistingParametersObj,
        [switch] $CompareValueEntryForDefinedParametersObj
    )

    $existingParameters = ConvertTo-HashTable $ExistingParametersObj
    $definedParameters = ConvertTo-HashTable $DefinedParametersObj

    $allKeys = $existingParameters.Keys + $definedParameters.Keys
    if ($existingParameters.psbase.Count -ne $definedParameters.psbase.Count) {
        # parameter count changed
        return $false
    }
    $uniqueKeys = $allKeys | Sort-Object -Unique
    if ($existingParameters.psbase.Count -ne $uniqueKeys.Count -or $definedParameters.psbase.Count -ne $uniqueKeys.Count) {
        # parameter names do not match
        return $false
    }
    foreach ($existingParameterName in $existingParameters.Keys) {
        $existingParameter = $existingParameters.$existingParameterName
        $definedParameter = $definedParameters.$existingParameterName
        if ($null -eq $definedParameter) {
            $definedParameterNameArray = $definedParameters.Keys -eq $existingParameterName
            if ($definedParameterNameArray.Count -eq 0) {
                # No matching parameter name found (case insensitive)
                return $false
            }
            $definedParameterName = $definedParameterNameArray[0]
            $definedParameter = $definedParameters.$definedParameterName
        }

        if ($existingParameter -is [System.Collections.Hashtable]) {
            $existingParameterValue = $existingParameter.value
        }
        else {
            $existingParameterValue = $existingParameter
        }

        $definedParameterValue = $definedParameter
        if (($null -ne $definedParameterValue.value) -and ((-not($uniqueKeys -contains "maintenanceConfigurationResourceId")) -or (-not($uniqueKeys -contains "AzurePatchRingmaintenanceConfigurationResourceId")))) {
            if ($definedParameterValue -isnot [array]) {
                $definedParameterValue = $definedParameter.value
            }
        }
        
        if (!(Confirm-ObjectValueEqualityDeep $existingParameterValue $definedParameterValue)) {
            return $false
        }
    }
    return $true
}
