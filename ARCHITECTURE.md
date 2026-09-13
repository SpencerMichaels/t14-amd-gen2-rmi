# Architecture and project status

This document describes two different things:

1. the **maintained patch**, which is the code in this repository and has been
   tested on one exact laptop; and
2. a **possible upstream design**, which has not been implemented or accepted
   by Linux maintainers.

Keeping these separate is important. The maintained patch is deliberately
machine-specific. The upstream design is a proposal for turning the proven
behavior into code that may fit the Linux kernel more generally.

## Current status

| Area | Status |
| --- | --- |
| Proven system | Lenovo ThinkPad T14 Gen 2 AMD, machine type `20XK001JUS` |
| Proven touchpad | Synaptics `TM3471-030`, firmware ID `3942087` |
| Proven kernel | Linux `6.18.48` on NixOS |
| Maintained delivery | Two kernel patches and an opt-in NixOS module |
| Other machines | Not enabled; each one needs an inventory and a separately reviewed gate |
| Upstream status | Not submitted; the controller architecture needs maintainer discussion |

The tested system provides touchpad motion, multi-finger scrolling and
gestures, clickpad input, TrackPoint input, and all three TrackPoint buttons.
Cold boot, quiet idle, suspend and resume, and device unbind/rebind have also
passed positive tests. See [TESTING.md](TESTING.md) for the exact claims and
test procedure.

## Terms used below

- **RMI4** is Synaptics' Register Mapped Interface version 4. The device exposes
  numbered functions, each with registers for a specific job. On this device,
  F01 controls the device, F12 reports touch contacts, F03 carries TrackPoint
  data, and F3A reports the physical buttons.
- **SMBus** is a two-wire communication bus derived from I2C. Linux uses the
  `rmi_smbus` driver to read and write RMI4 registers over this bus.
- **Host Notify** is an SMBus message sent by a device to get the host's
  attention. It tells Linux that data may be ready; Linux then reads the RMI4
  registers that contain the actual input report.
- **ASF** means Alert Standard Format. The AMD controller contains ASF target
  hardware that can receive the touchpad's Host Notify messages.
- **F03**, **F12**, and similar names are RMI4 function numbers.
- **DMI** is firmware-provided system identity data, such as the manufacturer,
  model, and machine type.
- **ACPI** is the firmware interface that describes hardware resources to the
  operating system.
- **IRQ** means interrupt request. The controller uses IRQ 7 to tell Linux that
  a Host Notify message arrived.

## The working data path

```text
Synaptics touchpad at SMBus address 0x2c
  |  RMI4 register reads and writes
  |  Host Notify attention messages
  v
AMD auxiliary SMBus and legacy ASF receiver
  |  handled by the patched i2c-piix4 driver
  v
rmi_smbus transport
  v
RMI4 core and function drivers
  |-- F01: device control and identity
  |-- F12: touch contacts and gestures
  |-- F03: TrackPoint data
  `-- F3A: physical buttons
  v
