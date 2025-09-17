<#
.SYNOPSIS
    Optimized PowerShell script for geographic data processing and API operations.

.DESCRIPTION
    This script provides optimized functions for processing geographic data, validating coordinates,
    calculating distances, and interacting with geo APIs. It's designed for high performance with
    proper error handling and comprehensive functionality.

.PARAMETER InputFile
    Path to the input file containing geographic data (CSV, JSON, or XML format).

.PARAMETER OutputFile
    Path to the output file where processed data will be saved.

.PARAMETER ApiEndpoint
    Base URL for the geo API endpoint.

.PARAMETER Format
    Output format: 'JSON', 'CSV', or 'XML'. Default is 'JSON'.

.PARAMETER Parallel
    Enable parallel processing for improved performance with large datasets.

.EXAMPLE
    .\GeoDataProcessor.ps1 -InputFile "locations.csv" -OutputFile "processed.json" -Parallel

.EXAMPLE
    .\GeoDataProcessor.ps1 -ApiEndpoint "https://api.example.com/geo" -Format "CSV"

.NOTES
    Author: GitHub Copilot
    Version: 1.0
    Optimized for performance and reliability
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$InputFile,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputFile,
    
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^https?://')]
    [string]$ApiEndpoint,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('JSON', 'CSV', 'XML', 'GeoJSON')]
    [string]$Format = 'JSON',
    
    [Parameter(Mandatory = $false)]
    [switch]$Parallel
)

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import required modules with error handling
try {
    Import-Module Microsoft.PowerShell.Utility -Force
    Write-Verbose "Required modules imported successfully"
}
catch {
    Write-Error "Failed to import required modules: $($_.Exception.Message)"
    exit 1
}

# Global variables for optimization
$script:ProcessedCount = 0
$script:ErrorCount = 0
$script:StartTime = Get-Date

#region Helper Functions

function Test-Coordinate {
    <#
    .SYNOPSIS
        Validates geographic coordinates with optimized performance.
    .PARAMETER Latitude
        Latitude value to validate (-90 to 90)
    .PARAMETER Longitude
        Longitude value to validate (-180 to 180)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [double]$Latitude,
        
        [Parameter(Mandatory = $true)]
        [double]$Longitude
    )
    
    # Optimized validation using direct comparison
    return ($Latitude -ge -90 -and $Latitude -le 90) -and 
           ($Longitude -ge -180 -and $Longitude -le 180)
}

function Get-DistanceHaversine {
    <#
    .SYNOPSIS
        Calculates distance between two points using optimized Haversine formula.
    .PARAMETER Lat1, Lon1
        First point coordinates
    .PARAMETER Lat2, Lon2
        Second point coordinates
    .OUTPUTS
        Distance in kilometers
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [double]$Lat1,
        
        [Parameter(Mandatory = $true)]
        [double]$Lon1,
        
        [Parameter(Mandatory = $true)]
        [double]$Lat2,
        
        [Parameter(Mandatory = $true)]
        [double]$Lon2
    )
    
    # Earth radius in kilometers
    $earthRadius = 6371.0
    
    # Convert degrees to radians (optimized calculation)
    $dLat = [Math]::PI * ($Lat2 - $Lat1) / 180.0
    $dLon = [Math]::PI * ($Lon2 - $Lon1) / 180.0
    $lat1Rad = [Math]::PI * $Lat1 / 180.0
    $lat2Rad = [Math]::PI * $Lat2 / 180.0
    
    # Haversine formula (optimized for performance)
    $a = [Math]::Sin($dLat / 2) * [Math]::Sin($dLat / 2) +
         [Math]::Sin($dLon / 2) * [Math]::Sin($dLon / 2) * 
         [Math]::Cos($lat1Rad) * [Math]::Cos($lat2Rad)
    
    $c = 2 * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1 - $a))
    
    return $earthRadius * $c
}

