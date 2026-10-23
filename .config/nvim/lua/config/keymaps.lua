-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- ── Make <leader>w and <leader>q leaf nodes (direct actions, not groups) ──
-- Remove sub-keys that LazyVim's core keymaps.lua sets via vim.keymap.set
-- (plugin "keys = { false }" can't remove these — we must del them here).
for _, lhs in ipairs({
  -- <leader>f sub-keys (replaced by <leader>f = Find Files)
  "<leader>fn",
  "<leader>ft",
  "<leader>fT",
  -- <leader>q sub-keys (replaced by <leader>q = Quit All)
  "<leader>qq",
  "<leader>qs",
  "<leader>qS",
  "<leader>ql",
  "<leader>qd",
  -- <leader>w sub-keys (replaced by <leader>w = Save; window cmds moved to <leader>v)
  "<leader>wd",
  "<leader>ww",
  "<leader>wm", -- Snacks.toggle.zoom registers this dynamically
  "<leader>L", -- LazyVim Changelog, now wrap-with-abbreviation
}) do
  pcall(vim.keymap.del, "n", lhs)
end

-- Remove which-key GROUP registrations so they become true leaf nodes.
-- Also remove <leader>wm (zoom) and <leader>L (changelog) from which-key
-- since we repurposed those keys — they register dynamically after plugin load.
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = function()
    -- Re-delete <leader>wm in case Snacks registered it after our loop above
    pcall(vim.keymap.del, "n", "<leader>wm")
    -- Remove which-key entries so they don't turn <leader>w / <leader>q into groups
    for _, k in ipairs({ "<leader>w", "<leader>q", "<leader>wm", "<leader>L" }) do
      pcall(function() require("which-key").remove({ k, mode = "n" }) end)
    end
  end,
})

-- <leader>w = Save file (leaf node)
vim.keymap.set({ "n", "v" }, "<leader>w", "<cmd>w<cr>", { desc = "Save file" })

-- Zoom toggle was <leader>wm, now <leader>vm
vim.keymap.set("n", "<leader>vm", function() require("snacks").toggle.zoom() end, { desc = "Zoom Window" })
-- Delete window was <leader>wwd, now <leader>vd
vim.keymap.set("n", "<leader>vd", "<C-W>c", { desc = "Delete Window", remap = true })

