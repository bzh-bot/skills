-- Display test coverage overlays from lcov.info files.
-- Uses full-row virtual text highlights so even indented lines are colored
-- across the entire window width.

local M = {}

--- Path to the loaded lcov.info file (nil until explicitly loaded).
M.lcov_path = nil
--- Parsed coverage data:  { [abs_path] = { covered = {[line]=true}, uncovered = {[line]=true} } }
M.data = {}
--- Whether coverage is currently displayed.
M.visible = false

------------------------------------------------------------------------
-- Parsing
------------------------------------------------------------------------

--- Parse an lcov.info file into a table keyed by absolute file path.
---@param path string  Path to lcov.info
---@return table
local function parse_lcov(path)
  local fh = io.open(path, "r")
  if not fh then return {} end

  -- lcov SF: paths are prefixed with backend/ (e.g. backend/src/foo.ts).
  -- They resolve correctly against the project root, which is the parent of
  -- backend/, i.e. :h:h:h from backend/coverage/lcov.info.
  local project_root = vim.fn.fnamemodify(path, ":h:h:h")

  local results = {}
  local current_file = nil
  local covered = {}
  local uncovered = {}

  for line in fh:lines() do
    local sf = line:match("^SF:(.+)$")
    if sf then
      -- Turn relative SF: path into an absolute path
      local abs = project_root .. "/" .. sf
      abs = vim.fn.simplify(abs)
      current_file = abs
      covered = {}
      uncovered = {}
    elseif line:match("^DA:") then
      local lno_s, hits_s = line:match("^DA:(%d+),(%d+)")
      if lno_s and hits_s then
        local lno = tonumber(lno_s)
        local hits = tonumber(hits_s)
        if hits > 0 then
          covered[lno] = true
        else
          uncovered[lno] = true
        end
      end
    elseif line:match("^end_of_record$") then
      if current_file then
        results[current_file] = {
          covered = covered,
          uncovered = uncovered,
        }
      end
      current_file = nil
      covered = {}
      uncovered = {}
    end
  end
  fh:close()
  return results
end

------------------------------------------------------------------------
-- Display
------------------------------------------------------------------------

-- Single namespace for all coverage decorations (signs + extmarks).
local NS = vim.api.nvim_create_namespace("coverage")

-- Sign definitions (only define once)
local signs_defined = false
local function define_signs()
  if signs_defined then return end
  signs_defined = true
  vim.fn.sign_define("coverage_covered", {
    text = "✓",
    texthl = "CoverageCoveredSign",
  })
  vim.fn.sign_define("coverage_uncovered", {
    text = "✗",
    texthl = "CoverageUncoveredSign",
  })
end

-- Highlight groups
local hl_defined = false
local function define_highlights()
  if hl_defined then return end
  hl_defined = true
  vim.api.nvim_set_hl(0, "CoverageCoveredSign", { fg = "#4CAF50", bg = "#1a2e1a" })
  vim.api.nvim_set_hl(0, "CoverageUncoveredSign", { fg = "#F44336", bg = "#2e1a1a" })
  -- Full-line highlight colors
  vim.api.nvim_set_hl(0, "CoverageCoveredLine", { bg = "#1a2e1a" })
  vim.api.nvim_set_hl(0, "CoverageUncoveredLine", { bg = "#2e1a1a" })
end

--- Clear all coverage decorations in a buffer.
local function clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.fn.sign_unplace("coverage_covered", { buffer = bufnr })
  vim.fn.sign_unplace("coverage_uncovered", { buffer = bufnr })
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
end

--- Apply coverage decorations to a buffer.
--- Uses a right-aligned extmark with a full-width virtual-text highlight
--- so the entire row is colored, even for indented lines.
---@param bufnr number
---@param file_data table  { covered = {[line]=true}, uncovered = {[line]=true} }
local function apply(bufnr, file_data)
  clear(bufnr)
  define_signs()
  define_highlights()

  local function row(line)
    return line - 1  -- 0-indexed row for nvim APIs
  end

  -- Covered lines: green sign + full-row highlight
  for line in pairs(file_data.covered) do
    vim.fn.sign_place(0, "coverage_covered", "coverage_covered", bufnr, {
      lnum = line,
      priority = 9,
    })
    vim.api.nvim_buf_set_extmark(bufnr, NS, row(line), 0, {
      line_hl_group = "CoverageCoveredLine",
      priority = 9,
    })
  end

  -- Uncovered lines: red sign + full-row highlight
  for line in pairs(file_data.uncovered) do
    vim.fn.sign_place(0, "coverage_uncovered", "coverage_uncovered", bufnr, {
      lnum = line,
      priority = 9,
    })
    vim.api.nvim_buf_set_extmark(bufnr, NS, row(line), 0, {
      line_hl_group = "CoverageUncoveredLine",
      priority = 9,
    })
  end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

