-- GitHub Copilot: multi-line inline ghost text + CopilotChat
--
-- Ghost text (inline suggestions):
--   • Tab   → accept full suggestion (like VSCode Tab)
--   • M-]   → cycle to next suggestion
--   • M-[   → cycle to previous suggestion
--   • C-]   → dismiss suggestion
--
-- CopilotChat keymaps:
--   • <leader>aa  → toggle chat
--   • <leader>ap  → prompt picker (Explain, Fix, Optimize, Tests, Docs…)
--   • <leader>aq  → quick chat (type a question, sends current selection)
--   • <leader>ax  → clear/reset chat
--   • <leader>am  → pick model
--   • <leader>ai  → inline edit at cursor (VSCode Ctrl+I)
--
-- Inside the chat buffer:
--   • <C-y>  → apply nearest diff into source file
--   • gj     → jump to nearest diff in source
--   • gd     → show diff overlay
--   • q      → close chat

return {
  ---- copilot.lua: ghost-text suggestions ----
  {
    "zbirenbaum/copilot.lua",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
        hide_during_completion = true,
        keymap = {
          accept = false, -- handled by blink.cmp ai_accept on Tab
          accept_line = false,
          accept_word = false,
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-]>",
        },
      },
      panel = { enabled = false },
      filetypes = {
        markdown = true,
        help = true,
      },
    },
  },

  ---- Remove blink-copilot — ghost text is better for multi-line ----
  {
    "saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
      if opts.sources and opts.sources.default then
        opts.sources.default = vim.tbl_filter(function(s)
          return s ~= "copilot"
        end, opts.sources.default)
      end
      if opts.sources and opts.sources.providers and opts.sources.providers.copilot then
        opts.sources.providers.copilot = nil
      end
    end,
  },
  {
    "fang2hou/blink-copilot",
    enabled = false,
  },

  ---- ai_accept: Tab accepts ghost text ----
  {
    "zbirenbaum/copilot.lua",
    opts = function()
      LazyVim.cmp.actions.ai_accept = function()
        if require("copilot.suggestion").is_visible() then
          LazyVim.create_undo()
          require("copilot.suggestion").accept()
          return true
        end
      end
    end,
  },

  ---- CopilotChat ----
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "canary",
    cmd = "CopilotChat",
    build = "make tiktoken",
    dependencies = {
      { "nvim-telescope/telescope.nvim" },
      { "nvim-lua/plenary.nvim" },
    },
    keys = {
      { "<leader>a", "", desc = "+ai", mode = { "n", "x" } },
      {
        "<leader>aa",
        function()
          require("CopilotChat").toggle()
        end,
        desc = "CopilotChat: toggle",
        mode = { "n", "x" },
      },
      {
        "<leader>ap",
        function()
          require("CopilotChat").select_prompt()
        end,
        desc = "CopilotChat: prompt picker",
        mode = { "n", "x" },
      },
      {
        "<leader>aq",
        function()
          vim.ui.input({ prompt = "Quick Chat ❯ " }, function(input)
            if input and input ~= "" then
              require("CopilotChat").ask(input)
            end
          end)
        end,
        desc = "CopilotChat: quick chat",
        mode = { "n", "x" },
      },
      {
        "<leader>ai",
        function()
          vim.ui.input({ prompt = "Inline edit ❯ " }, function(input)
            if input and input ~= "" then
              -- /COPILOT_GENERATE tells the model to output diff-ready code blocks
              -- that <C-y> can apply directly into the source file.
              require("CopilotChat").ask("> /COPILOT_GENERATE\n\n" .. input)
            end
          end)
        end,
        desc = "CopilotChat: inline edit",
        mode = { "n", "x" },
      },
      {
        "<leader>ax",
        function()
          require("CopilotChat").reset()
        end,
        desc = "CopilotChat: clear",
        mode = { "n", "x" },
      },
      {
        "<leader>am",
        function()
          require("CopilotChat").select_model()
        end,
        desc = "CopilotChat: model",
        mode = { "n", "x" },
      },
    },
    opts = {
      model = "gpt-4o",
      auto_insert_mode = true, -- enter insert mode when chat opens
      window = {
        layout = "vertical",
        width = 0.3,
      },
      question_header = "## You ",
      answer_header = "## Copilot ",
    },
  },
}