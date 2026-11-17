# Phone play

Magic Board uses its existing board, card renderer, hand, life/pile controls,
land organizer, and card inspector. Hold an empty part of the battlefield to open
the grouped Battlefield sheet. Its Play section opens Phone Play, the existing
Board Connect deck chooser, and Preloaded Games & Artwork.

One player hosts a nearby game and the other joins. Connect as Hand Only opens
the original Board Connect player selector within Magic Board. Return through
Players → Battlefield to leave that mode.

## Battlefield

Each device shows both battlefields, its own face-up hand, and a compact,
upside-down opposing hand. Card, hand, bar, and badge sizes grow with available
space. Rows shrink with density and page once the readable minimum is reached.
The two creature rows also respect their available vertical space. Layout uses
current container bounds and safe areas, with additional edge margins; bar
backgrounds extend behind the safe areas while controls remain inset.

Both land rows use the original organizer's compact grouping without its
background. Identical lands and tokens can share a Beleren `xN` badge. Tap the
badge to choose an individual card. Hold a permanent or land group to inspect
it. Attached cards overlap behind their bearer: hold the bearer, choose Attached
Cards…, and select an attachment to inspect or detach it.

Quickly drag a permanent or organized land to a pile to remove it. Dropping it
elsewhere leaves automatic placement intact. Hold without moving to inspect.
All permanents enter the battlefield immediately. Only instant and sorcery spells
use the manual Stack, which shows full card images and hides its label when
empty. Stack spells cannot be tapped. The Stack list supports resolving,
countering and inspecting spells. Players perform the effects;
there is no rules engine.

There is no targeting mode. Drag from a stack card to a permanent, a land, a
player's life total or another spell to toggle it as a target; a glowing arc
follows the finger and the target is outlined (on the mini card itself) with
"Target" or "Remove Target". Drag a stack card onto a graveyard, exile, library or
your hand to move it there without resolving it. Tapping and holding board cards
works as usual while spells are on the stack. Drag an instant, sorcery or Aura
from your hand onto a permanent and hold briefly: it outlines blue with "Target",
and releasing casts it onto the stack already targeting that permanent. Dragged
anywhere else, it goes onto the stack without targets. An Aura that resolves
attaches to the permanent it targeted. Glowing arcs connect visible stack cards
to their targets; spell-to-spell arcs loop outside the fan. The single chevron
and count button above the stack hides and shows it (there is no list view);
hidden, the cards slide aside leaving their edges visible, and tapping those
edges reopens it. Resolved cards fly from the stack into the battlefield or
graveyard; Reduce Motion uses a fade. Blocker-to-attacker lines show combat
assignments, with a dashed preview while dragging onto an attacker. Players
decide target legality and apply effects themselves.

Tap a card in the expanded hand to open its dedicated preview and Play sheet,
with the same face/mode choices and selected-card More actions as Board Connect.
Dragging upward uses that Play chooser too. The full manipulation menu belongs
to battlefield cards. Card-image previews do not spin in Phone Play.

Tap the local hand to expand it temporarily across the screen. Tap outside it
to return to its compact fan. Playing a card also collapses it. Drag cards within
the hand to reorder them. Both states animate smoothly; the compact fan sits low
and extends into the home-indicator area. Expansion overlays the battlefield without moving
permanents. The compact fan is wider, side controls are smaller, and the opponent
has no untap control. Both pile rows use the same label and count fonts, with
enough width to prevent individual labels from shrinking. All six pile previews
use the same image size, overlay their counts on the cards, and have vertical
padding. The local HUD is centered in the full bottom bar, including the
home-indicator area. Stack card images
have rounded corners. Creature rows stay centered even when the Stack is visible. Hand-card
corners scale with the card image in both states. Mana costs float above each
face-up card and follow its fan angle. Expanding the hand leaves pile, untap,
and life control frames fixed. During a battlefield drag, the source card is
hidden until the preview is dropped or cancelled. Tapped permanents and organized
lands display the existing tap arrow; lands keep the organizer's tapped/untapped
groups and rotation. Phone Play requests iOS bottom-edge gesture deferral, reducing accidental app
exits while playing cards. iOS manages the indicator appearance; explicit
auto-hiding stays disabled so it does not interfere with swipe protection.
Token creation from the card menu accepts automatically positioned source cards;
created tokens enter the shared battlefield without saved screen coordinates.

Life changes use the left and right halves of the existing counter: decrease on
the left, increase on the right. The opposing counter cannot be edited locally.

## Offline games and artwork

CardService.framework ships OfflineGames/catalog.json and artwork files. This
immutable catalog is independent of the downloaded database and purgeable image
cache. It includes all 555 packets across JumpStart (2020), JumpStart 2022,
Foundations JumpStart, Avatar: The Last Airbender JumpStart, and Marvel Super Heroes
JumpStart, plus SuperJump; DanDân; and 133 Jump In packet definitions from thirteen sets.
SuperJump retains the original 75 server lists and their selected land printings.
The bundle contains 6,290 card/token printings and 12,692 images. Jump In
uses the packet server's color-constrained offers, weighted random card slots,
and land-fixing rules locally. It generates a new 40-card deck for each pair;
it no longer replays a small snapshot of pre-generated pairs.