function ConvertTo-GeoJson {
    <#
    .SYNOPSIS
        Converts geographic data to optimized GeoJSON format.
    .PARAMETER GeoData
        Array of geographic data objects
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$GeoData
    )
    
    # Pre-allocate StringBuilder for better performance
    $jsonBuilder = [System.Text.StringBuilder]::new()
    [void]$jsonBuilder.AppendLine('{"type": "FeatureCollection", "features": [')
    
    $featureCount = $GeoData.Count
    for ($i = 0; $i -lt $featureCount; $i++) {
        $item = $GeoData[$i]
        
        # Build feature object efficiently
        $feature = @{
            type = "Feature"
            geometry = @{
                type = "Point"
                coordinates = @($item.Longitude, $item.Latitude)
            }
            properties = @{}
        }
        
        # Add all properties except coordinates
        foreach ($prop in $item.PSObject.Properties) {
            if ($prop.Name -notin @('Latitude', 'Longitude')) {
                $feature.properties[$prop.Name] = $prop.Value
            }
        }
        
        # Convert to JSON and append
        $featureJson = $feature | ConvertTo-Json -Depth 3 -Compress
        [void]$jsonBuilder.Append($featureJson)
        
        if ($i -lt ($featureCount - 1)) {
            [void]$jsonBuilder.AppendLine(',')
        } else {
            [void]$jsonBuilder.AppendLine()
        }
    }
    
    [void]$jsonBuilder.AppendLine(']}')
    return $jsonBuilder.ToString()
}

function Invoke-GeoApiRequest {
    <#
    .SYNOPSIS
        Makes optimized API requests with retry logic and error handling.
    .PARAMETER Endpoint
        API endpoint URL
    .PARAMETER Data
        Data to send in the request
    .PARAMETER Method
        HTTP method (default: GET)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        
        [Parameter(Mandatory = $false)]
        [object]$Data,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]$Method = 'GET'
    )
    
    $maxRetries = 3
    $retryDelay = 1
    
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $params = @{
                Uri = $Endpoint
                Method = $Method
                ContentType = 'application/json'
                TimeoutSec = 30
            }
            
            if ($Data -and $Method -in @('POST', 'PUT')) {
                $params.Body = $Data | ConvertTo-Json -Depth 10
            }
            
            $response = Invoke-RestMethod @params
            Write-Verbose "API request successful on attempt $attempt"
            return $response
        }
        catch {
            Write-Warning "API request failed on attempt $attempt`: $($_.Exception.Message)"
            
            if ($attempt -eq $maxRetries) {
                throw "API request failed after $maxRetries attempts: $($_.Exception.Message)"
            }
            
            Start-Sleep -Seconds ($retryDelay * $attempt)
        }
    }
}

function ProcessGeoDataChunk {
    <#
    .SYNOPSIS
        Processes a chunk of geographic data (optimized for parallel execution).
    .PARAMETER DataChunk
        Array of data items to process
    .PARAMETER ChunkIndex
        Index of the current chunk (for logging)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$DataChunk,
        
        [Parameter(Mandatory = $true)]
        [int]$ChunkIndex
    )
    
    $processedItems = [System.Collections.Generic.List[object]]::new()
    $chunkErrors = 0
    
    foreach ($item in $DataChunk) {
        try {
            # Validate coordinates
            if (-not (Test-Coordinate -Latitude $item.Latitude -Longitude $item.Longitude)) {
                Write-Warning "Invalid coordinates for item in chunk $ChunkIndex`: Lat=$($item.Latitude), Lon=$($item.Longitude)"
                $chunkErrors++
                continue
            }
            
            # Add processing timestamp
            $item | Add-Member -MemberType NoteProperty -Name 'ProcessedAt' -Value (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ') -Force
            
            # Add validation status
            $item | Add-Member -MemberType NoteProperty -Name 'IsValid' -Value $true -Force
            
            $processedItems.Add($item)
        }
        catch {
            Write-Error "Error processing item in chunk $ChunkIndex`: $($_.Exception.Message)"
            $chunkErrors++
        }
    }
    
    return @{
        ProcessedItems = $processedItems.ToArray()
        ErrorCount = $chunkErrors
        ChunkIndex = $ChunkIndex
    }
}

