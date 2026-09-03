# Kanto National Dex

## v0.9.11 — Native-style starter-aide dialogue

- Added complete shiny front/back artwork for all 1,025 species. The runtime selects shiny sheets from `mon.shiny` or the authentic Gen 2 shiny DV pattern in battles, party summaries, and evolution scenes; Pokédex entries remain the normal species artwork.
- Species #1–649 use animated Black/White shiny GIFs from PokeAPI. Later species use PokeAPI's static Black/White-style shiny art, with PokeAPI's default shiny collection filling unavailable or malformed individual assets. The build is pinned and reproducible through `tools/build_shiny_animation_sheets.py`.
- Because the DV fallback is generation-independent, R/B/Y Pokémon with Gen 2-compatible shiny DVs now receive shiny-colored sprites even though those cartridges have no native shiny flag. G/S/C continues using its native 1/8,192 DV-based shiny behavior.
- Fixed Blue failing to load when an authored starter-aide tile, notably Rowlet's requested Route 10 `(2,29)`, is not usable in that cartridge's map registry. Authored coordinates remain exact where valid; a tile mismatch uses the nearest safe tile on the same map, while a missing/unusable authored map retains the allocator's already collision-checked slot. Both fallbacks record the adjustment instead of aborting the mod.
- Added explicit Pokémon Crystal support. The manifest now targets every Gen 1 and Gen 2 cartridge, Crystal uses the shared Gen 2 content path, and every Kanto/static placement map was verified against an imported Crystal map registry.
- Split wild encounters by cartridge generation. R/B/Y continue using the existing 774-species, 41-map Kanto overlay without table changes.
- Gold/Silver/Crystal now use a separate 774-species overlay spanning 103 native maps: 68 in Johto and 35 in postgame Kanto. There are 483 unique species placements in Johto and 291 in Kanto, with all nine Pokémon generations represented in both regions.
- The Gen 2 table follows the campaign curve from Route 29 through Victory Road, postgame Kanto, and Mt. Silver. Water types were returned to water pools, non-Water outliers were removed from them, and powerful species remain concentrated in later areas.
- Generation weighting is unchanged: after the cartridge approves a wild battle, represented generations share the encounter probability evenly and unique species share their generation's portion evenly. Native encounter rates and Ruins of Alph behavior remain authoritative.
- Pokédex AREA rows now use `J:` for the new native Johto locations and `K:` for Kanto locations.
- Crystal's cartridge-native Suicune is recorded as a static Tin Tower 1F encounter in the Pokédex AREA catalog. Gold and Silver continue to show Suicune as roaming; Raikou and Entei remain roaming in all three games.
- The mod-added Bulbasaur, Charmander, and Squirtle gift aides appear in Red, Blue, Gold, Silver, and Crystal. Yellow alone omits them and uses its cartridge-native gifts.
- Their three placement slots remain reserved internally, so hiding the aides does not move any of the other 24 starter gifts.
- Added 29 legendary and mythical family questlines covering all 94 special-acquisition species. R/B/Y use Oak's aides around Kanto; G/S/C use a separate network of Elm's aides spread across 26 Johto locations. Every later family stage requires all Pokémon in the preceding stages to have been caught.
- Cartridge-native encounters are retained unchanged. This includes Articuno, Zapdos, Moltres, and Mewtwo in R/B/Y and Raikou, Entei, Suicune, Lugia, and Ho-Oh in G/S/C; their normal Pokédex caught state advances the corresponding family quest.
- Mew remains at its existing distributed encounter position and now answers immediately after Mewtwo has been caught; no prior researcher conversation is required. In R/B/Y, the native Cerulean Cave Mewtwo encounter itself is not patched or gated.
- The Birds survey treats Articuno, Zapdos, and Moltres as a non-linear investigation. R/B/Y's cartridge-native encounters remain available and are incorporated rather than replaced. G/S/C's distributed encounters are instead opened by Elm's Violet City aide, whose briefing follows three migrating storm fronts across Johto.
- The Regi expedition requires Blaine's Volcano Badge in R/B/Y and Clair's Rising Badge in G/S/C. Kanto's Fuchsia aide studies seals across Kanto, while Johto's Olivine aide follows carvings associated with ancient Johto ruins. Both routes progress through Regirock, Regice, and Registeel, open Regieleki and Regidrago, and retain the Regigigas Chamber requirement.
- The Lunar Duo mystery requires Blaine's Volcano Badge in R/B/Y and Clair's Rising Badge in G/S/C. The Gen 1 report begins in Lavender Town; the distinct Gen 2 report begins with Elm's aide in Ecruteak City. Both open Cresselia first, then use its recorded Lunar Feather clue to reveal Darkrai.
- Every other gated family uses its original Kanto researcher and Volcano/Earth Badge requirement in R/B/Y, but an Elm aide on a family-specific Johto map and the Rising Badge in G/S/C. This gives the two cartridge generations separate quest routes without duplicating or replacing their native legendary encounters.
- Quest encounters use persistent completion flags and only advance after a successful capture. A knockout, loss, or retreat leaves the current objective available for another attempt.
- Updated the Pokédex AREA method field for all eleven affected Pokémon to show `QUEST: BIRD SURVEY`, `QUEST: REGI SEALS`, or `QUEST: LUNAR DUO`; the location remains synchronized with the actual encounter map.
- Fixed the bundled Gen1Recomp save editor falling back to the native 151-species Pokédex. Editor sessions have no live `mod.game`, so cartridge generation now falls back to the native map registry; Blue was previously misidentified as Gold and the mod was rolled back while resolving the Regigigas entrance.
- Moved the Sprigatito starter-gift aide to tile `(13,11)` on Route 18; the authored coordinate is collision-checked and included in placement spacing.
- Replaced Regigigas's exposed Victory Road static with a dedicated Regigigas Chamber. An Oak aide at Victory Road 2F tile `(9,13)` investigates a mysterious wall carving describing a union of steel, ice, and rock; if it remains sealed, he only notes that it has not reacted. The carving opens only while Regirock, Regice, and Registeel are all in the active party; the chamber has a safe scripted return to Victory Road.
- The chamber derives its floor, walls, collision, and tileset registration from the running cartridge's native Victory Road data, keeping the new map portable across R/B/Y and G/S/C and previewable by the save editor.
- Updated Regigigas's Pokédex AREA/location entry to name the chamber while retaining Victory Road as its Kanto map marker.
- Moved Type: Null's distributed static encounter one map tile left and three tiles up.
- Placed the Regigigas Chamber's Oak-aide entrance at tile `(9,13)` on R/B/Y's Victory Road 2F.
- Moved Tapu Lele to tile `(23,0)` on its distributed static-encounter map.
- Moved Cresselia to tile `(16,0)` on its distributed static-encounter map.
- Expanded every enemy trainer party across Generations 1–9. Each party slot independently rolls a generation; a roll of 1 keeps the original Pokémon, while rolls 2–9 prioritize a replacement with the original Pokémon's primary type and evolution stage. Levels and other authored fields are preserved.
- Legendary, mythical, and other static-only special encounters are excluded from ordinary trainer randomization.

