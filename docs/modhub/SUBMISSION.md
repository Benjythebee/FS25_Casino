# ModHub submission

Draft: https://modhub.giants-software.com/mod.php?modId=381365 (guidelines v5.9.1:
https://www.farming-simulator.com/lp/mod-hub-guidelines-en.php)

## Before submitting

- [ ] Ask GIANTS first (ticket from the draft page) whether a roulette mod with in-game money only is acceptable.
      The guidelines ban "youth endangering contents ... or similar", which reviewers may apply to gambling.
- [ ] Load `dist/FS25_Casino.zip` (not the linked folder) and check `log.txt` has no errors or warnings from
      FS25_Casino. The old "Texture ... raw format" warnings should be gone now that every texture is BC1/BC3.
- [ ] Multiplayer test, 30 minutes at least (guideline 7.6): two players on different farms and on the same farm,
      bets, notifications, leaving mid-spin, a player joining mid-round, a dedicated server if possible.
- [ ] Check the Casino page at 4:3, 16:10 and 21:9 (guideline 8.2), e.g. windowed 1024x768, 1920x1200, 2560x1080.
- [ ] Run the GIANTS Testing Tool (https://forum.giants-software.com/viewtopic.php?t=187502) on the zip.
- [ ] A third screenshot (at least 3 are required, 1600x900). Ideas: a multiplayer table with several seats taken,
      or the result notification over the farm. Hide the HUD for clean shots: `<development><controls>true`
      in game.xml, console `gsToggleFlightAndNoHUDMode`, then O. No added text, logos or version numbers.

## Draft state (2026-11-03)

Saved on the draft: Manufacturer "Lizard", Category "Gameplay", the mod icon (`icon_casino.dds`) and screenshots
1-2 (`screenshot_1.jpg` = playing table, `screenshot_2.jpg` = idle table). Titles, descriptions, version and author
are greyed out on the form: ModHub fills them from `modDesc.xml` when the zip is uploaded with "Import Meta Data"
ticked, which also needs the terms checkbox (left for you). Still missing: the zip and screenshot 3.

## Form values

| Field | Value |
|---|---|
| ZIP | `dist/FS25_Casino.zip` (build with `tools/package.ps1`) |
| Meta data | "Import Meta Data" reads title, descriptions (en/de/fr) and version from modDesc.xml |
| Mod icon | `FS25_Casino/icon_casino.dds` is BC1 for the game; the form may want an image: export `tools/icon_preview.png` (512x512) |
| Title (EN/DE/FR) | Casino |
| Version | 1.0.0.0 |
| Author | Benjythebee |
| Manufacturer | Lizard (guidelines: no fantasy brands; Lizard is the generic brand) |
| Category | Gameplay |
| Screenshots | `docs/modhub/screenshot_1.jpg`, `screenshot_2.jpg` (1600x900) + one more |
| Submission comment | Script mod, PC only. No required mods. Source: https://github.com/Benjythebee/FS25_Casino |

## After release

- Replace the zip on the GitHub release with a link to the ModHub page: the guidelines only allow other sites to
  offer the mod by linking to ModHub. Linking the source repository is fine for script mods.
- Updates: changelog in the modDesc description, zip named `FS25_Casino_update.zip` for the upload, and
  non-critical updates at most every two weeks.
