# Persistent IP Change Helper — Design

## Intent

Provide one on-device command to change `eth0` or `portus0` at runtime and
persist the address and netmask across reboot, without stranding an SSH user.

## Approaches

- **README-only manual steps:** smallest change, but leaves users to edit
  runtime state and two config files consistently.
- **Target-side helper (recommended):** stages a new live address, then
  persists it only after confirmation through the new address. Handles both
  interfaces and a supplied CIDR prefix.
- **Single shared network config:** cleaner source of truth, but requires
  redesigning how the boot script and ifupdown read configuration.

The helper is recommended because it addresses the immediate need while
preserving the existing boot and ifupdown setup.

## Goals and constraints

- Support `eth0` and `portus0`; accept an IPv4 address with CIDR, such as
  `192.0.5.20/24`.
- Require the new IPv4 address to differ from the current address so both can
  coexist during the SSH verification window; netmask-only changes are out of
  scope.
- Apply the new address live while keeping the old address until confirmation.
- Persist the address and netmask in both `/etc/init.d/lumen-eth-static` and
  `/etc/network/interfaces`.
- Keep device-side changes across reboot. A reflash restores values from the
  Yocto recipe, which remains a separate build-time source of defaults.
- Avoid changing gateways or unrelated interfaces.

## Proposed command flow

```sh
sudo lumen-set-ip prepare eth0 192.0.5.20/24
# Connect to the device at 192.0.5.20, then:
sudo env SSH_CONNECTION="$SSH_CONNECTION" lumen-set-ip confirm
```

`prepare` validates the interface/address/prefix, adds the new address without
removing the old one, records pending state under `/run`, and starts a bounded
rollback timer (proposed default: 120 seconds). It does not alter persistent
files. If the timer expires, it removes the staged address; a reboot before
confirmation also uses the unchanged old config.

`confirm` must verify that the SSH session's local destination address matches
the staged address. It then updates both config files, using the CIDR prefix to
write the dotted netmask required by `interfaces`, and only after both writes
succeed removes the old live address and cancels rollback. Config updates must
be backed up and reverted if either write fails. A separate explicit console
confirmation is allowed when using serial/local access. `cancel` immediately
removes the staged address and discards pending state.

This reduces the chance of lockout; it cannot promise zero packet loss or
preserve every existing SSH session during a route/netmask change. Serial
console remains the recovery path if the network does not recover. The two
config files cannot be replaced atomically as a pair; backups handle ordinary
write failures, but sudden power loss between replacements can leave them
mismatched.

## Non-goals

- Automatically changing the Yocto recipe or future image defaults.
- Setting routes, gateways, DNS, DHCP, Wi-Fi, or arbitrary interfaces.
- Replacing the existing network manager or boot flow.

## Documentation and validation

Document the command flow, CIDR/netmask behavior, SSH reconnect step, cancel
path, and reflash caveat in `README.md`. Test supported interfaces, prefix to
netmask conversion, invalid input, prepare/cancel, and confirmed config updates
against temporary config files before deploying on a board.
