local config = require("dbtui.config")
local detect = require("dbtui.detect")
local i18n = require("dbtui.i18n")
local terminal = require("dbtui.terminal")

local uv = vim.uv or vim.loop
local M = {}

local BUILTIN_ADAPTERS = {
  lazysql = "dbtui.adapters.lazysql",
  mongosh = "dbtui.adapters.mongosh",
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "DB TUI" })
end

local function adapter_for(id, options)
  if options.adapters[id] then
    return options.adapters[id]
  end
  local module = BUILTIN_ADAPTERS[id]
  if not module then
    return nil
  end
  local ok, adapter = pcall(require, module)
  return ok and adapter or nil
end

local function resolve_profile(context, options)
  for _, profile in ipairs(options.profiles) do
    local ok, matches = pcall(profile.match, context)
    if ok and matches then
      local connections_ok, connections = pcall(profile.connections, context, detect)
      if connections_ok and connections and #connections > 0 then
        return { connections = connections, name = profile.name or vim.fs.basename(context.root), root = context.root }
      end
      if not connections_ok then
        notify(connections, vim.log.levels.ERROR)
        return nil
      end
    end
  end
  return options.autodetect and detect.generic(context) or nil
end

local function is_loopback(host)
  return host == "localhost" or host == "::1" or (host and host:match("^127%.")) ~= nil
end

local function probe_port(host, port, callback)
  local tcp = uv.new_tcp()
  local timer = uv.new_timer()
  local finished = false

  local function finish(is_open)
    if finished then
      return
    end
    finished = true
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    if tcp and not tcp:is_closing() then
      tcp:close()
    end
    vim.schedule(function()
      callback(is_open)
    end)
  end

  local ok = pcall(function()
    tcp:connect(host, port, function(err)
      finish(err == nil)
    end)
    timer:start(500, 0, function()
      finish(false)
    end)
  end)
  if not ok then
    finish(false)
  end
end

local function connection_summary(connection)
  if connection.adapter == "mongosh" then
    return string.format("%s · %s", connection.label, connection.uri)
  end
  return string.format(
    "%s · %s @ %s:%d",
    connection.label,
    connection.database,
    connection.host,
    connection.port
  )
end

local function launch(profile, connection, adapter, mode, messages, options)
  local command, err = adapter.command(connection, mode, messages)
  if not command then
    notify(err, vim.log.levels.ERROR)
    return
  end
  terminal.open(command, { cwd = profile.root, title = adapter.title(connection, mode) }, options.terminal)
end

local function connect(profile, connection, adapter, mode, messages, options)
  local function start()
    launch(profile, connection, adapter, mode, messages, options)
  end

  if connection.preflight == false or not is_loopback(connection.host) or not connection.port then
    start()
    return
  end
  probe_port(connection.host, connection.port, function(is_open)
    if is_open then
      start()
      return
    end
    local hint = connection.proxy_hint or connection.service_hint
    local suffix = hint and string.format(messages.start_service, hint) or ""
    notify(string.format(messages.no_listener, connection.host, connection.port) .. suffix, vim.log.levels.ERROR)
  end)
end

local function choose_mode(profile, connection, options, messages)
  local adapter = adapter_for(connection.adapter, options)
  if not adapter then
    notify("Unknown DB TUI adapter: " .. tostring(connection.adapter), vim.log.levels.ERROR)
    return
  end
  if not adapter.available() then
    notify(string.format(messages.not_installed, adapter.label), vim.log.levels.ERROR)
    return
  end

  local modes = adapter.modes(messages)
  if #modes == 1 then
    connect(profile, connection, adapter, modes[1], messages, options)
    return
  end
  vim.ui.select(modes, {
    format_item = function(mode)
      return mode.label
    end,
    prompt = string.format(messages.connection_prompt, connection.label),
  }, function(mode)
    if mode then
      connect(profile, connection, adapter, mode, messages, options)
    end
  end)
end

---Open the database picker for the current project.
function M.open()
  local options = config.get()
  local messages = i18n.get(options.language)
  local profile = resolve_profile(detect.context(), options)
  if not profile then
    notify(messages.no_connections, vim.log.levels.ERROR)
    return
  end

  vim.ui.select(profile.connections, {
    format_item = connection_summary,
    prompt = string.format(messages.connection_prompt, profile.name),
  }, function(connection)
    if connection then
      choose_mode(profile, connection, options, messages)
    end
  end)
end

---Configure dbtui.nvim.
---@param options? table
function M.setup(options)
  options = config.setup(options)
  if options.keymap then
    local messages = i18n.get(options.language)
    vim.keymap.set("n", options.keymap, M.open, { desc = messages.keymap_desc })
  end
end

return M
