param(
	[Parameter(Mandatory = $false)]
	[string]$SinglePackage,
	[Parameter(Mandatory = $false)]
	[string]$Token
)

# Resolve token: parameter > environment variables
$resolvedToken = if ($Token)
{
	$Token
}
elseif ($env:NANOS_PERSONAL_ACCESS_TOKEN)
{
	$env:NANOS_PERSONAL_ACCESS_TOKEN
}
elseif ($env:NANOS_API_KEY)
{
	$env:NANOS_API_KEY
}
elseif ($env:NANOS_STORE_TOKEN)
{
	$env:NANOS_STORE_TOKEN
}
else
{
	Write-Error "No token provided. Use -Token parameter or set NANOS_PERSONAL_ACCESS_TOKEN, NANOS_API_KEY, or NANOS_STORE_TOKEN environment variable."
	exit 1
}

$vaultRoot = "$PSScriptRoot\.."
$serverRoot = "$PSScriptRoot\..\.."
$binDir = "$vaultRoot\bin"
$packagesDir = "$serverRoot\Packages"
$publishDir = "$vaultRoot\publish"
$packagesJsonPath = "$vaultRoot\packages.json"

if (Test-Path -Path $packagesJsonPath)
{
	$packagesConfig = Get-Content -Raw -Path $packagesJsonPath | ConvertFrom-Json

	$packagesToProcess = if ($SinglePackage)
	{
		@{ $SinglePackage = $packagesConfig.$SinglePackage }
	}
	else
	{
		$packagesConfig.PSObject.Properties | ForEach-Object { @{ $_.Name = $_.Value } }
	}
}
else
{
	# Fallback: use *.zip files in publish folder
	$publishPath = $publishDir
	if (-not (Test-Path -Path $publishPath))
	{
		Write-Error "publish folder not found at: $publishPath"
		exit 1
	}

	$zipFiles = Get-ChildItem -Path $publishPath -Filter "*.zip"
	if (-not $zipFiles)
	{
		Write-Error "No .zip files found in: $publishPath"
		exit 1
	}

	$packagesToProcess = if ($SinglePackage)
	{
		@{ $SinglePackage = $SinglePackage }
	}
	else
	{
		$zipFiles | ForEach-Object { @{ $_.BaseName = $_.BaseName } }
	}
}

Push-Location $packagesDir

foreach ($packageEntry in $packagesToProcess)
{
	$folderName = $packageEntry.Keys[0]
	$packageName = $packageEntry.Values[0]

	if (-not $packageName)
	{
		Write-Warning "Package '$folderName' not found in packages.json"
		continue
	}

	Write-Host "Processing package: $packageName"

	# Run the packager to create a zip file for each package
	# --token "$resolvedToken"
	& "$binDir\packager.exe" -- "$vaultRoot\$folderName"
	if ($LASTEXITCODE -ne 0)
	{
		Write-Error "Packager failed (exit code: $LASTEXITCODE)"
		continue
	}
	# Check if zip file exists before extracting
	$zipFilePath = "$publishDir\$packageName.zip"
	if (-not (Test-Path -Path $zipFilePath))
	{
		Write-Error "Zip file not found: $zipFilePath"
		continue
	}

	Write-Host "Remove the extracted $packageName folder"
	if (Test-Path "$packagesDir\$packageName")
	{
		Remove-Item -LiteralPath "$packagesDir\$packageName" -Force -Recurse
	}
	Write-Host "Extract the zipped package"
	try
	{
		Expand-Archive -Path "$zipFilePath" -DestinationPath "$packagesDir\$packageName" -Force
	}
	catch
	{
		Write-Error "Failed to extract zip file '$zipFilePath': $_"
		continue
	}

	Write-Host "Uploading package"
	try
	{
		& "$serverRoot\NanosWorldServer.exe" --token "$resolvedToken" --cli upload package "$packageName"
		if ($LASTEXITCODE -ne 0)
		{
			Write-Error "Upload failed for package '$packageName' (exit code: $LASTEXITCODE)"
			continue
		}
	}
	catch
	{
		Write-Error "Upload command failed for package '$packageName': $_"
		continue
	}

	Write-Host "Remove the extracted $packageName folder"
	Remove-Item -LiteralPath "$packagesDir\$packageName" -Force -Recurse -ErrorAction SilentlyContinue
	Write-Host "Create a symbolic-link $packageName folder (source folder may not exist in fallback mode)"
	$sourcePath = "$vaultRoot\$folderName"
	if (Test-Path -Path $sourcePath)
	{
		try
		{
			New-Item -ItemType SymbolicLink -Path "$packagesDir\$packageName" -Target $sourcePath -Force -ErrorAction SilentlyContinue | Out-Null
		}
		catch
		{
			Write-Warning "Failed to create symbolic link (run as Admin for symlink support): $_"
		}
	}
	else
	{
		Write-Warning "Source folder '$folderName' not found, symbolic-link not created"
	}
}

Pop-Location
