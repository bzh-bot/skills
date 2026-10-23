-- Viewport (window) commands on <leader>v.
-- Wires every <C-w>X command to <leader>vX explicitly.
-- (Previously on <leader>w, now moved so <leader>w = save file)
--
-- Navigate:            <leader>v h/j/k/l
-- Move window:         <leader>v H/J/K/L
-- Splits:              <leader>v s (horiz)  <leader>v v (vert)
-- Close:               <leader>v c / <leader>vq    Close others: <leader>v o
-- Resize:              <leader>v =          equalize
--                      <leader>v _ / |      max height / max width
--                      <lider>v + / -       grow / shrink height
--                      <leader>v > / <      grow / shrink width
-- Rotate / exchange:   <leader>v r / R / x
-- Tab / prev:          <leader>v T (move to new tab)   <leader>v p (prev win)
-- Delete window:       <leader>v d
-- Zoom:                <leader>v m
local function map(lhs, rhs, desc)
  return { lhs, rhs, mode = "n", desc = desc, remap = true, silent = true }
end

return {
  {
    "LazyVim",
    keys = {
      -- Remove old <leader>w* keys that are now on <leader>v
      -- (These are also del'd in config/keymaps.lua for the ones set by core)
      { "<leader>wd", false },
      { "<leader>wm", false },
      { "<leader>ww", false },
    },
  },
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>vm", desc = "Zoom Window", icon = "󰁌 " },
      },
    },
  },
  {
    "LazyVim/LazyVim",
    keys = {
      -- <leader>w is now a leaf node (save file), set in config/keymaps.lua

      -- Focus movement
      map("<leader>vh", "<C-w>h", "Go to left window"),
      map("<leader>vj", "<C-w>j", "Go to down window"),
      map("<leader>vk", "<C-w>k", "Go to up window"),
      map("<leader>vl", "<C-w>l", "Go to right window"),
      map("<leader>vp", "<C-w>p", "Previous window"),

      -- Move the window itself
      map("<leader>vH", "<C-w>H", "Move window left"),
      map("<leader>vJ", "<C-w>J", "Move window down"),
      map("<leader>vK", "<C-w>K", "Move window up"),
      map("<leader>vL", "<C-w>L", "Move window right"),

      -- Splits & close
      map("<leader>vs", "<C-w>s", "Split horizontal"),
      map("<leader>vv", "<C-w>v", "Split vertical"),
      map("<leader>vc", "<C-w>c", "Close window"),
      map("<leader>vq", "<C-w>q", "Close window (quit)"),
      map("<leader>vo", "<C-w>o", "Close other windows"),

      -- Resize
      map("<leader>v=", "<C-w>=", "Equalize windows"),
      map("<leader>v_", "<C-w>_", "Max height"),
      map("<leader>v|", "<C-w>|", "Max width"),
      map("<leader>v+", "<C-w>+", "Grow height"),
      map("<leader>v-", "<C-w>-", "Shrink height"),
      map("<leader>v>", "<C-w>>", "Grow width"),
      map("<leader>v<", "<C-w><", "Shrink width"),

      -- Rotate / exchange / tab
      map("<leader>vr", "<C-w>r", "Rotate windows down/right"),
      map("<leader>vR", "<C-w>R", "Rotate windows up/left"),
      map("<leader>vx", "<C-w>x", "Exchange with next window"),
      map("<leader>vT", "<C-w>T", "Move window to new tab"),
    },
  },
}