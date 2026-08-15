# Away from home with Tailscale

Use this when Home Assistant already works **on your home Wi‑Fi** and you want the same numbers on a phone or laptop **off the LAN** — without opening Home Assistant to the public internet.

This repo’s installer does **not** install Tailscale. You add it on the Pi and on each device you travel with. You do **not** put Tailscale keys, machine names, or IPs in git.

## What you get

```
Phone / laptop (Tailscale on)
        │
        │  private VPN
        ▼
Raspberry Pi (Tailscale on)  →  Home Assistant :8123
```

With Tailscale connected, open Home Assistant in a browser or the HA app using the Pi’s **Tailscale name or Tailscale IP**, port **8123**. Same sensors as at home (Victron, optional Sungold, Pi metrics).

Do **not** port-forward `:8123` on your router. Tailscale is the path in.

## 1. Install Tailscale on the Pi

On the Raspberry Pi (the same machine that runs Home Assistant):

Follow [Tailscale’s Linux install](https://tailscale.com/download/linux) for Debian / Raspberry Pi OS, then:

```bash
sudo tailscale up
```

A login URL is printed. Open it on any device, sign in to **your** Tailscale account, and approve the Pi. Pick a machine name you will recognize (anything you like). That name is yours — do not commit it to this repo.

Check it is up:

```bash
sudo tailscale status
```

You should see this Pi listed as online. The console also shows a Tailscale IP (`100.x.x.x`) and, if MagicDNS is on, a name like `your-machine.tailnet-name.ts.net`.

## 2. Install Tailscale on the phone or laptop

Install the Tailscale app from [tailscale.com/download](https://tailscale.com/download) (or the App Store / Play Store). Sign in to the **same** Tailscale account. Turn the VPN **on** before you open Home Assistant.

## 3. Open Home Assistant while away

With Tailscale **connected** on the travel device:

```text
http://YOUR-TAILSCALE-NAME:8123
```

or

```text
http://100.x.x.x:8123
```

Use the name or `100.x` address from `sudo tailscale status` on the Pi or from the Tailscale admin console. Replace the placeholders — do not copy anyone else’s.

In the **Home Assistant Companion app**, add that URL as the server (or as the external URL). You still need your Home Assistant login. The phone must have Tailscale on; this is not a public website.

**MagicDNS:** In the Tailscale admin console, enable MagicDNS if you want the name form instead of remembering the `100.x` address.

## 4. Home Wi‑Fi vs away

| Where you are | How to open HA |
|---------------|----------------|
| Home LAN | `http://YOUR-LAN-IP:8123` (from `hostname -I` on the Pi) |
| Away, Tailscale on | `http://YOUR-TAILSCALE-NAME:8123` or the Tailscale `100.x` address |

Both talk to the **same** Home Assistant. You are not duplicating the stack.

## Troubleshooting

| Symptom | What to check |
|---------|----------------|
| Page does not load away from home | Tailscale app **on** on the phone? Pi still `tailscale status` online? |
| Works on Wi‑Fi, not on cellular | Phone is using LAN IP. Switch to the Tailscale name / `100.x` URL. |
| Login loop / old server in the app | Remove the server in the HA app and add the Tailscale URL again. |
| “Can’t connect” with Tailscale off | Expected. Turn Tailscale on, or wait until you are on home Wi‑Fi. |

## Out of scope

- Putting Tailscale auth keys in `.env` or this git repo
- Exposing `:8123` or `:5006` on the public internet
- Replacing Home Assistant’s own user login — Tailscale only provides the network path
