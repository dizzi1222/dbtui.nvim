# dbtui.nvim

![DB TUI notification](https://github.com/user-attachments/assets/1cda11a6-ddd7-47d2-a921-b0eb83c12da7)

[DB TUI demo video](https://github.com/user-attachments/assets/c00b414c-693d-469d-ab7d-d5495d9b85fe)

![DB TUI connection picker](https://github.com/user-attachments/assets/4c15f6f1-1ef6-4137-b5f5-840589390735)

Project-aware database TUI launcher for Neovim. It detects database connections, lets the user choose an environment,
and opens the appropriate client in a floating terminal.

## Features

- PostgreSQL connections through [LazySQL](https://github.com/jorgerojas26/lazysql).
- MongoDB connections through `mongosh`.
- Automatic detection from `.env`, `.env.qa`, `.env.production`, and Docker Compose files.
- Read-only and edit modes for PostgreSQL.
- English and Spanish interfaces.
- Custom project profiles and adapters.
- Snacks terminal integration with a built-in Neovim terminal fallback.

## Requirements

- Neovim 0.10 or newer.
- `lazysql` for PostgreSQL connections.
- `mongosh` for MongoDB connections.

Only the executable required by the selected connection needs to be installed.

## Installation

With lazy.nvim:

```lua
{
  "dizzi1222/dbtui.nvim",
  opts = {
    keymap = "<leader>gz",
  },
}
```

For local development:

```lua
{
  dir = vim.fn.stdpath("config") .. "/local-plugins/dbtui.nvim",
  name = "dbtui.nvim",
  opts = {
    keymap = "<leader>gz",
  },
}
```

The `:DbTui` command is always available. A keymap is created only when `keymap` is configured.

## Configuration

```lua
require("dbtui").setup({
  autodetect = true,
  keymap = "<leader>gz",
  language = "en", -- Use "es" for Spanish.
  terminal = {
    border = "rounded",
    height = 0.92,
    provider = "auto", -- "auto", "snacks", or "builtin".
    width = 0.96,
  },
})
```

### Custom profiles

Profiles override automatic detection when `match` returns `true`.

```lua
require("dbtui").setup({
  profiles = {
    {
      name = "My project",
      match = function(context)
        return context.remote and context.remote:match("example/my%-project$") ~= nil
      end,
      connections = function(context, helpers)
        local connection = assert(helpers.read_sql_env(vim.fs.joinpath(context.root, ".env")))
        connection.environment = "main"
        connection.id = "main-postgresql"
        connection.label = "MAIN · PostgreSQL"
        return { connection }
      end,
    },
  },
})
```

The profile context contains `root`, `cwd`, and the normalized Git `remote`. A connection selects an adapter with
`adapter = "lazysql"` or `adapter = "mongosh"`.

## Detection

The built-in detector recognizes:

- PostgreSQL variables such as `DB_NAME`, `DB_USER`, `DB_HOST`, and their `PG*` equivalents.
- Configured PostgreSQL ports from `DB_PORT` or `PGPORT`, without a hardcoded proxy port.
- MongoDB URIs in `MONGODB_URI`, `MONGO_URI`, or `MONGO_URL`.
- A local MongoDB service using the official `mongo` image in a Compose file.

Credentials embedded in a MongoDB URI are removed before the URI is passed to `mongosh`. The username is forwarded
separately so `mongosh` can request the password interactively.

## Safety model

PostgreSQL passwords are never placed in the process arguments. The LazySQL adapter reads the password only when the
terminal starts, writes it to a temporary `PGPASSFILE` with mode `0600`, and deletes the file when the process exits.
Read-only mode also sets PostgreSQL session defaults, but a dedicated read-only database role remains the strongest
server-enforced protection.

Write mode opens the selected connection directly, including production connections. Database access remains the
user's responsibility; use server-side roles and permissions when additional safeguards are required.

MongoDB does not expose an equivalent client-side read-only mode. Its effective permissions come from the MongoDB user
roles, so use a read-only account whenever writes must be impossible.

## License

MIT
