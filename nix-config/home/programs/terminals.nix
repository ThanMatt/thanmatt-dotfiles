{ pkgs, lib, config, ... }:

{
  # :: Alacritty — native HM (gruvbox material).
  programs.alacritty = {
    enable = true;
    settings = {
      font = {
        normal = { family = "FiraCode Nerd Font"; style = "Regular"; };
        size = 9;
      };
      colors = {
        primary    = { background = "#282828"; foreground = "#d4be98"; };
        normal     = { black = "#282828"; red = "#ea6962"; green = "#a9b665"; yellow = "#d8a657"; blue = "#7daea3"; magenta = "#d3869b"; cyan = "#89b482"; white = "#d4be98"; };
        bright     = { black = "#928374"; red = "#f2594b"; green = "#b8bb26"; yellow = "#fabd2f"; blue = "#83a598"; magenta = "#d3869b"; cyan = "#8ec07c"; white = "#ebdbb2"; };
        selection  = { text = "CellBackground"; background = "#504945"; };
      };
      keyboard.bindings = [
        { key = "Return"; mods = "Alt"; action = "ToggleFullscreen"; }
      ];
      mouse.bindings = [
        { mouse = "Middle"; action = "PasteSelection"; }
      ];
    };
  };

  # :: Ghostty — native HM. The module writes to ~/.config/ghostty/config on both
  # :: Linux and macOS (ghostty reads XDG on macOS too). The shader is referenced
  # :: straight out of the dotfiles repo so it resolves on every platform without
  # :: an extra symlink. On macOS the ghostty binary isn't packaged in nixpkgs, so
  # :: we only manage the config (package = null) and install the app via Homebrew.
  programs.ghostty = {
    enable = true;
    package = if pkgs.stdenv.isDarwin then null else pkgs.ghostty;
    settings = {
      background = "282828";
      foreground = "d4be98";
      palette = [
        "0=#282828"  "1=#ea6962"  "2=#a9b665"  "3=#d8a657"
        "4=#7daea3"  "5=#d3869b"  "6=#89b482"  "7=#d4be98"
        "8=#928374"  "9=#f2594b"  "10=#b8bb26" "11=#fabd2f"
        "12=#83a598" "13=#d3869b" "14=#8ec07c" "15=#ebdbb2"
      ];
      selection-background = "504945";
      selection-foreground = "282828";

      font-family = "FiraCode Nerd Font";
      font-size = 9;

      window-padding-x = 14;
      window-padding-y = 14;
      window-decoration = false;

      shell-integration = "fish";
      copy-on-select = "clipboard";

      cursor-style = "block";
      cursor-style-blink = true;

      custom-shader = "${config.home.homeDirectory}/thanmatt-dotfiles/ghostty/shaders/cursor_warp.glsl";
      custom-shader-animation = "always";
    } // lib.optionalAttrs pkgs.stdenv.isDarwin {
      macos-option-as-alt = true;
    };
  };

  # :: Kitty — binary via Nix, config symlinked from dotfiles (XDG path on both OSes).
  xdg.configFile."kitty".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/kitty";
}
