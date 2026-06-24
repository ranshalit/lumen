# Ethernet bring-up moved from inittab `once @ runlevel 5` to rcS.d/S07
# (see lumen-eth-static.bb). Firing early lets autoneg overlap with the
# rest of rcS work, saving ~2s of boot-to-ping time. This bbappend is
# intentionally empty — kept as a placeholder so removing it later doesn't
# silently reintroduce a stale inittab entry on upgrade.
