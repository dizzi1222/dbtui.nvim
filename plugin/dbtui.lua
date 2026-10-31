if vim.g.loaded_dbtui_nvim then
  return
end
vim.g.loaded_dbtui_nvim = true

vim.api.nvim_create_user_command("DbTui", function()
  require("dbtui").open()
end, { desc = "Open the database TUI picker" })
