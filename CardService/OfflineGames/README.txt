Offline Magic Board resources

This folder is shipped inside CardService.framework. It contains catalog.json:
Scryfall card records for all bundled games and referenced tokens, plus a map of
image URLs (normal + art crop) to file names. The images themselves are NOT
bundled: at launch the app downloads any missing ones into
Application Support/OfflineArtwork as the "Downloading artwork" step of the
card loading process. Runtime loaders use those files before the network or the
purgeable image cache. (Scripts keep a local copy in CardService/OfflineArtworkSource,
which is git-ignored and not part of the app.)

JumpStart: 2020, 2022, Foundations, Avatar: The Last Airbender, Marvel Super Heroes,
and SuperJump. Jump In: all 133 server packet definitions, including weighted
random card slots, across thirteen sets. Offers and decks are generated locally.
DanDan and Jump In mana-fixing cards are included as well.

Regenerate from the repository root:
  python3 Scripts/import_packet_server.py /path/to/TabletopSimulatorMagicBoosterPackServer
  python3 Scripts/preload_marvel_jumpstart.py
  python3 Scripts/preload_marvel_printings.py
  python3 Scripts/build_offline_catalog.py

The import script applies documented corrections to four malformed source lists
and verifies 20-card packets. See Docs/PhonePlay.md for details and sources.
Preloaded Games & Artwork shows the actual included packets, cards, and images.

Card records and artwork: https://api.scryfall.com/
Marvel themes: https://magic.wizards.com/en/news/announcements/marvel-super-heroes-jumpstart-booster-themes

Jump In updates add EOE, ECL, and SOS while preserving archived packets.
Run the server Scripts/update_jumpin_packets.py before importing with --jump-in-only.

JumpStart basic-land policy: J22 for JumpStart 2022; TLA for Avatar; MSH for
Marvel; THB full-art basics for SuperJump; FDN basics for other sets.
DanDân uses the official Secret Lair 80-card deck, SLD collector numbers
2138–2164, including five each of both Fish and all four panorama Islands:
https://magic.wizards.com/en/news/announcements/from-the-chaos-vault-secret-lair-dandan-decklist

To regenerate metadata and runtime artwork URLs without downloading artwork:
  python3 Scripts/build_offline_catalog.py --metadata-only
