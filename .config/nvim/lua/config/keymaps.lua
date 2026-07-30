-- Keymaps are automatically loaded on the VeryLazy event
local map = vim.keymap.set

-- =========================================================================
-- VS Code / Modern Style Keybinds
-- =========================================================================

-- 1. Select All (CTRL + SHIFT + A)
map({ "n", "i", "v" }, "<C-S-a>", "<Esc>ggVG", { desc = "Select All" })

-- 2. Select Line (CTRL + L)
map({ "n", "i" }, "<C-l>", "<Esc>V", { desc = "Select Line" })

-- 3. Cut (CTRL + X)
map("v", "<C-x>", '"+d', { desc = "Cut selection" })
map("n", "<C-x>", '"+dd', { desc = "Cut line" })

-- 3.5 x = true delete (black hole, no clipboard)
map({ "n", "v" }, "x", '"_x', { desc = "Delete char (no clipboard)" })

-- 4. Copy (CTRL + SHIFT + C)
map("v", "<C-S-c>", '"+y', { desc = "Copy to system clipboard" })

-- 5. Paste (CTRL + SHIFT + V)
map({ "n", "v" }, "<C-S-v>", '"+p', { desc = "Paste from clipboard" })
map("i", "<C-S-v>", "<C-r>+", { desc = "Paste from clipboard" })

-- 6. Search (CTRL + F)
map({ "n", "v" }, "<C-f>", "/", { desc = "Search" })
map("i", "<C-f>", "<Esc>/", { desc = "Search" })

-- 7. Undo (CTRL + Z)
map("n", "<C-z>", "u", { desc = "Undo" })
map("i", "<C-z>", "<C-o>u", { desc = "Undo" })

-- =========================================================================
-- SMART MOVE LINES (GLITCH-FREE VISUAL BLOCK SUPPORT)
-- Strategy: Esc -> Move -> Update Marks -> Reselect
-- =========================================================================

-- --- DOWN FUNCTIONS ---

local function smart_move_down()
  local current_line = vim.fn.line(".")
  local total_lines = vim.fn.line("$")

  -- Infinite Scroll: Add line if at bottom
  if current_line == total_lines then
    vim.api.nvim_buf_set_lines(0, total_lines, total_lines, false, { "" })
  end

  vim.cmd("silent! m .+1")
  vim.cmd("normal! ==")
end

local function smart_move_visual_down()
  -- 1. Exit visual mode to forcibly update '< and '> marks
  vim.cmd("normal! \27")

  local start_ln = vim.fn.line("'<")
  local end_ln = vim.fn.line("'>")
  local total_lines = vim.fn.line("$")

  -- Infinite Scroll: Add line if selection hits bottom
  if end_ln == total_lines then
    vim.api.nvim_buf_set_lines(0, total_lines, total_lines, false, { "" })
  end

  -- 2. Move the block
  vim.cmd("silent! " .. start_ln .. "," .. end_ln .. "m " .. end_ln .. "+1")

  -- 3. Manually update marks to point to the NEW location
  --    (We shift both marks down by 1)
  vim.api.nvim_buf_set_mark(0, "<", start_ln + 1, 0, {})
  vim.api.nvim_buf_set_mark(0, ">", end_ln + 1, 0, {})

  -- 4. Reselect and indent using the UPDATED marks
  vim.cmd("normal! gv=gv")
end

-- --- UP FUNCTIONS ---

local function smart_move_up()
  local current_line = vim.fn.line(".")
  if current_line > 1 then
    vim.cmd("silent! m .-2")
    vim.cmd("normal! ==")
  end
end

local function smart_move_visual_up()
  -- 1. Exit visual mode to forcibly update '< and '> marks
  vim.cmd("normal! \27")

  local start_ln = vim.fn.line("'<")
  local end_ln = vim.fn.line("'>")

  if start_ln > 1 then
    -- 2. Move the block
    vim.cmd("silent! " .. start_ln .. "," .. end_ln .. "m " .. start_ln .. "-2")

    -- 3. Manually update marks to point to the NEW location
    --    (We shift both marks up by 1)
    vim.api.nvim_buf_set_mark(0, "<", start_ln - 1, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", end_ln - 1, 0, {})

    -- 4. Reselect and indent using the UPDATED marks
    vim.cmd("normal! gv=gv")
  else
    -- If we hit the top, just restore selection so we don't lose it
    vim.cmd("normal! gv")
  end
end

-- --- KEYBINDINGS ---

-- Normal Mode
map("n", "<A-Down>", smart_move_down, { desc = "Move line down", silent = true })
map("n", "<A-Up>", smart_move_up, { desc = "Move line up", silent = true })

-- Visual Mode
map("v", "<A-Down>", smart_move_visual_down, { desc = "Move selection down", silent = true })
map("v", "<A-Up>", smart_move_visual_up, { desc = "Move selection up", silent = true })
