-- Neo-tree key remaps:
--   f          -> quick_jump (label-based jump, was <C-s>)
--   <leader>f  -> filter_on_submit (was f)
--   <C-s>      -> unbound (let Zellij handle it)
-- Note: `/` is still the default fuzzy_finder if you want multi-char search.

local quick_jump = {
  "quick_jump",
  config = {
    on_jump = "open_or_toggle",
    jump_labels = "jfkdlsahgnuvrbytmiceoxwpqz",
  },
}

return {
  "nvim-neo-tree/neo-tree.nvim",
  optional = true,
  opts = {
    window = {
      mappings = {
        ["<C-s>"] = "none",
        ["f"] = quick_jump,
      },
    },
    filesystem = {
      window = {
        mappings = {
          -- Re-declare here because filesystem-source mappings shadow the
          -- top-level window.mappings (default `f` = filter_on_submit).
          ["f"] = quick_jump,
          ["<leader>f"] = "filter_on_submit",
        },
      },
    },
    buffers = {
      window = {
        mappings = {
          ["f"] = quick_jump,
        },
      },
    },
    git_status = {
      window = {
        mappings = {
          ["f"] = quick_jump,
        },
      },
    },
  },
}
