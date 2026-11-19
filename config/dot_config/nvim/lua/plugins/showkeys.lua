-- Screencaster key overlay: <leader>k to toggle
return {
  "nvzone/showkeys",
  cmd = "ShowkeysToggle",
  opts = {
    timeout = 2,
    maxkeys = 4,
    show_count = true,
  },
  keys = {
    { "<leader>k", "<cmd>ShowkeysToggle<cr>", desc = "Toggle Showkeys" },
  },
}
