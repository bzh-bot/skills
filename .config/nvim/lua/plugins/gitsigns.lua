return {
  "lewis6991/gitsigns.nvim",
  opts = {
    current_line_blame = true,
    current_line_blame_opts = {
      virt_text_pos = "eol",
      delay = 300,
      ignore_whitespace = true,
    },
    current_line_blame_formatter = "<author>, <author_time:%R> - <summary>",

    -- LazyVim wires ]h/[h, <leader>ghs (stage), <leader>ghr (reset),
    -- <leader>ghp (preview), <leader>ghb (blame line). We add the missing
    -- power-user keys and override blame to show the FULL commit message popup.
    on_attach = function(buffer)
      local gs = require("gitsigns")
      local function map(mode, l, r, desc)
        vim.keymap.set(mode, l, r, { buffer = buffer, desc = desc })
      end

      -- Hunk navigation that auto-handles being inside diff mode
      map("n", "]h", function()
        if vim.wo.diff then return "]c" end
        vim.schedule(function() gs.nav_hunk("next") end)
        return "<Ignore>"
      end, "Next hunk")
      map("n", "[h", function()
        if vim.wo.diff then return "[c" end
        vim.schedule(function() gs.nav_hunk("prev") end)
        return "<Ignore>"
      end, "Prev hunk")

      -- Full-message blame popup (the "git blame this line, with full commit"
      -- view — way more useful than the EOL virtual text)
      map("n", "<leader>gB", function() gs.blame_line({ full = true }) end,
        "Blame line (full popup)")
      -- Whole-file blame in a side panel
      map("n", "<leader>gbf", function() gs.blame() end, "Blame whole file")

      -- Diff current file against index / last commit
      map("n", "<leader>ghd", gs.diffthis, "Diff against index")
      map("n", "<leader>ghD", function() gs.diffthis("~") end, "Diff against last commit")

      -- Toggle deleted-line ghosts inline
      map("n", "<leader>ghT", gs.toggle_deleted, "Toggle deleted lines")

      -- Hunk text object — `vih` selects the hunk, `dih` deletes (=reset) it
      map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "Select hunk")
    end,
  },
}
