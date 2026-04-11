# Author: Cheatoid ~ https://github.com/Cheatoid
# License: MIT

#$env:NVIM_APPNAME = "my-custom-config"; # nah don't use this

# Get the absolute path of the current directory
$repoRoot = Get-Location

# Tell Neovim where the config is
$env:XDG_CONFIG_HOME = "$repoRoot"

# Tell Neovim where to install plugins (coc.nvim, lazy, etc.)
$env:XDG_DATA_HOME = "$repoRoot\.nvim-data"
$env:XDG_STATE_HOME = "$repoRoot\.nvim-data\state"
$env:XDG_CACHE_HOME = "$repoRoot\.nvim-data\cache"

# Run your portable Neovim
& "$repoRoot\.nvim-win64\bin\nvim.exe" -u "$repoRoot\nvim\init.lua" $args
