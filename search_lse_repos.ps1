# Initialize arrays to store results
$allResults = @()
$codeDetails = @()

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "LSE DATA ANALYTICS GITHUB SEARCH" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Search for repos with "LSE Data Analytics" in name/description/README
Write-Host "Step 1: Searching repositories..." -ForegroundColor Yellow
$page = 1
$repoCount = 0

do {
    try {
        $results = gh api -H "Accept: application/vnd.github+json" `
          "/search/repositories?q=%22LSE%20Data%20Analytics%22%20in%3Aname,description,readme&per_page=100&page=$page" `
          --jq ".items[] | {name: .full_name, description: .description, url: .html_url, stars: .stargazers_count, language: .language, updated: .updated_at}"
        
        if ($results) {
            $results | ForEach-Object {
                $item = $_ | ConvertFrom-Json
                $allResults += [PSCustomObject]@{
                    Repository = $item.name
                    URL = $item.url
                    Description = if ($item.description) { $item.description.Replace("`n", " ").Replace("`r", " ") } else { "" }
                    Stars = $item.stars
                    Language = if ($item.language) { $item.language } else { "Not specified" }
                    LastUpdated = $item.updated
                    FoundIn = "Repository Search"
                    SearchType = "Name/Description/README"
                }
                $repoCount++
            }
            Write-Host "  ✓ Page $page processed ($repoCount repos found so far)" -ForegroundColor Gray
            $page++
            Start-Sleep -Milliseconds 500  # Rate limiting
        }
    } catch {
        Write-Host "  ⚠ Reached API limit or error occurred" -ForegroundColor Red
        break
    }
} while ($results -and $page -le 10)

Write-Host "  Repository search complete: $repoCount repositories found" -ForegroundColor Green

# Search for code containing "LSE Data Analytics"
Write-Host "`nStep 2: Searching code files..." -ForegroundColor Yellow
$page = 1
$codeCount = 0
$codeRepoList = @{}

do {
    try {
        $results = gh api -H "Accept: application/vnd.github+json" `
          "/search/code?q=%22LSE%20Data%20Analytics%22%20in%3Afile&per_page=100&page=$page" `
          --jq ".items[] | {name: .repository.full_name, url: .repository.html_url, file: .path, fileUrl: .html_url}"
        
        if ($results) {
            $results | ForEach-Object {
                $item = $_ | ConvertFrom-Json
                
                # Add to detailed code results
                $codeDetails += [PSCustomObject]@{
                    Repository = $item.name
                    RepositoryURL = $item.url
                    FilePath = $item.file
                    FileURL = $item.fileUrl
                    FileType = if ($item.file -match '\.([^.]+)$') { $matches[1].ToUpper() } else { "Unknown" }
                }
                
                # Track unique repos from code search
                if (-not $codeRepoList.ContainsKey($item.name)) {
                    $codeRepoList[$item.name] = $item.url
                    $allResults += [PSCustomObject]@{
                        Repository = $item.name
                        URL = $item.url
                        Description = ""
                        Stars = ""
                        Language = ""
                        LastUpdated = ""
                        FoundIn = "Code Search"
                        SearchType = "Code Content"
                    }
                }
                $codeCount++
            }
            Write-Host "  ✓ Page $page processed ($codeCount code files found so far)" -ForegroundColor Gray
            $page++
            Start-Sleep -Milliseconds 500  # Rate limiting
        }
    } catch {
        Write-Host "  ⚠ Reached API limit or error occurred" -ForegroundColor Red
        break
    }
} while ($results -and $page -le 10)

Write-Host "  Code search complete: $codeCount files in $($codeRepoList.Count) repositories" -ForegroundColor Green

# Process and create CSV files
Write-Host "`nStep 3: Processing and creating CSV files..." -ForegroundColor Yellow

# 1. COMBINED CSV (all results, including duplicates)
$combinedPath = "lse_repos_combined.csv"
$allResults | Sort-Object Repository, FoundIn | Export-Csv -Path $combinedPath -NoTypeInformation -Encoding UTF8
Write-Host "  ✓ Combined results saved to: $combinedPath" -ForegroundColor Green

# 2. DEDUPLICATED CSV (unique repositories only)
$uniqueRepos = @{}
foreach ($result in $allResults) {
    if ($uniqueRepos.ContainsKey($result.Repository)) {
        # Update existing entry
        $existing = $uniqueRepos[$result.Repository]
        
        # Merge FoundIn information
        if ($existing.FoundIn -notlike "*$($result.FoundIn)*") {
            $existing.FoundIn = "Repository Search + Code Search"
            $existing.SearchType = "Multiple"
        }
        
        # Fill in missing information
        if (-not $existing.Description -and $result.Description) {
            $existing.Description = $result.Description
        }
        if (-not $existing.Stars -and $result.Stars) {
            $existing.Stars = $result.Stars
        }
        if (-not $existing.Language -and $result.Language) {
            $existing.Language = $result.Language
        }
        if (-not $existing.LastUpdated -and $result.LastUpdated) {
            $existing.LastUpdated = $result.LastUpdated
        }
    } else {
        $uniqueRepos[$result.Repository] = $result
    }
}