- **Kanto-only update:** Removed every imported `J2_` map, tileset, trainer, event, travel, Fly, field-move, and map-service registration from the active mod.
- Relocated all 27 badge-gated starter gifts to native Kanto towns and routes. The aides retain the requested Oak-aide dialogue and scientist artwork.
- Relocated every added legendary and mythical static encounter to collision-checked positions on native Kanto maps. Cartridge-native statics and roamers are not duplicated.
- For R/B/Y, moved all 448 expanded-overlay species plus 27 ordinary species that were wild only in imported Johto into level- and habitat-matched Kanto encounter pools. That unchanged Gen 1 overlay covers 774 non-special species across 41 maps; G/S/C now select the separate Johto/Kanto table described above.
- Replaced the native-versus-added split with a unified generation-balanced encounter table. Every represented generation receives an equal share of 100%, divided evenly among the unique native and added species from that generation on the current map and terrain.
- Updated the exported Pokédex AREA/location catalog and compatible Gen 3 UI location field to use the new Kanto gift, static, and wild locations.
- Gold/Silver/Crystal retain their cartridge-native world and native special encounters; this mod no longer imports a second Johto map set.
- Rephrased starter-gift conversations in the style of Professor Oak's original Pokédex-reward aides.
- Each aide explains that Oak sent them, names the exact required badge and starter, confirms the badge on success, and identifies the missing badge on failure.
- Dialogue uses native-sized lines and page breaks for the original text box.
- Options-menu navigation now preserves the intended Up/Down destination when PotatoVoxel or another display mod rebuilds the row list during the same input tick; moving from ZOOM to VOID FILL no longer resets the cursor.

## v0.9.10 — Explicit starter-gift requirements

- Starter lab aides now name the exact badge required instead of referring vaguely to the next League milestone.
- Badge names adapt to the running campaign: Kanto badges in R/B/Y and Johto badges in Gold/Silver/Crystal.

## v0.9.9 — Starter lab aides

- Replaced Professor Oak's overworld sprite on all 27 distributed starter-gift NPCs with Professor Elm's lab-aide scientist sprite.

## v0.9.8 — Save-editor Johto map descriptors

- Fixed `unknown tileset: nil` when opening affected native Johto maps in the Gen1Recomp save editor.
- Gold/Silver object patches now carry complete render geometry and register their source tilesets, while continuing to inherit cartridge-native warps, signs, connections, and scripts during gameplay.
- The same change covers every map containing a distributed starter-gift NPC or legendary/mythical static encounter.

