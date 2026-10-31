local M = {
  id = "mongosh",
  label = "MongoDB",
}

---@return boolean
function M.available()
  return vim.fn.executable("mongosh") == 1
end

---@param messages table
---@return table[]
function M.modes(messages)
  return {
    { id = "server-permissions", label = messages.mongo_shell, write = true },
  }
end

---@param connection table
---@return string[]
function M.command(connection)
  local command = { "mongosh" }
  if connection.username and connection.username ~= "" then
    vim.list_extend(command, { "--username", connection.username })
  end
  command[#command + 1] = connection.uri
  return command
end

---@param connection table
---@param mode table
---@return string
function M.title(connection, mode)
  return string.format(" DB TUI · MongoDB · %s · %s ", connection.label, mode.label)
end

return M
