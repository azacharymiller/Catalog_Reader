# Sale Catalog (iPad)

An iPad tool for inspecting horses at Keeneland, Fasig-Tipton and OBS sales. Each catalog page becomes one sortable row of numbers. Pencil notes are converted to text and saved with the hip, and a ring board along the top shows the hip in the ring, the next three, and the last five prices.

The spec is a separate shared document: *Sale Catalog App — Technical Spec*.

## Build it on your Mac

1. Install Xcode 16 or later from the Mac App Store and open it once to finish setup.
2. Install XcodeGen, which creates the Xcode project from `project.yml`:
   ```
   brew install xcodegen
   ```
3. In this folder, run:
   ```
   xcodegen generate
   open SaleCatalog.xcodeproj
   ```
4. In Xcode, select the **SaleCatalog** target, open **Signing & Capabilities**, and choose your team.
5. Connect the iPad by USB (or pick an iPad simulator) and press **Run** (⌘R).

If the build fails, copy the full error list from Xcode's Issue navigator (⌘5) and paste it to Claude.

## What works in this first version

| Area | Status |
| --- | --- |
| Hip table | Sort by any column, search by hip, sire, dam or consignor, filter by type or short-list |
| Hip card | Numbers, short-list, favorite, rating, bid ceiling, Pencil notes converted to text, everyone's notes |
| Catalog | Import the sale's PDF, write on any page with the Pencil (fingers turn pages), double-tap the Pencil for the eraser |
| Compare | Short-listed hips side by side, best value in each row highlighted |
| Results and ring board | Results typed in by hand; session median, RNA count and gross |
| Photos and video | Camera or photo library, kept with the hip |
| Team sync | Short-list, bid ceilings, ratings, notes, ink, photos and results shared through the team server (`server/README.md`) |

The full Keeneland November 2026 book is built in: all 3,398 hips with catalog facts, agent score and tier, sire figures and price bands, the covering sire's weanling prices, and the dam's foals at auction, from the Timbercreek Bloodstock database (export checked hip by hip against the database's MD5). Black type, produce records, sire figures and catalog pages come from the 2026 catalog PDF for 3,394 hips; a page is only used when its dam matches the database. Hips 1730, 2247 and 2301 (no first-dam section on the page) and 265 (not in the PDF) have database numbers only.

## Catalog pipeline (`pipeline/`)

| Script | What it does |
| --- | --- |
| `export_hips.sql` | The database query behind the built-in book |
| `parse_catalog.py` | Reads a catalog PDF's fonts: stakes winners and placed under each dam, the dam's produce record, sire figures, race record, pregnancy. Tested on the 2021 Keeneland November catalog (3,866 of 3,866 hips found) |
| `build_sale.py` | Merges the two into the file the app loads: `python3 build_sale.py kee_nov_2026 out.json --pdf parsed.json` |

## Not built yet

- The live Keeneland results reader (needs network access to keeneland.com).
- Fasig-Tipton and OBS readers, Android.

## Notes for whoever builds next

- The iPad's PDF page matcher (`CatalogPDFIndexer`) finds each "Hip No." label and reads the number printed under it. The import shows how many hips it matched.
- The data format the server must serve is `SaleFile` / `HipRecord` in `Data/SaleImporter.swift`.
- Every model has a `needsSync` flag, so the sync layer can upload only what changed.