#endregion

#region Main Processing Functions

function Import-GeoData {
    <#
    .SYNOPSIS
        Imports geographic data from various file formats with optimized parsing.
    .PARAMETER FilePath
        Path to the input file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    Write-Verbose "Importing data from: $FilePath"
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    
    try {
        switch ($extension) {
            '.csv' {
                # Optimized CSV import with type inference
                $data = Import-Csv -Path $FilePath -Encoding UTF8
                
                # Convert numeric columns efficiently
                foreach ($row in $data) {
                    if ($row.PSObject.Properties['Latitude']) {
                        $row.Latitude = [double]$row.Latitude
                    }
                    if ($row.PSObject.Properties['Longitude']) {
                        $row.Longitude = [double]$row.Longitude
                    }
                }
                
                return $data
            }
            
            '.json' {
                # Optimized JSON import
                $jsonContent = Get-Content -Path $FilePath -Raw -Encoding UTF8
                return $jsonContent | ConvertFrom-Json
            }
            
            '.xml' {
                # Optimized XML import
                [xml]$xmlContent = Get-Content -Path $FilePath -Encoding UTF8
                return $xmlContent
            }
            
            default {
                throw "Unsupported file format: $extension"
            }
        }
    }
    catch {
        throw "Failed to import data from $FilePath`: $($_.Exception.Message)"
    }
}

function Export-GeoData {
    <#
    .SYNOPSIS
        Exports geographic data to specified format with optimization.
    .PARAMETER Data
        Data to export
    .PARAMETER FilePath
        Output file path
    .PARAMETER Format
        Export format
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Data,
        
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('JSON', 'CSV', 'XML', 'GeoJSON')]
        [string]$Format
    )
    
    Write-Verbose "Exporting $($Data.Count) items to $FilePath in $Format format"
    
    try {
        # Ensure output directory exists
        $outputDir = [System.IO.Path]::GetDirectoryName($FilePath)
        if ($outputDir -and (-not (Test-Path -Path $outputDir))) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        switch ($Format.ToUpper()) {
            'JSON' {
                $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $FilePath -Encoding UTF8
            }
            
            'CSV' {
                $Data | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
            }
            
            'XML' {
                $xmlDoc = [System.Xml.XmlDocument]::new()
                $root = $xmlDoc.CreateElement('GeoData')
                $xmlDoc.AppendChild($root) | Out-Null
                
                foreach ($item in $Data) {
                    $itemElement = $xmlDoc.CreateElement('Item')
                    
                    foreach ($prop in $item.PSObject.Properties) {
                        $propElement = $xmlDoc.CreateElement($prop.Name)
                        $propElement.InnerText = $prop.Value
                        $itemElement.AppendChild($propElement) | Out-Null
                    }
                    
                    $root.AppendChild($itemElement) | Out-Null
                }
                
                $xmlDoc.Save($FilePath)
            }
            
            'GeoJSON' {
                $geoJson = ConvertTo-GeoJson -GeoData $Data
                $geoJson | Set-Content -Path $FilePath -Encoding UTF8
            }
        }
        
        Write-Verbose "Data exported successfully to $FilePath"
    }
    catch {
        throw "Failed to export data to $FilePath`: $($_.Exception.Message)"
    }
}