$uniquePath = "lse_repos_unique.csv"
$uniqueResults = $uniqueRepos.Values | Sort-Object Repository
$uniqueResults | Export-Csv -Path $uniquePath -NoTypeInformation -Encoding UTF8
Write-Host "  ✓ Unique repositories saved to: $uniquePath" -ForegroundColor Green

# 3. CODE DETAILS CSV (all files containing "LSE Data Analytics")
if ($codeDetails.Count -gt 0) {
    $codePath = "lse_code_files_detailed.csv"
    $codeDetails | Sort-Object Repository, FilePath | Export-Csv -Path $codePath -NoTypeInformation -Encoding UTF8
    Write-Host "  ✓ Code file details saved to: $codePath" -ForegroundColor Green
}

# Display summary statistics
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SEARCH RESULTS SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nStatistics:" -ForegroundColor Yellow
Write-Host "  • Total entries (with duplicates): $($allResults.Count)" -ForegroundColor White
Write-Host "  • Unique repositories: $($uniqueResults.Count)" -ForegroundColor White
Write-Host "  • Repositories from name/description search: $repoCount" -ForegroundColor White
Write-Host "  • Repositories from code search: $($codeRepoList.Count)" -ForegroundColor White
Write-Host "  • Total code files found: $($codeDetails.Count)" -ForegroundColor White

# Show repositories found in both searches
$foundInBoth = $uniqueResults | Where-Object { $_.FoundIn -eq "Repository Search + Code Search" }
if ($foundInBoth.Count -gt 0) {
    Write-Host "`n  • Repositories found in BOTH searches: $($foundInBoth.Count)" -ForegroundColor Magenta
}

# Language statistics
Write-Host "`nTop Programming Languages:" -ForegroundColor Yellow
$languageStats = $uniqueResults | 
    Where-Object { $_.Language -and $_.Language -ne "Not specified" } | 
    Group-Object Language | 
    Sort-Object Count -Descending | 
    Select-Object -First 5

foreach ($lang in $languageStats) {
    Write-Host "  • $($lang.Name): $($lang.Count) repositories" -ForegroundColor White
}

# File type statistics from code search
if ($codeDetails.Count -gt 0) {
    Write-Host "`nTop File Types in Code Search:" -ForegroundColor Yellow
    $fileTypeStats = $codeDetails | 
        Group-Object FileType | 
        Sort-Object Count -Descending | 
        Select-Object -First 5
    
    foreach ($type in $fileTypeStats) {
        Write-Host "  • .$($type.Name): $($type.Count) files" -ForegroundColor White
    }
}

# Show top repositories by stars
$topStarred = $uniqueResults | 
    Where-Object { $_.Stars } | 
    Sort-Object { [int]$_.Stars } -Descending | 
    Select-Object -First 5

if ($topStarred.Count -gt 0) {
    Write-Host "`nTop 5 Most Starred Repositories:" -ForegroundColor Yellow
    foreach ($repo in $topStarred) {
        Write-Host "  • $($repo.Repository) (⭐ $($repo.Stars))" -ForegroundColor White
        Write-Host "    $($repo.URL)" -ForegroundColor Gray
    }
}

# Show sample of unique repositories
Write-Host "`nSample of Unique Repositories (first 10):" -ForegroundColor Yellow
$uniqueResults | Select-Object -First 10 | ForEach-Object {
    Write-Host "  • $($_.Repository)" -ForegroundColor White
    Write-Host "    $($_.URL)" -ForegroundColor Gray
    if ($_.Description) {
        $shortDesc = if ($_.Description.Length -gt 60) { 
            $_.Description.Substring(0, 57) + "..." 
        } else { 
            $_.Description 
        }
        Write-Host "    $shortDesc" -ForegroundColor DarkGray
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "FILES CREATED:" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. $combinedPath - All results including duplicates" -ForegroundColor White
Write-Host "2. $uniquePath - Deduplicated unique repositories" -ForegroundColor White
if ($codeDetails.Count -gt 0) {
    Write-Host "3. $codePath - Detailed list of code files" -ForegroundColor White
}
Write-Host "`nSearch complete! 🎉" -ForegroundColor Green