return {
  "mfussenegger/nvim-dap",
  recommended = true,
  desc = "Debugging support",
  dependencies = {
    "rcarriga/nvim-dap-ui",
    { "theHamsta/nvim-dap-virtual-text", opts = {} },
  },
  keys = {
    { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input('Breakpoint condition: ')) end, desc = "Breakpoint Condition" },
    { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
    { "<leader>dc", function() require("dap").run_to_cursor() end, desc = "Run to Cursor" },
    { "<leader>da", function() require("dap").continue() end, desc = "Run/Continue" },
    { "<leader>dC", function() require("dap").continue() end, desc = "Run/Continue" },
    { "<leader>dg", function() require("dap").goto_() end, desc = "Go to Line (No Execute)" },
    { "<leader>di", function() require("dap").step_into() end, desc = "Step Into" },
    { "<leader>dj", function() require("dap").down() end, desc = "Down" },
    { "<leader>dk", function() require("dap").up() end, desc = "Up" },
    { "<leader>dl", function() require("dap").run_last() end, desc = "Run Last" },
    { "<leader>do", function() require("dap").step_over() end, desc = "Step Over" },
    { "<leader>dO", function() require("dap").step_out() end, desc = "Step Out" },
    { "<leader>dP", function() require("dap").pause() end, desc = "Pause" },
    { "<leader>dr", function() require("dap").repl.toggle() end, desc = "Toggle REPL" },
    { "<leader>ds", function() require("dap").session() end, desc = "Session" },
    { "<leader>dt", function() require("dap").terminate() end, desc = "Terminate" },
    { "<leader>dw", function() require("dap.ui.widgets").hover() end, desc = "Widgets" },
    { "<leader>dW", function()
      local widgets = require("dap.ui.widgets")
      widgets.centered_float(widgets.scopes, { border = "rounded" })
    end, desc = "Scopes Float" },
    { "<leader>dL", function() require("dap").set_log("WARN") end, desc = "Set Log Level" },
    { "<leader>d9", function()
      local port = vim.fn.input('Debug port: ', '9229')
      if port == "" then return end
      require("dap").run({
        type = "pwa-node",
        request = "attach",
        name = "Attach " .. port,
        port = tonumber(port),
        host = "localhost",
        cwd = vim.fn.getcwd(),
        sourceMaps = true,
        skipFiles = { "<node_internals>/**", "node_modules/**" },
        resolveSourceMapLocations = { vim.fn.getcwd() .. "/**", "!**/node_modules/**" },
      })
    end, desc = "Attach Debugger (port)" },
    { "<leader>dx", function() require("dap").terminate() require("dapui").close() end, desc = "Terminate & Close DAP UI" },
    { "<leader>dA", function()
      local dap = require("dap")
      local ftype = vim.bo.filetype
      local configs = dap.configurations[ftype] or {}
      if #configs == 0 then
        vim.notify("No configurations for " .. ftype, vim.log.levels.WARN)
        return
      end
      vim.ui.select(configs, { prompt = "Select configuration", format_item = function(c) return c.name end }, function(choice)
        if choice then
          dap.run(choice)
        end
      end)
    end, desc = "Choose Configuration" },
  },
  config = function()
    local dap = require("dap")
    local dapui = require("dapui")
    dapui.setup({})
    dap.listeners.after.event_initialized["dapui_config"] = function()
      dapui.open({})
    end
    dap.listeners.before.event_terminated["dapui_config"] = function()
      dapui.close({})
    end
    dap.listeners.before.event_exited["dapui_config"] = function()
      dapui.close({})
    end
    vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpoint", linehl = "" })
    vim.fn.sign_define("DapBreakpointCondition", { text = "●", texthl = "DapBreakpointCondition", linehl = "" })
    vim.fn.sign_define("DapLogPoint", { text = "●", texthl = "DapLogPoint", linehl = "" })
    vim.fn.sign_define("DapStopped", { text = "●", texthl = "DapStopped", linehl = "" })
    vim.api.nvim_set_hl(0, "DapBreakpoint", { default = true, fg = "#f44747" })
    vim.api.nvim_set_hl(0, "DapBreakpointCondition", { default = true, fg = "#f44747" })
    vim.api.nvim_set_hl(0, "DapLogPoint", { default = true, fg = "#f44747" })
    vim.api.nvim_set_hl(0, "DapStopped", { default = true, fg = "#f44747" })
    vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Visual" })
  end,
}
