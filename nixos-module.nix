{ patchSource }:

{ config, lib, ... }:

let
  cfg = config.hardware.tm3471-rmi;

  # Give each patch its own content-addressed store path. Documentation-only
  # changes to this repository then do not force a kernel rebuild.
  patchFile = name: builtins.path {
    inherit name;
    path = patchSource + "/patches/${name}";
  };
in
{
  options.hardware.tm3471-rmi = {
    enable = lib.mkEnableOption ''
      native RMI4-over-SMBus support for the Synaptics TM3471 touchpad in the
      Lenovo ThinkPad T14 Gen 2 AMD (machine type 20XK001JUS)
    '';

    applyPatches = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Apply the kernel patches without enabling the runtime driver path.
        This is intended for development and recovery specializations. Normal
        installations should set only hardware.tm3471-rmi.enable.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable || cfg.applyPatches) {
      boot.kernelPatches = [
        {
          name = "t14-gen2a-preserve-irq7-level-low";
          patch = patchFile
            "0001-ACPI-resource-preserve-IRQ-7-flags-on-T14-Gen-2a.patch";
        }
        {
          name = "t14-gen2a-tm3471-host-notify";
          patch = patchFile
            "0002-TM3471-AMD-Host-Notify-and-Windows-F03-service.patch";
        }
      ];
    })

    (lib.mkIf cfg.enable {
      boot.kernelParams = [
        "i2c_piix4.amd_host_notify=1"
        "rmi_core.tm3471_windows_service=1"
        "psmouse.synaptics_intertouch=1"
      ];

      # The controller and RMI transport must be ready before psmouse starts
      # its intertouch handoff. Without this order, the device can register
      # after a multi-second startup stall and report false pinch geometry.
      boot.extraModprobeConfig = lib.mkAfter ''
        softdep psmouse pre: i2c_piix4 rmi_smbus
      '';
    })
  ];
}
