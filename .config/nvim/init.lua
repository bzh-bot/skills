-- Git discovery under $HOME is handled by the ~/.git gitfile
-- ("gitdir: ~/.dotfiles"), so no GIT_DIR/GIT_WORK_TREE env hack is needed.
-- Setting those globally broke other repos opened in the same nvim session.

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

vim.env.PATH = vim.env.PATH .. ":" .. vim.fn.expand("~/.local/bin")
