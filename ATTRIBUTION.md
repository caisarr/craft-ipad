# Attribution & Third-Party Licenses

**Craft Suite** packages the official open-source WebAssembly releases of the Craft productivity suite inside a native iPadOS WebKit/SwiftUI shell.

## Bundled Open-Source Applications

1. **GridCraft** — https://github.com/storytold/gridcraft
   - License: Dual-licensed under `MIT` or `Apache-2.0`
   - Bundled artifact: `gridcraft-web-*.zip` from official GitHub Releases
2. **PdfCraft** — https://github.com/storytold/pdfcraft
   - License: Dual-licensed under `MIT` or `Apache-2.0`
   - Bundled artifact: `pdfcraft-web-*.zip` from official GitHub Releases
   - Bundled OCR models (`models/*.onnx`): licensed under `CC-BY-SA-4.0` (see `ATTRIBUTION.toml` inside the `storytold/pdfcraft` repository for full model notices).
3. **WordCraft** — https://github.com/storytold/wordcraft
   - License: Dual-licensed under `MIT` or `Apache-2.0`
   - Bundled artifact: `wordcraft-web-*.zip` from official GitHub Releases

## Wrapper Code

The native Swift/SwiftUI shell and build scripts in this repository are licensed under the [MIT License](./LICENSE).
