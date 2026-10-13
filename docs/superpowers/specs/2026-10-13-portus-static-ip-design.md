# Portus Static IP Design

## Goal

Configure the Portus LAN743x interface at boot with `192.168.1.10/24`, without
changing the existing `eth0` address or slowing the boot path.

## Design

- Keep the existing udev rule that names LAN743x devices `portus0`. This rule
  sets only the interface name; it does not configure networking.
- Add a `portus0` static stanza to the generated `/etc/network/interfaces`.
- Extend the existing `lumen-eth-static` startup script to configure `portus0`
  independently in a background process. Wait only for the netdev to appear,
  bring it up, and assign `192.168.1.10/24`. Do not wait for carrier or tune
  its PHY.
- Preserve `eth0`'s existing address and fast-start sequence. Do not add a
  gateway for `portus0`.

This makes boot-time address assignment repeatable while keeping the boot
sequence asynchronous: startup does not wait for the Portus interface.

## Alternatives

- Only add the interfaces-file stanza: this records settings but does not
  automatically apply them on this image, requiring manual `ifup`.
- Add a separate init script: possible, but duplicates packaging/startup
  machinery already provided by `lumen-eth-static`.

## Validation

Check the generated interfaces file and script for both addresses and masks,
and run a focused BitBake parse/build for the affected recipe if the local build
environment permits. Confirm the existing udev naming rule remains unchanged.
