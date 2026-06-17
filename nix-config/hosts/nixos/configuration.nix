{ pkgs, lib, inputs, isVM ? false, isUEFI ? true, ... }:

{
  imports = [
    ../../modules/fonts.nix
    (if isUEFI then ../../modules/boot/uefi.nix else ../../modules/boot/bios.nix)
    # :: Integrated Home Manager — this box builds system + dubi's home together
    # :: via `nixos-rebuild switch` (Arch/Mac use standalone HM instead).
    inputs.home-manager.nixosModules.home-manager
  ]
  # :: hardware-configuration.nix is generated at install time. Import it only when
  # :: present, so the config still evaluates for `build-vm` before the real install.
  ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix
  ++ lib.optional isVM ../../modules/vm/virtualbox.nix;

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Manila";

  programs.fish.enable = true;
  users.defaultUserShell = pkgs.fish;

  # :: Window managers / desktop environments — system-level enablement.
  # :: Each adds a session entry that ly (the display manager) discovers.
  programs.niri.enable = true;
  programs.sway.enable = true;
  services.desktopManager.plasma6.enable = true;

  # :: ly — minimal TTY display manager / session switcher.
  # :: Pick niri / sway / plasma at login from the same place.
  services.displayManager.ly.enable = true;

  # :: Plasma + most Wayland apps expect PipeWire for audio.
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
  };
  security.rtkit.enable = true;
  security.pam.services.gtklock = {};

  # :: keyd — kernel-level key remapping, works on Wayland and TTY.
  # :: Caps hold → nav layer (hjkl as arrows), tap → noop.
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        main.capslock = "overload(nav, noop)";
        nav = {
          h = "left";
          j = "down";
          k = "up";
          l = "right";
        };
      };
    };
  };

  # :: nix-ld — lets generic Linux binaries (asdf, etc.) run on NixOS
  # :: by providing the expected dynamic linker path.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc
      zlib
      openssl
    ];
  };

  virtualisation.docker.enable = true;

  services.syncthing = {
    enable = true;
    user = "dubi";
    dataDir = "/home/dubi";
    configDir = "/home/dubi/.config/syncthing";
  };

  users.users.dubi = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "docker" ];
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    vscode
    signal-desktop
    qbittorrent
    claude-code
    bruno
    calibre
    dbeaver-bin
    obs-studio


    # :: vterm native module deps (Doom Emacs :term vterm)
    cmake
    libtool
    libvterm

    # :: Build deps for asdf-python (compiles from source)
    gcc
    gnumake
    openssl
    zlib
    bzip2
    readline
    sqlite
    libffi
    xz
    ncurses
    pkg-config
  ];

  # :: asdf-python (python-build) compiles CPython from source and hunts for these
  # :: libs' headers/.pc files in FHS paths that don't exist on NixOS — without
  # :: these flags it SILENTLY skips modules (zlib/_ssl/_ctypes/…) and the build
  # :: dies at ensurepip ("No module named 'zlib'"). Point the toolchain at the
  # :: nix-store dev/lib outputs. (The packages live in systemPackages above;
  # :: nix-ld handles asdf-nodejs's prebuilt binaries separately.)
  environment.sessionVariables = let
    pyBuildLibs = with pkgs; [ zlib openssl bzip2 readline sqlite libffi xz ncurses ];
  in {
    CPPFLAGS = lib.concatMapStringsSep " " (p: "-I${lib.getDev p}/include") pyBuildLibs;
    LDFLAGS = lib.concatMapStringsSep " " (p: "-L${lib.getLib p}/lib") pyBuildLibs;
    PKG_CONFIG_PATH = lib.concatMapStringsSep ":" (p: "${lib.getDev p}/lib/pkgconfig") pyBuildLibs;
  };

  # :: Integrated Home Manager config for dubi (home modules shared with Arch/Mac).
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; hmTarget = "dubi@nixos"; };
    users.dubi = {
      imports = [ ../../home/linux.nix ];
      home.stateVersion = "24.11";
    };
  };

  # :: QEMU `build-vm` overrides — ONLY affect `system.build.vm`, never a real
  # :: install. Boots this exact config in a throwaway VM to rehearse the reformat:
  # ::   nix build .#nixosConfigurations.nixos.config.system.build.vm
  # ::   ./result/bin/run-nixos-vm
  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 6144;
      cores = 4;
      diskSize = 20480;
      # :: Mount the live host dotfiles repo where the HM symlinks expect it, so
      # :: sway/noctalia/nvim configs + DOOMDIR resolve inside the guest.
      sharedDirectories.dotfiles = {
        source = "/home/thanmatt/thanmatt-dotfiles";
        target = "/home/dubi/thanmatt-dotfiles";
      };
      # :: Absolute pointer → fixes the duplicate/offset cursor under QEMU.
      qemu.options = [ "-device virtio-tablet" ];
      # :: Forward guest SSH to host:2222 so we can inspect/drive the guest from a
      # :: host terminal — Wayland-in-Wayland keyboard grab (Super, etc.) is
      # :: unreliable, so SSH is the dependable way in.
      forwardPorts = [{ from = "host"; host.port = 2222; guest.port = 22; }];
    };
    # :: SSH in:  ssh -p 2222 dubi@localhost   (password: test)
    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = true;
    };
    # :: Throwaway login + software-GL fallback so the DEs render under QEMU.
    users.users.dubi.initialPassword = "test";
    hardware.graphics.enable = true;
    environment.sessionVariables.WLR_RENDERER_ALLOW_SOFTWARE = "1";
  };

  system.stateVersion = "24.11";
}
