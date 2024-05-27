local fn = vim.fn
local api = vim.api
local ns = api.nvim_create_namespace "Colorify"

api.nvim_set_hl_ns(ns)

local utils = require "colorify.utils"
local conf = utils.config
local needs_hl = utils.not_colored
local set_extmark = api.nvim_buf_set_extmark
local get_extmarks = api.nvim_buf_get_extmarks

---------------------------------- highlighters -----------------------------------------------
local function highlight_hex(buf, line, str)
  for col, hex in str:gmatch "()(#%x%x%x%x%x%x)" do
    local hl_group = utils.add_hl(ns, hex)
    local end_col = col + #hex - 1

    local opts = { end_col = end_col, hl_group = hl_group }

    if conf.mode == "virtual" then
      opts.hl_group = nil
      opts.virt_text_pos = "inline"
      opts.virt_text = { { conf.virt_txt, hl_group } }
    end

    if needs_hl(buf, ns, line, col - 1, hl_group, opts) then
      set_extmark(buf, ns, line, col - 1, opts)
    end
  end
end

local function highlight_lspvars(buf, line, min, max)
  local param = { textDocument = vim.lsp.util.make_text_document_params() }

  for _, client in pairs(vim.lsp.get_clients { bufnr = buf }) do
    if client.server_capabilities.colorProvider then
      client.request("textDocument/documentColor", param, function(_, resp)
        if resp and line then
          resp = vim.tbl_filter(function(v)
            return v.range["start"].line == line
          end, resp)
        end

        if resp and min then
          resp = vim.tbl_filter(function(v)
            return v.range["start"].line >= min and v.range["end"].line <= max
          end, resp)
        end

        for _, match in ipairs(resp or {}) do
          local color = match.color
          local r, g, b, a = color.red, color.green, color.blue, color.alpha
          local hex = string.format("#%02x%02x%02x", r * a * 255, g * a * 255, b * a * 255)

          local hl_group = utils.add_hl(ns, hex)

          local range_start = match.range.start
          local range_end = match.range["end"]

          local opts = {
            end_col = range_end.character,
            virt_text_pos = "inline",
            virt_text = { { "󱓻 ", hl_group } },
          }

          if needs_hl(buf, ns, range_start.line, range_start.character, hl_group, opts) then
            set_extmark(buf, ns, range_start.line, range_start.character, opts)
          end
        end
      end, buf)
    end
  end
end

------------------------------- main function ------------------------------------------------
local function colorify_lines(args)
  local buf = args.buf
  local winid = vim.fn.bufwinid(buf)

  local min = fn.line("w0", winid) - 1
  local max = fn.line("w$", winid) + 1

  if args.event == "TextChangedI" then
    local cur_linenr = fn.line(".", winid) - 1
    local cur_line = api.nvim_get_current_line()
    highlight_hex(buf, cur_linenr, cur_line)
    highlight_lspvars(buf, cur_linenr)
  else
    local lines = api.nvim_buf_get_lines(buf, min, max, false)

    for i, str in ipairs(lines) do
      highlight_hex(buf, i - 1, str)
    end

    if vim.bo[buf].buflisted then
      highlight_lspvars(buf, nil, min, max)
    end
  end
end

api.nvim_create_autocmd({
  "TextChanged",
  "TextChangedI",
  "TextChangedP",
  "VimResized",
  "LspAttach",
  "WinScrolled",
}, {
  callback = colorify_lines,
})

local handle_deletions = function(args)
  local buf = args.buf

  if vim.b[buf].colorify_attached then
    return
  end

  vim.b[buf].colorify_attached = true

  api.nvim_buf_attach(args.buf, false, {
    -- del extmarks of all lines except the current
    on_lines = function(_, b, _, first_line, last_line)
      local ms = get_extmarks(b, ns, { first_line, 0 }, { last_line, 0 }, {})

      for _, mark in ipairs(ms) do
        if mark[2] ~= (fn.line "." - 1) then
          api.nvim_buf_del_extmark(b, ns, mark[1])
        end
      end
    end,

    -- handle only current line extmarks
    on_bytes = function(_, b, _, line, col, _, _, _, endcol)
      if line ~= fn.line "." - 1 then
        return
      end

      local ms = get_extmarks(b, ns, { line, col }, { line, col + endcol }, { overlap = true })

      for _, mark in ipairs(ms) do
        api.nvim_buf_del_extmark(b, ns, mark[1])
      end
    end,
    on_detach = function()
      vim.b[buf].colorify_attached = false
    end,
  })
end

api.nvim_create_autocmd("BufEnter", { callback = handle_deletions })