-- Move lines up/down with Alt+j / Alt+k
vim.keymap.set("n", "<M-j>", ":m .+1<CR>==", { desc = "Move line down" })
vim.keymap.set("v", "<M-j>", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
vim.keymap.set("n", "<M-k>", ":m .-2<CR>==", { desc = "Move line up" })
vim.keymap.set("v", "<M-k>", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Alt+g: "find usages" — always shows references (or implementations if the
-- symbol has any meaningful ones, e.g. interface/abstract methods). Never
-- jumps to def; use `gd` for that. Results land in a Trouble side panel.
-- <M-G> always forces references.
local function smart_usages(force_refs)
  local bufnr = 0
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/references" })
  if #clients == 0 then
    vim.notify("No LSP client supports references", vim.log.levels.WARN)
    return
  end

  local function open_trouble(mode)
    local ok, err = pcall(vim.cmd, "Trouble " .. mode .. " focus=true")
    if not ok then
      vim.notify("Trouble failed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end

  if force_refs then
    open_trouble("lsp_references")
    return
  end

  -- Probe implementations. Only prefer the impls panel if any server returns at
  -- least one result that isn't the cursor itself.
  local impl_clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/implementation" })
  if #impl_clients == 0 then
    open_trouble("lsp_references")
    return
  end

  local params = vim.lsp.util.make_position_params(0, impl_clients[1].offset_encoding)
  local cur_uri = vim.uri_from_bufnr(bufnr)
  local cur_line = params.position.line

  local function loc_matches_cursor(item)
    local uri = item.uri or item.targetUri
    local range = item.range or item.targetSelectionRange or item.targetRange
    return uri == cur_uri and range and range.start.line == cur_line
  end

  vim.lsp.buf_request_all(bufnr, "textDocument/implementation", params, function(impl_results)
    local meaningful = false
    for _, res in pairs(impl_results) do
      local r = res and res.result
      if r then
        local items = vim.islist(r) and r or { r }
        for _, it in ipairs(items) do
          if not loc_matches_cursor(it) then
            meaningful = true
            break
          end
        end
      end
      if meaningful then break end
    end
    if meaningful then
      open_trouble("lsp_implementations")
    else
      open_trouble("lsp_references")
    end
  end)
end

vim.keymap.set("n", "<M-g>", function() smart_usages(false) end,
  { desc = "Find usages: implementations or references" })
vim.keymap.set("n", "<M-G>", function() smart_usages(true) end,
  { desc = "Find usages: force references" })

-- (<leader>w is now a leaf node: save file. All window commands moved to <leader>v.)

-- <leader>bx = delete buffer
vim.keymap.set("n", "<leader>bx", ":bdelete<cr>", { desc = "Delete buffer" })

-- <leader>bn = new blank buffer
vim.keymap.set("n", "<leader>bn", ":enew<cr>", { desc = "New buffer" })

-- <leader>L: wrap visual selection with HTML tag (mini.surround 't' action).
-- Select text, press <leader>L, type "div" or "span.foo" etc.
-- Uses mini.surround's built-in tag surround which handles multi-line and
-- matching tags correctly — no custom buffer math needed.
vim.keymap.set("x", "<leader>L", "<cmd>lua MiniSurround.add('visual', 't')<CR>", { desc = "Wrap with tag" })


-- Workspace launcher and terminal toggle removed — window commands moved to <leader>v

-- Swap Ctrl-I / Ctrl-O: I = backward (older), O = forward (newer)
vim.keymap.set("n", "<C-i>", "<C-o>", { desc = "Jump backward" })
-- <C-o> becomes <C-i> (forward); but <C-i> is internally the same as Tab,
-- so we must remap Tab to jump forward and unmap <C-o> default.
-- Using the fact that nvim treats <C-i> == <Tab> internally:
--   remap <Tab> to forward-jump, and set <C-o> to the same.
-- First, clear the old <C-o> and set both to forward-jump.
vim.keymap.set("n", "<Tab>", "<C-i>", { desc = "Jump forward" })
vim.keymap.set("n", "<C-o>", "<C-i>", { desc = "Jump forward" })

-- Ctrl+n exits terminal mode (instead of Ctrl-\ Ctrl-n)
vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    vim.keymap.set("t", "<C-n>", "<C-\\><C-n>", { buffer = true })
  end,
})

-- Quick terminal commands
-- Moved to <leader>od ("open dev") since <leader>f is now a direct action
vim.keymap.set("n", "<leader>od", function()
  vim.cmd("vsplit")
  vim.cmd("terminal npm run dev")
  vim.cmd("startinsert")
end, { desc = "Run npm run dev in terminal" })

-- <leader>f is now the file finder (see fzf-lua plugin). Ctrl+p is used by zellij for pane mode.

-- ── Workspace symbol search (<leader>sS) ────────────────────────────
-- tsc (TypeScript Native Preview, formerly tsgo) does not support the LSP
-- `workspace/symbol` method, so LazyVim's default `<leader>sS`
-- (fzf-lua.lsp_live_workspace_symbols) shows nothing.  This override uses
-- ripgrep to collect ALL TS/JS symbol
-- declarations upfront, then fzf fuzzy-filters them as you type — the closest
-- thing to VSCode's Ctrl+T (Go to Symbol in Workspace).
--
--   <leader>sS  →  fuzzy search across function/class/const/interface/type/enum
--   <leader>ss  →  document symbols (still uses LSP, works within a single file)

-- Delete LazyVim's <leader>sS (lsp_live_workspace_symbols — broken with tsc)
-- then set our grep-based replacement.
pcall(vim.keymap.del, "n", "<leader>sS")
vim.keymap.set("n", "<leader>sS", function()
  require("fzf-lua").grep({
    -- Match TS/JS symbol declarations: function, class, const, interface,
    -- type, enum, getter, setter — followed by whitespace and an identifier.
    -- no_esc = true is critical: without it fzf-lua regex-escapes the pattern,
    -- turning (function\s+|...) into a literal string that matches nothing.
    search = "(function\\s+|class\\s+|const\\s+|interface\\s+|type\\s+|enum\\s+|get\\s+|set\\s+)\\w+",
    no_esc = true,
    prompt = "Workspace Symbols❯ ",
    git_icons = false,
    file_icons = true,
    -- Restrict to TypeScript / JavaScript / Svelte files.
    --   -t ts  covers *.ts *.tsx *.cts *.mts
    --   -t js  covers *.js *.jsx *.cjs *.mjs *.vue
    --   -t svelte covers *.svelte
    rg_opts = "--column --line-number --no-heading --color=always --smart-case "
      .. "-t ts -t js -t svelte",
  })
end, { desc = "Goto Symbol (Workspace)" })

-- ── Reference checklist ────────────────────────────────────────────────
-- Go through all usages of a symbol one by one, marking each completed:
--   1. <leader>cq  fill the quickfix list with every reference under cursor
--   2. fix the code, then <leader>cd — removes the entry ("done") and jumps
--      straight to the next remaining reference
--   3. when the list empties, the quickfix window closes itself
-- [q / ]q still work for skipping around without completing an entry.
local function references_to_quickfix()
  vim.lsp.buf.references(nil, {
    on_list = function(items)
      if #items.items == 0 then
        vim.notify("No references found")
        return
      end
      vim.fn.setqflist({}, " ", items)
      vim.cmd("copen")
      vim.cmd("cc 1")
      vim.notify(#items.items .. " references in checklist")
    end,
  })
end

local function quickfix_done_next()
  local qf = vim.fn.getqflist()
  local cur = vim.fn.getqflist({ idx = 0 }).idx
  if cur == 0 or #qf == 0 then
    vim.notify("Quickfix list empty", vim.log.levels.WARN)
    return
  end
  table.remove(qf, cur)
  vim.fn.setqflist(qf, "r")
  if #qf == 0 then
    vim.cmd("cclose")
    vim.notify("All references completed!")
  else
    vim.cmd("cc " .. math.min(cur, #qf))
  end
end

vim.keymap.set("n", "<leader>cq", references_to_quickfix,
  { desc = "References → quickfix checklist" })
vim.keymap.set("n", "<leader>cd", quickfix_done_next,
  { desc = "Quickfix: mark done & next" })