function Start-ParallelProcessing {
    <#
    .SYNOPSIS
        Processes geographic data using parallel execution for optimal performance.
    .PARAMETER Data
        Array of data to process
    .PARAMETER ChunkSize
        Size of each processing chunk (default: 1000)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Data,
        
        [Parameter(Mandatory = $false)]
        [int]$ChunkSize = 1000
    )
    
    Write-Verbose "Starting parallel processing with chunk size: $ChunkSize"
    
    # Calculate optimal chunk size based on data size and CPU cores
    $cpuCores = (Get-CimInstance -ClassName Win32_Processor).NumberOfLogicalProcessors
    $optimalChunkSize = [Math]::Max(1, [Math]::Ceiling($Data.Count / ($cpuCores * 2)))
    $actualChunkSize = [Math]::Min($ChunkSize, $optimalChunkSize)
    
    Write-Verbose "Using chunk size: $actualChunkSize for $($Data.Count) items across $cpuCores CPU cores"
    
    # Split data into chunks
    $chunks = @()
    for ($i = 0; $i -lt $Data.Count; $i += $actualChunkSize) {
        $endIndex = [Math]::Min($i + $actualChunkSize - 1, $Data.Count - 1)
        $chunks += , $Data[$i..$endIndex]
    }
    
    Write-Verbose "Created $($chunks.Count) chunks for parallel processing"
    
    # Process chunks in parallel using runspaces for better performance
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $cpuCores)
    $runspacePool.Open()
    
    $jobs = @()
    
    try {
        for ($i = 0; $i -lt $chunks.Count; $i++) {
            $scriptBlock = {
                param($chunk, $chunkIndex, $functionDef)
                
                # Import function definitions into runspace
                . ([ScriptBlock]::Create($functionDef))
                
                return ProcessGeoDataChunk -DataChunk $chunk -ChunkIndex $chunkIndex
            }
            
            # Get function definitions to pass to runspace
            $functionDef = "
                function Test-Coordinate {
                    param([double]`$Latitude, [double]`$Longitude)
                    return (`$Latitude -ge -90 -and `$Latitude -le 90) -and (`$Longitude -ge -180 -and `$Longitude -le 180)
                }
                
                function ProcessGeoDataChunk {
                    param([array]`$DataChunk, [int]`$ChunkIndex)
                    `$processedItems = [System.Collections.Generic.List[object]]::new()
                    `$chunkErrors = 0
                    
                    foreach (`$item in `$DataChunk) {
                        try {
                            if (-not (Test-Coordinate -Latitude `$item.Latitude -Longitude `$item.Longitude)) {
                                `$chunkErrors++
                                continue
                            }
                            
                            `$item | Add-Member -MemberType NoteProperty -Name 'ProcessedAt' -Value (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ') -Force
                            `$item | Add-Member -MemberType NoteProperty -Name 'IsValid' -Value `$true -Force
                            
                            `$processedItems.Add(`$item)
                        }
                        catch {
                            `$chunkErrors++
                        }
                    }
                    
                    return @{
                        ProcessedItems = `$processedItems.ToArray()
                        ErrorCount = `$chunkErrors
                        ChunkIndex = `$ChunkIndex
                    }
                }
            "
            
            $powerShell = [powershell]::Create()
            $powerShell.RunspacePool = $runspacePool
            $powerShell.AddScript($scriptBlock).AddParameter('chunk', $chunks[$i]).AddParameter('chunkIndex', $i).AddParameter('functionDef', $functionDef) | Out-Null
            
            $jobs += @{
                PowerShell = $powerShell
                Handle = $powerShell.BeginInvoke()
                Index = $i
            }
        }
        
        # Collect results
        $allResults = @()
        $totalErrors = 0
        
        foreach ($job in $jobs) {
            try {
                $result = $job.PowerShell.EndInvoke($job.Handle)
                $allResults += $result.ProcessedItems
                $totalErrors += $result.ErrorCount
                Write-Verbose "Completed chunk $($result.ChunkIndex) with $($result.ErrorCount) errors"
            }
            catch {
                Write-Error "Error in parallel job $($job.Index): $($_.Exception.Message)"
                $totalErrors++
            }
            finally {
                $job.PowerShell.Dispose()
            }
        }
        
        $script:ProcessedCount = $allResults.Count
        $script:ErrorCount = $totalErrors
        
        return $allResults
    }
    finally {
        $runspacePool.Close()
        $runspacePool.Dispose()
    }
}

#endregion

#region Main Execution

function Main {
    <#
    .SYNOPSIS
        Main execution function with comprehensive error handling and performance monitoring.
    #>
    
    Write-Host "🌍 Geographic Data Processor v1.0" -ForegroundColor Green
    Write-Host "Started at: $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
    
    try {
        $processedData = @()
        
        # Import data if input file specified
        if ($InputFile) {
            Write-Host "📄 Importing data from: $InputFile" -ForegroundColor Yellow
            $rawData = Import-GeoData -FilePath $InputFile
            Write-Host "✅ Imported $($rawData.Count) records" -ForegroundColor Green
            
            # Process data
            if ($Parallel -and $rawData.Count -gt 100) {
                Write-Host "⚡ Starting parallel processing..." -ForegroundColor Yellow
                $processedData = Start-ParallelProcessing -Data $rawData
            } else {
                Write-Host "🔄 Processing data sequentially..." -ForegroundColor Yellow
                $result = ProcessGeoDataChunk -DataChunk $rawData -ChunkIndex 0
                $processedData = $result.ProcessedItems
                $script:ProcessedCount = $processedData.Count
                $script:ErrorCount = $result.ErrorCount
            }
            
            Write-Host "✅ Processed $($script:ProcessedCount) records with $($script:ErrorCount) errors" -ForegroundColor Green
        }
        
        # Test API endpoint if specified
        if ($ApiEndpoint) {
            Write-Host "🌐 Testing API endpoint: $ApiEndpoint" -ForegroundColor Yellow
            try {
                $apiResponse = Invoke-GeoApiRequest -Endpoint "$ApiEndpoint/health" -Method GET
                Write-Host "✅ API endpoint is accessible" -ForegroundColor Green
                
                if ($processedData.Count -gt 0) {
                    Write-Host "📤 Sending sample data to API..." -ForegroundColor Yellow
                    $sampleData = $processedData | Select-Object -First 5
                    $apiResult = Invoke-GeoApiRequest -Endpoint "$ApiEndpoint/process" -Method POST -Data $sampleData
                    Write-Host "✅ API processing completed" -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "API endpoint test failed: $($_.Exception.Message)"
            }
        }
        
        # Export results if output file specified
        if ($OutputFile -and $processedData.Count -gt 0) {
            Write-Host "💾 Exporting processed data to: $OutputFile" -ForegroundColor Yellow
            Export-GeoData -Data $processedData -FilePath $OutputFile -Format $Format
            Write-Host "✅ Export completed" -ForegroundColor Green
        }
        
        # Performance summary
        $endTime = Get-Date
        $duration = $endTime - $script:StartTime
        
        Write-Host "`n📊 Performance Summary:" -ForegroundColor Cyan
        Write-Host "   ⏱️  Total Duration: $($duration.ToString('hh\:mm\:ss\.fff'))" -ForegroundColor White
        Write-Host "   📈 Records Processed: $($script:ProcessedCount)" -ForegroundColor White
        Write-Host "   ❌ Errors: $($script:ErrorCount)" -ForegroundColor White
        
        if ($duration.TotalSeconds -gt 0) {
            $recordsPerSecond = [Math]::Round($script:ProcessedCount / $duration.TotalSeconds, 2)
            Write-Host "   🚀 Processing Rate: $recordsPerSecond records/second" -ForegroundColor White
        }
        
        Write-Host "`n🎉 Processing completed successfully!" -ForegroundColor Green
    }
    catch {
        Write-Error "❌ Processing failed: $($_.Exception.Message)"
        Write-Host "Stack Trace:" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        exit 1
    }
}

#endregion

# Execute main function if script is run directly
if ($MyInvocation.InvocationName -ne '.') {
    Main
}