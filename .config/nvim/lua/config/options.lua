-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.env.PATH = vim.env.PATH .. ":" .. vim.fn.expand("~/go/bin")

vim.g.lazyvim_ts_lsp = "tsc"

-- Show all characters as-is (don't hide quotes in JSON, etc)
vim.opt.conceallevel = 0

-- Session options: auto-session requires 'localoptions' for correct
-- filetype/highlight restoration, and 'terminal' for terminal buffers.
vim.opt.sessionoptions:append("localoptions,terminal")
