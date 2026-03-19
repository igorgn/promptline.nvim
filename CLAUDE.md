# promptline.nvim — Developer Notes

## Workflow instructions

When the user says **"looks good"**, run:
```
jj describe -m'<concise summary of the changes made in this session>'
```
Write the summary yourself based on what was built or changed. Keep it short (one line, imperative mood, e.g. `add preset cycling with C-n/C-p`).


## Project structure

```
lua/promptline/
  init.lua      — public API: setup(), trigger(), visual selection capture, orchestration
  ui.lua        — float window: prompt input, preset cycling, spinner, explain display
  backend.lua   — AI backends: claude_cli, anthropic_api, copilot_chat
  replace.lua   — buffer text replacement (single undo step via nvim_buf_set_text)
plugin/
  promptline.lua — runtime guard (sets vim.g.loaded_promptline), no auto-setup
```

## Architecture

The plugin is intentionally kept to four small files with no dependencies beyond Neovim's built-in APIs and optional external tools (claude CLI, curl, CopilotChat.nvim).

**Flow:**
1. `init.lua:trigger()` — captures visual selection + LSP diagnostics before opening the float (opening a float exits visual mode and clears `'<`/`'>` marks)
2. `ui.lua:prompt()` — opens the input float, handles preset cycling, calls `on_submit({ prompt, mode }, win, buf)`
3. `init.lua` — calls `ui.show_working()` to convert the prompt float into a spinner, then calls `backend.run()`
4. `backend.lua` — runs the AI request async via `vim.fn.jobstart` (CLI/curl) or CopilotChat Lua API, calls `on_done(result, err)`
5. `init.lua` — on result: either calls `ui.show_explain()` (explain mode) or `replace.replace_selection()` + format + save (edit mode)

## Key implementation notes

**Visual selection capture** (`init.lua:get_visual_selection`)
- Must feed `<Esc>` to update `'<`/`'>` marks before reading them
- `nvim_buf_get_text` end_col is exclusive; mark end_col is inclusive — so pass `end_col + 1`
- `replace.lua` clamps end_col to line length to avoid out-of-range errors when selection ends at EOL

**Undo**
- Replacement uses `nvim_buf_set_text` which is a single undo step — `u` just works, no custom undo handling

**Async**
- All backends use `vim.fn.jobstart` (non-blocking) or CopilotChat's async `ask()`
- Results are delivered via `vim.schedule()` to safely update the UI from a callback

**Float lifecycle**
- Prompt float stays open during the backend call (repurposed as a spinner)
- `WinLeave` autocmd closes and cancels if the user focuses another window
- `submitted` flag prevents double-cancel

**LSP diagnostics**
- Collected at selection time via `vim.diagnostic.get(buf)`, filtered to the selected line range
- Appended to the prompt so the model knows about errors without the user having to describe them

**After edit**
- `vim.lsp.buf.format` (sync) runs if `format_on_apply = true`
- `silent! write` saves the file, which triggers LSP file watchers and refreshes diagnostics

## Adding a new backend

1. Add a `run_<name>` function in `backend.lua` with signature:
   ```lua
   function M.run_mybackend(config, selection, user_prompt, diagnostics, on_done)
     -- call on_done(result_string, nil) on success
     -- call on_done(nil, error_string) on failure
   end
   ```
2. Add the dispatch case in `M.run()`
3. Document the new `backend = "mybackend"` option in README.md

## Adding a new mode

Modes are set per-preset via `mode = "..."`. Currently: `"edit"` and `"explain"`.

To add a new mode:
1. Handle it in `init.lua` in the `backend.run` callback (after the `if mode == "explain"` block)
2. Add a `show_<mode>` function in `ui.lua` if it needs a custom display
3. Optionally override `system_prompt` in `cfg` for the mode (as done for `explain`)

## Preset system

Presets live in `config.presets` as `{ label, prompt, mode }` tables. In the UI:
- First `<C-n>`/`<C-p>` press expands the float and shows the list
- Selecting a preset writes its `prompt` text into the input field (editable)
- `mode` is tracked separately from the input text — editing the text doesn't change the mode
- Submitting reads the current input text (possibly edited) and the last-selected mode
