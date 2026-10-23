return {
  {
    "mason-org/mason.nvim",
    keys = {
      {
        "<leader>gD",
        function()
          Snacks.terminal({ "lazydocker" })
        end,
        desc = "LazyDocker",
      },
    },
  },
}
