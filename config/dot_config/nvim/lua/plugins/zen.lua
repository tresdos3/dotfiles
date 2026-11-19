-- Distraction-free fullscreen buffer: <leader>z to toggle
return {
  "folke/zen-mode.nvim",
  opts = {
    window = {
      width = 0.9,
      height = 0.9,
      options = {
        number = false,
        relativenumber = false,
        cursorline = false,
        signcolumn = "no",
        foldcolumn = "0",
      },
    },
    plugins = {
      twilight = { enabled = false },
      gitsigns = { enabled = false },
      todo = { enabled = false },
    },
  },
  keys = {
    { "<leader>z", "<cmd>ZenMode<cr>", desc = "Zen Mode" },
  },
}
