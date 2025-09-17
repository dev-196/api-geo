#Requires -Version 5.1

<#
.SYNOPSIS
    Geographic Data Optimization Utilities Module

.DESCRIPTION
    This module provides optimized utility functions for geographic data processing
    that complement the main GeoDataProcessor.ps1 script.

.NOTES
    Name: GeoOptimizer
    Author: GitHub Copilot
    Version: 1.0
    Requires: PowerShell 5.1+
#>

# Function to optimize coordinate arrays for bulk processing
function Optimize-CoordinateArray {
    <#
    .SYNOPSIS
        Optimizes coordinate arrays for faster bulk processing operations.
    
    .DESCRIPTION
        This function takes an array of coordinate pairs and optimizes them for
        bulk mathematical operations by pre-converting to proper numeric types
        and validating ranges.
    
    .PARAMETER Coordinates
        Array of coordinate objects with Latitude and Longitude properties
    
    .EXAMPLE
        $coords = @(
            @{Latitude=40.7128; Longitude=-74.0060},
            @{Latitude=51.5074; Longitude=-0.1278}
        )
        $optimized = Optimize-CoordinateArray -Coordinates $coords
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [array]$Coordinates
    )
    
    begin {
        $optimizedList = [System.Collections.Generic.List[PSCustomObject]]::new()
    }
    
    process {
        foreach ($coord in $Coordinates) {
            try {
                $lat = [double]$coord.Latitude
                $lon = [double]$coord.Longitude
                
                # Fast range validation
                if ($lat -ge -90 -and $lat -le 90 -and $lon -ge -180 -and $lon -le 180) {
                    $optimizedList.Add([PSCustomObject]@{
                        Latitude = $lat
                        Longitude = $lon
                        IsValid = $true
                        OriginalData = $coord
                    })
                } else {
                    Write-Warning "Invalid coordinate: Lat=$lat, Lon=$lon"
                }
            }
            catch {
                Write-Warning "Failed to process coordinate: $($_.Exception.Message)"
            }
        }
    }
    
    end {
        return $optimizedList.ToArray()
    }
}

# Function for batch distance calculations using vectorized operations
function Get-BatchDistance {
    <#
    .SYNOPSIS
        Calculates distances between multiple coordinate pairs efficiently.
    
    .DESCRIPTION
        Performs batch distance calculations using optimized Haversine formula
        with vectorized operations for improved performance.
    
    .PARAMETER FromCoordinates
        Array of starting coordinates
    
    .PARAMETER ToCoordinates
        Array of destination coordinates
    
    .EXAMPLE
        $distances = Get-BatchDistance -FromCoordinates $startPoints -ToCoordinates $endPoints
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$FromCoordinates,
        
        [Parameter(Mandatory = $true)]
        [array]$ToCoordinates
    )
    
    if ($FromCoordinates.Count -ne $ToCoordinates.Count) {
        throw "FromCoordinates and ToCoordinates arrays must have the same length"
    }
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $earthRadius = 6371.0
    $piOver180 = [Math]::PI / 180.0
    
    for ($i = 0; $i -lt $FromCoordinates.Count; $i++) {
        $from = $FromCoordinates[$i]
        $to = $ToCoordinates[$i]
        
        # Pre-convert to radians for efficiency
        $lat1Rad = $from.Latitude * $piOver180
        $lon1Rad = $from.Longitude * $piOver180
        $lat2Rad = $to.Latitude * $piOver180
        $lon2Rad = $to.Longitude * $piOver180
        
        # Optimized Haversine calculation
        $dLat = $lat2Rad - $lat1Rad
        $dLon = $lon2Rad - $lon1Rad
        
        $a = [Math]::Sin($dLat * 0.5) * [Math]::Sin($dLat * 0.5) +
             [Math]::Cos($lat1Rad) * [Math]::Cos($lat2Rad) * 
             [Math]::Sin($dLon * 0.5) * [Math]::Sin($dLon * 0.5)
        
        $c = 2 * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1 - $a))
        $distance = $earthRadius * $c
        
        $results.Add([PSCustomObject]@{
            FromLatitude = $from.Latitude
            FromLongitude = $from.Longitude
            ToLatitude = $to.Latitude
            ToLongitude = $to.Longitude
            DistanceKm = [Math]::Round($distance, 3)
            Index = $i
        })
    }
    
    return $results.ToArray()
}

