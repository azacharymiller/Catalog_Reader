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

Sample data: Keeneland November 2026, hips 1–14, from the Timbercreek Bloodstock database. The full book will come from the shared server.

## Not built yet

- Shared server: team sync, the Timbercreek data feed, and the live Keeneland results reader.
- Black-type counts read from the PDF fonts.
- Fasig-Tipton and OBS results readers, Android.

## Notes for whoever builds next

- The PDF page matcher (`CatalogPDFIndexer`) looks for "Hip No. 123" in each page's text. Check it against the real Keeneland November PDF; the import shows how many hips it matched.
- The data format the server must serve is `SaleFile` / `HipRecord` in `Data/SaleImporter.swift`.
- Every model has a `needsSync` flag, so the sync layer can upload only what changed.
