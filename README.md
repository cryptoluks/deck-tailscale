# Tailscale on the Steam Deck

This process is derived from the [official guide][official-guide], but has been
tweaked to make the process smoother and produce an installation that comes up
automatically on boot (no need to enter desktop mode) and survives system
updates.

## Installing Tailscale

TBD

## Updating Tailscale

TBD

## How it works

It uses the same system extension method as the official guide, but we put the
`tailscaled.service` file directly in `/etc/systemd/system/` because it's
actually safe to put things there. Changes in `/etc/` are preserved in
`/var/lib/overlays/etc/upper/` via an overlayfs, meaning that they survive
updates.

[official-guide]: https://tailscale.com/blog/steam-deck/
