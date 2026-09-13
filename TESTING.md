# Safe testing guide

This guide is for owners of ThinkPads that may have the same native RMI4
touchpad problem. The current patches are proven only on the machine listed in
the README. Similar model names do not prove that the controller, interrupt,
touchpad, or firmware interface is the same.

Do not test the patch on unmatched hardware until a maintainer has reviewed a
read-only inventory and approved a build with exact identity checks for that
machine.

## Prohibited actions

Do not:

- remove, weaken, or broaden an identity check to make the patch load;
- run `i2cdetect` with a bus number or otherwise scan SMBus addresses;
- use `i2cset`, `devmem`, or direct register writes;
- force-bind the driver to an unreviewed device;
- write to an F34 `update_fw` attribute or attempt a firmware update;
- enable optional F54 or F55 diagnostic functions for this test; or
- publish logs before removing serial numbers, UUIDs, MAC addresses, asset
  tags, and other private data.

These restrictions protect both the test machine and unrelated devices on its
buses.

## Stage 1: submit a read-only inventory

Open a
[hardware compatibility inventory](https://github.com/SpencerMichaels/t14-amd-gen2-rmi/issues/new?template=hardware-inventory.yml)
issue. The form requests:

- the exact ThinkPad and DMI identities;
- the AMD SMBus controller, revision, and subsystem;
- the ACPI device and interrupt resources;
- the touchpad, TrackPoint, board, and firmware identities;
- the current kernel, distribution, and boot parameters; and
- the behavior of unpatched Linux.

Run only the read-only commands shown in the form. In particular,
`i2cdetect -l` lists adapters without probing their addresses; do not replace
it with an address scan.

Submitting an inventory is not approval to run the patch. Wait for a
maintainer to compare the hardware with the proven machine.

## Stage 2: prepare an approved build

A first build for new hardware must have its own exact machine, controller,
interrupt, address, touchpad-product, and firmware checks. It must not expand
the production checks merely because two laptops have similar names.

Before installing the build:

1. Save important work.
2. Keep an unpatched, known-good boot entry.
3. Have a second usable input method available. An external USB mouse is
   preferred.
4. Record the complete Git commit of the approved patch.
5. Record the kernel version and distribution configuration revision.
6. Build without activating the result first and check that the patches and
   kernel compile successfully.
7. Install the result as a separate test entry. Do not make it the only boot
   choice or the default entry.

NixOS users should use the specialization pattern in the README. Testers on
other distributions need separately reviewed integration instructions; this
repository does not yet claim a supported generic installation method.

## Stage 3: first boot and initialization

Start from the known-good entry if the test entry cannot finish booting.

On the first test boot:

1. Select the approved test entry manually.
2. Do not touch the touchpad or TrackPoint for the first 30 seconds after
   login.
3. Confirm that the expected RMI parent and essential input functions are
   present and bound. The proven machine uses F01, F03, F12, and F3A; another
   approved device may have a different reviewed function map.
4. Check the kernel log for probe failures, timeouts, interrupt storms, or a
   long initialization delay.
5. Confirm that the system is otherwise responsive before testing input.

Stop and return to the known-good entry if the desktop freezes, the interrupt
count rises continuously while untouched, the RMI probe repeatedly fails, or
unrelated hardware stops working.

## Stage 4: physical input

Test each item separately and record Pass, Partial, Fail, or Not tested:

- one-finger touchpad motion;
- a mechanical clickpad press;
- tap-to-click, if it is enabled in the desktop configuration;
- two-finger scrolling in both directions;
- a deliberate pinch gesture;
- TrackPoint motion; and
- the left, middle, and right physical buttons.

Then use ordinary two-finger scrolling for several minutes. Watch for false
pinch-to-zoom events, lost scrolls, pointer jumps, or unusual sensitivity. A
feature that works once but fails intermittently is Partial, not Pass.

Stop if any input device generates continuous events after physical contact
ends, if the pointer becomes uncontrollable, or if input stops completely.

## Stage 5: quiet idle

Leave the touchpad and TrackPoint untouched before and after physical input.
The initial supervised test should include at least 60 seconds in each state.

Record the matching lines from `/proc/interrupts` at the beginning and end of
each interval. The Host Notify interrupt should become quiet after input ends.
Also record any pointer movement, wakeup, kernel warning, or input event that
occurs without physical contact.

Do not leave a first-time test unattended. Long soak testing comes only after
the supervised checks pass.

## Stage 6: suspend and resume

Test suspend only after startup, input, and idle have passed.

1. Keep the known-good entry and second input method available.
2. Suspend once using the normal desktop action.
3. Resume once and wait before touching either pointing device.
4. Check the kernel log for RMI, F03, timeout, or interrupt-read messages.
5. Repeat every physical-input item.
6. Repeat the post-input idle observation.

Record the approximate suspend duration and whether every input function
worked after resume. Do not hide a warning merely because input appeared to
recover.

One successful cycle is a smoke test, not proof of long-term reliability.
Additional cold boots, resumes, and ordinary-use observation may be requested
before a new hardware identity is considered supported.

## Evidence to preserve

Every report must identify the exact tested build. Preserve:

- the complete patch Git commit;
- `uname -r`;
- the distribution configuration or build revision;
- relevant boot parameters;
- the RMI function bindings;
- relevant kernel messages;
- beginning and ending interrupt counts;
- a feature-by-feature input result; and
- the recovery action for every failure.

Attach concise, redacted evidence. Full system journals often contain private
or unrelated information and should not be uploaded without review.

Submit the result with the
[approved hardware test result](https://github.com/SpencerMichaels/t14-amd-gen2-rmi/issues/new?template=test-result.yml)
form. Link the inventory issue that authorized the test.

## Recovery

If a test fails:

1. Stop testing and avoid experimental recovery commands.
2. Use the keyboard or external input device to save work.
3. Reboot into the known-good entry.
4. If a normal reboot does not restore the device, power the machine off fully
   before starting the known-good entry.
5. Report the failure, relevant logs, and recovery result from the known-good
   system.

Do not make a failing test build the default. Do not broaden its checks and
retry on the assumption that the failure was only an identity mismatch.

## Result and attribution policy

A Pass means every claimed test was observed to work and no unexplained
warning or regression occurred. Use Partial when some functions work, a result
is intermittent, or a warning remains unexplained. Use Fail when the system or
required input path does not work. Mark omitted tests as Not tested.

Permission to use a kernel `Tested-by:` tag is separate from submitting an
issue. The result form asks for explicit permission and the exact identity to
use. No tag will be inferred from a GitHub username or from the existence of a
test report.
