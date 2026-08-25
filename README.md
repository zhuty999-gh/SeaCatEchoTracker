# SeaCat Echo Tracker

海毛虫Echo Tracker — an Echo tracker for Preservation Evoker that still works in
World of Warcraft **12.1 (Midnight)**.

A fork of [Lazoro's EchoTracker](https://github.com/) (MIT). The UI is largely
his; the tracking mechanism has been rewritten, because the original approach
stopped working entirely in 12.1.

## Why this fork exists

Patch 12.1 made aura data **secret** whenever combat, encounter, Mythic+, or PvP
restrictions are active. Quoting the official API notes: all UnitAura APIs now
"either return full secrets or nil" to addons, and "AuraData structs are now
always fully secret."

The original addon scanned the raid every 0.1s and read `expirationTime` off each
Echo. In 12.1 that fails in two stages:

| Stage | Symptom |
| --- | --- |
| Reading a secret | A Lua error every 0.1s the moment you entered combat with an Echo out, requiring `/reload` |
| Guarding the read | No error, but the icon vanished entirely — the by-name lookup returns nil when the aura is secret |

There is no alternative aura API that gets around this; it is the explicit intent
of the restriction.

## How it works instead

Nothing about Echo is read from auras. State is **inferred from your own cast
sequence**, which is legal and plain-valued because a unit's cast info is only
secret when that unit is not the player or their pet.

```
Echo / Temporal Anomaly   →  push an expiry
a consuming heal          →  clear them all
Emerald Blossom           →  bank an extra-target stack
```

Echo's real duration is **calibrated out of combat**, where auras are still
readable, and cached. Talent 376240 (+15% per point) is therefore picked up
automatically rather than hardcoded.

See [DESIGN.md](DESIGN.md) for the full design, the spell tables, and a record of
the approaches that were tried and rejected.

## Accuracy

Being honest about this matters, because the two numbers have **opposite** error
directions:

**The timer is accurate and errs conservative.** Every known error source makes
it look like the Echo expires sooner than it really does, which is the safe side
for deciding whether to re-apply.

**The count is an estimate that errs high**, and is hidden outside raids by
default. Temporal Anomaly hits up to 5 allies without telling the addon who, so a
later Echo on one of those same allies is a refresh that gets counted as new. In
a 20-man raid the flat 5 holds up well; in a 5-man group the orb often clips
fewer, which is why you have to opt in via *Also show count outside raids*.

Note that Mythic+ reports as `party`, not `raid`, so the count is hidden there
under default settings.

## Commands

| Command | Effect |
| --- | --- |
| `/sce` | Toggle settings |
| `/sce spells` | Print the spell table with resolved names, to verify IDs |
| `/sce show` / `/sce hide` | Toggle always-show |
| `/sce unlock` / `/sce lock` | Move the tracker |
| `/sce reset` | Reset to defaults (keeps the calibrated duration) |

`/et` also works, for muscle memory from the original addon.

`/sce spells` is worth running once after any class patch: it resolves every
configured spell ID to its live name, so a renumbered spell shows up immediately
instead of silently breaking the tracker.

## Installation

Drop the `SeaCatEchoTracker` folder into `World of Warcraft\_retail_\Interface\AddOns\`.

Settings are imported once from the original addon's `EchoTrackerDB` if you have
it, so switching over keeps your layout.

## License

MIT. The original copyright notice is retained as required — see [LICENSE](LICENSE).
