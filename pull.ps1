# Author: Cheatoid ~ https://github.com/Cheatoid
# License: MIT

param(
	# The root directory to perform the pull in
	$baseDir = ".",

	# How deep down you want to look for .git folders
	$depth = 2,

	# The command you want to perform
	$cmd = "pull"
)

$gitFolderName = ".git"

function Main() {
	# Finds all .git folders by given path, the -match "h" parameter is for hidden folders
	$gitFolders = Get-ChildItem -Path $baseDir -Depth $depth -Recurse -Force | Where-Object { $_.Mode -match "h" -and $_.FullName -like "*\$gitFolderName" }
	ForEach ($gitFolder in $gitFolders) {
		# Remove the ".git" folder from the path
		#$folder = $gitFolder.FullName -replace $gitFolderName, ""
		$folder = Split-Path $gitFolder.FullName -Parent

		Write-Host "Performing git $cmd in folder: '$folder'..." -foregroundColor "green"

		# Go into the folder
		Push-Location $folder

		# Perform the command within the folder
		& git $cmd

		# Go back to the original folder
		Pop-Location
	}
}

# Executes the main function
Main
