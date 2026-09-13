# TM3471 native RMI4 support for the ThinkPad T14 Gen 2 AMD

This repository provides a small Linux kernel patch set and an opt-in NixOS
module. Together, they enable the Synaptics TM3471 touchpad's native RMI4 over
SMBus interface on one exact laptop configuration.

This is a machine-specific fix. It is not yet a generic or upstream-ready AMD
Host Notify implementation.

## Compatibility and test status

Only the following hardware and software combination has been tested:

| System | DMI identity | Touchpad | Firmware | Linux | Result |
| --- | --- | --- | --- | --- | --- |
| Lenovo ThinkPad T14 Gen 2 AMD | `20XK001JUS`, `ThinkPad T14 Gen 2a` | Synaptics `TM3471-030` | `3942087` | `6.18.48` on NixOS | Working |

On that machine, the native RMI mode has passed positive tests for:

- touchpad motion, multitouch scrolling, and gestures;
- mechanical clickpad presses;
- TrackPoint motion and its left, middle, and right buttons;
- tap-to-click when enabled in libinput;
- cold boot and suspend/resume;
- quiet idle before and after physical input;
- ordinary two-finger scrolling without false pinch gestures;
- removal and reconstruction of the live RMI device; and
- return to usable PS/2 mode when the patch's runtime path is deliberately
  disabled.

The following are not currently claimed:

- support for any other ThinkPad model, machine type, touchpad, or firmware;
- compatibility with Linux versions other than `6.18.48`;
- hibernation;
- completion of a long-term unattended reliability test;
- firmware updates through F34 or `fwupd`;
- optional F54/F55 diagnostic functions; or
- installation methods other than the supplied NixOS module.

The identity checks in the patches intentionally leave unmatched systems
unchanged. Similar hardware must be inventoried and tested before its identity
is added. Do not remove or broaden those checks merely to make the patch load.

Owners of other potentially affected ThinkPads should follow the
[safe testing guide](TESTING.md). Submit a read-only hardware inventory before
trying the patch on an unmatched machine.

## What the patch set changes

The first patch preserves the firmware-provided level-low, shared IRQ 7
configuration for the auxiliary SMBus controller. Its DMI match limits the
change to the exact machine above.

The second patch adds the AMD ASF target-mode Host Notify path needed by
`rmi_smbus`. It also implements the Windows-derived Synaptics F03 service
exchange and the controller completion sequence required by this TM3471. The
controller path and RMI behavior are disabled by default and protected by
machine, address, IRQ, and firmware identity checks.

The NixOS module also orders `i2c_piix4` and `rmi_smbus` before the `psmouse`
intertouch handoff. This is required. Without deterministic ordering, RMI can
register only after a long startup stall and the touchpad can emit incorrect
two-finger geometry, which applications interpret as pinch-to-zoom.

## Add it to a NixOS flake

Add this repository as a normal flake input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    tm3471-rmi.url = "github:SpencerMichaels/t14-amd-gen2-rmi";
  };

  outputs = inputs@{ nixpkgs, tm3471-rmi, ... }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        tm3471-rmi.nixosModules.default
        ./configuration.nix
        {
          hardware.tm3471-rmi.enable = true;
        }
      ];
    };
  };
}
```

For a local checkout, use this input while developing or testing:

```nix
tm3471-rmi.url = "git+file:///home/you/Projects/tm3471-linux-rmi";
```

Do not set `flake = false`; this repository now exports a NixOS module.

Then update the lock file and build without activating it:

```console
sudo nixos-rebuild build --flake .#your-host
```

Keep a known-good kernel entry available. On the first test, select the new
generation from the boot menu instead of making it the only recoverable entry.
After boot, confirm that motion, scrolling, all buttons, the TrackPoint, idle,
and suspend/resume work before making it your normal boot choice.

## Safer first test with a specialization

You can keep your normal configuration unpatched while adding a separate test
entry:

```nix
{
  imports = [ inputs.tm3471-rmi.nixosModules.default ];

  specialisation.touchpad-rmi.configuration = {
    system.nixos.tags = [ "touchpad-rmi" ];
    hardware.tm3471-rmi.enable = true;
  };
}
```

Build and install the generation, then choose `touchpad-rmi` from the boot
menu. The exact boot-menu presentation depends on your boot loader.

## Kernel updates

Once the module is enabled, future NixOS builds continue to apply the patches
to the kernel selected by `nixpkgs`. No manual copying is needed. If a later
kernel changes the affected source, patching or compilation should fail rather
than silently omit the fix.

The patches are known to apply to Linux 6.18.48. After a kernel update:

1. Build before activation and retain a known-good generation.
2. Check that both patches still apply and the kernel compiles.
3. Repeat cold-boot, input, idle, and suspend/resume smoke tests.
4. Check ordinary two-finger scrolling for false pinch gestures.

The module gives each patch a content-addressed Nix store path. Changes to this
README alone therefore do not change the patched kernel derivation.

For development configurations that need the patched kernel but must leave
the runtime path disabled, the module also provides the advanced option
`hardware.tm3471-rmi.applyPatches`. Normal installations do not need it;
`hardware.tm3471-rmi.enable = true` already applies the patches.

## License

This repository is licensed under GPL-2.0-only. See `COPYING`.
