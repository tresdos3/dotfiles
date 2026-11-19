-- Snacks picker: Cmd-j / Cmd-k to move the list while typing in the search box
return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      win = {
        input = {
          keys = {
            ["<D-j>"] = { "list_down", mode = { "i", "n" } },
            ["<D-k>"] = { "list_up", mode = { "i", "n" } },
          },
        },
        list = {
          keys = {
            ["<D-j>"] = "list_down",
            ["<D-k>"] = "list_up",
          },
        },
      },
    },
  },
}
