# Phone Play handoff

Updated 2026-11-17 (pile browser, spring-loaded piles, menus, companions, stack copies). Workspace: `/Users/compc/Xcode/Magic Board`.

## 2026-11-17 follow-ups (third round)

- **Drag into an open browser:** hand and battlefield cards dropped on any open library/graveyard/exile browser (incl. Search and Look at) go into that zone at the drop spot (`phoneBrowserDropZone`, `finishPhoneSpringLoad`); a drop on the browser's dimmed area returns the card instead of landing behind it (`phoneDropBlockedByBrowser`). The fan's drop band is the cards' own band (`fanDropArea`). UI test `testHandCardDragsIntoOpenBrowser`.
- **Board hit-testing:** the board's content view is a `PhoneBoardContentView` (set at load), which accepts touches on cards laid out past its edges — Phone Play's field can be wider than the zoomed board, and such cards ignored presses.
- **Closed Duo battlefield:** rows, land rows and the column layout read the reserved regions per band (`phoneBandInsets`, `phoneTrimmedBand`: a region that only nicks the column's top/bottom shortens it instead of narrowing it). Attachment spill reservations match the tucked attachments.
- **Hand ability tiles:** Arena styling — dark gradient tile, top-lit rim, gold-gradient symbol.
- **Stack count badge:** small dark label above the stack's top-left corner (Arena's "x23").
- **Battlefield placement rework:** done.
  - Step 1: count badge. Step 2: lanes sized by count.
  - Step 3, back row: with a land row shown, a player's noncreature, nonland permanents sit in that land row's band, right-aligned opposite the lands, at land size (`MiniCardView.layoutScale`). They overlap when crowded and stop short of the stack button and Resolve. Without the land organizer, the old support lane stays. Planeswalkers, sagas and battles keep their lane at the right end of the creature band. Fixture `--phone-board-backrow`; UI test `testNoncreaturePermanentsSitInTheBackRow`.
  - Step 4, overlap before paging: full rows overlap cards down to 45% of a card apart before paging. The crowded fixture now has 30 extra creatures.
  - Observed: on the SE, cards shrink to their minimum size before overlapping, so 30 creatures page as 15 + 15 without visible overlap. Overlap shows up only once a row exceeds what fits at minimum size.
- **Lanes:** no fixed 30% cap; lanes get the room their cards need, or a share by count. Fixture `--phone-board-walkers`, UI test `testTwoPlaneswalkersShowWithoutPaging`.
- **Face flavor names:** Swiftfall `Card.Face.flavorName`, `MTGCard.Face.flavorName`, Core Data model version **Card 2** (CardFace.flavorName; lightweight migration). Card face options and `CardRepresentation.flavorName` use them. Existing databases get them on the next card-database update.
- **Face-down play options:** Morph and Disguise offer "(Face Down)" beside a normal play (drag from hand shows the chooser). **Cloak** beside Manifest. Cloaked/disguised cards are `CardRepresentation.mysterious`, shown as "A Mysterious Creature" (tmkm 21).
- **Foretell fixed** (exiled face down, castable), **Plot** (exiled face up, marked castable; iPad board too), **Adventure** resolves into exile as the creature, marked castable.
- **Taplands:** `OracleTags` (CardService) keeps Scryfall Tagger oracle-tag lists — bundled in the offline catalog (`Scripts/add_oracle_tags.py`, 519 cards for `tapland` with its descendant tags) as a first-launch-offline seed only. At runtime the lists are built from Scryfall's `oracle_tags` bulk file and kept current: at most once a day the app checks the file's `updated_at` (a small request) and rebuilds only when it changed (skipped under tests). A land played from the hand whose oracle ID has `tapland` enters tapped (MDFCs only on their land face). Unit test `testTaplandsEnterTappedFromHand`.
- Verified: 63/63 unit; UI tests run per change on the SE (browser, stack, combat, other side, walkers) and the closed Duo. Full UI suite not re-run.

## 2026-11-17 follow-ups (second round)

