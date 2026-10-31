local M = {}

local defaults = {
  adapters = {},
  autodetect = true,
  keymap = nil,
  language = "en",
  profiles = {},
  terminal = {
    border = "rounded",
    height = 0.92,
    provider = "auto",
    width = 0.96,
  },
}

---@param options? table
---@return table
function M.setup(options)
  options = options or {}
  M.options = vim.tbl_deep_extend("force", {}, defaults, options)
  M.options.profiles = options.profiles or {}
  return M.options
end

---@return table
function M.get()
  return M.options or M.setup()
end

return M
