# Vellforge

Small tools for macOS, in one menu bar app. Free, no account, no telemetry.

Vellforge is one app with add-ons you switch on as you need them. It replaces
the separate Vellsnap, Vellscroll and Vellbar apps, and adds Buttons.

Part of [Vellund](https://vellund.com). Website: [vellforge.com](https://vellforge.com).

## Add-ons

**Snap: window snapping and layouts.** Drag a window to a screen edge and a
preview shows where it will land; drag toward the top for a layout chooser.
The chooser starts with a full-screen tile. Every region has a rebindable shortcut (defaults match Rectangle and Magnet:
`⌃⌥` plus arrows for halves, `U I J K` for quarters, `D F G` for thirds,
`⌃⌥⌘` plus arrows to move between displays). A 6×4 grid in the menu covers
regions with no name, and saved layouts capture every window's position to
restore later.

**Scroll: scroll direction per device.** macOS has one natural scrolling switch
for every device. Scroll flips the mouse wheel, the trackpad, or both, and the
menu says what each device actually does. It tells them apart by the gesture
phase a trackpad reports, so smooth-wheel mice such as Logitech's MX range
count as mice.

**Bar: hide menu bar clutter.** Adds a divider and a chevron at the right end
of the menu bar; click the chevron to hide everything to the left of the
divider, and ⌘-drag icons to its right to keep them on show. The list can
click any item for you, even while it's hidden.

**Buttons: middle click and side buttons.** A three-finger click on the
trackpad is a middle click (a three-finger tap too, if you want), and a mouse's
side buttons go back and forward in every app (as ⌘[ and ⌘]).

## Permissions

Permissions belong to the app, so one grant covers every add-on that uses it.
Vellforge only asks when you switch on an add-on that needs something.

| Add-on | Accessibility | Screen Recording |
| --- | --- | --- |
| Snap | Required: moving other apps' windows | — |
| Scroll | Required: changing scroll events | — |
| Bar | Optional: listing and clicking menu bar items | Optional: real icons in the list |
| Buttons | Required: changing clicks and button presses | — |

Bar hides icons with no permissions at all. It photographs one strip of the
menu bar for icons, never records continuously, never saves an image and never
sends one anywhere.

Updates come through [Sparkle](https://sparkle-project.org), which only
fetches `vellforge.com/appcast.xml`. No system profile is sent.

## Requirements and install

macOS 14 or later. Download `Vellforge.zip` from
[Releases](https://github.com/AKowel/vellforge/releases/latest), unzip, and move
Vellforge to Applications. It isn't notarised yet, so the first launch needs
System Settings → Privacy & Security → Open Anyway.

**Coming from Vellsnap, Vellscroll or Vellbar?** On first launch Vellforge
finds them, copies their settings (shortcuts, saved layouts, scroll choices,
the divider's position), quits them and moves copies in Applications to the
Bin. Settings → General → Bring Settings Over… runs it again later. Don't run
an old app alongside its add-on: Vellscroll and Scroll together flip scrolling
twice, which cancels out.

## Building

```
swift build && swift test
./Scripts/bundle.sh              # debug build at build/Vellforge.app
./Scripts/bundle.sh --release    # universal (Apple silicon + Intel)
./Scripts/bundle.sh --reset-tcc  # also clear the permission grants
swift Scripts/make-icon.swift    # regenerate the icon
```

The bundle script picks a signing identity from your keychain (override with
`VELLFORGE_SIGN_IDENTITY`). That matters more than it sounds: a real
certificate makes the designated requirement certificate-based, so the
Accessibility grant survives rebuilds and updates. Ad-hoc signing silently
loses it on every build.

## Releasing

1. Once: run `.build/artifacts/sparkle/Sparkle/bin/generate_keys`. It keeps
   the private key in your login keychain and prints the public key. Put that
   in `Resources/sparkle-public-key.txt` and commit it.
2. Bump `VERSION`, commit, then run `./Scripts/release.sh`. It builds, zips,
   signs the update and writes `appcast.xml` into `build/release/`, then prints
   the `gh release create` command.

The app checks `https://vellforge.com/appcast.xml`, which the site redirects to
the newest release's `appcast.xml` on GitHub. A release needs no site deploy,
and the feed address can move without a new build. Releases must be signed
with the same certificate each time, or people lose their permission grants.

## How it's put together

| Module | What |
| --- | --- |
| `SnapCore`, `ScrollCore`, `BarCore`, `ButtonsCore` | Pure logic with no AppKit, unit tested |
| `VellforgeKit` | The `AddOn` protocol, permissions, the registry that starts and stops add-ons, importing from the old apps, shared menu and UI pieces |
| `Snap`, `Scroll`, `Bar`, `Buttons` | One module per add-on |
| `Vellforge` | The app: menu bar icon, Settings, welcome window, Sparkle |

An add-on is one type conforming to `AddOn`: its name, the permissions it uses
(required or optional, with the reason), `start()`/`stop()`, its menu section
and its Settings pane. `AddOnRegistry` runs an add-on when it's switched on and
every required permission is granted, and re-checks whenever either changes. A
new add-on is a new module plus one line in `AppDelegate`.

Settings keep the keys the old apps used (`vellsnap.*`, `vellscroll.*`,
`vellbar.*`), so importing them is a straight copy.

Things worth knowing if you read the code:

- **`AXUIElementSetMessagingTimeout` is not optional.** Accessibility calls are
  synchronous IPC; without a timeout one hung app freezes the menu bar.
- **AppKit and Accessibility disagree about the origin.** The flip lives in one
  function, `CoordinateSpace`, and is always relative to the primary display.
- **Scroll reads all three delta encodings before writing any.** Setting one
  makes macOS recompute the others.
- **Bar hides by making its own status item 10,000 points wide.** Items lay out
  right to left, so everything to its left is pushed off screen. No API needed,
  nothing to break on a macOS update.
- **New menu bar icons go to the far left**, which on a full menu bar is behind
  the camera notch. So on first run Vellforge seeds the positions AppKit reads
  (`NSStatusItem Preferred Position <name>`; lower is further right): the
  Vellforge icon at 0, Bar's chevron at 1 and divider at 2. Collapsing then
  hides everything else straight away, and the Vellforge icon is never hidden.
- **Buttons reads finger counts from gesture events** in its event tap (as
  `NSEvent` touches); nothing about them is changed or stored.

## Licence

MIT. See [LICENSE](LICENSE).