Linux input system -> libinput -> desktop and applications
```

The Host Notify message does not contain a complete touch report. It wakes the
RMI transport. The transport then reads the appropriate RMI4 registers over
SMBus. This is why ordinary SMBus transfers and target-mode notification
reception both have to work on the same controller.

## What the maintained patch does

### 1. Preserve the correct interrupt description

The first patch changes `drivers/acpi/resource.c`. Firmware describes IRQ 7 as
level-sensitive, active-low, and shared for the `SMB0001` device. A legacy ACPI
rule would otherwise replace those flags with edge-triggered settings.

The patch preserves the firmware flags only for the exact tested DMI identity.
This lets the controller receive a level-low Host Notify interrupt correctly.

### 2. Add legacy AMD Host Notify reception

The second patch extends the auxiliary adapter in `i2c-piix4`. It enables the
legacy AMD ASF target registers that Windows uses on this laptop. The receive
path:

1. verifies the PCI device, revision, Lenovo subsystem, DMI identity,
   `SMB0001` resources, I/O address, and IRQ configuration;
2. performs the required power-management setup transition;
3. resets the target receiver and sets its listen address to `0x11`;
4. receives the touchpad's four-byte Host Notify frames from two hardware
   banks;
5. drains full banks in their recorded oldest-first order and releases their
   full flags together;
6. delivers a valid notification for touchpad address `0x2c`, including a
   notification whose data value is zero; and
7. clears the required power-management bit at the SMBus transaction
   completion boundary.

The controller has both master and target roles. Master transfers read and
write the touchpad. The target role receives notifications. The patch uses the
controller's host semaphore, masks the target interrupt during master
transfers, and explicitly selects the master side. This prevents the two roles
from changing shared controller state at the same time.

The interrupt handler has a fixed storm limit of 1,000 interrupts per second.
If the limit is exceeded, it disables the receiver instead of allowing an
interrupt storm to consume the system. Removal and error paths quiesce the
receiver and restore the saved power-management state.

### 3. Perform the required F03 setup

The normal Linux F03 driver registered a TrackPoint child before this device
was ready. The patch adds the setup sequence observed in the Windows driver:

1. install a temporary RMI interrupt mask;
2. send command `0xf5` and wait for reply `0xfa`;
3. send command `0xf4` and wait for reply `0xfa`;
4. install and verify the final interrupt mask; and
5. register the TrackPoint interface.

The setup is enabled only when the complete tested RMI identity matches. That
identity includes the F01 product and firmware ID, important register
addresses, and the expected F12 and F3A interrupt layout.

Suspend marks this setup as no longer valid. Resume repeats it and asks the RMI
core to restore cached function settings, including the F12 touch settings.

### 4. Make startup order deterministic

The NixOS module enables the two opt-in kernel parameters and requests RMI
InterTouch mode from `psmouse`. It also loads `i2c_piix4` and `rmi_smbus` before
the `psmouse` handoff.

This ordering matters. A late controller setup can cause a long startup stall
and bad initial contact geometry. Applications can then mistake an ordinary
two-finger scroll for a pinch gesture.

## Safety boundaries in the maintained release

The controller path is off unless `i2c_piix4.amd_host_notify=1`. The F03 setup
is off unless `rmi_core.tm3471_windows_service=1`. The NixOS module supplies
both parameters when it is enabled.

Those switches are not the only protection. The kernel code also checks the
exact machine, controller, firmware resources, touchpad address, touchpad
identity, firmware ID, register map, and function interrupt layout. An
unmatched system keeps the normal kernel behavior.

These checks must not be widened from a model name alone. A similar ThinkPad
can have different firmware, resource wiring, or controller behavior.

## Known limits and open technical questions

- Only Linux 6.18.48 and the hardware listed above are proven.
- One experimental double-suspend run lost F12 touch input while TrackPoint and
  button input remained available. Later double-suspend testing passed. The
  evidence points to an intermittent F03 resume race, not to F34 itself.
- One isolated RMI interrupt-read error (`-6`) was recorded after an idle test,
  with no persistent input failure.
- Long ordinary-use observation and repeated boot and suspend cycles are still
  useful. Hibernation is not claimed.
- F34 can be identified and read safely, but firmware writing is not part of
  this release. `fwupd` does not gain native RMI firmware-update support from
  these kernel patches.
- Optional F54 and F55 diagnostic functions are outside the current scope.

## Relationship to the newer AMD ASF platform driver

Mainline Linux has `i2c-amd-asf-plat.c` for newer AMD ASF hardware described by
ACPI ID `AMDI001A`. This laptop instead exposes the legacy `SMB0001` interface.
The newer driver cannot be used directly here:

| Newer platform driver | Interface on this laptop |
| --- | --- |
| Binds to `AMDI001A` | Firmware exposes `SMB0001` |
| Requires an I/O range, IRQ, and a memory-mapped end-of-interrupt resource | Does not expose the same end-of-interrupt resource |
| Creates a separate I2C adapter | RMI uses the PIIX4 auxiliary SMBus adapter |
| Delivers generic I2C target events | `rmi_smbus` needs SMBus Host Notify |
| Rejects read transfers | RMI needs frequent block reads and writes |
| Uses delayed work | Pointing input needs prompt notification delivery |

The two implementations still duplicate useful concepts: ASF register
definitions, target reset and setup, receive-bank handling, locking, resource
validation, and cleanup. That overlap should be discussed with the AMD ASF and
I2C maintainers before a general implementation is written.

## Proposed upstream design — not implemented

A reasonable starting proposal is a shared AMD ASF core with two front ends:

```text
                    shared AMD ASF core
             registers, banks, ownership,
                 setup, cleanup, locking
                         /        \
                        /          \
             AMDI001A platform   legacy SMB0001
                front end          front end
              newer EOI method   PIIX4 auxiliary bus
              generic target     SMBus Host Notify
```

This is an RFC idea, not a settled architecture. Maintainers may instead
prefer a helper library, a legacy mode in the platform driver, or a smaller
shared register layer.

An upstream series would probably separate the work into these reviewable
parts:

1. the exact ACPI IRQ quirk;
2. legacy AMD ASF Host Notify support, placed where I2C maintainers prefer;
3. a clean way to express the exact RMI device identity;
4. the device-specific F03 initialization quirk;
5. resume-race fixes and power-management tests; and
6. additional DMI identities only after positive testing on each machine.

The controller transport and the Synaptics device setup belong to different
kernel subsystems and should remain separate. The current module parameters
are useful safety switches for an out-of-tree release. For upstream code,
maintainers may prefer automatic selection through narrow DMI, ACPI, or device
properties instead of permanent user-facing parameters.

Before submission, the code also needs a rebase onto current mainline,
maintainer feedback on the controller design, normal kernel style checks, and
positive reports from other separately gated systems. Until then, the shipped
patch remains the tested reference implementation.
