-- vim-conflict-marker: Better conflict resolution with shortcuts
return {
  "rhysd/conflict-marker.vim",
  lazy = false,
  config = function()
    -- Custom keymaps - intuitive: o=ours, t=theirs, b=both
    vim.keymap.set("n", "<leader>x]", "<plug>(conflict-marker-next-hunk)", { desc = "Next conflict" })
    vim.keymap.set("n", "<leader>x[", "<plug>(conflict-marker-prev-hunk)", { desc = "Previous conflict" })
    vim.keymap.set("n", "<leader>xi", "<plug>(conflict-marker-ourselves)", { desc = "Take local" })
    vim.keymap.set("n", "<leader>xo", "<plug>(conflict-marker-themselves)", { desc = "Take remote" })
    vim.keymap.set("n", "<leader>xb", "<plug>(conflict-marker-both)", { desc = "Take both" })
    vim.keymap.set("n", "<leader>x3", "<cmd>Gvdiffsplit!<CR>", { desc = "3-way diff split" })

    -- Conflict markers — purple background, preserve syntax highlighting.
    -- (Diff colors live in colors/capo-dark.lua, not here.)
    local function set_bg_only(name, bg)
      vim.api.nvim_set_hl(0, name, { bg = bg, ctermbg = nil, link = "", default = false })
    end

    set_bg_only("ConflictMarkerOurs", "#3d2d5a")
    set_bg_only("ConflictMarkerTheirs", "#3d2d5a")
    set_bg_only("ConflictMarkerCommonAncestorsOurs", "#3d2d5a")
    set_bg_only("ConflictMarkerCommonAncestorsTheirs", "#3d2d5a")
    set_bg_only("ConflictMarkerCommonAncestorsBase", "#3d2d5a")
    set_bg_only("ConflictMarkerEnd", "#3d2d5a")
    set_bg_only("ConflictMarkerBegin", "#3d2d5a")
    set_bg_only("ConflictMarkerSeparator", "#3d2d5a")
    set_bg_only("ConflictMarkerNonConflict", "#3d2d5a")
  end,
}
