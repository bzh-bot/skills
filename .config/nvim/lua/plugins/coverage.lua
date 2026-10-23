-- Coverage overlay plugin: shows lcov.info line coverage in the signcolumn
-- and as line highlights.  Uses the coverage.lua config module.
--
-- Commands:
--   :CoverageShow   — load (if needed) and display coverage for current file
--   :CoverageHide   — remove coverage signs/highlights
--   :CoverageToggle — toggle coverage display
--   :CoverageLoad [path] — load an lcov.info file

return {
  dir = vim.fn.stdpath("config"), -- use local config dir so lazy doesn't try to clone
  name = "coverage-overlay",
  lazy = false,
  config = function()
    local coverage = require("config.coverage")

    vim.api.nvim_create_user_command("CoverageShow", function()
      coverage.show()
    end, { desc = "Show test coverage for the current file" })

    vim.api.nvim_create_user_command("CoverageHide", function()
      coverage.hide()
    end, { desc = "Hide test coverage signs and highlights" })

    vim.api.nvim_create_user_command("CoverageToggle", function()
      coverage.toggle()
    end, { desc = "Toggle test coverage display" })

    vim.api.nvim_create_user_command("CoverageLoad", function(opts)
      coverage.load(#opts.args > 0 and opts.args or nil)
    end, {
      nargs = "?",
      complete = function(_, _, _)
        return {}
      end,
      desc = "Load an lcov.info file (defaults to searching upward)",
    })

    -- Keymap: <leader>ut = coverage toggle
    vim.keymap.set("n", "<leader>ut", coverage.toggle, { desc = "Toggle Coverage" })
  end,
}