## v0.9.7 — Distributed legendary encounters and starter gifts

- Removed the League Research Annex entrance. All 27 base starters are now individual, one-time level-5 gifts spread across Kanto and Johto towns and routes.
- Starter gifts are badge-gated in regional order: Kanto badges in R/B/Y and Johto badges in Gold/Silver.
- Replaced generated sanctuary chambers with visible, one-time static encounters in existing caves, towers, ruins, and late/postgame dungeons.
- Placement is derived from each authored map's collision data and avoids warps, signs, existing actors, and four-way travel tiles. No two added actors share a tile.
- Native cartridge encounters remain authoritative: the four R/B/Y statics and Gold/Silver's three roamers plus Lugia and Ho-Oh are not duplicated.
- Pokédex AREA/location rows now name each Pokémon's real gift or static map. The compatible Gen 3 Inspired UI build consumes the same updated catalog.
- Legacy Annex, sanctuary, and chamber IDs remain as inaccessible rescue-only maps so a save made inside v0.9.6 can speak to an officer and return to Pewter City.
- See `DISTRIBUTED_PROGRESSION_QA.json` for the generated coordinate audit.

## v0.9.6 — League Research Annex collision fix

- Corrected the generated Annex, sanctuary-hub, and legendary-chamber floor collision.
- Cave block `2` is now used for the walkable interior; solid block `1` is used for the perimeter and border.
- All scripted arrival coordinates retain an unobstructed adjacent escape tile, including Annex entry/returns, sanctuary entry/returns, and chamber entry/returns.
- Continue using the compatible `Gen-3-Inspired-UI-Overhaul-2.0.1-Kanto-National-Dex` build from v0.9.5; it reads this release through the unchanged mod ID and catalog API.

## v0.9.5 — Direct Gen 3 UI compatibility pair

- Replaced the sandbox-sensitive external UI bridge with a direct integration in the companion `gen3_battle_ui` v2.0.1 replacement build.
- This content mod remains authoritative and exports the same complete `pokedexAreas` API; the companion UI now consumes it inside its own Gen I and Gold/Silver location builders.
- Install `Kanto-National-Dex-0.9.5.zip` together with `Gen-3-Inspired-UI-Overhaul-2.0.1-Kanto-National-Dex.zip`.
- Disable/remove the unmodified UI overhaul v2.0.0 because the compatible build intentionally uses the same `gen3_battle_ui` mod ID.

## v0.9.4 — Gen 3 Inspired UI location compatibility

- Added optional compatibility with HighDrexler's `gen3_battle_ui` v2.x Pokédex.
- Its Gen I **WILD LOCATIONS / METHOD** field and Gold/Silver **HABITAT DATA** page now merge this mod's authoritative 1,025-species AREA catalog.
- Progression-balanced wild maps appear even though the expanded encounter overlay is runtime-owned rather than stored in the cartridge tables scanned by the UI mod.
- Starter families display `GIFT ANNEX` or their evolution source; legendary and mythical Pokémon display their native static/roaming method or generational sanctuary.
- Native UI rows keep their more specific grass, Surf, fishing, Headbutt, contest, and current-roamer information. Catalog rows fill missing locations without replacing those details.
- The bridge is inert when the optional UI overhaul is absent or its revamped Pokédex is disabled.

## v0.9.3 — Pokédex AREA synchronization

- Updated the Pokédex AREA section for all 1,025 species using the mod's authoritative acquisition catalog.
- Wild entries now use the progression-balanced encounter maps rather than the cartridge's stale pre-overlay tables.
- Starter bases show `GIFT: ANNEX`; starter-only evolved stages show their preceding evolution source.
- Legendary and mythical entries identify native static/roaming methods or their generational sanctuary and point to the Pewter Annex when applicable.
- Gen I keeps its native Kanto nest map and adds a readable acquisition/location footer, including Johto-only locations that cannot be plotted on Kanto's map graphic.
- Gold/Silver unions the mod's locations into its native Kanto/Johto landmark maps and preserves live roaming-beast positions.
- Corrected Gold/Silver availability for Articuno, Zapdos, Moltres, and Mewtwo: because they are not native Gen II encounters, they now receive Generation 1 sanctuary chambers there.

## v0.9.2 — Progression-balanced encounters and special acquisition

