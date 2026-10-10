-- Tells Seamtype which mode neovim is in, so that in an app whose Esc key is set to "Vim" every
-- normal-mode key goes straight to neovim and words are decided only in insert mode.
-- Put this file in ~/.config/nvim/plugin/ (or require it from init.lua). Vim: seamtype.vim.
local seamtype
for _, dir in ipairs({ vim.fn.expand('~/Library/Input Methods'), '/Library/Input Methods' }) do
  local path = dir .. '/Seamtype.app/Contents/MacOS/Seamtype'
  if vim.fn.executable(path) == 1 then
    seamtype = path
    break
  end
end
if not seamtype then return end

local function tell(mode)
  -- Detached, so the last word still goes out when neovim is quitting.
  vim.fn.jobstart({ seamtype, '--vim', mode }, { detach = true })
end

local function current()
  local mode = vim.api.nvim_get_mode().mode
  return (mode:find('^[iR]') and 'insert') or 'normal'
end

local group = vim.api.nvim_create_augroup('Seamtype', { clear = true })
local function on(events, mode)
  vim.api.nvim_create_autocmd(events, {
    group = group,
    callback = function() tell(type(mode) == 'function' and mode() or mode) end,
  })
end

on('InsertEnter', 'insert')
on({ 'InsertLeave', 'VimEnter', 'VimResume' }, 'normal')
on('FocusGained', current)
-- Whatever is in front next (a shell in another pane) isn't neovim.
on({ 'VimLeavePre', 'VimSuspend', 'FocusLost' }, 'off')