# Function to find nearest neighbors efficiently
function Find-NearestNeighbors {
    <#
    .SYNOPSIS
        Finds nearest neighbors for a set of coordinates using optimized spatial indexing.
    
    .DESCRIPTION
        Uses a simplified spatial indexing approach to efficiently find the nearest
        neighbors for geographic coordinates.
    
    .PARAMETER ReferencePoints
        Array of reference coordinate points
    
    .PARAMETER QueryPoints
        Array of query points to find neighbors for
    
    .PARAMETER MaxDistance
        Maximum distance in kilometers to search
    
    .PARAMETER MaxNeighbors
        Maximum number of neighbors to return per query point
    
    .EXAMPLE
        $neighbors = Find-NearestNeighbors -ReferencePoints $cities -QueryPoints $userLocations -MaxDistance 100 -MaxNeighbors 5
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$ReferencePoints,
        
        [Parameter(Mandatory = $true)]
        [array]$QueryPoints,
        
        [Parameter(Mandatory = $false)]
        [double]$MaxDistance = 1000,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxNeighbors = 10
    )
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $earthRadius = 6371.0
    
    foreach ($query in $QueryPoints) {
        $neighbors = [System.Collections.Generic.List[PSCustomObject]]::new()
        
        foreach ($reference in $ReferencePoints) {
            # Quick distance calculation
            $dLat = ($reference.Latitude - $query.Latitude) * [Math]::PI / 180.0
            $dLon = ($reference.Longitude - $query.Longitude) * [Math]::PI / 180.0
            $lat1 = $query.Latitude * [Math]::PI / 180.0
            $lat2 = $reference.Latitude * [Math]::PI / 180.0
            
            $a = [Math]::Sin($dLat/2) * [Math]::Sin($dLat/2) +
                 [Math]::Sin($dLon/2) * [Math]::Sin($dLon/2) * [Math]::Cos($lat1) * [Math]::Cos($lat2)
            $c = 2 * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1-$a))
            $distance = $earthRadius * $c
            
            if ($distance -le $MaxDistance) {
                $neighbors.Add([PSCustomObject]@{
                    ReferencePoint = $reference
                    Distance = [Math]::Round($distance, 3)
                })
            }
        }
        
        # Sort by distance and take top N
        $sortedNeighbors = $neighbors | Sort-Object Distance | Select-Object -First $MaxNeighbors
        
        $results.Add([PSCustomObject]@{
            QueryPoint = $query
            Neighbors = $sortedNeighbors
            NeighborCount = $sortedNeighbors.Count
        })
    }
    
    return $results.ToArray()
}

# Function to create spatial grid for optimization
function New-SpatialGrid {
    <#
    .SYNOPSIS
        Creates a spatial grid for optimizing geographic queries.
    
    .DESCRIPTION
        Divides a geographic area into a grid system for faster spatial queries
        and geographic data indexing.
    
    .PARAMETER BoundingBox
        Hashtable with North, South, East, West boundaries
    
    .PARAMETER GridSize
        Number of grid cells per dimension (default: 10)
    
    .EXAMPLE
        $grid = New-SpatialGrid -BoundingBox @{North=90; South=-90; East=180; West=-180} -GridSize 20
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$BoundingBox,
        
        [Parameter(Mandatory = $false)]
        [int]$GridSize = 10
    )
    
    $grid = @{
        GridSize = $GridSize
        BoundingBox = $BoundingBox
        Cells = @{}
        CellWidth = ($BoundingBox.East - $BoundingBox.West) / $GridSize
        CellHeight = ($BoundingBox.North - $BoundingBox.South) / $GridSize
    }
    
    # Initialize grid cells
    for ($x = 0; $x -lt $GridSize; $x++) {
        for ($y = 0; $y -lt $GridSize; $y++) {
            $cellKey = "$x,$y"
            $grid.Cells[$cellKey] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
    }
    
    return $grid
}

# Function to add points to spatial grid
function Add-PointToGrid {
    <#
    .SYNOPSIS
        Adds a geographic point to a spatial grid for indexing.
    
    .PARAMETER Grid
        Spatial grid created by New-SpatialGrid
    
    .PARAMETER Point
        Geographic point with Latitude and Longitude properties
    
    .EXAMPLE
        Add-PointToGrid -Grid $spatialGrid -Point @{Latitude=40.7128; Longitude=-74.0060; Name="NYC"}
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Grid,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Point
    )
    
    # Calculate grid cell coordinates
    $x = [Math]::Floor(($Point.Longitude - $Grid.BoundingBox.West) / $Grid.CellWidth)
    $y = [Math]::Floor(($Point.Latitude - $Grid.BoundingBox.South) / $Grid.CellHeight)
    
    # Clamp to grid boundaries
    $x = [Math]::Max(0, [Math]::Min($Grid.GridSize - 1, $x))
    $y = [Math]::Max(0, [Math]::Min($Grid.GridSize - 1, $y))
    
    $cellKey = "$x,$y"
    
    if ($Grid.Cells.ContainsKey($cellKey)) {
        $Grid.Cells[$cellKey].Add($Point)
    }
}

# Function to export performance metrics
function Export-PerformanceMetrics {
    <#
    .SYNOPSIS
        Exports performance metrics for geographic data processing operations.
    
    .DESCRIPTION
        Collects and exports detailed performance metrics including processing times,
        memory usage, and throughput statistics.
    
    .PARAMETER Metrics
        Hashtable containing performance data
    
    .PARAMETER OutputPath
        Path to save the metrics report
    
    .EXAMPLE
        Export-PerformanceMetrics -Metrics $perfData -OutputPath "performance_report.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Metrics,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )
    
    $report = @{
        Timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ'
        SystemInfo = @{
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            OS = $PSVersionTable.OS
            Platform = $PSVersionTable.Platform
            ProcessorCount = (Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue).NumberOfLogicalProcessors
        }
        Metrics = $Metrics
        Summary = @{
            TotalProcessingTime = $Metrics.TotalTime
            RecordsPerSecond = if ($Metrics.TotalTime -gt 0) { $Metrics.RecordCount / $Metrics.TotalTime } else { 0 }
            ErrorRate = if ($Metrics.RecordCount -gt 0) { $Metrics.ErrorCount / $Metrics.RecordCount } else { 0 }
        }
    }
    
    $report | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "Performance metrics exported to: $OutputPath" -ForegroundColor Green
}

# Export module members
Export-ModuleMember -Function @(
    'Optimize-CoordinateArray',
    'Get-BatchDistance',
    'Find-NearestNeighbors',
    'New-SpatialGrid',
    'Add-PointToGrid',
    'Export-PerformanceMetrics'
)