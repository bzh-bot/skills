-- Neo-tree coverage component: shows per-file test coverage percentage
-- next to files in the file explorer. Activated by <leader>ut.

return {
  "nvim-neo-tree/neo-tree.nvim",
  optional = true,
  opts = function(_, opts)
    -- Register the custom component
    local components = require("neo-tree.sources.common.components")
    components.coverage = function(config, node, state)
      local cov = require("config.coverage")
      -- Don't auto-load: only show coverage when user explicitly loaded it
      if vim.tbl_isempty(cov.data) then
        return {}
      end
      if node.type == "directory" then
        return {}
      end

      local filepath = vim.fn.simplify(vim.fn.fnamemodify(node.path, ":p"))

      local file_data = cov.data[filepath]
      -- Fallback: suffix match
      if not file_data then
        for p, d in pairs(cov.data) do
          if filepath:sub(-#p) == p then
            file_data = d
            break
          end
        end
      end
      if not file_data then
        return {}
      end

      local covered_count = 0
      local total = 0
      for _ in pairs(file_data.covered) do
        covered_count = covered_count + 1
        total = total + 1
      end
      for _ in pairs(file_data.uncovered) do
        total = total + 1
      end
      if total == 0 then
        return {}
      end

      local pct = math.floor((covered_count / total) * 100 + 0.5)

      local hl = "NeoTreeCoverageLow"
      if pct >= 80 then
        hl = "NeoTreeCoverageHigh"
      elseif pct >= 50 then
        hl = "NeoTreeCoverageMed"
      end

      return {
        text = string.format(" %d%%", pct),
        highlight = hl,
      }
    end

    -- Define highlight groups
    vim.api.nvim_set_hl(0, "NeoTreeCoverageHigh", { fg = "#4CAF50" })
    vim.api.nvim_set_hl(0, "NeoTreeCoverageMed",  { fg = "#FFC107" })
    vim.api.nvim_set_hl(0, "NeoTreeCoverageLow",  { fg = "#F44336" })

    -- Inject the coverage component into the file renderer, right-aligned
    -- We need to walk the file renderer and add it inside the "container"'s content
    opts.renderers = opts.renderers or {}
    -- Find or create the file renderer
    local file_renderer = opts.renderers.file
    if not file_renderer then
      -- Default file renderer structure (matches neo-tree defaults)
      file_renderer = {
        { "indent" },
        { "icon" },
        {
          "container",
          width = "100%",
          content = {
            { "name", zindex = 10 },
            {
              "symlink_target",
              zindex = 10,
              highlight = "NeoTreeSymbolicLinkTarget",
            },
            { "clipboard", zindex = 10 },
            { "bufnr", zindex = 10 },
            { "modified", zindex = 20, align = "right" },
            { "diagnostics", zindex = 20, align = "right" },
            { "git_status", zindex = 10, align = "right" },
            { "file_size", zindex = 10, align = "right" },
            { "type", zindex = 10, align = "right" },
            { "last_modified", zindex = 10, align = "right" },
            { "created", zindex = 10, align = "right" },
          },
        },
      }
    end

    -- Insert coverage component into the container's content (after git_status)
    for _, item in ipairs(file_renderer) do
      if type(item) == "table" and item[1] == "container" and item.content then
        table.insert(item.content, { "coverage", zindex = 10, align = "right" })
        break
      end
    end

    opts.renderers.file = file_renderer
    return opts
  end,
}