return {
  {
    "rmagatti/auto-session",
    branch = "main",
    lazy = false,
    config = function()
      local auto_session = require("auto-session")
      auto_session.setup({
        log_level = "error",

        root_dir = vim.fn.stdpath("state") .. "/sessions/",

        suppressed_dirs = { "~/", "~/Downloads", "/" },
        git_use_branch_name = true,
        auto_restore = true,
        allowed_dirs = nil,

        lazy_support = false,

        auto_create = function()
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted and vim.bo[buf].modifiable then
              return true
            end
          end
          return false
        end,

        bypass_save_filetypes = { "snacks_dashboard" },

        pre_restore_cmds = {
          function()
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
              if vim.bo[buf].filetype == "snacks_dashboard" then
                pcall(vim.api.nvim_buf_delete, buf, { force = true })
              end
            end
          end,
        },
        post_restore_cmds = {
          function()
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
              if vim.bo[buf].filetype == "snacks_dashboard" then
                pcall(vim.api.nvim_buf_delete, buf, { force = true })
              end
            end
          end,
        },

        -- BUG WORKAROUND for auto-session + git_use_branch_name + `nvim .`:
        --
        -- When you launch with `nvim .` AND git_use_branch_name=true,
        -- auto-session computes session_name="/path/to/repo|main" but
        -- cwd is just "/path/to/repo" (no |branch suffix). Because they
        -- don't match, auto-session does:
        --   Config.auto_save = false
        -- in init.lua's auto_restore_session_at_vim_enter (around the
        -- "Not enabling autosave because launch argument didn't load
        -- session and doesn't match cwd" debug line).
        --
        -- Result: nothing ever saves on quit, so the next launch finds
        -- no session, leaving you with a blank buffer.
        --
        -- The no_restore hook fires AFTER that line, so we re-enable
        -- auto_save here whenever no session was restored. Our
        -- suppressed_dirs and auto_create checks already prevent
        -- saving in dirs we don't want.
        no_restore_cmds = {
          function()
            require("auto-session.config").auto_save = true
          end,
        },
      })
    end,
  },
}