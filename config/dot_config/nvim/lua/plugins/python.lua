return {
  -- keep basedpyright installed (LazyVim auto-installs anything in ensure_installed)
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = { "basedpyright" },
    },
  },

  -- ruff owns Python formatting; safe fixes + import sorting run on save
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = { python = { "ruff_fix", "ruff_format" } },
      formatters = {
        -- override args so `--extend-select I` lands before the `-` stdin sentinel
        ruff_fix = {
          args = {
            "check",
            "--fix",
            "--force-exclude",
            "--exit-zero",
            "--no-cache",
            "--extend-select",
            "I",
            "--stdin-filename",
            "$FILENAME",
            "-",
          },
        },
      },
    },
  },

  -- uv workflow: <leader>uv* prefix (plain <leader>u is taken by LazyVim toggles)
  {
    "benomahony/uv.nvim",
    ft = "python",
    opts = {
      auto_activate_venv = false, -- venv-selector owns activation, avoid conflict
      picker_integration = true,
      keymaps = { prefix = "<leader>uv" },
    },
  },

  -- show the active venv in the statusline
  {
    "linux-cultist/venv-selector.nvim",
    opts = {
      options = {
        statusline_func = {
          lualine = function()
            local venv = require("venv-selector").venv()
            return venv and venv ~= "" and (" " .. vim.fn.fnamemodify(venv, ":t") .. " ") or ""
          end,
        },
      },
    },
  },
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, 2, {
        "venv",
        icon = " ",
        cond = function()
          return vim.bo.filetype == "python" and package.loaded["venv-selector"] ~= nil
        end,
        color = { fg = "#98c379" },
      })
    end,
  },
}
