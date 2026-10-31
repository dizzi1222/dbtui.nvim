local M = {}

local function open_with_snacks(command, options, terminal_options)
  if terminal_options.provider == "builtin" then
    return false
  end
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.terminal then
    return false
  end

  snacks.terminal.focus(command, {
    cwd = options.cwd,
    win = {
      border = terminal_options.border,
      height = terminal_options.height,
      position = "float",
      title = options.title,
      title_pos = "center",
      width = terminal_options.width,
    },
  })
  return true
end

local function close_buffer(buffer)
  if vim.api.nvim_buf_is_valid(buffer) then
    vim.api.nvim_buf_delete(buffer, { force = true })
  end
end

local function open_builtin(command, options, terminal_options)
  local columns = vim.o.columns
  local lines = vim.o.lines
  local width = math.max(40, math.floor(columns * terminal_options.width))
  local height = math.max(10, math.floor(lines * terminal_options.height))
  local buffer = vim.api.nvim_create_buf(false, true)
  local window = vim.api.nvim_open_win(buffer, true, {
    border = terminal_options.border,
    col = math.floor((columns - width) / 2),
    height = height,
    relative = "editor",
    row = math.floor((lines - height) / 2),
    style = "minimal",
    title = options.title,
    title_pos = "center",
    width = width,
  })

  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].filetype = "dbtui"
  vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], { buffer = buffer, desc = "DB TUI: terminal normal mode" })
  vim.keymap.set("n", "q", function()
    close_buffer(buffer)
  end, { buffer = buffer, desc = "DB TUI: close" })

  vim.api.nvim_buf_call(buffer, function()
    vim.fn.jobstart(command, {
      cwd = options.cwd,
      on_exit = function(_, exit_code)
        if exit_code == 0 then
          vim.schedule(function()
            close_buffer(buffer)
          end)
        end
      end,
      term = true,
    })
  end)
  vim.api.nvim_set_current_win(window)
  vim.cmd.startinsert()
end

---@param command string[]
---@param options table
---@param terminal_options table
function M.open(command, options, terminal_options)
  if not open_with_snacks(command, options, terminal_options) then
    open_builtin(command, options, terminal_options)
  end
end

return M
