return {
  "vuki656/package-info.nvim",
  ft = "json",
  dependencies = "nvim-treesitter/nvim-treesitter",
  config = function()
    local ok, package_info = pcall(require, "package-info")
    if not ok then
      return
    end

    package_info.setup({
      auto_reload_on_update = true,
      hide_upgrade_from_file = true,
      -- Disable auto-show on BufEnter - only show via explicit keymap
      auto_start_showing = false,
    })

    vim.keymap.set("n", "<leader>nu", function()
      pcall(require("package-info").update)
    end, { desc = "Update package.json versions", silent = true })

    vim.keymap.set("n", "<leader>nd", function()
      pcall(require("package-info").delete)
    end, { desc = "Delete package.json dependency", silent = true })

    vim.keymap.set("n", "<leader>ni", function()
      pcall(require("package-info").install)
    end, { desc = "Install new package", silent = true })

    -- Explicit show command (use when you need it)
    vim.keymap.set("n", "<leader>ns", function()
      pcall(require("package-info").show)
    end, { desc = "Show package.json versions", silent = true })
  end,
}