local function refresh_neotree()
  local ok, neotree = pcall(require, 'neo-tree')
  if ok and neotree and neotree.refresh then
    neotree.refresh()
  end
end

--- Load an lcov.info file and optionally display coverage in current buf.
---@param path string?  Path to lcov.info; defaults to searching upward.
function M.load(path)
  if path then
    M.lcov_path = path
  else
    -- Search upward for a coverage/lcov.info file
    local dir = vim.fn.getcwd()
    for _ = 1, 20 do
      local candidate = dir .. "/backend/coverage/lcov.info"
      if vim.fn.filereadable(candidate) == 1 then
        M.lcov_path = candidate
        break
      end
      local parent = vim.fn.fnamemodify(dir, ":h")
      if parent == dir then break end
      dir = parent
    end
  end

  if not M.lcov_path or vim.fn.filereadable(M.lcov_path) ~= 1 then
    vim.notify("coverage: no lcov.info found", vim.log.levels.WARN)
    return
  end

  M.data = parse_lcov(M.lcov_path)
  vim.notify(string.format("coverage: loaded %d files from %s",
    vim.tbl_count(M.data), M.lcov_path))

  if M.visible then
    M.show()
  end
end

--- Show coverage for the current buffer.
function M.show()
  if vim.tbl_isempty(M.data) then
    M.load()
  end
  if vim.tbl_isempty(M.data) then return end

  M.visible = true
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  local file_data = M.data[filepath]
  -- Fallback: also try relative match in case buf name differs slightly
  if not file_data then
    for p, d in pairs(M.data) do
      if filepath:sub(-#p) == p then
        file_data = d
        break
      end
    end
  end

  if not file_data then return end
  apply(bufnr, file_data)
  refresh_neotree()
end

--- Hide coverage decorations for the current buffer.
function M.hide()
  M.visible = false
  clear()
  refresh_neotree()
end

--- Toggle coverage display.
function M.toggle()
  if M.visible then M.hide() else M.show() end
end

------------------------------------------------------------------------
-- mini.map integration
------------------------------------------------------------------------

--- Return a mini.map integration callable that highlights covered/uncovered lines
--- in the minimap gutter.
---
--- Usage in mini.map setup:
---   integrations = {
---     require('config.coverage').minimap_integration({
---       covered   = 'CoverageCoveredLine',
---       uncovered = 'CoverageUncoveredLine',
---     }),
---   }
---
---@param hl_groups table|nil  Highlight groups for covered/uncovered lines.
---   Fields: <covered> (default 'CoverageCoveredLine'),
---           <uncovered> (default 'CoverageUncoveredLine').
---@return function  A callable returning {line, hl_group} entries for mini.map.
M.minimap_integration = function(hl_groups)
  if hl_groups == nil then
    hl_groups = { covered = 'CoverageCoveredLine', uncovered = 'CoverageUncoveredLine' }
  end

  -- Ensure highlight groups are defined (needed for minimap rendering)
  define_highlights()

  return function()
    local cov = require('config.coverage')

    -- Only show coverage when user explicitly loaded it
    if vim.tbl_isempty(cov.data) then return {} end

    -- Use the source buffer, NOT the current buffer (which is the minimap)
    local has_map, map = pcall(require, 'mini.map')
    local source_bufnr = has_map and map.current.buf_data and map.current.buf_data.source
    if not source_bufnr then return {} end

    local filepath = vim.api.nvim_buf_get_name(source_bufnr)
    if filepath == '' then return {} end

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
    if not file_data then return {} end

    local line_hl = {}
    -- Uncovered first (red) so covered (green) overwrites on same line
    for line in pairs(file_data.uncovered) do
      table.insert(line_hl, { line = line, hl_group = hl_groups.uncovered })
    end
    for line in pairs(file_data.covered) do
      table.insert(line_hl, { line = line, hl_group = hl_groups.covered })
    end
    return line_hl
  end
end

return M