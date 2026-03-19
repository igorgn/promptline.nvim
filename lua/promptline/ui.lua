local M = {}

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function create_float(title, width, height)
  height = height or 1
  width = width or 60
  local row = math.floor((vim.o.lines - height) / 2) - 4
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })

  vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder"

  return buf, win
end

function M.close_float(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

function M.show_working(win, buf, msg)
  vim.bo[buf].buftype = ""
  vim.bo[buf].modifiable = true

  local frame = 1
  local timer = vim.loop.new_timer()

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then
      timer:stop()
      return
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { spinner_frames[frame] .. "  " .. msg })
    frame = (frame % #spinner_frames) + 1
  end

  render()
  timer:start(0, 80, vim.schedule_wrap(render))

  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, { title = " promptline — working… ", title_pos = "center" })
  end
  vim.cmd("stopinsert")
  vim.cmd("wincmd p")

  local stopped = false
  return function()
    if stopped then return end
    stopped = true
    timer:stop()
    timer:close()
  end
end

function M.show_explain(win, buf, text)
  vim.bo[buf].buftype = ""
  vim.bo[buf].modifiable = true

  local width = vim.api.nvim_win_get_width(win)
  local wrapped = {}
  for _, para in ipairs(vim.split(text, "\n", { plain = true })) do
    if para == "" then
      table.insert(wrapped, "")
    else
      local pos = 1
      while pos <= #para do
        local chunk = para:sub(pos, pos + width - 3)
        if #chunk == width - 2 and para:sub(pos + width - 2, pos + width - 2) ~= "" then
          local last_space = chunk:match(".*()%s")
          if last_space and last_space > 1 then
            chunk = chunk:sub(1, last_space - 1)
          end
        end
        table.insert(wrapped, chunk)
        pos = pos + #chunk
        if para:sub(pos, pos) == " " then pos = pos + 1 end
      end
    end
  end

  local height = math.min(#wrapped, math.floor(vim.o.lines * 0.6))
  vim.api.nvim_win_set_config(win, {
    height = height,
    title = " promptline — explanation ",
    title_pos = "center",
  })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, wrapped)
  vim.bo[buf].modifiable = false
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.api.nvim_set_current_win(win)

  local function close() M.close_float(win) end
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "q",     close, { buffer = buf, nowait = true })
end

-- Draw preset rows below the input line and resize the window.
-- Called only after the first C-n/C-p press.
local function draw_presets(buf, win, presets, selected_idx, width)
  local ns = vim.api.nvim_create_namespace("promptline_presets")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  -- Build rows: separator then one row per preset
  local hint = " <C-n/p> presets "
  local dashes = math.max(0, math.floor((width - #hint) / 2))
  local sep = string.rep("─", dashes) .. hint .. string.rep("─", math.max(0, width - dashes - #hint))

  local rows = {}
  for _, p in ipairs(presets) do
    local tag = p.mode == "explain" and "  [explain]" or ""
    table.insert(rows, string.format("  %s%s", p.label, tag))
  end

  -- Overwrite lines 1..N (line 0 is owned by the prompt buftype)
  vim.bo[buf].buftype = ""
  vim.bo[buf].modifiable = true
  local all = { "" } -- placeholder for line 0 (prompt line, will be restored)
  table.insert(all, sep)
  for _, r in ipairs(rows) do table.insert(all, r) end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, all)
  vim.bo[buf].buftype = "prompt"
  vim.fn.prompt_setprompt(buf, "")

  -- Highlight separator
  vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, { end_col = #sep, hl_group = "Comment" })

  -- Highlight preset rows
  for i, r in ipairs(rows) do
    vim.api.nvim_buf_set_extmark(buf, ns, 1 + i, 0, {
      end_row = 1 + i,
      end_col = #r,
      hl_group = (i == selected_idx) and "PmenuSel" or "Pmenu",
    })
  end

  -- Resize window: 1 input + 1 sep + N presets
  vim.api.nvim_win_set_config(win, { height = 2 + #presets })
  -- Keep cursor on the input line
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
end

function M.prompt(opts, on_submit, on_cancel)
  local title       = opts.title or "Prompt"
  local placeholder = opts.placeholder or ""
  local width       = opts.width or 60
  local presets     = opts.presets or {}

  -- Start as a single-line float
  local buf, win = create_float(title, width, 1)

  vim.bo[buf].buftype = "prompt"
  vim.fn.prompt_setprompt(buf, "")

  local hint_ns = vim.api.nvim_create_namespace("promptline_hint")
  local preset_idx = 0
  local preset_mode = "edit"  -- tracks mode of currently selected/typed preset
  local presets_visible = false

  -- Show faded placeholder when input is empty
  local function set_placeholder()
    vim.api.nvim_buf_clear_namespace(buf, hint_ns, 0, -1)
    if placeholder ~= "" then
      vim.api.nvim_buf_set_extmark(buf, hint_ns, 0, 0, {
        virt_text = { { placeholder, "Comment" } },
        virt_text_pos = "overlay",
        hl_mode = "combine",
      })
    end
  end

  set_placeholder()

  if #presets > 0 then
    vim.api.nvim_win_set_config(win, {
      title = " promptline  <C-n/p> presets ",
      title_pos = "center",
    })
  end

  vim.cmd("startinsert")

  -- Clear placeholder on first keystroke (only when user types, not via cycle)
  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = buf,
    once = true,
    callback = function()
      preset_idx = 0
      preset_mode = "edit"
      vim.api.nvim_buf_clear_namespace(buf, hint_ns, 0, -1)
    end,
  })

  local submitted = false

  local function do_cancel()
    if submitted then return end
    submitted = true
    M.close_float(win)
    vim.schedule(on_cancel)
  end

  local function cycle(dir)
    if #presets == 0 then return end
    preset_idx = ((preset_idx - 1 + dir) % #presets) + 1
    local p = presets[preset_idx]
    preset_mode = p.mode or "edit"

    -- Expand the window to show the list on first cycle
    if not presets_visible then
      presets_visible = true
    end
    draw_presets(buf, win, presets, preset_idx, width)

    -- Write the preset prompt text into the input line so user can edit it
    vim.bo[buf].buftype = ""
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { p.prompt })
    vim.bo[buf].buftype = "prompt"
    vim.fn.prompt_setprompt(buf, "")
    vim.api.nvim_buf_clear_namespace(buf, hint_ns, 0, -1)

    -- Put cursor at end of the prefilled text
    vim.cmd("startinsert!")
  end

  vim.keymap.set("i", "<C-n>", function() cycle(1)  end, { buffer = buf, nowait = true })
  vim.keymap.set("i", "<C-p>", function() cycle(-1) end, { buffer = buf, nowait = true })

  vim.keymap.set("i", "<CR>", function()
    if submitted then return end
    submitted = true

    local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
    local prompt = (lines[1] or ""):gsub("^%s*(.-)%s*$", "%1")
    if prompt == "" then prompt = placeholder end
    local mode = preset_mode

    vim.schedule(function()
      on_submit({ prompt = prompt, mode = mode }, win, buf)
    end)
  end, { buffer = buf, nowait = true })

  vim.keymap.set("i", "<Esc>", do_cancel, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", do_cancel, { buffer = buf, nowait = true })

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if not submitted then vim.schedule(on_cancel) end
    end,
  })

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      do_cancel()
    end,
  })
end

return M
