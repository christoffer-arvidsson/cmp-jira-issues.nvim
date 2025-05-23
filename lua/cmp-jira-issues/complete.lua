local M = {}

local Job = require('plenary.job')

local enabled = true

local function extract_field(parent, field)
  if #field == 1 then
    return parent[field[1]]
  else
    local t = vim.deepcopy(field)
    table.remove(t, 1)
    return extract_field(parent[field[1]], t)
  end
end

local get_fields = function(issue, items_from)
  local t = {}
  for _, item_key in ipairs(items_from) do
    table.insert(t, extract_field(issue, item_key))
  end
  return t
end

M.get_complete_fn = function(complete_opts)
  return function(self, _, callback)
    if not enabled then
      return
    end

    local bufnr = vim.api.nvim_get_current_buf()

    local cached = complete_opts.get_cache(self, bufnr)
    if cached ~= nil then
      callback({ items = cached, isIncomplete = false })
      return
    end

    Job:new({
      'curl',
      '--silent',
      '--get',
      '--header',
      'Content-Type: application/json',
      '--data-urlencode',
      'fields=' .. complete_opts.fields,
      '--config',
      complete_opts.curl_config,
      on_exit = function(job)
        local result = job:result()
        local ok, parsed = pcall(vim.json.decode, table.concat(result, ''))

        if not ok then
          enabled = false
          print('bad response from curl after querying jira')
          return
        end

        if parsed == nil then -- make linter happy
          enabled = false
          return
        end

        local items = {}
        for _, issue in ipairs(parsed.issues) do
          for _, item_format in ipairs(complete_opts.items) do
            local label = string.format(item_format[1], unpack(get_fields(issue, item_format[2])))
            table.insert(items, {
              label = label,                     -- shown in the completion menu
              insertText = issue.key,           -- only insert the issue tag
              documentation = {
                kind = 'plaintext',
                value = string.format('[%s] %s\n\n%s', issue.key,
                  (issue.fields or {}).summary or '',
                  string.gsub(tostring((issue.fields or {}).description or ''), '\r', '')
                ),
              },
            })
          end
        end

        callback({ items = items, isIncomplete = false })

        complete_opts.set_cache(self, bufnr, items)
      end,
    }):start()
  end
end

return M