- **Spring-loaded browser:** the dragged card stays above the browser (`orderPhoneBrowser` brings `phoneDragPreview` to front; battlefield previews too). Piles under the expanded hand spring-load on a 0.9 s hold, so hand cards can go into the library at an exact spot.
- **Expanding the hand over the browser** doesn't move the browser's cards (`phoneBrowserContentBottomInset` always uses the collapsed hand's height).
- **Two-color tokens** use the plain (land) P/T box again (original rule restored).
- **Kept-revealed top card** shows face up in that library's browser for players it's revealed to. **Reset Decks and Life** clears `revealedTops`.
- **Card menu other side** (`CardImageViewController.showsOtherSideButton`, on in the battlefield and hand card menus): a round arrows button (`card-other-side`) under the card previews the other face locally only (nothing is sent; the card on the field doesn't change). Double-faced layouts flip with a 3D transition; Kamigawa flip cards (`layout == "flip"`) rotate 180°; backs with frame effect `upsidedowndfc` (Havengul Laboratory // Havengul Mystery, printed as Hawkins National Laboratory // The Upside Down) show upside down. Fixture `--phone-board-faces`; UI test `testCardMenuPreviewsOtherSide`.
- **Hand ability tiles:** hand cards show Arena's hand-only ability icons (`!isPermanentEffect`, e.g. Cycling, Flash, Kicker, Ninjutsu) on gold reminder plates at their left edge (`PhoneHandAbilityTiles`, `PhoneHandCardFace.abilityTiles`).
- **Arena icons from mtg.wiki** (`MTGA_<Ability>.png`, template assets): new for Cycling, Equip, Enlist, Specialize, Scry, Fight; the guild/clan stand-ins for Adapt, Afterlife, Addendum, Undergrowth, Riot, Spectacle, Jump-Start, Mentor, Raid, Ferocious, Delve, Prowess and Outlast are replaced by their own icons; 52 new abilities added to `MTGCardView.Icon` with styles (keywords, keyword numbers, costs, ability words, mentions), e.g. Ninjutsu, Plot, Disguise, Warp, Offspring, Spree, Gift, Bargain, Landfall, Morbid, Revolt, Toxic, Backup, Explore, Investigate, Mill, Venture, Discover, Forage.
- **Closed iPhone Duo edges:** `phoneBandInsets(_:margin:minimum:)` keeps each horizontal band (top bar, bottom bar, stack, hand) clear only of the iOS 27.1 occlusion regions that cross it (outer camera, its bar strip), instead of a whole safe-area side plus 24 pt. Falls back to the safe area before iOS 27.1. The life total anchors to its bar's edge, not the bar's own safe area. Verified on the Duo simulator (closed) with the combat tests.
- **Blocks look like Arena:** golden glowing curves from each blocker's facing edge to its attacker, a golden halo arc over that edge (`PhoneCombatLinesView`), gold blocker outlines.
- **Attachments** tuck right behind their card, each peeking a little further left (Arena).
- **Collapsed stack** peek target is 44 pt (it was ~65% of a card wide and stole long presses from cards under it).
- Verified: 59/59 unit; affected UI tests on the SE (combat, blocking, other side, revealed top, graveyard browser, four stack tests) and combat tests on the closed Duo. Full UI suite not re-run.

## 2026-11-17 batch (to-do item plus a list of fixes and features)

- **Piles open in the browser.** In Phone Play, tapping either player's graveyard, exile or library opens `PhoneZoneBrowserView` in `PhoneBrowserMode.pile(location, owner)` (`BottomBarViewController.viewPile`); the old sheet is `presentPileSheet`, reachable from the browser's "⋯" menu (`phone-browser-more`: Open List; for your library also Search, Look at, Shuffle and Keep Top Card Revealed To). A library shows face down and **uncondensed** (`condensesFaceDown = false`). Reordering your own pile sends `PhoneAction.arrangePile(location, ids)` (top-first).
- **Spring-loaded piles.** Holding any dragged card (hand, pile or battlefield) over a pile for 0.65 s opens that pile's browser mid-drag (`updatePhoneSpringLoad`, called from `updatePhoneZoneHover`). Over the fan a gap opens where the card would go (`externalDragMoved`, with edge auto-scroll); releasing there moves the card into the pile and arranges it to that spot (`finishPhoneSpringLoad`), and the browser closes 0.6 s later. Released elsewhere, the browser closes and the drop works as before. Not spring-loaded when the card is already in that pile.
- **Outlines follow flying creatures.** Attach, target, combat and inspection outlines are hosted in the mini card's `cardView` (`phoneOutlineHost`), so they share its flying wiggle and lift.
- **Attack arrows** sit below the stack container.
- **Stack button** shows `square.stack.3d.up.fill` instead of a number (accessibility label still "Stack · N").
- **Token copies** keep the token frame again (black name bar, small caps, centered title). Two-color tokens use the gold P/T box (hybrid keeps the land one).
- **Phased out:** `Counter.phasedOut` (a card state, not listed as a counter) dims the permanent to 30%; the controller's untap step phases it back in. Toggle: the card menu's "Phased Out" tile.
- **Card menu redesign** (`CardControlView`): a grid of icon tiles (`card-tile-<id>`) at the top for every quick action — the board's card actions (Attack, Unattach, Cast…), Switch Control, Token Copy, Transform, Face-Up/Down, Phased Out, Doesn't Auto-Untap, Doesn't Untap Next Turn, Commander, Remove. Toggles light up in the accent color. Below: card-specific rows (Prepared and its spell, Room doors), Card Face only when there are faces, Create… only when there is something to create, Commander Tax when a commander, and Colors.
- **Board hold menu redesign** (`BoardMenuSheetController`): one scrolling page of grouped icon tiles (Game, Cards, Board, More). Game has Load Deck, Preloaded Games, Connection, **Reset Decks and Life, Clear Board, Exit Game** and **Reveal Hand / Stop Revealing Hand** right on the first page. Pushed pages (deck picker, packet chooser) still navigate inside the sheet.
- **Reveal hand:** reveals your whole hand to the opponent (`.reveal(handIDs, opponent, true)`); the opponent's phone opens its revealed-cards browser. Stop Revealing Hand un-reveals.
- **Shield counters:** `Counter.shield` with the official symbol (`Icon_Shield`, vector template from the user's SVG); in the counter screen's "More Counters" menu.
- **Top card revealed:** `PhoneAction.revealTopCard(owner, viewers)` / `PhoneGame.revealedTops`; each phone's library pile shows the top card face up when it's revealed to that phone's player (`HUDCardPileView.revealsTopCardOverride`). Set from the library browser's "⋯" menu or the pile sheet's eye button (`pile-top-card`), for either player's library: Me, Opponent, Both, No One.
- **Companions:** a deck's Companion group now loads into the sideboard, marked (`PhoneGame.companions`), not the command zone. Marked companions in your sideboard show beside the hand with a teal glow (`castableCompanions`) and can be played onto the battlefield or put into the hand. Any card with the Companion keyword has Mark as Companion / Not My Companion in its hand-card menu.
- **Copy a spell on the stack:** stack card menu "Copy" → `PhoneAction.copyStackItem` puts a token copy with the same targets on the stack. A copied instant/sorcery ceases to exist on resolving; a copied permanent spell enters as a token. Test: `testCopiedStackSpellsVanishOrEnterAsTokens`.
- **Browser cards** are `PhoneBrowserCardView`s: rounded clip, a thin dark edge and a soft shadow, so overlapping cards and the condensed stack stay distinct.
- Card menu tiles on the SE controls pane: 3 columns, 52 pt tall; Prepared/Room rows sit above the grid. The combat glow now lives inside the mini card's image (follows flying), so it is no longer visible to UI tests; `testCombatModeAttackTogglesAndEndCombat` checks the "Attacking" value instead.
- Not covered by a UI test: the spring-loaded drop (XCUITest can't move a held drag after pausing over a pile). Verify by hand: drag a card over your graveyard, hold, move into the fan, release.
- Full suite: 59/59 unit, 50/50 UI (SE, fresh private build). New UI test `testTappingGraveyardOpensItsBrowser`; pile-sheet tests reach the sheet via the browser's ⋯ → Open List.
- New unit tests: `testCopiedStackSpellsVanishOrEnterAsTokens`, `testCompanionInSideboardIsListedBesideHand`, `testTopCardRevealedToChosenPlayers`. Board menu UI tests now tap tiles (`app.buttons[...]`).

## Arena-style card browser (search / look at / revealed) — reworked 2026-11-16

- `PhoneZoneBrowserView` (bottom of `PhoneSessionControllers.swift`):
  - Cards appear large in a horizontally scrolling fan with Arena's arc and a scrubbable pill scrollbar.
  - **The board's bottom bar (your HUD and collapsed hand) stays undarkened and usable**: `uncoveredBottom`, and `hitTest` passes touches through there.
  - Hold a card (0.15 s) to lift it. Drop it in the fan to reorder (a haptic tick per gap move), on your **hand, library, graveyard or exile in the bottom bar** (the board answers `zoneAt`; the card shrinks there and a "Move to …" label floats above it), or on the **Battlefield** zone at the top.
  - A library drop asks **Top / Bottom**; Cancel puts the card back in the browser.
  - **Show Opponent** checkmark: reveals the browsed cards to the opponent, and un-reveals them on close.
  - Done uses the stack's Resolve style.
- **Modes** (`PhoneBrowserMode`): `.search` (whole library, with Shuffle & Done), `.look(n)` and `.revealed`, which un-reveals on close. Opening the browser dismisses any open sheet (the library sheet, a reveal).
- **Library sheet:** Search, plus **Look at** (Top Card … Top 10 Cards). Look at replaces Scry/Surveil and the Reveal button; scry and surveil are done by dropping cards where they go. Reordering sends `PhoneAction.arrangeLibraryTop`.
- Tests: `testArrangeLibraryTopPutsCardsOnTopInOrder` (unit); `testLookAtBrowserMovesCardsToLibraryBottomAndGraveyard` and `testSearchBrowserShowsWholeLibrary` (UI).

## 2026-11-16 follow-ups (costs, fan, hold, planets, packet navigation)

- **Alternate costs:** a card shown beside the hand because it's castable from the graveyard or exile floats the cost it's cast for there (`PhoneGame.alternateCastCost`, parsed from the rules text after Flashback, Escape, Disturb, Unearth, Embalm, Eternalize, Harmonize, Mayhem or Foretell). Retrace and jump-start keep the normal cost. Test: `testCastableCardsShowTheirAlternateCost`.
- **Hand fan** (`PhoneHandFanView.slots`) uses the browser's geometry: cards overlap at about 62% of a card width (squeezed only when they don't fit), tilt up to about ±7° by their distance from the middle and dip slightly at the edges, so two or three cards sit together.
- **Hold to open a card's menu:** 0.35 s (battlefield cards and organized lands).
- **Planets and Spacecraft** mini cards: large art behind a fully transparent frame (no `bg-colorless` lightening), with the card's own colored name/type bars, border and P/T box (`MTGCardView.CardProperties.isPinlineFrame`, set from the type line). Fixture: `--phone-board-planet`; screenshot reviewed.
- **Browser order matches Arena:** a library reads bottom to top from left to right, so the top card is on the right (`phoneBrowserDisplayOrder`; the board keeps top-first internally), and long lists open scrolled to the right end. In Look at, the face-down rest of the library is condensed into one tight stack with a count (`phone-browser-hidden-count`).
- **JumpStart / Jump In loading navigates** instead of stacking sheets. Starting a packet game from the board menu's Load Deck page pushes `PhonePacketChoiceView(embedsNavigation: false)` into the same sheet (back hidden, the sheet can't be swiped away), and the sheet closes when both packets are chosen. The other phone, with no menu open, still gets the chooser as a sheet.
- Full suite: 56/56 unit, 49/49 UI (SE, fresh private build).

## Browser follow-up (2026-11-16, later)

- **Layout:**
  - The dim reaches down to the bottom row (your HUD; `phoneBrowserUncoveredBottom`).
  - The controls start below the opponent's HUD (`topInset`).
  - The fan is sized to the space left and centered (up to 460 pt tall, so it fills an unfolded Duo). It stays above the top of the collapsed hand (`contentBottomInset`).
  - The hand draws **above** the browser so it stays visible and usable, except while a card is lifted (`orderPhoneBrowser`, `onLiftChanged`).
- **Show Opponent** is drawn like Arena's settings checkbox: a dark diamond when off, a glowing orange check when on.
- **Look at** lists "1 card" … "10 cards". The browser shows the whole library: the cards looked at face up, the rest face down (`phoneBrowserLookedAt`), so cards can be moved anywhere in it. Library modes follow the library's actual order after every change (a card sent to the bottom reappears at the end).
- **Edge auto-scroll:** holding a lifted card near either edge keeps the fan scrolling that way, faster nearer the edge (`scrollAtEdge`, a `CADisplayLink`).
- **Dropping on a library from anywhere** (hand, battlefield, stack, a pile or the browser) asks **Top / Bottom**, plus **Command Zone** for a commander (`promptPhoneLibraryDrop`, sent with `PhoneGameSession.sendDirectly` so the commander question isn't asked twice). Commanders dropped on a graveyard or exile still get the zone-or-Command-Zone choice (`chooseCommanderZone`).

## 2026-11-16 round

- **The open hand collapses whenever a card leaves it** (played, discarded via its menu, moved…), as on Arena (`refreshPhoneBoard`).
- **Piles under the open hand** aren't drop targets: `phonePileZone` returns nil when the open hand covers the point. All drag finishes (hand, battlefield, stack) go through it.
- **Token copies** render as the card they copy (`objectType = .card` for a `.tokenCopy` of a non-token), so the frame and P/T box match the original. A two-color copy had been getting the token-only tan P/T box.
- **Rooms** (`CardRepresentation.isRoom`: split layout, "Room" in the type line):
  - Drawn as the full card image turned sideways (90° clockwise: first door on the left). Each locked door is darkened with the **LOCKED door symbol** cut from the user's DSK token (`Icon_LockedDoor`).
  - Locks are `Counter.lockedDoorLeft/Right` (not drawn as counter discs). Casting a door (`.play` with a face) puts the whole Room on the battlefield with the other door locked.
  - The card menu has a **"<door> Locked"** checkmark per door in the main section, and Rooms show no Card Face section.
  - The mini card's accessibility value lists locked doors.
  - Test: `testRoomShowsLockedDoorAndUnlocks` (fixture `--phone-board-room`).
- **Haptics** tick as cards are reordered in the hand or the browser.
- **Shuffle wiggle:** `PhoneGame.shuffles` counts shuffles per player; the board wiggles that player's library pile (`wigglePhoneLibrary`) on both phones.
- **Hand pickup:** holding a card up and letting go without moving changes nothing (`liftPoint`). For commanders and castable cards that's a cancel. Test: `testHoldingHandCardWithoutMovingKeepsOrder`.
- The graveyard/exile/library sheets no longer show the iPad's flip button in Phone Play.

## Hand, reveal and hold follow-ups (2026-11-15)

- **Hand stays open while dragging within it:** picking up a hand card no longer collapses the hand; it collapses once the card leaves the hand area (`movePhoneHandCardPreview`), so you can reorder in the open hand. Pile drags still collapse it on pickup. Two UI tests were updated: a reorder now leaves the hand open, and playing drops above the open hand.
- **Reveal:** in Phone Play, the library's Reveal choices are **Me / Opponent / Both** (sent as `.reveal` actions). On the iPad board they're the player names plus **Both**.
  - Cards revealed to this phone's player open a **Revealed Cards** sheet (`updatePhoneRevealedCards` / `presentPhoneRevealedCards`, a `PileViewController` with `.revealedCards`). It comes up again only for newly revealed cards.
  - Closing it stops revealing those cards to that player. `.reveal(..., false)` is allowed for yourself even on cards you can't otherwise use.
  - Test: `testRevealingLibraryCardsShowsRevealedCardsSheet`.
- **Castable cards into the hand:** a graveyard/exile card shown beside the hand shows "Move to Hand" when dragged among the hand cards and moves there on drop. Dropped back on its own spot (`isNearPhoneHandDragOrigin`), it stays where it is. Test: `testCastableCardDraggedIntoHandMovesThere`.
- **Hold to open a card's menu:** 0.5 s, about a system context menu's hold (was 0.65 s), for battlefield cards and organized lands.

## Cards castable from other zones (Arena-style, beside the hand)

- `PhoneGame.castableCards(for:)` covers:
  - your graveyard cards with a graveyard-casting keyword (`graveyardCastKeywords`: Flashback, Jump-start, Retrace, Escape, Disturb, Unearth, Embalm, Eternalize, Harmonize, Mayhem), plus aftermath split cards;
  - your **foretold** cards in exile.

  It's a convenience list, not a rules check: players decide whether a cast is allowed right now. Adventure and plot cards in exile aren't listed, since an exiled card doesn't say whether it went there on an adventure or by plotting.
- The board publishes the list to `PhoneHandPresentation.castable` on every refresh. `PhoneHandFanView` shows them after the commanders, to the right of the hand past the same gap, glowing **purple when in the graveyard, orange when in exile** (`PhoneHandCardFace.castableFrom`, `PhoneHandPresentation.castableInExile`). Accessibility IDs are `phone-castable-N`.
- Tapping one opens the hand card menu (Play / Play Tapped); dragging works like a hand card. `PhoneGameSession.castOptions` casts a disturb card as its back face. `.play` turns a foretold card face up. A castable card dropped back over the hand returns to its spot (only commanders move into the hand).
- **Manual mark:** a pile sheet card in a graveyard or exile has a **Castable** toggle in its hold menu (`PhoneAction.markCastable`). It's stored in `PhoneGame.markedCastable` (card → the player who may cast it; works for an opponent's graveyard or exile too) and cleared in `remove(_:)`, so leaving the zone, including by being cast, resets it.
- **Flashback exile:** a spell cast from a graveyard with Flashback, Jump-start or Harmonize gets `StackItem.exileOnResolve` and is exiled instead of going to the graveyard when it resolves or is countered (`exilesAfterCasting`). Cast from the hand, it goes to the graveyard as usual.
- Tests: `testCardsMarkedCastableShowUntilCastAndFlashbackIsExiledAfter` (unit) and `testGraveyardCardMarkedCastableShowsBesideHand` (UI).
- Tests: `testCardsCastableFromGraveyardAndExileAreListed` (unit) and `testFlashbackCardShowsBesideHandAndCasts` (UI, fixture `--phone-board-flashback`); the screenshot was reviewed.

## Prepared cards (layout "prepare")

- **Casting:** prepare cards always cast as their creature face (`Command.PlayCardParameters.options`; `choosingFrontFace` includes "prepare").
- **Marker:** a new `Counter.prepared` (appended to the enum) marks the card. The card's hold menu has a **Prepared** checkmark row where Transform sits for transforming cards; it only appears for `layout == "prepare"`. In Phone Play it sends `.counter(id, .prepared, ±1)`. The marker draws as a purple counter disc with the symbol on the mini card.
- **Casting the spell:** while prepared, a **Cast <spell>** row appears directly under the Prepared checkmark (`card-cast-prepared`, in `SideTableViewController`; no longer in the top action list). Tapping it unchecks Prepared and closes the menu → `PhoneAction.castPrepared`. That puts a token copy of the second face on the stack and removes the marker. The copy resolves to the graveyard, where it ceases to exist as a token, and the creature stays.
- **Symbol:** `CardView/Assets.xcassets/Icon_Prepared.imageset` (template), cut from the user's SOS Prepared token image (white symbol, brightness → alpha). `Counter.symbolImage` falls back to SF Symbol `sparkles` only if the asset is missing. Verified on the mini-card marker and in the menu row.
- **Hand cost:** a prepare card in hand shows only its creature face's cost (`PhoneHandCardFace.handCost`; test `testPrepareCardInHandShowsOnlyItsCreatureCost`).
- **Tests:** `testPrepareCardsCastAsCreatureAndCastTheirPreparedSpellAsACopy` (unit) and `testPreparedMarkerCastsThePreparedSpell` (UI, fixture `--phone-board-prepare`) pass; the screenshots were reviewed.

## Latest follow-up — drag polish (2026-11-15, final)

- **Blue play glow:** outline only (rim and halo, clear center), so it never covers the card.
- **Pile drags** (graveyard/exile/library) lift to battlefield-card size once and keep that size; only hand cards grow and shrink between the hand and the battlefield.
- **Organized lands dropped where nothing happens** glide back to their slot in the land row; the slot stays concealed until the preview arrives.
- **Hand drop zone** = the hand's own frame (`phoneContentFrame`, compact or expanded), no longer the whole HUD band between the piles. This applies to battlefield, stack and pile drags and to drops.
- **Drop labels** ("Move to …", Attach, Block, Target, Unattach, Stop Blocking) sit just above the dragged card, or above the finger for a stack card's arrow, via `phoneDragLabelCenter`; they're no longer placed over the zone or target, so nothing covers them. Their position isn't covered by a screenshot test (XCUITest can't capture mid-drag).
- **Zone hovers** show only the "Move to …" label over the zone; no outline box (`showPhoneDragHover(outlined: false)`). Targets keep their outline.
- **"Move to …" / "Target" labels:** white Beleren text on a deep blue with a cyan rim (~6:1 contrast).
- **Floating mana costs:** no black capsule; each symbol has Arena's soft dark shadow.
- **Haptics:** a light tick when a dragged card *enters* a zone it would move to. It plays once per entry, not on every move: `phoneZoneHoverKey` resets only when the card leaves every zone or a drag ends (the outline itself is redrawn on each move).
- **Verification:** full suite 50/50 unit and 40/40 UI tests pass before the last two items. After those, the stack drag, pile drag and menu/hand screenshot tests pass on a fresh private build, and the expanded-hand screenshot shows the shadowed costs.

## Latest follow-up — drag feel, glow, haptics, saga fix (2026-11-15 late)

**Build note:** the shared DerivedData stopped re-linking the app again, probably because the user was building in Xcode at the same time. Agents should build into a private DerivedData: `-derivedDataPath <scratchpad>/dd -clonedSourcePackagesDirPath ~/Library/Developer/Xcode/DerivedData/Magic_Board-gcphwddapphdduhfgkksnavwdoee/SourcePackages ENABLE_DEBUG_DYLIB=NO`, and check that the app binary's timestamp is newer than the edits.

- **Target arrows** stay visible while the stack collapses or expands. `phoneStackAnchor` follows the stack layer's presentation transform, and a `CADisplayLink` (`phoneStackArcLink`) redraws the arcs during the slide.
- **Counters:** Stun is back to its old blue and Finality is black. Both icons are template images drawn in white, on the mini cards, the counters list and the palette buttons.
- **Battlefield drag release** settles instead of snapping (`settlePhoneDragPreview`): it glides back to the card's place, shrinks into the pile it was dropped on, or fades (hand, attach).
- **Saga tapped → card back:** fixed. Clearing `MiniCardView.properties` while the view showed a full card image (sagas, undecided double-faced cards) set the contents to the card back. Now only rendered mini cards fall back. Reproduced and verified with the `--phone-board-saga` fixture and `testSagaShowsCardImageAndStaysFaceUpWhenTapped`.
- **Haptics** (`PhoneHaptics`):
  - Pick-up and attach/target/block offers arming: medium impact.
  - A card landing in a new zone (pile, hand, battlefield, stack, attach, cast targeting), or a target being set: rigid.
  - A stack card's arrow reaching something it can target: light tick.
  - Menu zoom: medium.
- **Face-down library drags** show the card back with no floating mana cost (`PhoneHandCardFace.faceDown`).
- **Blue "release to play" glow** (Arena) behind a dragged hand or pile card whenever letting go would play it (past the hand area and not over a pile): a cyan-blue halo with a bright rim.
- **Drop labels** ("Target", "Attach", "Block", "Move to …") use Beleren.
- **"Move to …" zone outline everywhere:** stack drags show "Move to Hand" again (no arrow over zones). Hand drags show it over piles; pile drags over piles and the hand; battlefield drags over piles and the hand (`showPhoneZoneHover` / `updatePhoneZoneHover`).
- **Verification:** full run on a fresh private build (SE, iOS 17.5): **50/50 unit, 40/40 UI tests pass**. Haptic strength, the glow's look next to Arena, and the arc tracking mid-slide need a look on a device.

## Latest follow-up — arcs, counters, pile drags, inspecting outline (2026-11-15 night)

**Build warning (read first):** at some point after 17:42, incremental `build-for-testing` kept reporting success while leaving `Magic Board.app` and the UI test runner unchanged: the app's sources compiled but it never re-linked. So any test results from 17:42 to 18:28 ran an older binary. After deleting the app and test intermediates, the rebuilt Debug app wouldn't launch ("Trying to load an unsigned library: Magic Board.debug.dylib"). **Build and test with `ENABLE_DEBUG_DYLIB=NO`** and check the product timestamps (`Build/Products/Debug-iphonesimulator/Magic Board.app/Magic Board`) after building.

User requests this round:
- **Target arcs while the stack is collapsed.** They're drawn from the edges of the cards left showing. They fade out during the slide and come back at the new anchors.
- **Stack drags into the hand:** no outline, label or arrow. Over piles, the outline and "Move to …" label show but no arrow; arrows are only for targets. The live drag arc is its own view (`phoneStackDragArc`) and fades out on release.
- **Your own life total can be targeted.** It sits in the HUD band, which the drag had treated as the hand.
- **Token copies of double-faced cards** copy the front face (`CardRepresentation.choosingFrontFace`; `.play` with no face uses it too), so they render as mini cards rather than the whole card's image. Test: `testTokenCopyOfDoubleFacedCardUsesItsFrontFace`.
- **Counter icons.**
  - The counters page shows the ability symbol instead of a number for keyword counters, and for stun and finality.
  - Exalted and Shadow use the user's icons (`Icon_Exalted`, `Icon_Shadow`, template).
  - Stun and the new **Finality** counter (`Counter.finality`, appended to the enum) use full-color icons (`Icon_Stun`, `Icon_Finality`) via `Counter.symbolImage`. Stun's disc is light so the black spiral reads; Finality's is dark under the gold skull.
  - The Stun palette button shows its icon, and a Finality button sits beside it.
  - Mini-card counters draw the icon, with a count badge only when there's more than one.
- **Dragging the top card off a graveyard, exile or library** (any player's graveyard/exile; only your own library) works like the hand drag: `PhonePilePanGesture` → `phonePilePanned` → the hand-drag pipeline with `sourcePile`. The card lifts at the pile's size and grows to hand size; a hidden library card travels face down. Drops: battlefield (play), attach/target hovers, piles, or the hand (moves it there). Native pile drags are disabled in Phone Play.
- **Opponent-is-looking outline (Arena).** `PhoneAction.inspect` and `PhoneGame.inspecting`. A phone reports the battlefield card whose menu is open (`presentPhoneCardMenu`) or the pile sheet it's viewing (`BottomBarViewController.viewPile`) through `PhoneGameSession.trackInspection`, and clears it when the sheet closes. The other phone draws a thin white outline inside that mini card (or around an organized land) or around that pile's small top card (`updatePhoneInspectionOutline`).
- **The stack no longer moves the battlefield.** The field layout dropped its stack insets; the stack draws over the field, and hiding it uncovers the cards.
- **Right-hand lane (Arena):** planeswalkers, sagas and battles that aren't creatures sit at the right of their player's band (`PhoneBattlefieldLayout.Row.side`, `row(for:)`, `phoneLanes`). Other permanents stay on the left, creatures in the middle. Card size now fits the fullest *band* (all of a player's lanes), not the longest row; before, sharing a band made the creature row page after one card once the stack stopped narrowing the field. Row page buttons draw above the stack. Test: `testPlaneswalkersSagasAndBattlesUseTheRightLaneUnlessCreatures`.
- **Sagas** draw their full card image on the battlefield (`MiniCardView.isUndecidedFace`), since there's no good mini-card form for them.

Verification (SE, iOS 17.5, built with `ENABLE_DEBUG_DYLIB=NO` and fresh products):
- Full run: 50/50 unit tests and 37/38 UI tests passed. The failure was the attach test tapping a "Done" that Unattach had already closed; the test now tolerates that, and it passed together with the counter test and the new `testTopCardDragsOffLibraryIntoHandAndGraveyardOntoBattlefield`.
- Screenshots reviewed: the collapsed stack keeps its arc, and counters show Exalted/Stun/Finality icons on both the counters page and the mini card.
- Not exercised in automation: the opponent-inspecting outline (it needs two connected phones) and the planeswalker/saga lane visually (no fixture has them).

## Latest follow-up — stack drags, hand pickup, menus, Jump In duals (2026-11-15 evening)

User requests this round, all implemented:

- **Hand card corners** were square: `PhoneHandMenuSource` (the UIKit zoom source behind each hand card) set its corner radius before it had a size. Its `SourceView` now rounds itself in `layoutSubviews`.
- **Menu zoom from lands and stack cards.** Both are SwiftUI with no UIKit view to lift, so `phoneMenuStandIn(for:zooming:)` puts a UIKit stand-in in the card's place for each zoom in or out (the real card is concealed), then removes it once that transition ends. **The haptic now plays when the zoom starts**, not after the sheet settles.
- **Jump In duals follow the server** (`TabletopSimulatorMagicBoosterPackServer`, `JumpInParser.addLands`). `Scripts/add_jumpin_duals.py` (run by `build_offline_catalog.py`) stores each set's common two-color lands in `catalog.jumpInDuals`. FIN uses its towns, SOS has five college lands, and BLB/ECL/EOE/LCI/MKM/WOE have none. Starter-product-only printings are skipped (BLB's starter gainlands, FDN's guildgates). `OfflineGameLibrary.jumpInDual(for:sets:)` prefers the packet set that shares more of the pair's colors, then DMU, then Evolving Wilds. Test: `testJumpInDualsUseTheSetsCommonLandsBeforeDMU`. Artwork for the new lands downloads with the rest.
- **Battlefield menu pushes instead of stacking sheets.** `BoardMenuAction(title:push:)`. Load Deck and Preloaded Games now push inside the menu's sheet. Connection shows its alert over the menu, and choosing a deck file opens the picker over the menu. The user's "Load Deck sheet doesn't come up" didn't reproduce on the iOS 17 SE; it came from closing the menu and presenting a new sheet in the completion handler, which this removes.
- **Stack: no targeting mode, no list.** Removed: the targeting overlay (bar, checkmarks), `PhoneTargetPickerController`, `PhoneStackController`, the automatic prompt when a spell is cast, and "Choose Targets".
  - A pan on the stack's hosting view handles dragging from any visible stack card (`phoneStackPanned`). Released on a player, battlefield card, land or other spell, it toggles that target. Released on a pile or your hand, it moves the card there without resolving it (`moveToPlayer`).
  - The target is outlined inside the mini card, with a "Target"/"Remove Target" or "Move to …" label.
  - Board taps are unaffected (targets only change by dragging from stack cards, as the user asked).
  - Abilities on the stack (no card) show Resolve / Remove from Stack when tapped.
  - The single `phone-stack` button (chevron + count) toggles collapse. `phone-stack-collapse` is gone.
- **Hand spells target by dragging.** An instant, sorcery or Aura held over a permanent for 0.4 s gets the blue outline with "Target" (`PhoneDropIntent.target`). Releasing sends the new `PhoneAction.castTargeting(id, target)`. Auras dropped elsewhere go onto the stack untargeted; instants and sorceries still use the Play chooser. **A resolving Aura attaches to its targeted permanent** (`.resolve`).
- **Attach/Block outlines** now live inside the target `MiniCardView` (`phoneDrawnCardRect(in:)`, shared with the combat glow), so tapped cards outline correctly.
- **Hand pickup.** `DragGesture(minimumDistance: 0)`: a card lifts after a 0.16 s hold (`PhoneHandFanView.holdDelay`) or once the finger moves 6 pt. A quicker release is a tap (opens the card's menu, or expands the collapsed hand). Over the hand area, the card floats with its bottom 14 pt above the finger; past it, the finger holds the card's center, easing over 0.2 s.
- **Pile sheets (Phone Play):** holding a card you can see opens a context menu. Move to: Battlefield (Stack for instants and sorceries), Hand, Graveyard, Exile, Top/Bottom of Library. Non-spell cards also get Create Token Copy (`.copy`; the original stays put). Before this, pile sheets had no menu in Phone Play (`isLocalPhone` is false for board roles).
- **Library Reveal:** while choosing cards to reveal, the Reveal button that started it is hidden, so only the confirming Reveal and Cancel show.

- **Commanders.**
  - Tax and the yellow glow never showed in Phone Play because `PhoneHandCardFace` checked `card.pile`, which searches `GameState.current` (the iPad's state, not Phone Play's). The fan now passes `inCommandZone`.
  - Casting from the command zone (`.play` / `.moveToStack`) adds a cast. The new `PhoneAction.commanderTax(id, casts)` sets the count, from a Commander Tax stepper in the hand card menu (which now also opens for command-zone cards).
  - Decks loaded into the command zone are marked `isCommander`, as on the iPad.
  - `PhoneGameSession.chooseCommanderZone` (wired by the board) asks "Hand/Graveyard/… or Command Zone" before any commander moves to another zone, like the iPad's prompt.
  - "Move to Command Zone" is in the hand menu and the battlefield card menu for commanders.
  - Test: `testCommanderTaxGrowsWithCastsFromTheCommandZoneAndCanBeSet`.
- **Stack hit area:** the stack's hosting view sits in a full-screen `PhoneTouchFilterView` that only takes touches on drawn stack cards. Before this, the empty part of the fan's frame covered the battlefield's "Next battlefield cards" button (`testCrowdedOriginalBoardKeepsReadableCardsAndCanBrowse` failed).

Verification (SE, iOS 17.5):
- Full run: every unit test passed, and every UI test except one. `testDraggingOntoCardAttachesAndUnattaches` hit the known "Lost connection to the application" XCTest flake (no crash report), then passed twice on its own.
- New UI tests: `testStackCardDragsTargetAndMovesToZones`, `testHandSpellDraggedOntoCreatureCastsTargetingIt`, `testMenusZoomFromLandsAndStackAndRestoreTheCard`.
- Rewritten: the attach test now attaches a battlefield Soldier, since dragging an instant onto a creature now targets. `testArenaStackFansCollapsesAndResolves` uses the single stack button.
- Removed: the targeting-mode UI tests (the mode no longer exists).
- Load Deck now pushes inside the menu: `testMenuDeckChoosersAndOfflineCatalog` passes.
- Not verified in automation: iOS 18+ zoom (lands, stack), the haptic timing, and the hold-to-pick-up feel. These need a device. **iOS 18+ zoom and the haptic can't be checked in automation:** on iOS 27.0 and 27.3 simulators, XCTest waits forever for the app to go idle ("App event loop idle notification not received"), even though the app runs fine. Check them on a device.

## Latest follow-up — card motion, tapped rendering, menu zoom and basic lands (2026-11-15)

**Status as of 2026-11-15 16:40 — cached-art flight verified. START HERE NEXT:**

1. The settled-destination change and broadened AX assertion PASS (`Test-Magic Board-2026.11.15_16-32-24--0500.xcresult`).
2. The cached-art seeding (`CardRepresentation.imageIfLoaded(type:alwaysUpright:)`, used for `MiniCardView`'s first properties and `SwiftUICardView`'s initial `@State art`) is **verified**. The run interrupted at the earlier stop request had actually finished: `/tmp/magic-card-polish-cached-art.log` compiled both edited files and `testTappedPermanentAndTravellingMiniCard` PASSED. A fresh rerun with a recording also PASSED (19.8s). The landing frames show the travelling mini card carrying its Grizzly Bears art for the whole flight, where the old recording showed blank art. Crop: [References/ArenaStack/Implementation/phone-cached-art-flight.png](References/ArenaStack/Implementation/phone-cached-art-flight.png). The black "x4" tiles on that board are fixture lands with no cached art on the SE; they are unrelated.
   - Trade-off: on a cache hit, `imageIfLoaded` decodes the art synchronously on the main thread (an SDImageCache memory/disk hit, or a file read for offline artwork). This only happens on a mini card's first render; keep an eye on it if large boards hitch on load.
3. **Still open:** native menu zoom (iOS 18+ `preferredTransition = .zoom`) has not been visually verified. Both earlier iOS 27.0 simulator launches stalled before the test runner; don't retry that unchanged. Easiest check: on a real device, open a hand card and a battlefield card menu. The haptic also needs hardware. The user's Duo simulator `3E3C2185-…` is theirs; leave it alone.

No commits/pushes. Preserve all existing uncommitted feature changes and unrelated scheme-management edits. The rest of this section records earlier implementation and test history; the status above supersedes older pending/rerun notes.

Latest user requests: attacking outlines must rotate with the card; Jump In basics must come from their packet sets and balance every regular illustration (full-art fallback only when no regular prints); dropped cards must become mini-cards during flight; entering-tapped cards must be darkened; field/hand card menus should zoom from their card and play a haptic.

Implemented:

- **Attack outline:** combat glow views now live inside each `MiniCardView` using unrotated art bounds. They inherit the card's animated tap transform. Border/shadow dimensions account for board zoom.
- **Tapped rendering:** `MiniCardView.properties` always reads the current tapped state, including initial rendering. Async artwork completion merges only the new art into current properties rather than resetting newer state from a captured copy.
- **Hand morph:** a moving full-card preview crossfades into a moving mini-card snapshot over the same 0.32s flight. Actual destination stays hidden until completion. Organized lands use a temporary SwiftUI mini host and presentation-only concealment. Cleanup restores hidden cards; Reduce Motion uses a short fade. **Last change:** `flyPhoneHandPreviewToBoard` explicitly calls `layoutPhoneBattlefield()` before capturing the destination, because the recording showed a row regrouping after the flight had started. This is retained and compiles.
- **Menus:** UIKit `preferredTransition = .zoom` on iOS 18+ when Reduce Motion is off. Provider reacquires the field mini-card image view or the hand's weak UIKit image source for dismissal. Hand sources have explicit frames and `sizeThatFits` to prevent artwork intrinsic size overflowing the fan. Source artwork is refreshed immediately before presentation in case it loaded since SwiftUI last updated. Older iOS / Reduce Motion use the existing transition. Soft impact on presentation completion; physical sensation needs hardware.
- **Jump In basics:** `OfflineGameLibrary.jumpInDeck` allocates basics to eligible packet sets and balances each set/basic over its preferred art pool (counts differ by at most one). Includes explicit basics already in packet lists (notably ECL). Existing mana weighting, nonbasic fixing and 40-card totals remain. Catalog now includes 135 basic art records and runtime image URL mappings for all 13 sets, plus `jumpInBasics`. FIN uses full-art fallback; the other 12 sets use regular basics. `Scripts/add_jumpin_basics.py` selects/deduplicates illustrations and is invoked by `build_offline_catalog.py`; artwork itself was not downloaded. Raw Scryfall caches `/tmp/magic-jumpin-basic-sets/`, import log `/tmp/magic-jumpin-basics-import.log`.

Verification:

- Python policy tests **2/2 PASS**: `python3 -m unittest discover -s Scripts -p test_jumpin_basics.py`.
- `/tmp/magic-card-polish-new-tests.log`: **3/3 model tests PASS** — `testJumpInBasicArtsUsePacketSetsAndBalancedPrintings`, `testOfflineJumpInPairsBuildFortyCardDecks`, `testAllSetsJumpInOffersAndCrossSetDecks`. Covers all set/basic pools, balanced counts including zeros, BLB regular arts, FIN full-art fallback, mixed ECL/FIN.
- `/tmp/magic-card-polish-final.log`: SE `testCombatModeAttackTogglesAndEndCombat` **PASS**. Screenshot and frame sequence reviewed: outline follows rotation. Existing Play Tapped land UI check also passed in `/tmp/magic-card-polish.log`.
- `/tmp/magic-card-polish-empty-drop.log`: new SE `testTappedPermanentAndTravellingMiniCard` **PASS**, before the explicit destination-layout call. Tapped/untapped screenshots reviewed: Dandân visibly dark when entering tapped and lighter after untap. Successful attachments `/tmp/magic-card-polish-success-shots/`, recording `/tmp/magic-card-polish-final-morph.mp4`. Durable screenshots are linked in [References/ArenaStack/README.md](References/ArenaStack/README.md).
- **Most recent run:** `/tmp/magic-card-polish-settled.log`, result `/Users/compc/Library/Developer/Xcode/DerivedData/Magic_Board-gcphwddapphdduhfgkksnavwdoee/Logs/Test/Test-Magic Board-2026.11.15_16-27-40--0500.xcresult`. App builds, tapped/untap checks pass, final creature-only AX count was 2 instead of 3. Exported `/tmp/magic-card-settled-shots/`; `35D827BA-1108-4CDB-8462-7786029864D6.png` clearly shows all three Grizzly Bears (opponent, original local, newly landed local) and five cards left in hand. Likely early/generic permanent AX classification rather than failed play. **After that run**, broadened the test query to accept either `phone-creature-card` or `phone-permanent-card` and wait up to 5s for count 3. This small test-only adjustment is **not rerun yet**. Do not claim the most recent run passed.
- Recording of the latest run: `/tmp/magic-card-settled-shots/6652F5F3-6835-4FF8-860C-E9C231BD48C2.mp4` (XCTest). Earlier successful simctl recording `/tmp/magic-card-polish-final-morph.mp4` is only ~6s and shows the pre-slot-fix flight. Art can arrive after the snapshot on a fresh cache; inspect whether that needs further polish, without conflating it with the initial tapped-state bug.
- **Modern iOS blocked:** `/tmp/magic-card-polish-modern.log` built successfully but stalled before launching the test runner. Restarted only the isolated simulator; bootstatus succeeded. `/tmp/magic-card-polish-zoom-reuse.log` stalled again before tests. Interrupted both; no more retries this session per working preferences. Native iOS 18+ zoom needs a healthy simulator or physical device check. Haptic also needs hardware.
- Automation lessons: stale test executables initially silently skipped new tests; rebuilt only affected target intermediates/products. An older app fixture was fixed by refreshing `PhoneGame.swift` / `PhoneGameSession.swift` timestamps. Do not trust a test name that never appears as executed. A real zoom-source intrinsic-size overflow was fixed. New test now collapses the stack before tapping the arriving rightmost permanent (otherwise the stack inspector intercepts the tap), and drops at normalized `(0.45, 0.7)` (the earlier `(0.45, 0.5)` hit a creature and attached the bear). Do not alter application behavior to compensate for those automation targets.

Next agent:

1. Cached-art flight and destination layout are verified (see the status above).
2. If recordings are needed again, avoid broad test suites or repeated builds without new evidence. `simctl` recordings may carry rotation metadata: use `ffmpeg -noautorotate ... -vf transpose=2` for raw 750×1334 SE pixels; first inspect dimensions. Sparse/VFR timestamps made time-based contact sheets misleading; selecting by frame number worked reliably.
3. Verify hand and field menu zoom on a healthy iOS 18+ device/simulator; do not repeat the two stalled modern launches unchanged. Use existing hand Play Tapped land and combat-menu flows. Hardware haptic confirmation remains.

Reusable command: `nice -n 10 xcodebuild -project 'Magic Board.xcodeproj' -scheme 'Magic Board' -configuration Debug -destination 'platform=iOS Simulator,id=180A4550-3336-4B5C-9DD9-D6C0739E8034' -disableAutomaticPackageResolution -parallel-testing-enabled NO -jobs 2 -enableAddressSanitizer NO -only-testing:PhoneBoardUITests/PhoneBoardUITests/testTappedPermanentAndTravellingMiniCard test` (redirect output to a new /tmp log).

Task SE `180A4550-3336-4B5C-9DD9-D6C0739E8034` / iOS 17.5 remains booted. Created isolated `Magic Board Menu Zoom` iPhone 17 Pro / iOS 27.0 simulator `429F36A0-8E06-45CC-AD96-DF51F9CD9FF5`; it is **shut down**. Leave the user's running Duo `3E3C2185-5F0B-4ED3-AA9E-C34D72E4FEBF` alone. No task build or recording should still be running. Preserve unrelated preexisting scheme-management changes and earlier feature edits.

## Latest requested follow-ups (2026-11-15) — completed

User: "Implement choosing targets directly on the board. When the stack is collapsed, it should slide over with the edges of the cards left only partially visible. Implement combat assignment lines. Add resolution animations as well."

- [x] **Direct board targeting.** Newly cast targeted spells now enter board selection mode instead of immediately opening a table. Tap cards / life totals to toggle targets; drag from the stack to a target for a live arc. The transparent overlay consumes the touches so selecting doesn't tap/attack/move a card or adjust life. Cyan outlines and checkmarks identify selections. Toolbar: Done commits the draft through `.setStackTargets`, Cancel discards it, List opens the existing native picker for public piles / offscreen cards / precise duplicate selection. List edits stay in the draft until board Done; List Cancel leaves the draft unchanged. Choose Targets from the inspector or stack context menu dismisses the sheet and starts this same board mode. VoiceOver gets selectable board elements and the native List fallback.
- [x] **Collapsed stack slides to the right.** The fan remains rendered, leaving only its overlapping left edges visible. Tap those edges (`phone-stack-peek`) or the chevron to reopen it. A 0.25s property animator changes only the stack's transform, preserving battlefield/HUD positions, with interruption support. Cards are hidden from accessibility while collapsed; the peek button exposes Show Stack cards. Target arcs / Resolve remain hidden while collapsed. Reduce Motion switches the slide to an immediate state change.
- [x] **Combat assignment lines.** Glowing cyan/white lines connect actual blocker and attacker art edges after the blocker moves into place. Hovering a dragged blocker over an attacker previews a dashed line from its original position. Drop commits the existing `.block` action. Clear on Stop Blocking / End Combat / removed combatants; stale previews are validated against current combat. Lines never intercept touches. `phone-untap-local` accessibility value reports the assignment count.
- [x] **Resolution animations.** Cache displayed stack frames before snapshots replace them. Departing spells fly/shrink/crossfade into their actual battlefield card or graveyard/exile preview over 0.42s. This covers the direct Resolve button, list resolution, and other stack-to-public-zone moves, using authoritative snapshots for either player. Game state changes immediately; animation completion only removes presentation views. Reduce Motion uses a short fade. Backgrounding clears temporary hosting controllers and restores battlefield alpha. Only departures from visible stack cards with a visible destination animate (hidden older stack items / no visible destination skip the effect).

Implementation: `BoardViewController` owns the targeting draft/overlay, stack slide, combat line geometry and transient resolution hosts. `PhoneSessionControllers.swift` adds `PhoneBoardTargetOverlay`, accessibility target elements and `PhoneCombatLinesView`, shares fan transforms, and lets the list picker return a draft without sending an action. `PhoneGameSession.hostFixture` adds `--phone-board-resolution` (a permanent above an instant). No new game rules, data migrations or project file entries.

Verification:

- `/tmp/magic-arena-interactions.log`: all **5/5 UI tests PASS** on SE: direct tap/drag targeting + Cancel + no accidental tap, list fallback / editing / arcs, stack hide/peek/show and resolution, blocker drag, permanent-to-field and instant-to-graveyard resolution. Screenshots exported to `/tmp/magic-arena-interactions-shots/` and reviewed.
- `/tmp/magic-combat-lines-verified.log`: extended block test **PASS**, confirming assignment count 1 → 0 after Stop Blocking. An earlier extension used nonexistent `phone-untap-a`; inspected the hierarchy and corrected the test to the actual `phone-untap-local` identifier, without changing app behavior for the automation failure.
- Recorded `/tmp/magic-arena-interactions.mp4`; reviewed frame sequences for the stack sliding out/back and both resolution flights. `simctl` records portrait pixels on this simulator, so transpose counterclockwise for landscape. Fast input seeking gave misleading locations for a stack clip; decoding then filtering by video timestamps found the actual motion. Durable short clips and screenshots are in [References/ArenaStack/README.md](References/ArenaStack/README.md): direct targets, partial-edge collapsed stack, combat lines, resolution, stack-slide MP4, resolution MP4.
- SE only. Duo / larger-device visual checks, actual peer-device animation and VoiceOver/Reduce Motion device interaction were not separately exercised. Keep follow-up verification proportional; no need to repeat the full UI suite without a new concern.
- No commits or pushes. Other running simulators and existing unrelated scheme-management changes were left alone.

## To-do list (requested 2026-11-15)

- **Piles open in the browser (requested 2026-11-16).** DONE 2026-11-17 — see "2026-11-17 batch" above.

- **Stack, Arena style.** DONE (first implementation, 2026-11-15). User redirected this session to the stack and explicitly requested online references saved into Docs. Four original screenshots, source links and observations are in [References/ArenaStack/README.md](References/ArenaStack/README.md), including an official mobile single-spell screenshot and a four-spell counterspell stack. Large right-aligned upright top card, older cards fanned left (newest four shown), compact count/browser, collapse/show chevron and direct Resolve button. SE interaction tests PASS and final screenshots reviewed; details below. Larger-device/Duo visual check remains available as a follow-up.
- **Move to Stack.** DONE. The hand card sheet's second section starts with "Move to Stack" for nonland permanent cards (`PhoneAction.moveToStack`; it resolves onto the battlefield). Unit test `testVigilanceCounterAndMoveToStack`.
- **Targets.** DONE (first implementation, 2026-11-15). Follow-up user instruction: "Also work on the arcs for showing targeting." Targeted spells/Auras offer a chooser when entering the stack. Choose Targets in the spell inspector or stack list's context menu edits them later. Glowing cyan/orange arcs connect visible stack cards to their selected targets; spell-to-spell connections loop outside the fan. Three model tests and the SE selection/editing/arc UI check PASS; final screenshot reviewed and saved in Docs. See details below. Saved Arena references already show the curves; no need to wait for user screenshots.
- **Attack and combat mode.** DONE (2026-11-15).
  - The creature card menu (`AppDelegate.phoneCardActions`) has "Attack" (closes the inspector), "Remove from Combat", "Stop Blocking", and during your combat a plain "Tap"/"Untap".
  - Attacking taps unless the creature has vigilance (keyword or counter: `CardInstance.hasVigilance`). Leaving the attack untaps it again.
  - `PhoneGame.Combat.player` records the attacker; `attackingPlayer` is used everywhere, and the defender can't declare attackers mid-combat.
  - Combat mode: the local untap button turns orange and reads "End Combat" in Beleren (`BottomBarViewController.configureUntapButton`). Pressing it sends `.endCombat`, which clears every attacker and blocker.
  - In your combat, tapping your creature toggles its attack (`tapUnTapGestureRecognized`).
  - Attackers glow orange and blockers glow blue around the actual card art (`updatePhoneCombatGlows`). The existing Arena chevron stays.
  - While the opponent attacks, dragging your creature onto an attacker shows an orange "Block" glow after the hover delay; dropping blocks it. Dragging a blocker off shows "Stop Blocking".
  - Blockers move to sit against the attacker, on their own side, with arrow room (attachments move with them).
  - UI tests: `testCombatModeAttackTogglesAndEndCombat` and `testDraggingOntoAttackerBlocks` (fixture flag `--phone-board-opponent-attacking`). Unit test `testAttackTapsUnlessVigilantAndOnlyOnePlayerAttacks`.
- **Exalted and Shadow icons.** Both still use SF Symbol stand-ins: mtg.wiki returns 403 to automated fetches. Ask the user for the official Arena icon files, add them as `Icon_Exalted` / `Icon_Shadow` in `CardView/Assets.xcassets`, and map them in `Counter.keywordIcon`.

## Latest follow-up — target selection and arcs (2026-11-15)

- `PhoneGame.Target` represents a card UUID or player. Optional `StackItem.targets` preserves old saves. `.setStackTargets` goes through the existing host-authoritative session/transport; only the spell's player can edit it. Duplicates, self-targets, private-hand cards and missing cards are filtered. Removing/moving a target, resolving a targeted spell (including a permanent), and zone edits clear incoming connections. This does not automatically counter/fizzle anything.
- `PhoneTargetPickerController` is a native table with Players, Battlefield, Stack, Graveyards, face-up Exile and Command Zone sections. Supports multiple/no targets, duplicate-card numbering, existing selections, Done and Cancel. It refreshes from snapshots and closes if its spell leaves the stack.
- `BoardViewController.refreshPhoneBoard` detects newly added local spells and queues optional target prompts. `CardInstance.offersPhoneSpellTargets` checks English oracle text for "target"/"targets" (selected face when applicable), plus Auras. This is deliberately a convenience heuristic, not a legality/parser implementation; it can prompt for cards whose abilities mention targets, and players may cancel or edit manually. Existing stacks on resume don't reopen prompts.
- `PhoneTargetArcsView` draws static glowing curves and arrow tips, cyan for your spells and orange for the opponent's, without intercepting touches. Shared fan geometry supplies stack anchors; actual card art, organizer frames, life boxes and graveyard/exile previews supply endpoints. Spell-to-spell curves loop left outside the overlapping fan so they remain visible. Hiding the stack hides the arcs; showing it restores them. Arcs update on layout and organizer frame changes.
- Land organizer frame preferences now map every card in a group to its visible stack rectangle (previously only the top card had a frame), allowing any grouped land to be targeted. The native drag/hit selection still chooses the top card through its existing reverse-order search.
- Visible-source limitation: arcs originate from the newest four visible stack cards; hidden older sources don't draw until they enter the visible fan. Offscreen battlefield pages or command-zone cards with no visible endpoint retain their stored targets but don't draw an arc. Public graveyard/exile targets connect to their pile preview. Larger-device/Duo visual checks and actual peer-device interaction were not run; snapshot/action coding and model ownership were tested.
- PASS in `/tmp/magic-target-arcs.log`: `testStackTargetsAreOwnedPublicUniqueAndSurviveSnapshots`, `testStackTargetsClearOnZoneChangesAndPermanentResolution`, `testSpellTargetPromptUsesSelectedFaceAndRecognizesAuras`, plus existing `testArenaStackFansCollapsesAndResolves`. The initial target UI run had a bad pre-tap `isHittable` assertion; the actual table tap scrolled to the row and the rest of the interaction passed. Removed the manual swipes/assertion and let UITableView automation scroll the exact row (no app workaround).
- Final `testSpellTargetPickerDrawsAndEditsArcs` PASSES in `/tmp/magic-target-arcs-loop.log` (27.7s): casting opens the chooser, selecting a creature / any grouped land / player / other spell draws four connections, hide/show preserves targets, editing removes the player connection, and resolving clears the arcs. Screenshot review caught and fixed the previously hidden short spell-to-spell curve. Reviewed final screenshot: [References/ArenaStack/Implementation/phone-target-arcs.png](References/ArenaStack/Implementation/phone-target-arcs.png). The fixture intentionally chooses arbitrary manual endpoints; this is not an example of Memory Lapse's legal targets.
- No commits/pushes. Existing unrelated scheme-management changes remain untouched.

## Previous work — Arena stack (2026-11-15)

- Latest user instruction: "Forget what you're working on -- I want you to work on the Arena-style stack. Search online for reference images and save them into docs so the other agent later can find them as well."
- Online reference acquisition is complete; no need to wait for user-provided stack images. See the reference README above. Original image files and three final implementation screenshots are saved in the repository (not just `/tmp`).
- `PhoneStackCardsView` in `PhoneSessionControllers.swift`: full-card buttons with the newest upright/in front, older cards rotated counterclockwise and offset left, shadows/edges, max four visible. Tap/hold still inspects; drag still works. Every item remains reachable in `PhoneStackController` through the count/magnifier. Motion respects Reduce Motion.
- `BoardViewController.layoutPhoneStack`: larger fan anchored to the screen's right safe edge, independent of the battlefield's row/column bounds; count/magnifier, hide/show chevron, orange Beleren Resolve. Hiding doesn't change the model or battlefield geometry. All controls disappear when empty. Hand drag landing now uses the actual front stack-card rectangle instead of shrinking toward the count button.
- Like the saved Arena screenshots, the expanded fan can cover rightmost battlefield cards. Hide Stack exposes them without rearranging the board. Existing battlefield sizing/reservations are preserved.
- Added debug fixture `--phone-board-stack` (four alternating-player spells) and UI test `testArenaStackFansCollapsesAndResolves`: newest in front, older cards to the left, full list, hide/show preserves cards, hand stays hittable, sequential direct resolution and empty-state controls.
- PASS: new test plus existing `testOriginalBoardPhoneHandAndStack` (hand drag onto stack, list resolution, attachment inspector) in `/tmp/magic-arena-stack.log`. Screenshot review found the initial count badge overlapping the title; fixed spacing/chevron placement, then the new focused test PASSED again in `/tmp/magic-arena-stack-polish.log` (16.3s). Single/four-spell/collapsed screenshots exported to `/tmp/magic-arena-stack-polish-shots/` and copied to `Docs/References/ArenaStack/Implementation/`.
- No commits/pushes. Existing unrelated `xcschememanagement.plist` modification was present before this session and is preserved. Other running simulators were left alone; this pass used only the existing SE.

## Hand fixes (2026-11-15)

- Root cause of "the hand disappears when I leave the app / fold / unfold", found with on-device logging: during UIKit's background-snapshot and fold layout passes, `BottomBarViewController.refreshForPhoneSession()` ran its non-local branch. Its `insertSubview(handContainerView, …)` pulled the board-adopted hand container back into the bar, and `layoutPhoneHandOverlay` then bailed (`superview !== view`).
- Fixes:
  - The bar only reorders a container it still owns.
  - The board re-adopts the container on every layout (`adoptPhoneHandContainer()`, idempotent).
- The user confirmed on the Duo that the hand stays.
- Hand drag (Arena):
  - Only from the expanded hand. Picking a card up collapses the rest of the hand.
  - The card lifts from its exact fan geometry (`PhoneHandCardFace`, with its mana cost) and is full size over the hand, battlefield size over the battlefield.
  - The fan opens a gap at the insertion point (`PhoneHandPresentation.heldIndex`).
  - It lands with a fly/crossfade into the battlefield card, land row, stack, pile, or its hand slot.
  - Cancelled touches (fold/app switch) put it back.

## Session 6 follow-up (OPEN, top priority)

- "I unfolded the Duo for you. The hand is very inconstent -- now just dragging a card from the battlefield makes the hand disappear. I can't get it to consistenly work as expected, either, it often just won't appear, or makes the card menu show up instead of letting me drag a card out."
- "Can you access the Magic Board Duo Layout simulator? It's not opening in Device Hub" (Device Hub error: "Live device view took longer than expected to connect.", DeviceKitError 4002, device 2F31FF38-..., interaction: connecting).
  - Device Hub error: the sim was booted but reported no displays (`simctl io enumerate` empty; screenshots "Invalid argument"). Fixed by `simctl shutdown` + `boot` (it comes back folded; the user unfolded it again).
  - [x] Found + fixed: in Phone Play the fan's drag path (`!isDragEnabled` branch in `FannedHandView`) called `onTapGesture` when a drag began. That expanded the hand or, when already expanded, opened the card sheet mid-drag ("makes the card menu show up instead of letting me drag a card out"). It also used an EmptyView drag preview (the dragged card was invisible). Phone Play now has its own branch: the drag only sets `draggedCard` and uses the system card preview. Classic behavior unchanged.
  - New `testHandStaysThroughBattlefieldDragAndHandDragPlays` (battlefield drag → hand still there, same position, hittable; drag a compact-hand card onto the battlefield → no card sheet, the hand shrinks by one, still visible). PASSES on the SE and the unfolded Duo, plus reorder, Play sheet and foreground (Duo) tests. Duo recording reviewed: the dragged card now shows, lands on the Stack, and the hand stays.
  - [ ] NOT reproduced in simulators: "dragging a card from the battlefield makes the hand disappear" and "it often just won't appear". Simulated drags on battlefield cards use the custom pan (quick drag); a real long-press on device starts the native UIDragInteraction (`BoardViewController.dragInteraction(_:sessionWillBegin:)`) and opens paths the tests don't exercise. Next: get a screen recording from the device (after a clean install of the latest build), then inspect.
  - Tooling note: the UI test target silently stopped rebuilding (binary stuck at 03:30; `-only-testing` ran 0 tests for new methods). Fixed by deleting `DerivedData/.../Intermediates.noindex/Magic Board.build/Debug-iphonesimulator/PhoneBoardUITests.build` and the `PhoneBoardUITests-Runner.app` product. If a new UI test reports "Executed 0 tests", check the xctest binary's timestamp.
  - Duo notes: `XCUIScreen.main.screenshot()` captures the (black) outer display; use `simctl io <udid> recordVideo --display=3` and extract frames with `ffmpeg -vf fps=2` (the recording only writes frames on changes, so `-ss` seeking near the end can be empty).

- "Another thing to add to the list: For JumpStart packs, if it has a front card, don't show the name or colors in text -- they're alredy visible on the front card. For JumpStart pickers without front cards, don't show the "best" card -- it should be a bit of mystery which cards are available. Here, still show the name of the pack, and the colors, but don't show the number (eg, show "Vampires" and not "Vampires 4". And, show the colors as mana symbols, not as words."
  - [x] Front-card-only / mystery tile changes verified 2026-11-15. Both `testMarvelJumpStartLoadsOffline` and `testOfflineJumpInAndArtworkBrowser` PASS (`/tmp/magic-handoff-packets.log`), screenshots reviewed in `/tmp/magic-handoff-packet-shots/`. Marvel shows front cards with no duplicate labels; Jump In shows only theme names and mana symbols. The previous unsigned-debug-dylib launch blocker no longer reproduces with the existing DerivedData; no clean needed.

## Session 6 (2026-11-13): requests verbatim and status (all done except the Duo foreground check)

- (Resumed from a pasted exchange) "It's not quite the newest version, but on a slightly earlier version, on my Duo, I switched back into the app after switching away, and the hand still disappeared. I can see mana costs at the bottom, so maybe it's just misplaced?" (screenshot not available to session 6). The previous agent replied that the latest version pins the hand overlay with constraints and restores layout on foreground (`restorePhonePresentation()`), and was about to check the vertical positioning.
  - [ ] OPEN (needs the user): run on the unfolded Duo sim. Session 6: `testPhoneHandSurvivesForegroundAndAcceptsEmptyHandDrops` only asserted `isHittable`, which a mostly-offscreen card still satisfies. Strengthened it to require the first card's frame to be unchanged (±2pt) after Home + activate. Running on the SE; Duo inner-display run pending (the user must unfold "Magic Board Duo Layout" `2F31FF38-...` in Device Hub each time it boots).
- "Clean up the UI for picking packets for JumpStart. It should use front cards, like the Board Connect app's jumpstart packet picker, and show the three packs side by side horizontally, rather than only listing them out by name, vertically."
  - [x] "Board Connect's picker" = the old `~/Xcode/Magic Board with cocoapods/Magic Board/JumpStartView.swift` (showed the pack's front card, a card from a 4-letter `f…` set). New `Scripts/add_front_cards.py` (run automatically at the end of `build_offline_catalog.py`) adds `catalog.frontCards` {JMP: fjmp, J22: fj22, J25: fj25, TLA: jtla, MSH: fmsc; SuperJump has none} and adds their image URLs to `images`, so the runtime artwork download fetches them (now 12,7xx+ files). `OfflineGameLibrary.packetImageURL(kind:set:name:)` matches the packet theme (strip "Set · " prefix and trailing number; compare letters/digits, with a prefix fallback: "Mill"→"Milling", "Kang Dynasty"→"Kang Dynasty (Theme)"), else uses the packet's highest-rarity non-land card (Jump In, SuperJump). `PhonePacketChoiceView` now shows the three offers side by side as `PacketChoiceCard`s (image + name + colors), titled "Choose First Packet"/"Choose Second Packet", with "First packet: …" above when choosing the second; it's exempt from the auto close button (it re-presents while a choice is pending). The classic `JumpStartView` (non-Phone-Play) is unchanged. Tests updated for the new titles; Marvel, menu deck chooser and Jump In tests PASS; screenshots reviewed (Marvel front cards; Jump In best cards). The Jump In test's stale "2 images bundled" assertion was updated to the runtime-download label.
- "On my iPhone 8, things are very small. This is to be expected somewhat since it's a small screen, but I still feel like the cards on the field could be bigger, with less padding between them. There should still be a pleasing amount of padding and spacing, but the cards can be bigger as well." (Screenshot: iPhone 8 landscape 667×375; battlefield creatures ~50pt cards with large gaps; land rows small at the left; lots of empty space.)
  - [x] Column layout in `layoutPhoneBattlefield`: when the land rows' content is narrow, the battlefield uses the full height between the bars, to the right of the lands (`columnVisible`), and stays clear of the compact hand's top (`view.height - 0.44*handHeight`). It's chosen only if its fitted extent (shrunk so the largest row fits without paging, accounting for the Stack inset) beats the row layout by more than 5%. The land edge comes from `LandOrganizerViewController.landContentFrames` (window coordinates; `onLandContentChanged` deferred with `DispatchQueue.main.async`) with a per-game reservation that only grows, with 1.5 card widths of slack (`phoneLandReservation`), so land taps (stack splits) never move the battlefield. Land rows are `PhoneLandContainerView`s (storyboard customClass for the local one; a code wrapper for the opponent's, pinned with constraints because the organizer view uses Auto Layout) whose `point(inside:)` only accepts touches on actual land stacks. Spill is reserved for fanned duplicates/attachments only when present; card gap 40→20 world units. SE fixture cards are ~75pt (were ~45). PASS: battlefield overlap test (now checks the actual land stacks, not the full-width rows), land tap fixed-frames test (now compares all creature frames, sorted), crowded paging, quick drag, attach drag, tapping/arrows, HUD dump. Screenshot reviewed.

- "Adjusting the properties' colors for a land should override its frame colors. No colors set should use the default frame colors for it."
  - [x] `MTGCardView.CardProperties.applyFrameColors(_:isLand:defaults:)` (bottom of MiniCardView.swift): a land with no colors set keeps its default frame colors (from the mana it makes, computed by `MTGCardView.properties`); any colors set override them. Non-lands are unchanged (instance colors). `MiniCardView` stores `defaultFrameColors` and re-applies on `cardInstance.colors` changes; before this, the colors subscription replaced a land's frame with its empty instance colors. `SwiftUICardView` (land organizer) now observes `card.colors` and applies the same rule. Inspector color buttons have ids `card-color-w/u/b/r/g`. `testLandColorPropertyOverridesFrame` PASSES; screenshot: the local Island turns red, the opponent's stays default blue.
- "Commanders in the hand view should be shown off to the side a bit, and their mana costs should include the commander tax, and the card should glow yellow, all just like in the Board Connect app's hand view."
  - [x] Shared `FannedHandView`: in Phone Play the first command-zone card gets leading padding `gap − spacing` (gap = 0.3 card width), with the hand's spacing solved so the row still fits (`hasCommandGap`, `commandGap`). The old flexible spacer is non-phone only, since it collapsed in the exact-width phone fan. The last hand card counts as uncovered, so its cost uses its true corner. The commander glow scales with card height (`max(3, 3% of height)`). The floating cost shows tax like Board Connect: `{tax}+cost` when `commanderCasts * 2 > 0` (`displayedCost`). Fixture flag `--phone-board-commander` (Dandân commander, cast once) + `testCommanderShowsBesideHand` PASS; compact and expanded screenshots reviewed. `testBigHandFitsOnScreen` still PASSES.
- "Add small subtle + and - icons to the ends of the life tracker so it's clear that they're buttons."
  - [x] Added: SF Symbols minus/plus at the left/right ends inside `LifeTracker` (white 35% opacity, size ~20% of height, non-interactive, hidden from accessibility). Applies to classic and phone. [x] Seen in screenshots (both life boxes).
- "Support only landscape for the board, but support rotating vertically when a sheet is presented to view a stack like the library, graveyard, etc."
  - [x] Info.plist (both keys) now also lists Portrait; `BoardViewController.supportedInterfaceOrientations = .landscape`; Phone Play pile sheets on iPhone are presented `.fullScreen` in `PhonePortraitNavigationController` (`.allButUpsideDown`) instead of a popover (BottomBarViewController.viewPile). `testBoardIsLandscapeButPileSheetsRotate` PASSES (the board ignores portrait; the open library sheet rotates; closing returns to landscape). Portrait screenshot reviewed. Other presented sheets keep UIKit's default orientation behavior (not separately checked).
- "On iPhone 8, where sheets can't be dismissed on their own by dragging, there's no way to close a sheet once it's been opened."
  - [x] `UIViewController.addPhoneCloseButtonIfNeeded(to:)` (PhoneSessionControllers.swift), called from `present` overrides in BoardViewController, BottomBarViewController and PileViewController. Phone Play only. Nav sheets get an ✕ (`phone-sheet-close`) in the empty left slot, or at the trailing end when the left is taken (the pile sheet's Shuffle); other sheets get a floating `UIButton(type: .close)`. Skips alerts, share sheets, document/image pickers, `PhoneSheetProvidesClose` types, hosting views marked `view.accessibilityHint = PhoneSheet.providesCloseHint` (card inspector, Offline Games), and nav roots that already have a Done/Close/dismiss item. New `testPileSheetHasCloseButton` PASSES on SE.
- "Add keyword counters into the list of counters. Adding one should show the keyword as a tile on the card, tinted blue like how Arena does. I think there's already code for that style of tile? Include all the standard keyword counters that could be used. Flying should activate the flying animation appropriately."
  - [x] `Counter` gains decayed/exalted/haste/shadow (appended after `stun`; raw values of existing cases unchanged) + `keywordCounters` (all 15 keyword counters from CR 122.1b) + `keywordIcon` (`MTGCardView.Icon.counter(...)`; the existing blue `icon-counter` plate + white glyph; shadow/exalted use template SF Symbols). `MiniCardView.properties` setter strips and re-inserts counter tiles (after any commander tile) from `cardInstance.counters`, re-applied on counter changes; the flying wiggle/scale triggers on `isFlying || counters.contains(.flying)`. Counter palette: a full-width "Keyword Counter" capsule button (third row, `counter-add-keyword`) whose menu lists all keyword counters. Fixed a latent bug: the palette's generic button colors used `Counter.allCases.suffix`, which appending cases would have shifted; now they use the same `rawValue = index + 12` mapping as the button taps. `testKeywordCounterFromPalette` PASSES (adds Flying + Deathtouch; screenshot shows the blue feather/skull tiles and the flying lift). `SwiftUICardView` (land organizer) doesn't draw counter tiles.
- "After fixing all of the requested issues, do a pass through everything to polish it up UI and UX."
  - [x] First polish pass done. Full SE regression PASSED before it (`/tmp/magic-full-s6.log`: PhoneGameTests 35/35, PhoneBoardUITests 27/27); all 28 screenshots reviewed. Fixed: (1) duplicate ✕ + Done on sheets whose controllers add their own Done in viewDidLoad (NearbyGamePicker, PhoneStack, BoardMenuSheet, PhoneHandCard now conform to `PhoneSheetProvidesClose`); (2) the counter palette's black loyalty shield was invisible on the dark sheet (soft white glow; the button no longer clips); (3) row page buttons ("1–6 ›") sat over cards next to the Stack: a paging row now reserves 76pt at its end and the button sits just past the last card. Re-verified: crowded paging, hand Play sheet, counter palette, battlefield overlap PASS; screenshots reviewed.
  - Possible further polish (not done): the crowded board shows 4 groups/page (was 6 with the button overlapping), and could use the empty left area; the 15-item keyword menu needs scrolling on short landscape screens (a two-level or grid picker would be nicer); `SwiftUICardView` (land rows) doesn't draw keyword counter tiles; the classic (non-Phone-Play) `JumpStartView` still lists names.
- Foreground check on SE with the strengthened frame assertion: PASS (`/tmp/magic-fg-se.log`).

## Session 5 — completed follow-ups and successful iPhone 8 installation

User prompts, verbatim:

- "Tapping a card on the battlefield causes it (and the whole row) to shrink."
- "Can you implement dragging a card ontop of another one to attatch it to the card it's dropped onto?"
- "After doing that, remove the "Attach to..." menu item. Also change Detach to Unattach."
- "Remove the separate "Attack and Tap" and "Attack without Tapping" rows. Just don't tap it when choosing to attack if it has vigilance. In fact, remove the attack and block rows entirely -- I plan to overhaul combat. But keep the code for highlighting things as attackers, as we'll continut to use that later. Although, change how attackers are rendered -- show the orange/white arrow, as MTG Arena does."
- "Another thing -- I'm trying to test this on my iPhone 8, running iOS 16.7.15. It should run, but Xcode isn't seeing it as a run destination."
- "So how can I load it onto that device to test? I don't need to debug there, but I want to install it."
- "Work on your other changes first."

Completed UI/model changes:

- Tapped footprint is now always reserved, and density sizing groups ignore tapped state. Actual grouping still separates tapped/untapped cards. Tapping never changes the card scale; the short-screen UI test readability bound is 48pt to fit the constant rotation/attachment footprint (64pt nominal extent still used before the viewport cap).
- New host-authoritative `attachDroppedCard` action supports hand/zone-to-field + attachment atomically, preserves battlefield cards' state, and rejects cycles. Native drops hit-test actual card bounds; custom battlefield/land pans use the same target resolution. Root-view drop interaction handles organizer targets. Land stacks report global rectangles and render their attachments behind the lands in the same row. Nested attachments are collected recursively for battlefield rendering and inspector pages.
- Removed Attach to…; renamed Detach to Unattach. Removed attack, block, and End Combat rows. Combat model/actions remain for the future overhaul. Attack highlight is now a white chevron with orange stroke/glow, above local attackers and below opponent attackers, instead of a red border. Blue blocking border logic is retained internally. Fixture flag `--phone-board-attacking` exercises the visual state without combat menu rows.
- Inspector pages now use stable card UUIDs, not positions, when removing an attachment page. Added a native Done button and selected-card title; compact full-screen sheets couldn't reliably be dismissed by swiping down. An initial UI assertion expecting no Unattach button after a page removal targeted an offscreen/stale inspector; the finalized test closes explicitly, asserts actual battlefield hit targets, and uses a quick pan (0.05s) for the field drag rather than a long press that opens the inspector.

Verification:

- PASS: Deck Ready removal / automatic local chooser dismissal (`/tmp/magic-no-deck-ready.log`).
- PASS: attachment from hand, nested attachment traversal, cycle prevention, and tap-invariant sizing groups (`/tmp/magic-drag-attach-combat.log`, model tests).
- PASS: actual card side length unchanged through tap/untap, other row frames unchanged, attacker arrow visible, all combat/Attach to rows absent (`/tmp/magic-drag-attach-combat.log`, tap UI check). Arrow screenshot reviewed at `/tmp/magic-attack-arrow-check/1E69930F-E596-457C-BA4C-E2C3AB42801E.png`.
- PASS: native hand-to-card drag, Unattach, compact Done dismissal, actual quick battlefield-to-card drag, reattachment, base/attachment page switching and circular counters (`/tmp/magic-attach-final.log`).

Device install investigation:

- App and framework deployment targets remain iOS 16.0. This Mac uses macOS 27.2.1 / Xcode 27.1; Apple's table lists device debugging only on iOS 17+ for Xcode 27, while deployment still includes iOS 16: https://developer.apple.com/xcode/system-requirements/ . Xcode 26 supports iOS 16 device debugging but is listed only for macOS 26.x, not this Mac's OS.
- `ios-deploy` already installed at `/opt/homebrew/bin/ios-deploy`, and it detects the iPhone 8 over USB on iOS 16.7.15. Install-only route is `ios-deploy --id <device-UDID> --bundle '<signed app path>'` without `--debug`. Existing Debug-iphoneos app had no embedded provisioning profile, so it couldn't simply be installed as-is.
- As requested, finished UI work first. Signed generic iOS device build PASSED in `/tmp/magic-iphone8-device-build.log` (reuse main DerivedData). Verified physical iPhoneOS platform, minimum iOS 16.0, strict/deep signature validation, and that the embedded profile includes the iPhone 8 (expires 2027-11-05). Installed successfully over USB with ios-deploy, without --debug or --uninstall, preserving app data. `/tmp/magic-iphone8-install.log` ends with `[100%] InstallComplete` / `Installed package`. User can open Magic Board from the Home Screen. No Xcode device-support patch, older Xcode install, IPA export or Configurator was needed.

## Follow-up — remove Deck Ready

User: "Remove the "Deck Ready" screen entirely."

Removed the completion/waiting screen from PhonePacketChoiceView. BoardViewController dismisses the packet chooser as soon as the local player completes their choices, even while the other player is still choosing, and doesn't reopen it for a completed selection on resume. Both-decks-ready text and Return to Battlefield button are removed too. Existing packet UI checks now assert automatic dismissal and absence of Deck Ready. Focused check PASSED: `/tmp/magic-no-deck-ready.log`.

## Session 4 — hand lifecycle, background, attachment paging, counters (implemented; focused SE checks pass)

User requests and clarifications, verbatim:

- "I can no longer see any cards in my hand, at all. I also can't drag cards into the hand area."
- "Phone Play. I did resume game, then reset it and loaded a Jumpstart deck."
- "Tapping or untapping a land makes the background change" (two screenshots show the planeswalker logo changing size).
- "I restarted the app and started fresh and saw the hand. But after switching away from the app and coming back, the hand disappeared."
- "Question: Is it easier for you to just replace the UIKit/SwiftUI views with a new implementation that doesn't use native components?"

Answer given during work: a nonnative rewrite adds touch, drag/drop, accessibility, and lifecycle work; the problem is the overlay's integration, not native controls themselves. Continue fixing the native hierarchy.

Additional requests, verbatim:

- "Instead of an "Attached Cards..." menu item, make the left-hand pane, with the card image, a page view, starting with the base card, and then paging through the attatched cards. Changing which card is being viewed should change the right-hand pane's contents to view the controls for that card."
- "The counters menu is all weird -- these should be circles, but they look like blobs. And the spacing is  a little messed up."

Implementation:

- Replaced manually assigned hand/container frames and child autoresizing with explicit root overlay constraints and four hosting-view edge constraints. The hand remains a separate sibling of the HUD and only SwiftUI expansion animates. Foreground scene activation refreshes Phone Play layout through `restorePhonePresentation()`.
- Added a native UIDropInteraction to the hand container itself, delegated to HandViewController. An empty SwiftUI fan has no card hit regions; previously only the hosting view/cards were drop targets, leaving the empty container without a reliable receiver.
- Reparented the existing planeswalker logo into the fixed screen background below the scrolling battlefield; its frame now depends on the scene/bar geometry, never card zoom. Tapped-card footprint calculations now ignore lands drawn in the organizer, so tapping a land doesn't resize battlefield cards either.
- New focused UI checks cover background/foreground with populated and empty hands, native library-to-hand drops, expansion after drawing, and background + creature frame equality through land tap/untap. SE hand checks pass in `/tmp/magic-hand-foreground.log`; land checks pass in `/tmp/magic-inspector-paging.log`. Earlier session 3 tests did not cover app backgrounding or an empty hand.

Current verification / inspector changes:

- SE hand foreground/drop check PASSED for both populated and empty hands in `/tmp/magic-hand-foreground.log` (70.9s). The land test's first assertions confirm fixed background/creature frames; its later query incorrectly expected all five Islands to tap, while tapping a stack only taps one card. Corrected the target to `Island, 1, tapped`; no application change for that test failure.
- The normal inspector now builds a page per base/attached card. Its left native page-style TabView starts at the base; changing the page selects that card's own controls, modifiers, counters, rulings, and remembered right-pane page. Detached cards are removed from the pager. Removed the obsolete Attached Cards action/controller. Existing hand-card Play inspector stays as before.
- Counter palette: moved existing buttons/targets into a header laid out at its actual pane width, with consistent 10pt gaps and 12pt padding, square circular buttons, and radius recalculated after layout. Loyalty retains its shield aspect. Header height follows button size so the counter list doesn't overlap the palette. The old radius was calculated before final layout and the header height was fixed, producing blobs/clipping when the pane resized.
- Inspector/counters test PASSED in `/tmp/magic-inspector-final.log`; corrected land tap/untap test PASSED in `/tmp/magic-inspector-paging.log`. The first inspector run used an earlier test assertion that expected the right pane to reset, whereas the app deliberately restores each card’s remembered pane; corrected the test and recompiled, without an application change. Counter screenshot `/tmp/magic-counter-pager-attachments/68BB2D94-FB7D-452F-B266-BB49DD38C059.png` reviewed: circular buttons and clean spacing. The attachment preview is blank only because the Feral Invocation fixture has no artwork URL.

Session 4 final validation:

- PASS: populated hand survives Home/background/activate, empty hand accepts first native library drop, added cards are visible/hittable and expand (`/tmp/magic-hand-foreground.log`, hand test).
- PASS: land tap and untap preserve exact background + creature frames (`/tmp/magic-inspector-paging.log`, land test).
- PASS: left-page swipes select attachment controls, counter circles have equal width/height and remain within the pane, adding a counter works, base/attachment switching restores each card's controls page (`/tmp/magic-inspector-final.log`). Circular palette screenshot reviewed.
- The extra iPhone 17 Pro run (`/tmp/magic-lifecycle-inspector-home.log`) stalled during simulator startup for about three minutes, and a screenshot request blocked for about a minute. The simulator eventually began launching the runner as the run was being stopped; no functional test result from this extra run is claimed. Stopped it instead of retrying simulator tools/rebuilding. SE focused interactions are the verification for this session. Physical Duo foreground behavior still needs the updated app on the device.
- No commits or pushes. No nonnative rewrite. Updated the original broad phone-board UI test to use attachment swiping instead of the removed Attached Cards menu.

## Session 3 — 2026-11-13 (all requests from this session implemented and verified)

New user requests, verbatim:

- "The current issue: Expanding and minimizing the hand view causes the untap button and life total to animate and move positions. They should not ever animate."
- "When starting a phone play game, before loading a deck, the life tracker is mispositioned. Actually I just tried after loading and it's still misaligned."
- "After loading a deck through JumpStart, then resetting the board, it then shows a "your deck is ready" sheet and I can't seem to load a different Jumpstart deck until I close the app."
- "The hand, when expanded, still animates weirdly up and down, with a slight horizontal movement as well."
- "The floating mana costs above the cards. Compare how they look to how it looks on Arena."
- "Also: The positioning of the gaveyard, library, and exile still look wrong. They should have equal padding on all edges, but have no padding on top currently. They should all fit cleanly into the bottom bar."

Additional user requests, verbatim:

- "Another thing to add to the list: For JumpStart 2022, use J22 basics. Marvel and Avatar get their own set's basics. SuperJump keeps its Theros Beyond Death basics. All other JumpStart sets without anything more specific should get Foundations basics."
- "And: Rounded corners in the card previews in the card menu and hold down menu."
- "And another thing: Cards can overlap each other on the battlefield. Fix that as wel" (screenshot shows Control Magic intruding into the local land row).
- "And: Update the DanDan list to use the list and printings from the Secret Lair dandan deck: https://secretlair.wizards.com/us/en/product/1249043/secret-lair-dandan-deck"

Recordings inspected as frame strips: `/Users/compc/Downloads/ScreenRecording_11-13-2026 00-28-14_1.mov` (2.45s), and `00-31-13_1.mov` (3.28s, Arena). The first clearly shows the untap symbol SHRINKING while life slides DOWN; prior outer frame assertions missed the visible contents. Arena uses smaller costs above the actual top-right card corner with a dark background, not the uncovered left strip.

Implementation:

- Local hand container and HandViewController reparented to BoardViewController, entirely outside the HUD hierarchy. Its UIKit frame is constant during expansion. SwiftUI receives explicit compact/expanded fan dimensions and animates once (0.22s ease-in/out, Reduce Motion respected). Removed UIKit whole-board animation and the geometry-triggered SwiftUI animation. Empty overlay areas pass taps through using `phoneContentFrame`.
- Both bars are now exactly `barHeight` (no old compact hand lift in the bottom bar). HUD heights use the same metric even before the first layout. Life hosting controllers disable safe-area regions on iOS 16.4+, and LifeTracker no longer expands through safe areas. This is set during phone refresh, since the initial hosting-controller bind happens before the phone session starts. Pile label widths have symmetric 5*scale horizontal padding.
- Costs are smaller (7.5% card height, cap 22pt), dark capsule backing, right-aligned above the actual card corner; costs remain in the separate top rendering pass.
- Reset Game in Phone Play now sends a host-authoritative `.reset` action instead of replacing the storyboard while leaving PhoneGameSession alive. Clears packet selection, decks, stack, combat, etc., starting a fresh game ID so queued edits/choices from the old board are discarded while the nearby connection stays active. The chooser ID is cleared when selection ends. Added `testResetClearsCompletedPacketSelectionAndAllowsAnotherDeck`.
- Verification: reset regression PASSES in `/tmp/magic-phone-overlay.log`. First run caught the opponent hand z-order `else if` also running for the detached local hand and pulling it back into the bar; corrected to `else if !isLocal`. The initial run's expansion failure was this real code issue (not tooling). Corrected SE run PASSED: host + guest expand/collapse with static HUD and tap shielding, 15-card screen fit, reorder/play, HUD dump, reset regression. Actual animation recording `/tmp/magic-hand-overlay.mp4` reviewed as strips (`/tmp/overlay-motion.jpg`): costs have dark backing, hand grows/collapses over the HUD; no HUD movement. First-run HUD screenshot already confirms balanced pile content padding and matching life box alignment. Simulator tools require sandbox escalation; the initial un-escalated simctl failure was a sandbox issue.

Additional implementation:

- JumpStart basics: original 2020 packets and Foundations JumpStart now use FDN regular basics (272/274/276/278/280). J22, TLA, MSH retain their set-specific printings. SuperJump retains THB full-art lands; its one stray NEO Island is now THB 251. Source lists and offline catalog updated. Import script preserves the J25/SuperJump policy on refresh.
- `Dandan.txt` now contains the official 80-card Secret Lair list, all exact SLD printings 2138–2164 (27 distinct printings). Five each of Fish 2138/2139 and Islands 2144–2147. Source: https://magic.wizards.com/en/news/announcements/from-the-chaos-vault-secret-lair-dandan-decklist (product URL returned 403, Wizards article provides full list). Catalog includes metadata and runtime image URLs for the new printings; no artwork was bundled or downloaded. Catalog now 6333 unique cards / 12778 image files. Added `--metadata-only` to the builder. Note: its cache uses `tempfile.gettempdir()` (macOS per-user T directory), NOT necessarily `/tmp`.
- CardImageViewController masks the actual aspect-fit card rectangle with a rounded path, recomputed after layout and image load. Previously only the UIImageView's larger letterbox frame was rounded, leaving the card corners square. Pile hold-down previews now reuse that controller. Screenshot attachment added to existing hand-menu test.
- Deck/preview checks: `/tmp/magic-decks-preview.log` PASSED (four model checks + hand-menu play interaction); policy checks cover every packet's basics, exact Secret Lair printings/counts, 20-card packet totals, and offline DanDân dealing. UI check opens hand menu and plays tapped land.

- Battlefield overlap fix: fractional support centers (.18/.88) and creature centers (.25/.76) did not reserve card height, so support cards extended into lands and into creature rows. Both players now get bounded half-field bands; support and creatures have separate horizontal lanes within each band. Card extent fits the band's entire footprint (group offsets, attachment offsets, tapped rotation), horizontal capacity includes that footprint, and groups page instead of overlapping. This can take cards below the old 64pt viewport floor on short phones; existing UI readability floor is now 56pt. Added `--phone-board-support` fixture and an interaction test checking actual support/creature/land frames before and after tapping. Final checks PASSED in `/tmp/magic-battlefield-final.log` (SE) and `/tmp/magic-phone-home-indicator.log` (17 Pro). The first collision-test run mistakenly asserted against deliberately fanned identical token copies; corrected the test to compare separate groups. No application change was needed for that assertion.

Final validation:

- SE: static HUD through host/guest hand expand/collapse, tap shielding, 15-card screen fit, reorder/play, reset regression (`/tmp/magic-phone-overlay.log`); deck policy, all 20-card packets, exact 80-card Secret Lair printings and offline dealing (`/tmp/magic-decks-preview.log`); support/creature/land separation before and after tapping, plus crowded paging (`/tmp/magic-battlefield-final.log`, crowded paging passed in the first `/tmp/magic-battlefield-fit.log` run).
- iPhone 17 Pro iOS 26.5: reset regression, battlefield separation including tapped creature, matching HUD insets, host+guest expansion/collapse all PASS in `/tmp/magic-phone-home-indicator.log`. HUD controls 42pt high, 5pt from bar edges; local life y=355–397 within the 350–402 bar, opponent y=5–47 within 0–52. Screenshot reviewed.
- Final mana/preview visual check PASS in `/tmp/magic-preview-final.log`. Actual rounded card image verified in `/tmp/magic-cost-preview-final/D4B8B9D7-C579-447C-9C6E-232E8BA7E2D7.png`; compact mana labels now have a snug dark backing (explicit symbol-sized font avoids inherited body line height). The fixture originally omitted large-image URLs, causing the preview screenshot to be blank; added a large URL alias to its normal image without changing production loading. Card-menu/hold-down previews share the rounded renderer.
- Python scripts parse successfully; all changed Swift sources build. No commits or pushes. No real-device Duo run was available in this session; the structural hand isolation replaces the earlier shared-bar implementation.

The older START HERE and session 2 structure below describe the PREVIOUS implementation and are retained for context; use this section for current structure.

## Prior investigation: untap button / life tracker movement (resolved in session 3)

**The user will send you a video** of the life tracker and untap button moving as they expand and minimize the hand. Watch it first, then work out what moves, in which direction, when (expand, collapse, or both; during the animation or after), and which side (host or guest).

**What the user said (verbatim, in order):**
- "Just checked myself, and the behavior of the hand expanding and minimizing is terrible. It shifts around the other things in the row (the graveyard, library, exile, untap button, life tracker). The hand cards should NEVER move those things around. Those things should NEVER move. They should be static. The hand cards should be drawn above the rest of those things so it can safely expand and minimize when needed."
- "I still see the untap button and life total buttons move out of the way when the hand is expanded"
- "They should never move. They should not be part of the same stack as the hand. The hand should be drawn on top of that area."
- Device: "Real device, latest build, on iPhone Duo" / "unfolded" (inner display).

**What the user wants:** the HUD controls (graveyard/library/exile piles, untap button, life tracker) are completely static, independent of the hand ("not part of the same stack"). The hand is drawn on top of that area and expands/collapses over it. Note the user's wording "move out of the way"; the old (pre-fix) behavior did push them, because expanding resized the whole bar.

**Current structure (as of session 2):**
- The local bar is `BottomBarViewController` (embedded in `player1/2BarContainerView` in BoardViewController). Its view (`PlayerBarHitAreaView`, storyboard id `6ET-ee-pWt`) contains as SIBLINGS: the three `HUDCardPileView`s, `untapButton` (`WDS-YZ-bCW`), the life tracker container (`bIq-nX-Lx7`, hosts SwiftUI `LifeTracker` via an embed segue) and `handContainerView` (`CzI-qE-FrI`, hosts `HandViewController`, SwiftUI `FannedCardHandView`).
- `refreshForPhoneSession()` (`Magic Board/BottomBarViewController.swift:474`) deactivates the storyboard's vertical constraints for piles/life/untap and `untap.leading = hand.trailing + 54`, then pins each HUD control `bottom = bar.bottom - hudPadding`, `height = rowHeight - 2*hudPadding` (lines ~520–548), with `life.trailing = bar.trailing - 4` and `untap.trailing = life.leading - 8`. So no active constraint ties them to the hand any more.
- Expanding: `HandViewController.phonePresentation.isExpanded` (`HandViewController.swift:70`) → `onChange` in `BoardViewController.swift:2017` → `updatePhoneHandShield()` + `UIView.animate(0.25) { refreshForPhoneSession(); view.layoutIfNeeded() }`. The bar container height is now CONSTANT (`BottomBarViewController.phoneHandLift(expanded: false…)` in `layoutPhoneBattlefield`, `BoardViewController.swift:2090`); expanding only changes the hand's own constraints: top constant `-overflow` (line ~596), height, and width (expanded = scene width minus margins), plus `bringSubviewToFront(handContainerView)` (line 565). The SwiftUI fan also animates via `.animation(.easeInOut(duration: 0.25), value: proxy.size)` (`FannedHandView.swift:140`).
- `PhoneHandShieldView` (`PhoneSessionControllers.swift:336`) is a full-screen overlay shown only while expanded; it swallows taps outside the hand.

**What was verified (none of these reproduce the bug):**
- iPhone SE (iOS 17.5), iPhone 17 Pro (iOS 26.5, home indicator), iPad Pro 11 (no Auto Layout conflict logs), and the iPhone Duo sim UNFOLDED ("Magic Board Duo Layout" `2F31FF38-61BB-4280-B027-756A737A03F2`, inner window 951×669pt): `testPhoneHandExpandsAndCollapsesWithoutMovingBattlefield` (host + guest) PASSES. It asserts untap/library/life frames are equal before and after expanding, and samples them right after the tap.
- Frame-by-frame recordings (iPhone 17 Pro and the unfolded Duo, host): untap/life are pixel-identical through expand and collapse; the expanded hand just covers the untap button.
- Not ruled out: (a) the user's device build being stale (ask them, or have them delete the app + Clean Build Folder; note the bundle changed a lot: artwork is no longer bundled); (b) guest side (the Duo guest recording only showed the relaunch, though the guest frame assertions passed); (c) things the tests don't cover: many cards in hand, Hand Only/Board Connect mode, after folding/unfolding or rotating, a real hinge/reserved region, real game data instead of the fixture; (d) movement caused by something other than constraints, e.g. a SwiftUI re-layout inside the life tracker hosting view, safe-area changes when the shield/hand appears, or the bars' transforms in `layoutPhoneBattlefield` (`translate(...)` only assigns when changed).

**If you can't find a precise cause from the video, do the structural fix the user asked for:** take the hand out of the bar's view hierarchy, or the HUD controls out of it, so they share no superview whose layout changes. Options:
1. Keep the HUD in the bar; move `handContainerView` into a dedicated overlay view in `BoardViewController.view` above the bars (pinned to the screen bottom/center), sized and positioned only by its own constraints. Careful: it hosts the child `HandViewController`, so keep the VC containment consistent (the child's view must stay inside its parent VC's view hierarchy, or re-parent the child VC to BoardViewController); expect to update `PlayerBarHitAreaView` hit forwarding, `PhoneHandShieldView.passesThrough`, hand drop interactions, and the `phone-local-hand` accessibility id.
2. Or drop the UIKit `UIView.animate` wrapper so only the hand's own SwiftUI animation runs (the HUD can't animate if nothing in the bar is animated). Cheaper, but doesn't satisfy "not part of the same stack".
Then re-run the hand tests on SE + the Duo sim and record video again.

**Duo simulator how-to:** sims boot FOLDED. Open Device Hub (`open -a /Applications/Xcode.app/Contents/Applications/DeviceHub.app`) and unfold (pose control; ⌥-click for a hinge slider); there's no Apple CLI. Displays: `xcrun simctl io <udid> screenshot --display=1 out.png` = outer, `--display=3` = inner; `recordVideo --display=3 --codec h264 --force out.mp4` (stop with `pkill -INT -f recordVideo`). Run UI tests with `-destination 'platform=iOS Simulator,id=2F31FF38-61BB-4280-B027-756A737A03F2'` (build-for-testing, then test-without-building). A manual `simctl launch … --phone-board-fixture` on the Duo showed the classic board; the UI tests start Phone Play fine. Frame strips: `ffmpeg -ss <t> -t 4 -i in.mp4 -vf "fps=6,crop=W:H:X:Y,scale=300:-1,tile=4x6" -frames:v 1 out.png`.

**Session notes:** background shell tasks die when the session/computer restarts; run long xcodebuild commands in the foreground (600s timeout). After a reboot /tmp logs are gone.

**Latest full check (session 2, after all changes):** SE: PhoneGameTests 31/31 + 5 focused UI tests PASS (`/tmp/magic-final-se.log`); `MagicBoardConnect` builds. iPhone 17 Pro iOS 26.5: hand host+guest, library drag, layout dump PASS.
**Remaining open:** bottom-edge swipe deferral (`preferredScreenEdgesDeferringSystemGestures`) can't be exercised by XCUITest; it needs a real device. Source-sized battlefield drag preview not visually checked.

## User requests, verbatim (session 2, 2026-11-12), with status

Keep this list current. Quote new requests word for word and track each one here.

1. > "Read Docs/PhonePlayHandoff.md and pick up from where it left off. Update the document as you go to check off completed tasks and record important findings so that when my usage here runs out, another agent is able to pick up from where you left off. This is a fun project for personal use, so don't go overboard with testing and stuff."
   - Ongoing.
2. > "Keep going on the still open things. You shouldn't have stopped when there are still things to do"
   - Ongoing. Don't stop with open items; keep working through the checklist.
3. (User pasted the earlier Codex transcript and asked) > "Are all the things I asked for implemented?"
   - Audit: everything in that transcript is implemented. Not visually checked: bottom-edge swipe deferral (needs a home-indicator device) and the source-sized drag preview.
4. > "Just checked myself, and the behavior of the hand expanding and minimizing is terrible. It shifts around the other things in the row (the graveyard, library, exile, untap button, life tracker). The hand cards should NEVER move those things around. Those things should NEVER move. They should be static. The hand cards should be drawn above the rest of those things so it can safely expand and minimize when needed."
   - [x] Fixed: the bar is a constant height and the hand overflows upward (details in the checklist below). PASS in `/tmp/magic-static-hud.log`, including mid-animation HUD frame samples, host and guest.
5. > "Tapping outside of the hand when it's expanded should minimize it, which it already does, but it shouldn't result in anything else receiving taps as well."
   - [x] Fixed with `PhoneHandShieldView`. PASS: tapping a creature while expanded collapses the hand and leaves the creature untapped.
6. > "Large stacks of stacked tokens show the "x5" quantity banner *underneath* the stack of tokens, so you can't even see it."
   - [x] Code fix (badge zPosition 1000 + re-fronting). Badges visibly on top in the SE screenshot; the token-copy test passes. (A large runtime-created stack was not screenshotted separately.)
7. > "There is inconsistent padding EVERYWHERE, around the land rows for you an dopponent, on the untap and life tracker buttons, which also appear at different sizes between yours and your opponents'... There's extra padding on the bottom of the grayeyard/library/exile, and zero padding on the top of them... lots of graphical issues which need to be polished up."
   - The user's screenshot is from a device with a home indicator. Seen in it: local Swamp land row flush to the left edge (x≈12pt) while the opponent's lands and the local support row start at x≈46pt; pile tiles touch the top of the bar with spare space underneath (block ~10pt too high, about half the bottom safe inset); the life boxes differ (opponent's is wide and short, local is tall); the `{Q}` untap symbol is smaller than life and sits off-center; the bars differ in height.
   - Root causes found in code: the bars use different height formulas (top `min(90,max(40,0.105h))`, bottom `min(124,max(52,0.12h))`); per-control ad-hoc heights/insets (`rowHeight`, `-8`/`-4` for life, `-20`/`-10` for untap); the pile preview is sized for `commonRowHeight`, not the row height; `LifeTracker` has `.ignoresSafeArea(.container, edges: .bottom)` in phone mode (so the local box extends into the home-indicator inset); the local land organizer container uses storyboard horizontal constraints while the opponent's uses `safe.left + 8`.
   - [x] Code changes made (session 2): top bar = same `barHeight` as the bottom bar and sits at `safeAreaInsets.top` (no extra +8); every HUD control has height `rowHeight - 2*hudPadding` and bottom inset `hudPadding` (`5*uiScale`); the untap button image fills its button (`contentHorizontal/VerticalAlignment = .fill`, aspect fit); pile previews are sized from `controlHeight`; `LifeTracker` ignores ALL safe areas in phone mode; the local land row is translated to `safe.left + 8` like the opponent's; both land rows use `landGap = 6*uiScale` from their bar (also used for battlefield `bottomY`). Verified on SE (`/tmp/magic-hud-polish.log`; /tmp is wiped on reboot): `testDumpPhoneHUDLayout` frames are symmetric (every control 5pt from its bar edge, 42pt tall; both life boxes 71×42; both land rows at x=32 with a 6pt gap to their bar); hand expand, quick-drag and token tests PASS; screenshot reviewed. [x] Also verified on the iPhone 17 Pro iOS 26.5 sim (`AC360DEA-B5CC-4D10-AE17-FD796376517C`, home indicator, safe insets L/R 62, bottom 20): symmetric frames (controls 5pt from bar edges, land gaps 6pt), screenshot reviewed; hand host+guest, library drag and dump PASS.
   - **Found and fixed while verifying: an infinite layout loop as GUEST on home-indicator devices** (100% CPU, UI tests time out with "Timed out while evaluating UI query"). `layoutPhoneBattlefield` reset the bar/land container transforms to `.identity` each pass. For the guest, the local bar is `player2BarContainerView`, whose storyboard home is the TOP, so the reset flipped its safe-area insets (bottom 0 ↔ 20), the hosted SwiftUI views re-laid out, and viewDidLayoutSubviews ran again forever. Fix: no identity resets; compute the untransformed frame from the current translation (`untransformedFrame`) and assign the transform only when it changes (`translate`). Diagnosis: `sample <pid>` showed viewDidLayoutSubviews→layoutPhoneBattlefield on every CA commit; NSLog was rate-limited (only 7 identical lines), so check CPU (`ps -o %cpu=`) instead of trusting the log count.
   - Original TODO notes: one shared metric for both bars (same bar height H, same vertical padding on every control, life and untap the same height, piles centered); make LifeTracker fill its container exactly (ignore all safe areas in phone mode); align the local land row's left edge with the opponent's row and the battlefield (`safe.left + 8`), with symmetric gaps between land rows and bars. Measure on a home-indicator sim using `testDumpPhoneHUDLayout` (prints `HUDDUMP` frames + screenshot). The 15 Pro iOS 17.5 sim is broken; try an iOS 26.5 iPhone 17 Pro (`AC360DEA-...`). The built `.app` installs on any sim runtime.
8. > "Floating mana costs over cards in hand often appear unclear which card they're attatched to." (compared to MTG Arena screenshots)
   - In Arena, costs are right-aligned at each card's top-right, centered on the card's top edge, rotated with the card. Ours floated a full symbol height + 3pt above the card at its far-right corner, which the next card covers, so costs appeared over the neighbor.
   - [x] Code fix in `FannedHandView`: phone mode passes `visibleWidth` (card width + negative spacing, or full width for the last card); the cost is right-aligned within that uncovered strip with a small inset, offset up by half a symbol so it straddles the top edge. Classic/Board Connect keeps the old placement. [x] Screenshots (compact + expanded) reviewed on SE: costs sit on each card's own top-right edge.
9. > "As you update the handoff document with my requests, include my original prompts, so that an agent in another session picking up where you left off knows exactly what I asked for, and can easily keep track of my requests."
   - [x] This section.

10. > "Are art and card image assets bundled with the app? Is that what makes installing it slow? The app shouldn't include them in the bundle, but rather download them ahead of time." / "At runtime* I mean." / "Do all of this. It should download from network when the app launches and detects that images/artwork are missing." / "Should be a step in the process of downloading cards and rulings."
    - [x] Implemented (session 2): the app was 1.2 GB, 1.0 GB of it 12,692 JPEGs in `CardService/OfflineGames`. JPEGs moved to git-ignored `CardService/OfflineArtworkSource/` (not in the project; the script's cache). Bundle keeps `catalog.json` (43 MB) + README. New `ContentLoader` (CoreDataManager.swift) runs steps serially with one overall progress/notifications (the existing `CardLoadingProgressWindow`): the card+rulings import is a step; `OfflineGameLibrary.downloadMissingArtworkIfNeeded()` queues a "Downloading artwork… n of N" step (6 parallel requests, stops after 25 consecutive failures, throws `ArtworkDownloadError` so the window shows the failure; retried next launch). Files go to `Application Support/OfflineArtwork` (excluded from backup); `artworkURL(for:)` reads from there. Called at launch (AppDelegate, skipped for fixtures/XCTest) and after a database update. Debug app is now ~205 MB. [x] Verified end to end on the SE (normal launch, no fixture): the progress window showed "Downloading artwork… 1,295 of 12,692 · 10%"; about 85 files/s (2,179 in 30 s). Card+rulings DB import isn't triggered at launch while the offline catalog exists (`CardService.shouldInitializeCards = false` in AppDelegate), so the artwork step usually runs alone; after `updateDatabase()` it runs as the step after the import.
11. > "I still see the untap button and life total buttons move out of the way when the hand is expanded" / "They should never move. They should not be part of the same stack as the hand. The hand should be drawn on top of that area."
    - User: "Real device, latest build, on iPhone Duo" / "unfolded". Not reproducible on SE, iPhone 17 Pro, or iPad Pro 11 (no Auto Layout conflicts logged). The iPhone Duo sims (`5E23955B-...` iOS 27.1, `2F31FF38-...` "Magic Board Duo Layout") boot FOLDED (inner display, `simctl io --display=3`, is off); there's no Apple CLI to unfold (Device Hub GUI, or the third-party `hinge` CLI, which needs user OK). Screenshots: `simctl io <udid> screenshot --display=1` = outer, `--display=3` = inner.
    - Session 2 result: the user unfolded "Magic Board Duo Layout" (`2F31FF38-...`) via Device Hub (`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`). Inner display window 951×669pt. `testDumpPhoneHUDLayout` + `testPhoneHandExpandsAndCollapsesWithoutMovingBattlefield` PASS there; a frame-by-frame recording (`simctl io <udid> recordVideo --display=3`) shows untap/life pixel-identical before, during and after expand/collapse (host); the expanded hand simply covers the untap button. Still NOT reproduced; waiting for the user to describe or record what they see (maybe a stale device build, or a case not covered: guest, Hand Only, many cards, after rotation/fold). Note: a manual `simctl launch --phone-board-fixture` on the Duo showed the classic board (the fixture only starts from viewDidAppear after orientation?); the UI tests work.
    - [x] Resolved in session 3 by reparenting the hand into its own board overlay (see current notes at the top). Prior investigation: Constraints don't link them any more (storyboard `untap.leading = hand.trailing + 54` is deactivated), and tests sampling frames pass, yet the user still sees movement. Next: record video of expansion on the 17 Pro sim and inspect frames; if needed, move the hand out of the bar's subview hierarchy entirely (an overlay on top of the HUD).
12. > "With a lot of cards in hand, the angles of the cards can cause some cards on the ends of the hand to render off screen. All cards should fit on screen."
    - [x] Fixed in `FannedHandView` (phone mode only): the row is inset by the most-rotated card's bounding-box overhang (`fannedHandRotationOverhang`, `fanWidth`), and the arc's drop is limited to 12% of a card height (was a fixed 700pt radius, which dropped small cards about a whole card). New fixture flag `--phone-board-big-hand` (15 cards) + `testBigHandFitsOnScreen` (first/last card frames inside the window, compact and expanded) PASS on SE; screenshot reviewed. `testExpandedHandReordersAndCollapsesAfterPlaying` press points moved to the middle-left of the card strips (0.25, 0.45) with a hold; it PASSES.
13. > "Handle disconnects with an alert. Currently a disconnect has no notifiaction that you've been disconnected."
    - [x] `PhoneGameSession.onConnection`: when an established connection (`wasConnected`) goes `.notConnected` in host/join mode, it sets `error` with a host- or guest-specific message; BoardViewController's existing error alert shows it, titled "Disconnected". Compiles; not exercised with two devices (no automated test).

## Earlier requests from the Codex session (verbatim), all implemented

- "Rounded corners for cards in hand aren't consistent between sizes."
- "Expanding the cards in hand moves some of the other elements in the bottom row (the untap button, the life counter) out of the way. They shouldn't ever visibly move -- only the cards should move. They're already on top of the other elements, so they don't need to move anything out of the way." (Previously fixed only in end state; truly fixed in session 2, see request 4 above.)
- "Dragging cards from the battlefield -- the original card stays in its position, so while dragging, the card appears duplicated."
- "MTG Arena draws the mana cost of a card above it, so it can easily be seen while the cards are fanned. I already do something similar in the Board Connect app's hand view. Replicate this behavior over the fanned cards in a player's hand." Follow-up: costs "should float just above each card's top edge, follow its angle, and stay visible in both hand sizes." (Refined in session 2, request 8.)
- "Tapped cards should draw the tap arrow over them when rotated, as in the arena screenshots."
- "Lands out on the field aren't being rotated when they're tapped. Fix this." + "they should use the same grouping and logic as in the land organizer."
- "Creating tokens from the menu doesn't seem to place them onto the battlefield."
- "It can be easy to accidentally drag up from the bottom of the screen -- shouldn't it, as a full screen app, make you drag up a bit first before revealing the home indicator?" (Implemented via `preferredScreenEdgesDeferringSystemGestures`; NOT verified on a home-indicator device.)
- "Not sure if you fixed this, but the animation for the hand when expanding or minimizing seems to move it horizontally as well as vertically. It should just expand and remain centered."
- "Why are the sizes of the card icons in the graveyard/library different? Graveyard/library/exile should all be a consistent size between the three of them. Also the library for some reason has its number underneath the top card preview? It should be overlaid on it, like the graveyard. Exile should be the same. They can also be a bit smaller overall, and have a bit of vertical padding."
- "And, also notice how the bottom bar still isn't centered in that screenshot -- the life tracker has empty space underneath it for some reason. It looks like it's leaving space for a home indicator, but we should be a full screen app and ignore it." (Still visible on the user's home-indicator device; see request 7.)
- "Don't show the full card menu when tapping a card in the hand. [...] it needs an interface to expose the play and ... button functions that are available on a selected card in the Board Connect app. Obviously, dragging a card onto the battlefield should trigger the "play" function, displaying a menu if there are multiple faces. But maybe a separate sheet needs to be used that shows the current card on the left like the current card menu does, but showing the play options instead, while it's in hand."
- "Also: In phone play mode, we don't need to be able to tap a card image in the menu to spin it."
- "I can't currently drag a card from library into hand." (Fixed in session 2: UTType declaration.)
- "Only instants and sorceries should go to the stack when dragging up. Other permanents should go onto the battlefield."
- "When dragging cards from the battlefield, the draggable preview should be the same size as the battlefield preview." (Implemented; not visually verified.)

## Current unfinished work (do these next)

- [x] Verification run `/tmp/magic-hand-play-drop-check.log` completed: model suite 31/31 PASS; UI `testExpandedHandReordersAndCollapsesAfterPlaying`, `testPhoneHandUsesPlaySheetAndPlaysTappedLand`, `testQuickDragRemovesCreaturesAndOrganizedLands` PASS. `testDragLibraryCardIntoPhoneHand` FAILED (library count stayed 15). Drop code path reviewed and looks correct; the test released with 0 hold at velocity 500. Test changed to `withVelocity: 300, thenHoldForDuration: 0.6` (same approach that fixed the token test). Rerun log: `/tmp/magic-library-hand-drop.log`.
- [x] Library-to-hand drag FIXED and verified (`/tmp/magic-library-hand-drop3.log` PASS; logs showed validate conforms=true → entered → receive). Root cause: the custom type `com.josh.birnholz.Magic-Board.CardInstance` was never declared as a UTType. SwiftUI `DropInfo.hasItemsConforming` matches by UTType and returned false, while UIKit `canLoadObjects(ofClass:)` matches strings (so classic UIKit drops always worked). Fix: `UTExportedTypeDeclarations` (conforms to public.data) in `Magic Board/Info.plist` and `MagicBoardConnect/Info.plist` (PlistBuddy alphabetized a few keys in the Connect plist; content otherwise unchanged). TEMP NSLogs removed. The test now holds 0.6s before release. Tip: xcodebuild shuts the sim down after tests; `simctl boot` again before `simctl spawn ... log show`.
- [x] Screenshots: older xcresults were pruned, so I launched the fixture directly (`simctl launch ... --phone-board-fixture` + `simctl io screenshot`; the raw PNG is portrait, rotate it). Pile previews have equal geometry with counts overlaid, floating mana costs sit above the hand fan, and the HUD and lands look right. Black Soldier tokens are expected: the fixture token has no image URL. The hand Play sheet was not screenshotted, but `testPhoneHandUsesPlaySheetAndPlaysTappedLand` passes.
- [x] Standalone `MagicBoardConnect` scheme BUILD SUCCEEDED (`/tmp/magic-connect-build.log`) after the shared Play helper / fan / Info.plist changes.
- [x] **User-reported (session 2): hand expand/collapse visibly shifted piles/untap/life.** Cause: expansion resized the whole bottom bar container (`bottomSpan = barHeight + handLift(expanded)`) inside `UIView.animate`, so the HUD drifted mid-animation even though end frames matched (old tests only checked end frames). Fix: the bar container is now ALWAYS the compact height (`BottomBarViewController.phoneHandLift(expanded:sceneHeight:)`, shared by both files); when expanded, the hand's top constraint gets a negative constant and it overflows upward (PlayerBarHitAreaView already forwards touches outside bounds). Local hand is always front-most within the bar. The hand test now also samples HUD frames right after the tap. PASS in `/tmp/magic-static-hud.log` (all 5 focused UI tests).
- [x] **User-reported: tapping outside the expanded hand must ONLY collapse it.** (PASS) The old `PhoneHandDismissRecognizer` (removed) didn't cancel touches. Replaced by `PhoneHandShieldView` (PhoneSessionControllers.swift): a transparent full-screen view in BoardViewController.view, shown only while expanded, kept front-most (`updatePhoneHandShield`, plus re-fronting at the end of both layout passes). It consumes touches outside the hand container and passes through touches on the hand and non-touch hit tests (drag-and-drop). Test: tapping a creature while expanded collapses the hand and leaves the creature untapped.
- [x] **User-reported: "xN" badges on stacked token groups drawn underneath the stack.** `addPhoneBadge` buttons now get `layer.zPosition = 1000` and are re-fronted at the end of `layoutPhoneBattlefield`. Needs a visual check with a big token stack.
- iPhone 15 Pro (iOS 17.5) sim: booting took >5 min and launching failed with "system shell probably crashed". Don't use it again; the iOS 27 iPhone 17 Pro sim was booted by other work and was left alone.
- [x] Full-height HUD verified on home-indicator sims (iPhone 17 Pro, Duo inner). [ ] Native bottom-edge swipe protection still needs a real device (XCUITest can't do system gestures). The SE has no home indicator; don't claim this device behavior was verified there. Prior other-runtime simulator problems are described below.
- [x] (Done for the library drag.) If new UI tests fail, inspect their actual targets first. User prefers focused verification; do not chase automation errors by changing app behavior.

The user asked for this document now and wants completed items cleared/checked as work proceeds. Do not stop simply because the document exists.

### Latest implementation (now verified, see checklist above)

- Added `Command.PlayCardParameters.options(for:tapped:increaseTax:)` in Command.swift and refactored Board Connect's `playButtonPressed` to use it. It preserves transform/Aftermath front face, Adventure reversed faces, split/Fuse, modal faces, Morph/Megamorph and Prototype choices.
- Added `PhoneHandCardController` to the existing PhoneSessionControllers.swift (no new project entries needed). Card preview left, Play / Play Tapped plus selected-card More actions right. It conforms to PileDisplaying and reuses its existing actions, filtering View Card, Reveal to Opponent and Morph (Morph remains in Play choices). No arbitrary Face-Down / token / battlefield controls in this hand sheet.
- `BoardViewController.focus` intercepts local hand cards for the new sheet. `HandView.select` resets selection before accepting it in Phone Play so the same card can be reopened. First compact-hand tap still only expands.
- Hand-to-battlefield drops now call `playPhoneCard`, which uses the shared Play choices and presents a face/options chooser when needed.
- `PhoneGame.apply(.play)` now puts ONLY instants and sorceries onto the Stack. All other cards go directly onto the field. Updated old Equipment-on-stack test and added model coverage for all permanent categories and multi-face Play choices.
- Phone Play no longer installs the card-image spin tap recognizer; legacy inspector `.card` row spinning is guarded too. Classic behavior remains.
- Fan DropDelegate accepts external cards separately from reordering. HandView loads provider UUID data asynchronously and sends Command.moveCards to the local hand. The UIKit hand drop path uses the same asynchronous receiver in Phone Play, covering empty hands and shared DanDan ownership through the session move path.
- Transparent mana-only fan has no drag/drop registrations, touch handling or hand accessibility IDs, preventing it from intercepting drops/reorders.
- Custom battlefield drag previews now measure actual source edges after zoom/scale/rotation instead of guessing from group count. Organizer drag callbacks include the exact displayed card CGSize; organizer previews use the same cropped canvas and preserve rotation/tap arrow. Native UIKit previews are system-generated (the old custom preview code in Board.dragItem is commented out), so no fixed native size was changed.

## What is implemented and verified in the latest work

- Fixed HUD life/untap/pile controls during hand expansion: explicit bottom anchors and heights independent of the hand. Hand compact and expanded states now use the same screen-center anchor. Tests assert fixed control frames and middle hand card center for hosting and joining perspectives.
- Hand card corners now clip after aspect-fit sizing and use a radius proportional to card size.
- Floating mana costs use the existing `addSymbols` helper. They render in a second transparent fan above all actual cards, so neighboring cards do not cover the costs. The transparent fan should not expose accessibility IDs or receive touches; `manaOnly` controls those flags. Screenshots were reviewed before the final pile sizing change; new hand screenshot export/review is still useful.
- Tapped battlefield cards and lands show the existing `tap` artwork as a translucent white arrow. MiniCardView has a UIKit overlay; SwiftUICardView has a SwiftUI overlay.
- Phone lands use the organizer's original grouping and tapped/untapped split, with the original 12-degree rotation restored. Do NOT create separate grouping logic for phone lands.
- Battlefield custom drags hide the original MiniCardView and restore it on drop/cancel. Native drag delegate also hides/restores it. Organized land dragging uses GestureState to hide the actual SwiftUI source and cancellation callbacks to clear the preview.
- Fixed token creation from the card menu: original Rx callback required `cardInstance.center`, which is deliberately nil in Phone Play. It now falls back to visibleBoardCenter and created phone cards keep nil saved coordinates. Actual Token Copy menu interaction passed, and a guest-token patch/host roundtrip model test passed.
- All six pile previews now have identical fixed image geometry independent of image resolution; counts overlay their images; titles have consistent sizes and vertical padding. `HUDCardPileView.configurePhoneLayout` detaches the old stack's image/title and installs explicit constraints. Binding subscriptions reset on actual pile-relay changes.
- Full bottom HUD no longer reserves bottom safe-area space. Life, untap and pile areas center in the full visible bar; hand still extends to the screen bottom. Side safe-area clearance remains for rounded corners/notches.
- Phone Play requests `.bottom` via `preferredScreenEdgesDeferringSystemGestures`. Auto-hide remains FALSE: hiding the indicator can defeat two-swipe protection. Root is BoardViewController directly, no navigation forwarding needed. `attachPhoneSession` invalidates system-gesture preferences. Physical home-indicator gesture behavior is not verified on a device.

## Latest validation and artifacts

Latest PASS: `/tmp/magic-pile-hud-check.log`:
- `testPhonePilePreviewsIgnoreImagePixelSizeAndOverlayCounts`
- `testCreateTokenCopyFromPhoneCardMenu`
- `testPhoneHandExpandsAndCollapsesWithoutMovingBattlefield` (both host and guest)

Earlier PASS: `/tmp/magic-phone-polish-final.log` has passing centered-hand and quick creature/organized-land drag removal checks; token UI test in that run failed because fast swipes overshot the Create section, not because token creation failed. The latest test uses short coordinate drags held before release, which passed. Keep that approach.

Earlier PASS `/tmp/magic-hand-tap-polish.log`: land tap/untap, repeated life changes, tap arrow screenshots, fixed HUD frames, quick removal drags.
Guest-created token model passed in `/tmp/magic-token-floating-mana-check.log` (that run's token UI test failed due to scrolling; fixed in latest run).

Screenshot export `/tmp/magic-hand-tap-review/`:
- `165CBEBD-7954-4EC2-B31E-72F0E2F63649.png`: compact hand (before costs moved above all siblings)
- `8BA76945-63FF-4EB5-9A5B-A9C4B4B26663.png`: expanded hand
- `9CE029D2-43BB-412E-A639-9695BFD6EBBC.png`: tapped land + tapped creature; arrows/rotation correct.

Find latest xcresult under:
`/Users/compc/Library/Developer/Xcode/DerivedData/Magic_Board-gcphwddapphdduhfgkksnavwdoee/Logs/Test`
Only export after `Info.plist` exists. Use `xcrun xcresulttool export attachments --path ... --output-path ...` with escalated filesystem permissions. Manifest lists screenshot filenames.

## Relevant code and reuse points

- `Magic Board/PhonePlay/PhoneGame.swift`: host-authoritative rules-free model, manual stack, attachments, packet selection. `.playCard(Command.PlayCardParameters)` handles special modes before `.play`.
- `Magic Board/PhonePlay/PhoneGameSession.swift`: original Command bridge, guest patch ACKs/pending optimistic edits (fixes life flicker), transport/snapshots. Use this path for new actions.
- `Magic Board/PhonePlay/PhoneSessionControllers.swift`: UIKit/SwiftUI session sheets; suitable place for a new hand card sheet (already included in target; no project edits needed).
- `Magic Board/Command.swift`: shared PlayCardParameters with faceIndex, mode (default/morph/manifest/foretell/prototype), tapped, increaseTax.
- `MagicBoardConnect/LandscapeHandViewController.swift`: `playButtonPressed` around line 960 has existing Play choice logic. Transform and Aftermath play front; Adventure faces reversed; other multi-face cards offer faces; Fuse adds Fuse; Morph/Megamorph and Prototype add choices. `updateButtons` adds Play Tapped. `makePlayCardUIMenu` / `showPlayCardMenu` reuse PileDisplaying actions.
- `Magic Board/PileViewController.swift`: PileDisplaying protocol and shared `actions(for:includeFaceCasts:includeIndividualCast:)` supply Manifest/Foretell/Morph/Prototype, move top/bottom library, discard, exile, reveal, etc. A hand-specific controller can conform to this protocol to reuse “…” actions and filter View Card / Reveal to Opponent like Board Connect does.
- `Magic Board/BoardViewController.swift`: `focus(on:view:)` currently always presents full inspector; intercept local `.hand` in Phone Play before that. `moveCardItemsToBattlefield` currently sends `.play` directly with face nil; must route hand cards through shared Play choice logic. `movePhoneCardPreview`, `clearPhoneDragPreview`, native drag delegate near line 1900. Original card creation callback near line 450.
- `Magic Board/HandViewController.swift`: first local Phone Play hand tap expands; subsequent taps set selectedCard and invoke the bar focus callback. Contains UIKit UIDropInteractionDelegate too.
- `MagicBoardConnect/FannedHandView.swift`: shared fan, `manaOnly` overlay, reorder DropViewDelegate; likely source of library-to-hand drop rejection.
- `Magic Board/HUDCardPileView.swift`: new shared preview sizing. `BottomBarViewController.refreshForPhoneSession` configures all HUD frames and fonts.
- `CardService/LandOrganizerViewController.swift`: original grouping, GestureState source hiding; callbacks carry global drag points. For exact drag preview size, extend these callbacks to report rendered source size or a snapshot/frame.
- `Magic Board/MiniCardView.swift`: UIKit + SwiftUI battlefield card renderers. Preserve original title/PT layout metrics.

## Existing feature context / do not regress

User wants adaptation of the original UI, not a redesign. Landscape only; local 1v1 phone-to-phone offline, with optional Hand Only/Board Connect mode. Manual rules, attachments, manual stack, JumpStart/Jump In and shared DanDan. Responsive readable cards and pages at high density; original Beleren count badges. Opponent lands retain their own full row using the organizer. No organizer background in Phone Play. Opponent hand is upside down. Empty Stack label hidden; full rounded cards on Stack; Stack cards cannot tap. Expanded hand overlays HUD/battlefield and collapses on play/tap-away; hand reorder must remain available.

IMPORTANT legacy naming: `bottomBarA` refers to player B and vice versa. Use `localPhoneBar` or actual `bar.player.identifier`, never infer player from those variable names.

Jump In “All Sets” option was added and tested in the prior turn. Qualified choices are `SET · NAME` to distinguish duplicate packet names. Both shared and classic choosers support it, offline. Packet metadata/art are bundled.

30 newer Jump In packets (EOE/ECL/SOS) were added to BOTH this app and `/Users/compc/Xcode/TabletopSimulatorMagicBoosterPackServer`; total 133 packets / 13 sets. Old 103 retained. Shared Python importer updated; production Swift server parser and offers tested in a lightweight SwiftSoup harness (2920 offer rounds), plus focused Python tests. Do not rebuild the full server dependencies unnecessarily. Server modifications are uncommitted and user-authorized.

SuperJump: user explicitly cancelled updating its lists. Keep original 75 packets and chosen Theros full-art lands untouched.

Offline artwork bundle is ~1 GB (691 games / 6290 unique card/token printings / 12692 image files). Resource copying/install/signing can dominate build time. Do not regenerate artwork or data for UI fixes.

## Working preferences and verification commands

- User AGENTS.md: keep small fixes quick; verify interactions once and other affected layouts when relevant. If a verification method fails twice due to tooling, change method. Check actual visible target before changing app code for an automation failure.
- No subagents unless explicitly authorized; user asking for a handoff does not request spawning agents.
- Do not commit/push this feature unless asked. An old unrelated commit/push request was completed earlier (`e273635`). There are many intentional uncommitted changes; preserve them.
- Use one simulator owned by this task, `nice -n 10`, `-jobs 2`, `-parallel-testing-enabled NO`, `-enableAddressSanitizer NO`. Other work may use other simulators; do not shut them down or kill their processes.
- Working simulator: iPhone SE 3 / iOS 17.5: `180A4550-3336-4B5C-9DD9-D6C0739E8034`.
- Prior iPhone 15 Pro home-indicator runtime check exposed a land self-measurement loop. Fixed by sizing LandStack from its parent row (no OverlayedGeometryReader). Later CoreSimulator stalled/disconnected; do not repeatedly reboot runtimes or run heavy UI tests to chase tooling.
- Main build/test command: `nice -n 10 xcodebuild -project 'Magic Board.xcodeproj' -scheme 'Magic Board' -configuration Debug -destination 'platform=iOS Simulator,id=180A4550-3336-4B5C-9DD9-D6C0739E8034' -disableAutomaticPackageResolution -parallel-testing-enabled NO -jobs 2 -enableAddressSanitizer NO -only-testing:PhoneGameTests/... -only-testing:PhoneBoardUITests/PhoneBoardUITests/... test > /tmp/meaningful-log.log 2>&1`
- App bundle: `com.josh.birnholz.Magic-Board`; standalone scheme `MagicBoardConnect`.
- Main DerivedData: `/Users/compc/Library/Developer/Xcode/DerivedData/Magic_Board-gcphwddapphdduhfgkksnavwdoee`.
- Source files often contain extensions. Put stored properties in the actual class, NOT an extension (caught twice in earlier work).
- Skills applied/read: ios-adaptive-layout, iphone-duo-readiness, swiftui-modern, ios-shipping-engineer, swift-concurrency-pro, ios-animations-guide, swiftui-performance-profiling. Preserve iOS 16 / Swift 5 project conventions.
- Current filesystem write sandbox: app repo and temp only; server writes/Xcode/sim commands need `require_escalated` with concrete justification.

### Packet picker (front card only / mystery tile): verified 2026-11-15
- `packetFrontCardURL`, `packetDisplayName` and `packetColorSymbols` in CardService.swift, and `PacketChoiceCard` in PhoneSessionControllers.swift are implemented and visually verified. Marvel and Jump In UI tests both PASS; see `/tmp/magic-handoff-packets.log` and `/tmp/magic-handoff-packet-shots/`.
- The 2026-11-13 unsigned-debug-dylib launch failure no longer reproduces. The existing DerivedData built and launched without a clean; do not delete DerivedData for that historical blocker alone.
