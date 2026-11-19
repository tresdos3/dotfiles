-- Direct buffer jumps (browser-style) on top of LazyVim's bufferline defaults
return {
  "akinsho/bufferline.nvim",
  keys = function()
    local keys = {
      { "<C-Tab>", "<cmd>BufferLineCycleNext<cr>", desc = "Next Buffer" },
      { "<C-S-Tab>", "<cmd>BufferLineCyclePrev<cr>", desc = "Prev Buffer" },
    }
    -- <A-1>..<A-8> jump to buffer by position, <A-9> jumps to the last one
    for i = 1, 9 do
      keys[#keys + 1] = {
        "<A-" .. i .. ">",
        function()
          require("bufferline").go_to_buffer(i, true)
        end,
        desc = "Buffer " .. i,
      }
    end
    return keys
  end,
}