Preloaded Games & Artwork lists the actual included packets, possible cards, and
images. Starting JumpStart or selecting a Jump In set starts packet selection
for both phones. The host stores each player's three distinct offers, first
choice, and completion in snapshots. Either player can start; each independently
chooses two packets. Jump In’s All Sets option mixes offers across every bundled
set, retaining each packet’s set identity and the usual color preferences.
Offers persist through updates and reconnections. New games
sample new offers. A player who finishes first can return to the battlefield
while the other finishes choosing.

Non-bundled decks or images still require network access or an existing cache.
A fresh install can play the bundled games without downloading the full database.
The full database remains available through Update Card Database.
The existing Lands 2 packet was repaired to include its missing themed Forest,
matching the official JumpStart list:
https://magic.wizards.com/en/news/feature/jumpstart-decklists-2020-06-18

Regenerate the bundle with Scripts/import_packet_server.py (pointing at the local
TabletopSimulatorMagicBoosterPackServer checkout),
Scripts/preload_marvel_jumpstart.py, Scripts/preload_marvel_printings.py, then
Scripts/build_offline_catalog.py.
Marvel packet source:
https://magic.wizards.com/en/news/announcements/marvel-super-heroes-jumpstart-booster-themes
 The build scripts require network access;
playing the resulting bundled games does not.

DanDân uses a shared library and graveyard. Draw controls identify the local
player rather than the shared pile's owner, and drawn cards acquire the drawing
player's ownership/controller identity.

## Connectivity and state

Nearby play uses an encrypted, one-host/one-guest Multipeer Connectivity session.
Keep Wi-Fi and Bluetooth available; no router or Internet connection is required.
The host applies actions and publishes snapshots. Original controls feed the same
session, and guest edits patch changed fields without replacing unrelated state.
Leaving restores the previous classic board. The nearby picker uses a consistent
published snapshot and ignores taps on disappeared peers.

## Verification

The 26 model tests pass. UI checks cover both hosting and joining perspectives,
including hand expansion, reordering, play-to-collapse, land tapping/holding, life
changes, and packet selection.
The SE checks passed hand expansion/collapse for both roles, reordering followed
by playing, packet selection, and land tap/untap. The initial life UI check
selected the opposing counter; its corrected test has not completed. Home-indicator
verification exposed a land-row self-measurement loop, now replaced with sizing
from the row's available height. The updated app compiles, but the subsequent
simulator run stalled in test preparation and direct launch was interrupted by
CoreSimulator. Final home-indicator interaction verification remains outstanding.
The standalone Board Connect simulator build succeeds for arm64 and x86_64.
A two-simulator check confirmed a guest can start packet selection on both
devices, with three separate offers per player and the same selection identifier.

Model tests cover Stack/creature placement, shared draws, attachments, grouping,
combat, snapshot identity, state patches, density scaling, bundled artwork, and
40-card Jump In pairs. UI checks cover the existing hand drag, Stack, attachment
inspection, land holds, quick removal drags, crowded paging, deck chooser, and
embedded companion navigation. Fixtures are Debug-only and avoid saved games.

The iPad and Duo outer layouts were inspected on their actual landscape displays.
A fresh Duo simulator launches the board successfully; its inactive inner display
captures black. Inner-display and actual fold-transition behavior remain unverified. A physical
router-free two-device session also remains a release verification task.

Arena's mobile battlefield is the arrangement/proportion reference; the app
retains its own card rendering and controls:
https://magic.wizards.com/en/news/mtg-arena/mtg-arena-state-game-january-2021-01-21

## Imported packet corrections

Four copied packets had incorrect totals. Primates (2022) has six basic Forests;
Goblins 3 (Foundations) excludes the stray Hearts on Fire, Fling, and duplicate
Shock; Modified excludes Cultivate and Declare Dominance. Too Many includes a
seventh Mountain to produce a complete 20-card packet (the published list itself
only totals 19). The importer reapplies these corrections and verifies all copied
packets contain 20 cards. Sources:
https://magic.wizards.com/en/news/feature/jumpstart-2022-booster-themes-and-card-lists
https://magic.wizards.com/en/news/announcements/foundations-jumpstart-booster-themes

## Updating Jump In

The server archive retains the previous 103 packets and adds ten packets each
from Edge of Eternities (EOE), Lorwyn Eclipsed (ECL), and Secrets of Strixhaven
(SOS). Current source: https://mtgabuddy.com/en/jump-in-packet-list

The mirrored Scripts/jumpin_packet_data.py / server Scripts/update_jumpin_packets.py
tool merges only missing (set, name) keys, preserves the existing definitions,
and handles both legacy tables and newer symbol cells / fixed 100% card rows.
Refresh the server archive with its updater, then run:

    python3 Scripts/import_packet_server.py --jump-in-only
    python3 Scripts/build_offline_catalog.py

The server's Swift parser handles the same markup. Its offer selector falls back
to three distinct packets when a set has no monocolor tags (as with ECL).
