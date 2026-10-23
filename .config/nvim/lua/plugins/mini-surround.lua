return {
  {
    "nvim-mini/mini.surround",
    version = "*",
    opts = {
      mappings = {
        add = "gsa", -- add surround: gsa)
        delete = "gsd", -- delete surround: gsd)
        find = "gsf", -- find surround (to right)
        find_left = "gsF", -- find surround (to left)
        highlight = "gsh", -- highlight surround
        replace = "gsr", -- replace surround: gsr)]
        update_n_lines = "gsn", -- update `n_lines`
      },
    },
  },
}