return {
  {
    dir = vim.fn.stdpath("config"),
    name = "capo-dark",
    lazy = false,
    priority = 1000,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "capo-dark",
    },
  },
}
