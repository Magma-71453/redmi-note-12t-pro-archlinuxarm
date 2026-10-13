# Pearl Linux kernel 7.2.10++

Source: https://github.com/MT6895-Mainline/linux
Branch: 7.2-mt6895-xiaomi-pearl
Commit: a908b7825c7d619873392e5fbbcba2e54695d0eb

Build:
  ./scripts/kernel-build-gadget.sh

Config is `config` (base = mt6895 pearl 7.2.9+ artifact, merged with
`arch/arm64/configs/pearl.config`, USB MTU3 forced to gadget-only).
The kernel embeds `mt6895-xiaomi-pearl.dtb` and overrides the LK FDT at boot.
