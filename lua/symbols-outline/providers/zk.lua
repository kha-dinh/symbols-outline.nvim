local config = require 'symbols-outline.config'
local lsp_utils = require 'symbols-outline.utils.lsp_utils'
local jsx = require 'symbols-outline.utils.jsx'
local zk_api = require 'zk.api'
local zk_util = require 'zk.util'
local zk_ui = require 'zk.ui'

local M = {}

local function getParams()
  return { textDocument = vim.lsp.util.make_text_document_params() }
end

function M.hover_info(bufnr, params, on_info)
  local clients = vim.lsp.buf_get_clients(bufnr)
  local used_client

  for id, client in pairs(clients) do
    if config.is_client_blacklisted(id) then
      goto continue
    else
      if client.server_capabilities.hoverProvider then
        used_client = client
        break
      end
    end
    ::continue::
  end

  if not used_client then
    on_info(nil, {
      contents = {
        kind = 'markdown',
        content = { 'No extra information availaible!' },
      },
    })
  end

  used_client.request('textDocument/hover', params, on_info, bufnr)
end

-- probably change this
function M.should_use_provider(bufnr)
  local clients = vim.lsp.buf_get_clients(bufnr)
  local ret = false

  for id, client in pairs(clients) do
    if client.config.name == 'zk' then
      ret = true
      break
    end
    ::continue::
  end

  return ret
end

function M.postprocess_symbols(response)
  local symbols = lsp_utils.flatten_response(response)

  local jsx_symbols = jsx.get_symbols()

  if #jsx_symbols > 0 then
    return lsp_utils.merge_symbols(symbols, jsx_symbols)
  else
    return symbols
  end
end

function M.parse_zk_response(response)
  local level_symbols = {}

  for index, value in ipairs(response) do
    local lines = string.gmatch(value.body, '([^\n]*)\n?')
    local matching_lines = {}
    -- Is this a HACK?
    local note_id = vim.fn.expand '%:t:r'
    local line_no = 1
    for line in lines do
      line_no = line_no + 1
      if string.match(line, note_id) then
        table.insert(matching_lines, { line = line, line_no = line_no })
      end
    end
    local entry = {
      kind = 1,
      name = value.title,
      filename = value.filename,
      selectionRange = {
        start = { character = 1, line = 1 },
        ['end'] = { character = 1, line = 1 },
      },
      range = {
        start = { character = 1, line = 1 },
        ['end'] = { character = 1, line = 1 },
      },
      children = {
        -- {
        --   kind = 13,
        --   name = 'OK',
        --   -- name = value.body,
        --   selectionRange = {
        --     start = { character = 1, line = 1 },
        --     ['end'] = { character = 1, line = 1 },
        --   },
        --   range = {
        --     start = { character = 1, line = 1 },
        --     ['end'] = { character = 1, line = 1 },
        --   },
        -- },
      },
    }
    for _, line in ipairs(matching_lines) do
      print(vim.inspect(line))
      local children_entry = {
        kind = 15,
        name = line.line,
        filename = value.filename,
        selectionRange = {
          start = { character = 1, line = line.line_no },
          ['end'] = { character = 1, line = line.line_no },
        },
        range = {
          start = { character = 1, line = line.line_no },
          ['end'] = { character = 1, line = line.line_no },
        },
      }
      table.insert(entry.children, children_entry)
    end
    level_symbols[index] = entry
  end
  return level_symbols
end

---@param on_symbols function
function M.request_symbols(on_symbols)
  local option = {
    select = { 'title', 'absPath', 'filename', 'body' },
    linkTo = { vim.api.nvim_buf_get_name(0) },
  }
  zk_api.list(nil, option, function(err, response)
    assert(not err, tostring(err))
    on_symbols(M.parse_zk_response(response))
    -- on_symbols(M.postprocess_symbols(response))
  end)
  -- vim.lsp.buf_request_all(
  --   0,
  --   'textDocument/documentSymbol',
  --   getParams(),
  --   function(response)
  --     on_symbols(M.postprocess_symbols(response))
  --   end
  -- )
end

return M
