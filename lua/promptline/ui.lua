local M = {}

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function create_float(title, width)
  width = width or 60
  local height = 1
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

-- Switch an existing float window into a non-editable status display.
-- Returns a stop() function that clears the spinner timer.
function M.show_working(win, buf, msg)
  -- Make buffer normal (not prompt) so we can set lines freely
  vim.bo[buf].buftype = ""
  vim.bo[buf].modifiable = true

  local frame = 1
  local timer = vim.loop.new_timer()

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then
      timer:stop()
      return
    end
    local line = spinner_frames[frame] .. "  " .. msg
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    frame = (frame % #spinner_frames) + 1
  end

  render()
  timer:start(0, 80, vim.schedule_wrap(render))

  -- Update float title and return focus to the editing buffer
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

function M.close_float(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

-- Open a float prompt. Calls on_submit(text, win, buf) or on_cancel().
-- win/buf are passed to on_submit so the caller can reuse the window for status.
function M.prompt(opts, on_submit, on_cancel)
  local title = opts.title or "Prompt"
  local placeholder = opts.placeholder or ""
  local width = opts.width or 60

  local buf, win = create_float(title, width)

  vim.bo[buf].buftype = "prompt"
  vim.fn.prompt_setprompt(buf, "")

  local ns = vim.api.nvim_create_namespace("promptline_hint")

  -- Pre-fill placeholder as virtual text hint
  if placeholder ~= "" then
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
      virt_text = { { placeholder, "Comment" } },
      virt_text_pos = "overlay",
      hl_mode = "combine",
    })
  end

  vim.cmd("startinsert")

  -- Clear hint as soon as user types
  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = buf,
    once = true,
    callback = function()
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end,
  })

  local submitted = false

  local function do_cancel()
    if submitted then return end
    M.close_float(win)
    vim.schedule(on_cancel)
  end

  -- Submit on <Enter>
  vim.keymap.set("i", "<CR>", function()
    if submitted then return end
    submitted = true
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, ""):gsub("^%s*(.-)%s*$", "%1")
    -- Don't close — pass win/buf to on_submit so it can show spinner there
    vim.schedule(function()
      on_submit(text, win, buf)
    end)
  end, { buffer = buf, nowait = true })

  -- Cancel on <Esc>
  vim.keymap.set("i", "<Esc>", do_cancel, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", do_cancel, { buffer = buf, nowait = true })

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if not submitted then
        vim.schedule(on_cancel)
      end
    end,
  })
end

return M
