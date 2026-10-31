local translations = {
  en = {
    connection_prompt = "DB TUI · %s · connection:",
    edit = "Edit",
    insecure_env = "Connection cancelled: %s has %03o permissions. Run: chmod 600 %s",
    keymap_desc = "DB TUI: choose connection and access mode",
    mongo_shell = "MongoDB shell (database permissions)",
    no_connections = "No supported database connection was detected in this project",
    no_listener = "No database is listening on %s:%d",
    not_installed = "%s is not installed",
    prod_cancelled = "Production write access cancelled",
    prod_confirm = "⚠ PROD @ %s · type PROD EDIT to enable writes: ",
    read_only = "Read-only (recommended)",
    start_service = "\nStart the required service with:\n%s",
  },
  es = {
    connection_prompt = "DB TUI · %s · conexión:",
    edit = "Edición",
    insecure_env = "Conexión cancelada: %s tiene permisos %03o. Ejecuta: chmod 600 %s",
    keymap_desc = "DB TUI: elegir conexión y modo de acceso",
    mongo_shell = "Shell de MongoDB (permisos de la base de datos)",
    no_connections = "No se detectó una conexión de base de datos compatible en este proyecto",
    no_listener = "No hay una base de datos escuchando en %s:%d",
    not_installed = "%s no está instalado",
    prod_cancelled = "Edición de producción cancelada",
    prod_confirm = "⚠ PROD @ %s · escribe PROD EDIT para habilitar escritura: ",
    read_only = "Solo lectura (recomendado)",
    start_service = "\nInicia el servicio requerido con:\n%s",
  },
}

---@param language? string|table
---@return table
local function get(language)
  if type(language) == "table" then
    return vim.tbl_deep_extend("force", {}, translations.en, language)
  end
  return translations[language or "en"] or translations.en
end

return { get = get }
