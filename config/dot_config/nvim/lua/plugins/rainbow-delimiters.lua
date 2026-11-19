-- Rainbow brackets everywhere except Python (call/list literals get noisy)
return {
  "HiPhish/rainbow-delimiters.nvim",
  event = "VeryLazy",
  config = function()
    ---@type rainbow_delimiters.config
    vim.g.rainbow_delimiters = {
      strategy = {
        [""] = "rainbow-delimiters.strategy.global",
      },
      query = {
        [""] = "rainbow-delimiters",
        lua = "rainbow-blocks",
      },
      blacklist = { "python" },
    }
  end,
}
