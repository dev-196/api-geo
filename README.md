# api-geo

Geographic API project with optimized PowerShell processing tools.

## Components

### 🚀 GeoDataProcessor.ps1
Optimized PowerShell script for high-performance geographic data processing with:
- Parallel processing using runspaces
- Multiple format support (CSV, JSON, XML, GeoJSON)
- API integration with retry logic
- Comprehensive error handling and performance monitoring

### 🔧 GeoOptimizer.psm1
PowerShell module providing utility functions for:
- Coordinate array optimization
- Batch distance calculations
- Nearest neighbor search
- Spatial grid indexing

### 📊 Test-Optimizations.ps1
Comprehensive test suite validating all optimization features.

## Quick Start

```powershell
# Process geographic data with parallel execution
.\GeoDataProcessor.ps1 -InputFile "data.csv" -OutputFile "processed.json" -Parallel

# Test all optimizations
.\Test-Optimizations.ps1
```

See [GeoProcessor-README.md](GeoProcessor-README.md) for detailed documentation.