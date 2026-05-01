{ ... }:

{
  # :: VirtualBox guest configuration.
  # ::
  # :: Provides:
  # ::   - VBox guest additions (vboxsf, vboxvideo modules, vboxservice)
  # ::   - 3D acceleration support (required for wlroots compositors: sway, niri)
  # ::   - Clipboard sharing, drag-and-drop, shared folders
  # ::
  # :: Pair with VirtualBox host-side settings (in the VBox Manager UI):
  # ::   - Display → Graphics Controller: VMSVGA
  # ::   - Display → Video Memory: 128 MB
  # ::   - Display → Enable 3D Acceleration: ✓
  # ::
  # :: Imported conditionally via the `isVM` flag in flake.nix's mkSystem.
  virtualisation.virtualbox.guest = {
    enable = true;
    dragAndDrop = true;
  };
}
