--Credential Handling
local PASSWORD_FILE_LAUNCHER = [=[
env_file=$1
access_mode=$2
db_host=$3
db_port=$4
db_name=$5
db_user=$6
shift 6

db_password=$(
  awk '
    /^[[:space:]]*(export[[:space:]]+)?(DB_PASSWORD|DATABASE_PASSWORD|PGPASSWORD)[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      first = substr($0, 1, 1)
      last = substr($0, length($0), 1)
      if ((first == "\"" && last == "\"") || (first == "\047" && last == "\047")) {
        $0 = substr($0, 2, length($0) - 2)
      }
      print
      exit
    }
  ' "$env_file"
)

if [ -z "$db_password" ]; then
  printf 'DB TUI: no database password was found in %s\n' "$env_file" >&2
  exit 1
fi

escape_pgpass() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/:/\\:/g'
}

umask 077
runtime_dir=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
pgpass_file=$(mktemp "$runtime_dir/dbtui-pgpass.XXXXXX") || exit 1
cleanup() {
  rm -f "$pgpass_file"
}
trap cleanup 0
trap 'exit 130' 2
trap 'exit 143' 1 15

printf '%s:%s:%s:%s:%s\n' \
  "$(escape_pgpass "$db_host")" \
  "$(escape_pgpass "$db_port")" \
  "$(escape_pgpass "$db_name")" \
  "$(escape_pgpass "$db_user")" \
  "$(escape_pgpass "$db_password")" > "$pgpass_file"

export PGPASSFILE="$pgpass_file"
export PGAPPNAME="nvim-dbtui-$access_mode"
unset PGPASSWORD PGSERVICE PGSERVICEFILE

if [ "$access_mode" = "read-only" ]; then
  export PGOPTIONS="${PGOPTIONS:+$PGOPTIONS }-c default_transaction_read_only=on -c statement_timeout=30000 -c lock_timeout=3000"
fi

lazysql "$@"
exit $?
]=]

local M = {
  id = "lazysql",
  label = "LazySQL",
}

local function percent_encode(value)
  return (tostring(value):gsub("([^%w%-._~])", function(character)
    return string.format("%%%02X", string.byte(character))
  end))
end

local function connection_url(connection)
  local host = connection.host
  if host:find(":", 1, true) and not host:match("^%[.*%]$") then
    host = "[" .. host .. "]"
  end
  return string.format(
    "postgres://%s@%s:%d/%s?sslmode=%s&connect_timeout=5",
    percent_encode(connection.username),
    host,
    connection.port,
    percent_encode(connection.database),
    percent_encode(connection.sslmode or "disable")
  )
end

local function secure_env_file(path, messages)
  local stat = (vim.uv or vim.loop).fs_stat(path)
  if stat and stat.mode and stat.mode % 64 ~= 0 then
    return nil, string.format(messages.insecure_env, path, stat.mode % 512, path)
  end
  return true
end

---@return boolean
function M.available()
  return vim.fn.executable("lazysql") == 1
end

---@param messages table
---@return table[]
function M.modes(messages)
  return {
    { id = "read-only", label = messages.read_only, write = false },
    { id = "edit", label = messages.edit, write = true },
  }
end

---@param connection table
---@param mode table
---@param messages table
---@return string[]?, string?
function M.command(connection, mode, messages)
  local secure, err = secure_env_file(connection.env_file, messages)
  if not secure then
    return nil, err
  end

  local command = {
    "sh",
    "-c",
    PASSWORD_FILE_LAUNCHER,
    "dbtui.nvim",
    connection.env_file,
    mode.id,
    connection.host,
    tostring(connection.port),
    connection.database,
    connection.username,
  }
  if mode.id == "read-only" then
    command[#command + 1] = "-read-only"
  end
  command[#command + 1] = connection_url(connection)
  return command
end

---@param connection table
---@param mode table
---@return string
function M.title(connection, mode)
  return string.format(" DB TUI · LazySQL · %s · %s ", connection.label, mode.label)
end

return M
