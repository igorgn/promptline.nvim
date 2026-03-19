# promptline.nvim

Edit text in-place using AI — select text in visual mode, type a short instruction, and the selection is replaced with the result. Press `u` to undo.

## Features

- Visual mode selection → float prompt → in-place replacement
- Native undo (`u`) — the replacement is a single undo step
- Two backends: **Claude CLI** (uses your existing `claude` login, no API key needed) or **Anthropic API**
- Configurable default prompt, system prompt, model, keymap

## Requirements

- Neovim 0.9+
- For `claude_cli` backend: [`claude`](https://claude.ai/code) CLI installed and logged in
- For `anthropic_api` backend: `curl` + `ANTHROPIC_API_KEY` env var

## Installation

### lazy.nvim

```lua
{
  "yourusername/promptline.nvim",
  config = function()
    require("promptline").setup()
  end,
}
```

### Local (from this directory)

```lua
{
  dir = "/path/to/promptline",
  config = function()
    require("promptline").setup()
  end,
}
```

## Usage

1. Select text in **Visual mode**
2. Press `<leader>p` (default keymap)
3. A float window appears — type your instruction and press `<Enter>`, or press `<Enter>` on an empty prompt to use the default
4. The selection is replaced in-place
5. Press `u` to undo if you don't like the result

## Configuration

All options with their defaults:

```lua
require("promptline").setup({
  -- "claude_cli" uses the `claude` binary (existing Claude Code login)
  -- "anthropic_api" uses the Anthropic REST API directly
  backend = "claude_cli",

  -- Model used by the anthropic_api backend
  model = "claude-sonnet-4-6",
  max_tokens = 8096,

  -- API key for anthropic_api backend (defaults to $ANTHROPIC_API_KEY)
  api_key = nil,

  -- Shown as greyed-out hint in the prompt window; used when user submits empty input
  default_prompt = "Improve this",

  -- System prompt sent to the model
  system_prompt = "You are a precise code and text editor. When given text and an instruction, you apply the instruction and return only the edited result.",

  -- Visual mode keymap that triggers the plugin
  keymap = "<leader>p",

  -- Width of the prompt float window
  float_width = 60,
})
```

## Examples

| Selection | Prompt | Effect |
|-----------|--------|--------|
| Rust function | `make more idiomatic` | Rewrites using idiomatic Rust patterns |
| Paragraph | `make concise` | Shortens while preserving meaning |
| Function | `add error handling` | Adds proper error handling |
| Comment | `rewrite as docstring` | Converts to doc comment format |
| *(empty prompt)* | — | Uses `default_prompt` ("Improve this") |
