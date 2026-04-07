-- 1. Bootstrap plugin manager (lazy.nvim)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim", "--branch=stable",
		lazypath
	})
end
vim.opt.rtp:prepend(lazypath)

vim.opt.shellquote = ""
vim.opt.shellxquote = ""

-- 2. Plugin Setup
require("lazy").setup({
	-- LSP Management
	{ "neovim/nvim-lspconfig" },
	{ "williamboman/mason.nvim",           opts = {} },
	{ "williamboman/mason-lspconfig.nvim", opts = { ensure_installed = { "lua_ls" } } },

	-- Session management
	{
		"folke/persistence.nvim",
		event = "BufReadPre", -- This starts the plugin when you open a file
		opts = {}       -- Uses default settings
	},

	-- Autocompletion
	{ "hrsh7th/nvim-cmp",                dependencies = { "hrsh7th/cmp-nvim-lsp", "L3MON4D3/LuaSnip" } },

	-- Best Lua Support (Adds Neovim-specific completion/docs)
	{ "folke/neodev.nvim",               opts = {} },

	-- The main IntelliSense engine
	{ 'neoclide/coc.nvim',               branch = 'release' },

	-- Syntax highlighting for Lua
	{ "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },

	-- Theme
	{ "folke/tokyonight.nvim" },
}, {
	-- 2. Lazy settings (This part hides the popup)
	ui = {
		show_on_startup = false, -- Only show if there's an error or you type :Lazy
	},
})

-- 3. LSP Configuration (Lua Specific)
if false then
	local lspconfig = require('lspconfig')
	lspconfig.lua_ls.setup({
		settings = {
			Lua = {
				completion = { callSnippet = "Replace" },
				diagnostics = { globals = { "vim" } }, -- Stops "undefined global 'vim'" warnings
			},
		},
	})
end
-- 3. REMOVE the "lspconfig" section entirely.
-- Instead, use CoC global extensions for Lua:
vim.g.coc_global_extensions = { 'coc-lua', 'coc-json', 'coc-explorer' }
-- Set the absolute path to your node.exe
vim.g.coc_node_path = 'C:\\Program Files\\nodejs\\node.exe'

-- 4. Completion Setup (Basic)
if false then
	local cmp = require('cmp')
	cmp.setup({
		snippet = { expand = function(args) require('luasnip').lsp_expand(args.body) end },
		mapping = cmp.mapping.preset.insert({
			['<CR>'] = cmp.mapping.confirm({ select = true }),
			['<Tab>'] = cmp.mapping.select_next_item(),
		}),
		sources = cmp.config.sources({ { name = 'nvim_lsp' } })
	})
end
-- 4. Keybindings (VS Code style)
vim.g.mapleader = " "
-- Close the current window (editor) with Space + q
vim.keymap.set("n", "<leader>q", "<Cmd>q<CR>", { desc = "Close current window" })
-- Space + e opens the File Explorer
vim.keymap.set("n", "<leader>e", "<Cmd>CocCommand explorer<CR>", { silent = true })
-- Keybindings to restore sessions
vim.keymap.set("n", "<leader>qs", function() require("persistence").load() end, { desc = "Restore Session" })
vim.keymap.set("n", "<leader>ql", function() require("persistence").load({ last = true }) end,
	{ desc = "Restore Last Session" })

-- 5. General Options (Equivalent to .vimrc settings)
vim.opt.number = true         -- Show line numbers
vim.opt.relativenumber = true -- Relative line numbers
vim.opt.shiftwidth = 2        -- Tab size
-- Auto-save files when focus is lost or after 1 second of idling
vim.opt.autowriteall = true
local autosave = vim.api.nvim_create_augroup("AutoSave", { clear = true })
vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged" }, {
	group = autosave,
	pattern = "*",
	command = "silent! wall",      -- This saves all open files quietly
})
vim.cmd [[colorscheme tokyonight]] -- Apply theme

-- Force coc-explorer to always open on the left
vim.g.coc_explorer_global_presets = {
	['.vim'] = {
		['position'] = 'left',
		['width'] = 30,
	}
}
vim.api.nvim_create_autocmd("FileType", {
	pattern = "coc-explorer",
	callback = function()
		vim.opt_local.winfixwidth = true
	end,
})
-- Update your toggle command to use this preset
vim.keymap.set("n", "<leader>e", "<Cmd>CocCommand explorer --preset .vim<CR>", { silent = true })

-- Automatically restore the session on startup
vim.api.nvim_create_autocmd("VimEnter", {
	group = vim.api.nvim_create_augroup("RestoreSession", { clear = true }),
	callback = function()
		-- Only restore if we started nvim without arguments (like just double-clicking the .bat)
		if vim.fn.argc() == 0 then
			require("persistence").load()
		end
	end,
})
-- Auto-save session when quitting (ensures it's always fresh)
vim.api.nvim_create_autocmd("VimLeave", {
	group = vim.api.nvim_create_augroup("SaveSession", { clear = true }),
	callback = function()
		require("persistence").save()
	end,
})
