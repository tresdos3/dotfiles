-- Buffer-wide cellular automaton animations: <leader>fma / <leader>fms
return {
  "eandrju/cellular-automaton.nvim",
  cmd = { "CellularAutomaton" },
  keys = {
    { "<leader>fma", "<cmd>CellularAutomaton make_it_rain<cr>", desc = "Automaton: Make it Rain" },
    { "<leader>fms", "<cmd>CellularAutomaton scramble<cr>", desc = "Automaton: Scramble" },
  },
}
