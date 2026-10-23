return {
  {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    config = function()
      local mc = require("multicursor-nvim")
      mc.setup()

      -- User commands so multicursor actions show up in : command search
      vim.api.nvim_create_user_command("MultiCursorToggle", function() mc.toggleCursor() end, { desc = "Add/remove cursor at current position" })
      vim.api.nvim_create_user_command("MultiCursorAddBelow", function() mc.lineAddCursor(1) end, { desc = "Add cursor one line below" })
      vim.api.nvim_create_user_command("MultiCursorAddAbove", function() mc.lineAddCursor(-1) end, { desc = "Add cursor one line above" })
      vim.api.nvim_create_user_command("MultiCursorMatchNext", function() mc.matchAddCursor(1) end, { desc = "Add cursor at next match" })
      vim.api.nvim_create_user_command("MultiCursorMatchPrev", function() mc.matchAddCursor(-1) end, { desc = "Add cursor at previous match" })
      vim.api.nvim_create_user_command("MultiCursorMatchAll", function() mc.matchAllAddCursors() end, { desc = "Add cursor at every match" })
      vim.api.nvim_create_user_command("MultiCursorClear", function() mc.clearCursors() end, { desc = "Remove all extra cursors" })

      -- Add and remove cursors with CTRL + left click.
      vim.keymap.set("n", "<c-leftmouse>", mc.handleMouse)
      vim.keymap.set("n", "<c-leftdrag>", mc.handleMouseDrag)
      vim.keymap.set("n", "<c-leftrelease>", mc.handleMouseRelease)

      -- Toggle a cursor at the current position
      vim.keymap.set({ "n", "v" }, "<leader>md", mc.toggleCursor, { desc = "MC: toggle cursor here" })

      -- Visual: add a cursor at the end of every line in the selection
      vim.keymap.set("v", "<leader>mi", function()
        -- Capture the visual selection range, then exit visual mode
        local s_line = vim.fn.line("v")
        local e_line = vim.fn.line(".")
        if s_line > e_line then
          s_line, e_line = e_line, s_line
        end
        vim.cmd("normal! \27") -- <esc> to leave visual mode

        mc.action(function(ctx)
          for lnum = s_line, e_line do
            local col = math.max(#vim.fn.getline(lnum), 1)
            local cursor = ctx:addCursor()
            cursor:setPos({ lnum, col })
          end
        end)
      end, { desc = "MC: add cursor at end of each line in selection" })

      -- Layer active only while multiple cursors exist
      mc.addKeymapLayer(function(layerSet)
        -- Enable and clear cursors using escape.
        layerSet("n", "<esc>", function()
          if not mc.cursorsEnabled() then
            mc.enableCursors()
          else
            mc.clearCursors()
          end
        end)
      end)
    end,
  },
}
