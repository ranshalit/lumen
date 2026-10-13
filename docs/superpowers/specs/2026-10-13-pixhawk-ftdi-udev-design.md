# Pixhawk FTDI udev Rule Design

## Goal

Expose USB serial adapters with FTDI vendor/product IDs `0403:6001` at
`/dev/ttyPixhawk`, with mode `0666`.

## Design

Add the requested tty rule to the existing Pixhawk adapter section in
`meta-lumen/recipes-core/udev/lumen-udev-rules/99-lumen-devices.rules`:

```udev
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", SYMLINK+="ttyPixhawk", MODE="0666"
```

Keep the two existing adapter matches. The existing Yocto recipe packages this
rules file, and the minimal image already installs that recipe; no packaging or
image changes are needed.

## Alternatives

- Create a separate rules file and extend recipe packaging: unnecessary
  duplication for one device match.
- Give this adapter a distinct symlink: differs from the requested
  `ttyPixhawk` alias.

## Validation

Confirm the exact rule is present alongside both existing Pixhawk matches and
that the recipe continues to package the rule file. Run the smallest relevant
available validation.
