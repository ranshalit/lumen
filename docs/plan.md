## Autoresearch plan

Goal: reduce device boot time by iterating on the Lumen image and measuring boot time after flashing.

Planned flow:
1. Confirm metric, scope, constraints, and experiment budget with the user.
2. Inspect current image recipe and boot/flash scripts.
3. Establish a baseline boot-time measurement.
4. Stabilize the measurement workflow if the board is not already at `linux-prompt`.
5. Run focused image changes in the scoped repo files.
6. Build the image, flash it with the `flash-lumen` workflow (recovery reboot + initrd-flash), boot, and measure after each experiment.
7. Keep only improvements and record all runs in `results.tsv`.
8. For any experiment that is kept, amend the commit message to include the boot-time delta from the previous best before logging it.
9. Review `/home/ranshal/project/jetson/orin_yocto` history from `79731243b6418b8b0197982c4f9248c10fa1bb21` through HEAD for ideas that fit current constraints.
