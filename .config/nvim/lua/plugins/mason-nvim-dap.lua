return {
  "jay-babu/mason-nvim-dap.nvim",
  dependencies = "mason.nvim",
  cmd = { "DapInstall", "DapUninstall" },
  opts = {
    automatic_installation = { exclude = { "chrome" } },
    ensure_installed = {},
  },
}
