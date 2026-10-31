local uv = vim.uv or vim.loop

local M = {}

local SQL_ENV_KEYS = {
  DATABASE_NAME = true,
  DATABASE_USER = true,
  DB_DATABASE = true,
  DB_HOST = true,
  DB_NAME = true,
  DB_PORT = true,
  DB_SSLMODE = true,
  DB_USER = true,
  DB_USERNAME = true,
  PGDATABASE = true,
  PGHOST = true,
  PGPORT = true,
  PGSSLMODE = true,
  PGUSER = true,
}

local MONGO_ENV_KEYS = {
  MONGODB_URI = true,
  MONGO_URI = true,
  MONGO_URL = true,
}

local DATABASE_MARKERS = {
  ".env",
  ".env.local",
  ".env.prod",
  ".env.production",
  ".env.production.local",
  ".env.qa",
  ".env.qa.local",
  "compose.yaml",
  "compose.yml",
  "docker-compose.yaml",
  "docker-compose.yml",
}

local function is_file(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

local function trim_env_value(value)
  value = vim.trim(value)
  local first = value:sub(1, 1)
  local last = value:sub(-1)
  if #value >= 2 and ((first == '"' and last == '"') or (first == "'" and last == "'")) then
    return value:sub(2, -2)
  end
  return vim.trim((value:gsub("%s+#.*$", "")))
end

local function read_selected_env(path, accepted_keys)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local values = {}
  for line in file:lines() do
    local key = line:match("^%s*export%s+([%a_][%w_]*)%s*=") or line:match("^%s*([%a_][%w_]*)%s*=")
    if key and accepted_keys[key] then
      values[key] = trim_env_value(line:match("^[^=]*=(.*)$") or "")
    end
  end
  file:close()
  return values
end

local function percent_decode(value)
  return (value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function find_database_root(start, git_root)
  local directory = start
  while directory do
    for _, marker in ipairs(DATABASE_MARKERS) do
      if is_file(vim.fs.joinpath(directory, marker)) then
        return directory
      end
    end
    if directory == git_root then
      break
    end
    local parent = vim.fs.dirname(directory)
    if not parent or parent == directory then
      break
    end
    directory = parent
  end
  return git_root
end

local function root_context()
  local buffer_path = vim.api.nvim_buf_get_name(0)
  local start = buffer_path ~= "" and vim.fs.dirname(buffer_path) or vim.fn.getcwd()
  local git_root = vim.fs.root(start, ".git") or start
  local root = find_database_root(start, git_root)
  local remote

  if vim.fn.executable("git") == 1 then
    local result = vim.system({ "git", "-C", git_root, "remote", "get-url", "origin" }, { text = true }):wait(1000)
    if result.code == 0 then
      remote = vim.trim(result.stdout or ""):gsub("%.git$", "")
    end
  end

  return { cwd = vim.fn.getcwd(), remote = remote, root = root }
end

---@param path string
---@return table?, string?
function M.read_sql_env(path)
  local values = read_selected_env(path, SQL_ENV_KEYS)
  if not values then
    return nil, "Could not read " .. path
  end

  local host = values.DB_HOST or values.PGHOST or "127.0.0.1"
  local database = values.DB_NAME or values.DB_DATABASE or values.DATABASE_NAME or values.PGDATABASE
  local username = values.DB_USER or values.DB_USERNAME or values.DATABASE_USER or values.PGUSER
  if not database or database == "" or not username or username == "" then
    return nil, path .. " does not define a database name and user"
  end

  local loopback = host == "localhost" or host == "::1" or host:match("^127%.") ~= nil
  return {
    adapter = "lazysql",
    database = database,
    env_file = path,
    host = host,
    port = tonumber(values.DB_PORT or values.PGPORT) or 5432,
    sslmode = values.DB_SSLMODE or values.PGSSLMODE or (loopback and "disable" or "require"),
    username = username,
  }
end

local function contains_sensitive_query(uri)
  local query = uri:match("%?(.*)$")
  if not query then
    return false
  end
  query = "&" .. query:lower()
  for _, key in ipairs({ "password", "passwd", "secret", "token", "api_key", "apikey" }) do
    if query:find("&" .. key .. "=", 1, true) then
      return true
    end
  end
  return false
end

local function sanitize_mongo_uri(uri)
  local scheme, rest = uri:match("^(mongodb[%+%w]*):%/%/(.+)$")
  if (scheme ~= "mongodb" and scheme ~= "mongodb+srv") or contains_sensitive_query(uri) then
    return nil
  end

  local boundary = rest:find("[/?]")
  local authority = boundary and rest:sub(1, boundary - 1) or rest
  local tail = boundary and rest:sub(boundary) or ""
  local userinfo, hosts = authority:match("^(.*)@([^@]+)$")
  local username
  if userinfo then
    username = percent_decode(userinfo:match("^([^:]+)") or "")
    authority = hosts
  end

  local sanitized = scheme .. "://" .. authority .. tail
  local host, port
  if scheme == "mongodb" and not authority:find(",", 1, true) then
    host, port = authority:match("^([^:]+):(%d+)$")
    host = host or authority
    port = tonumber(port) or 27017
  end

  return {
    adapter = "mongosh",
    database = percent_decode(tail:match("^/([^?]*)") or ""),
    host = host,
    port = port,
    preflight = scheme == "mongodb" and host ~= nil,
    uri = sanitized,
    username = username,
  }
end

local function read_mongo_env(path)
  local values = read_selected_env(path, MONGO_ENV_KEYS)
  if not values then
    return nil
  end
  for _, key in ipairs({ "MONGODB_URI", "MONGO_URI", "MONGO_URL" }) do
    if values[key] and values[key] ~= "" then
      return sanitize_mongo_uri(values[key])
    end
  end
end

local function mongo_from_compose(root)
  for _, filename in ipairs({ "compose.yml", "compose.yaml", "docker-compose.yml", "docker-compose.yaml" }) do
    local path = vim.fs.joinpath(root, filename)
    if is_file(path) then
      local file = io.open(path, "r")
      local contents = file and file:read("*a") or ""
      if file then
        file:close()
      end
      if contents:lower():match("image:%s*['\"]?mongo[:'\"]") then
        local host_port = 27017
        for line in contents:gmatch("[^\r\n]+") do
          if line:match(":27017['\"]?%s*$") then
            host_port = tonumber(line:gsub(":27017['\"]?%s*$", ""):match("(%d+)%s*$")) or host_port
            break
          end
        end
        return {
          adapter = "mongosh",
          database = "",
          environment = "main",
          host = "127.0.0.1",
          id = "main-mongodb-compose",
          label = "MAIN · MongoDB",
          port = host_port,
          service_hint = "docker compose up -d",
          uri = string.format("mongodb://127.0.0.1:%d", host_port),
        }
      end
    end
  end
end

---@return table
function M.context()
  return root_context()
end

---@param context table
---@return table?
function M.generic(context)
  local candidates = {
    { environment = "main", label = "MAIN", files = { ".env.local", ".env" } },
    { environment = "qa", label = "QA", files = { ".env.qa.local", ".env.qa" } },
    { environment = "prod", label = "PROD", files = { ".env.production.local", ".env.production", ".env.prod" } },
  }
  local connections = {}
  local found_mongo = false

  for _, candidate in ipairs(candidates) do
    for _, filename in ipairs(candidate.files) do
      local path = vim.fs.joinpath(context.root, filename)
      if is_file(path) then
        local detected = false
        local sql = M.read_sql_env(path)
        if sql then
          sql.environment = candidate.environment
          sql.id = candidate.environment .. "-sql"
          sql.label = candidate.label .. " · PostgreSQL"
          connections[#connections + 1] = sql
          detected = true
        end

        local mongo = read_mongo_env(path)
        if mongo then
          mongo.environment = candidate.environment
          mongo.id = candidate.environment .. "-mongodb"
          mongo.label = candidate.label .. " · MongoDB"
          connections[#connections + 1] = mongo
          found_mongo = true
          detected = true
        end
        if detected then
          break
        end
      end
    end
  end

  if not found_mongo then
    local compose = mongo_from_compose(context.root)
    if compose then
      connections[#connections + 1] = compose
    end
  end

  if #connections == 0 then
    return nil
  end
  return { connections = connections, name = vim.fs.basename(context.root), root = context.root }
end

return M