- Rebuilt the expanded wild overlay around campaign progression and habitat. Opening routes contain basic, low-BST species; evolved powerhouses, Paradox Pokémon, Ultra Beasts, and pseudo-legendary families are pushed into later areas.
- Reduced the expanded-roster replacement chance from 35% to 25%, leaving more room for each cartridge's native encounter identity.
- Removed all 81 members of the nine regional starter families from the expanded wild pool. A League Research Annex in Pewter City gives all 27 base starters as one-time, badge-gated gifts at level 5; their evolutions come from the retained evolution system.
- Removed all 71 legendary and 23 mythical species from random encounter pools.
- Retained Articuno, Zapdos, Moltres, and Mewtwo in their native R/B/Y static locations. Gold/Silver also retains its native Raikou, Entei, Suicune, Lugia, and Ho-Oh encounters.
- Added protected, one-time chambers for every legendary or mythical species that is not already native to the running cartridge. The Annex's nine generational sanctuary gates unlock in three tiers: Soul Badge (Generations 1–3), Volcano Badge (4–6), and Earth Badge (7–9).
- The same Annex, starter gifts, sanctuary hubs, and chambers are installed through the portable content registry on R/B/Y and Gold/Silver.
- See `PROGRESSION_QA.json` for roster counts and the automated early-power audit.

## v0.9.1 — v0.9.0 feature merge + expanded-roster evolutions

- Merged the complete v0.9.0 Gen1–9 update: integrated QOL/CHEATS, continuous capture-ball animation, early-Johto progression and trainer fixes, Gold prize money, and automatic Gym Leader post-battle dialogue.
- Retained the v0.3.13 gameplay evolution payload: 483 evolution edges across 456 source species through National Dex #1025.
- Retained Pokédex evolution-family pages and the `evolutionsOf` API for 822 family members.
- Preserved cartridge-native evolution rows and appended only later-generation branches to native Kanto/Johto species.
- R/B/Y and Gold/Silver use their correct per-engine evolution record shapes.
- Modern-only conditions use the documented compatibility approximations in `EVOLUTION_QA.json`; exact canonical levels and supported Gen-1 stones remain exact.

## v0.9.11 — Native TM/HM compatibility for the expanded roster

- Added TM/HM compatibility for Pokémon supplied by this mod, including alternate forms.
- Red/Blue/Yellow use their 50 TM and 5 HM roster; Gold/Silver use their 50 TM and 7 HM roster.
- Compatibility comes from canonical main-series machine learnability. A later Pokémon can learn an older cartridge move when that species has been able to learn that move from a machine in an official game.
- Cartridge-native base species keep the ROM's own compatibility table unchanged.
- Move references are resolved against the running cartridge, so differing Gen I/II move-id spellings cannot create broken TM entries.

## v0.8.3 — Gold Trainer Prize Money

Johto/Gold trainer classes now use Pokémon Gold’s original class-based prize-money values. Winnings are calculated from the final party Pokémon’s level, matching Generation II behavior.

# v0.7.6 — Player house Mom cleanup

- Removed the duplicate Mom NPCs from the Johto player's house.
- Kept only the Mom at the table at tile (7,3).
- Her original dialogue/object remains intact.
- All v0.7.5 campaign behavior is otherwise unchanged.


## v0.8.2 — Scrollable QoL + Always Catch in Cheats

- Moved **Always Catch** from QOL to **CHEATS** while keeping its single canonical implementation.
- Replaced the QOL card grid/ticker labels with a **scrollable full-width list** using wrapped multi-line labels and no scrolling text.

## v0.8.0 — Integrated QoL + Cheats

- Added a single **OPTIONS → QOL** submenu integrating QoL Toggles, Quality of Life, and the unique parts of swuff QoL.
- Renamed the main-menu **GameShark** entry to **CHEATS**.
- De-duplicated overlapping behavior so only one implementation can own a given effect.
- Canonical shared implementations: EXP bar, map-location banner, forgettable HMs, rename-anywhere, party scrolling, field-HM shortcuts, and repel reuse.
- Added conflicts for the four standalone source mods so an installed duplicate cannot double-register the same hooks.
- Unique retained extras include caught indicators, easy interactions, faster battles, colored attacks, DVs/stat EXP, move info, quick party reorder, cursor Fly map, new Fly spots, relearn-anywhere, 30-item bag and 16 PC boxes.


## v0.8.2
- Fixed CHEATS → NO BATTLES with the integrated Kanto/Johto encounter runtime.

## v0.8.8
- Keeps the Poké Ball visible continuously through the pre-shake pause during capture animations. Catch odds, shake timing, and other battle animations are unchanged.


## v0.8.9
- Fixed Capture Ball Continuity integrated initializer contract so the mod loads correctly.
- Retains the v0.8.8 Poké Ball visibility fix.


## v0.9.0 - Automatic Gym Leader Post-Battle Dialogue
- After defeating an imported Johto Gym Leader in the R/B/Y arm, their new overworld dialogue starts automatically as soon as the battle screen closes.
- The dialogue is deferred until the Gym overworld is active, so it does not appear on top of the battle UI.
- Normal trainers and already-defeated leader interactions are unchanged.
- Clair keeps her special Gold progression: her automatic line directs the player to Dragon's Den rather than awarding the Rising Badge early.
