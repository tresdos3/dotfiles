-- Inline color swatches for hex/rgb values
return {
  "catgoose/nvim-colorizer.lua",
  ft = { "python", "css", "scss", "html", "javascript", "typescript", "lua", "json", "yaml" },
  opts = {
    user_default_options = {
      names = false,
      mode = "virtual",
      virtualtext = "■",
    },
  },
}
