# PokeAPI sprite notice

The party icons in `assets/party_icons` use the same pinned PokeAPI repository's
Generation VIII icon collection for species 1–898. Species 899–1025 use miniature
versions of this mod's existing front artwork, because that icon collection
does not cover them. All are fitted to 16x16 native party slots with a second
one-pixel bob frame. `tools/build_party_icons.py` reproduces the assets and
`PARTY_ICON_QA.json` records their sources and checksums. These are regular-color
species icons; shiny party members use the same icons.

The shiny front and back sprite sheets in `assets/anim/shiny` were generated
from the [PokeAPI sprites repository](https://github.com/PokeAPI/sprites),
pinned to commit `b2486a428a7548c874ad3900951d5334a40d21a5`.

The builder prefers the Generation V Black/White animated shiny GIFs, then the
Black/White static shiny PNGs, and finally PokeAPI's default shiny PNG when a
Black/White asset is unavailable or malformed. Exact source counts and the
aggregate generated-asset checksum are recorded in `SHINY_SPRITE_QA.json`.

PokeAPI states that the repository is distributed under CC0 1.0 Universal and
that all image contents are copyright The Pokémon Company. The Generation V
collection also credits Smogon community artists for custom National Dex
sprites beyond the original Black/White roster. Refer to the upstream
repository's `README.md` and `LICENCE.txt` for its complete notices and terms.
