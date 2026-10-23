return {
  {
    "pwntester/octo.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    cmd = "Octo",
    keys = {
      { "<leader>go", "<cmd>Octo pr list<cr>", desc = "Octo PR List" },
    },
    opts = {
      -- Use the repo from the current working directory
      -- Set to false to always prompt, or leave default to auto-detect
      default_remote = { "upstream", "origin" },
    },
  },
}