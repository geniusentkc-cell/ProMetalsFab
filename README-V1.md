# ProMetalsFab — V1 field test

This is a modified Xcode project based on the uploaded FieldFab fork. The app opens in the new ProMetalsFab job/area/fittings interface. The original transition workshop remains accessible through **Legacy transition tool** on the home screen.

## V1 included
- Locally saved jobs, named areas, and fittings stored as JSON in the app Documents folder.
- Add/edit/delete/reorder fittings; move fittings into the job root if an area is deleted.
- Rectangular straight, transition, elbows, offsets, and square-to-round; round straight, reducers, elbows, offsets, and tee/lateral.
- Field-entered dimensions, top-down and other offset alignments, independent inlet/outlet connections, quantity, and notes.
- Area defaults for rectangular liner and round insulation type/thickness, with independent per-fitting overrides.
- Native share sheet for portrait US Letter PDFs with **4 stacked full-width fitting rows per page**, sketch on the left and fabrication specifications on the right.
- No developed flat patterns; no automatic insulation or liner adjustment to finished dimensions.

## Deliberate V1 limitations / do not use for production without checking
- **Drawings are assembly schematics, not dimensionally to scale or developed flat patterns.** The entered written dimensions control fabrication. Some fittings (especially elbows, tees, square-to-round) are simplified for initial workflow testing; they are not fabrication-ready production shop drawings.
- A fitting's geometry is not yet a PractiCAM model or CNC pattern. The original FieldFab transition workshop is preserved separately, not yet coupled to the new request generator.
- No cloud sync, user accounts, collaborative edits, backups, or cross-device job migration. Deleting the app may delete locally saved jobs. Export your PDFs before reinstalling.
- No job/area editing of existing fitting ordering across areas; reordering is within each area. Deleting an area moves its fittings to the job root.
- No automatic gauge/material selection, branch takeoff geometry, or production-level fabrication validation.
- PDF export currently uses the current locale's date, job name and area name; notes may truncate if very long. Check resulting pages on device.
- No iPhone or Xcode compiler test was possible in the Linux editing environment. The GitHub Actions macOS build is required.

## Build with GitHub Actions and Signulous (Windows workflow)
1. Extract this source ZIP on your PC.
2. Clone or open **your existing** `geniusentkc-cell/ProMetalsFab` repository using GitHub Desktop. Copy the extracted **contents** into the repository folder, replacing files with the same names. Do not put the ZIP itself in GitHub.
3. In GitHub Desktop, review the changed/new Swift files, commit (for example, `ProMetalsFab V1`), and **Push origin**.
4. On GitHub, open **Actions → ProMetalsFab iOS Build → Run workflow**. This compiles iOS Simulator and device builds, and produces the `ProMetalsFab-iPhone-IPA` artifact containing `ProMetalsFab-unsigned.ipa`.
5. Download the IPA artifact, extract it if GitHub downloaded it as a ZIP, and upload the `.ipa` to **Signulous** for signing and installation.
6. If the GitHub build fails, copy the **first Swift compile error** (file name, line and message) for the next revision.

**Do not pay for Apple Developer Program yet.** Signulous is for sideloading a test build, not publishing to the App Store.

## Recommended first shop test
- Create `School Number 1`, areas `First Floor` and `Second Floor`.
- Set `Second Floor`: rectangular liner `1"`; round insulation `Double Wall` with thickness `1"`.
- Create a rectangular transition `24 × 18 → 18 × 12`, length 24, top down 2, horizontal centered, S&D on both ends. The outlet center is up 1 inch relative to inlet center; top drops 2 inches and bottom rises 4 inches. The PDF should show the entered **Top Down 2"** setting as well as X/Y displacement.
- Create a second round fitting with `Spiracoustic` and `2"` as overrides; confirm changing the area default leaves it unchanged.
- Add at least 5 fittings. Export the area and verify exactly 4 full-width rows on page 1 and 1 on page 2. Then export the whole job and check area info.
- Close and reopen app; verify edits remain.

## Source modifications
- `FieldFab/ProMetalsFab/FabModels.swift`: models, calculations, persistence.
- `FieldFab/ProMetalsFab/FabViews.swift`: job/area/fitting input screens.
- `FieldFab/ProMetalsFab/FabPDF.swift`: PDF assembly sketches and four-up pagination.
- `FieldFab/AppMain.swift`: launches V1 UI.
- `FieldFab/Info.plist`: display name `ProMetalsFab`.
- `FieldFab.xcodeproj/project.pbxproj`: includes new sources, distinct bundle identifier `com.prometals.prometalsfab`, V1 app version.
- `FieldFabTests/FieldFabTests.swift`: geometry, inheritance, and Codable tests.

## Credits
Uses code and components from the original open-source FieldFab project. Retain its upstream license and notices.
