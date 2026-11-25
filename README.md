# Craft Suite untuk iPadOS (GridCraft + PdfCraft + WordCraft)

Proyek ini membungkus build WebAssembly resmi dari **GridCraft**, **PdfCraft**, dan **WordCraft** (`storytold/gridcraft`, `storytold/pdfcraft`, `storytold/wordcraft`) ke dalam **1 aplikasi iPadOS (`.ipa`) offline** dengan shell Swift/SwiftUI + server loopback lokal (`127.0.0.1`).

Kenapa 1 `.ipa` gabungan?
- Dengan Apple ID gratis (SideStore / AltStore / Sideloadly), batasnya maksimal **3 app aktif**. Menggabungkan ketiganya dalam 1 app hanya memakai **1 slot**.
- Berjalan sepenuhnya **offline** di iPad tanpa butuh server internet.
- Mendukung **Open from Files** (`.xlsx`, `.csv`, `.pdf`, `.docx`) dan **Save to Files** lewat `UIDocumentPickerViewController`.

---

## Cara Build `.ipa` Gratis via GitHub Actions (Tanpa Mac)

1. **Buat repository publik baru di GitHub** (misalnya `craft-ipad`).
   > Pastikan repository **Public** agar runner macOS GitHub Actions gratis tidak memakan kuota private repo.
2. **Push folder `C:\craft-ipad` ke GitHub** dari PowerShell/Terminal:
   ```powershell
   cd C:\craft-ipad
   git add .
   git commit -m "Initial Craft Suite iPadOS project"
   git remote add origin https://github.com/<USERNAME_ANDA>/craft-ipad.git
   git push -u origin main
   ```
3. **Jalankan Workflow Build**:
   - Buka tab **Actions** di repository GitHub Anda.
   - Workflow **Build iPad IPA** akan otomatis berjalan saat push ke `main` (atau klik **Run workflow** jika ingin menentukan versi tertentu).
4. **Download hasil `.ipa`**:
   - Setelah workflow selesai (~2–4 menit), buka run yang berhasil, lalu download artefak **`CraftSuite-iPad-unsigned`** di bagian **Artifacts** dan ekstrak file `CraftSuite-iPad-unsigned.ipa`.

---

## Cara Install `.ipa` ke iPad (Sideload)

Pilih salah satu metode berikut menggunakan Apple ID biasa:
- **SideStore** (direkomendasikan, bisa refresh langsung di iPad via Wi-Fi tanpa PC setelah setup awal)
- **AltStore** (membutuhkan AltServer aktif di PC/Windows saat install & refresh 7 hari)
- **Sideloadly** (install langsung lewat kabel USB dari Windows)

> **Catatan tentang "Unable to Verify App":** setelah install pertama kali, buka **Settings → General → VPN & Device Management**, pilih akun Apple ID Anda, lalu tekan **Trust**.

---

## Fitur & Tips Penggunaan di iPad

- **Pindah Aplikasi:** gunakan segmented switcher di bar atas (**GridCraft** | **PdfCraft** | **WordCraft**). Aplikasi yang tidak aktif otomatis dilepas dari memori agar hemat RAM iPad.
- **Layar Penuh:** tekan tombol ikon mata di kanan atas untuk menyembunyikan toolbar saat menulis/menggambar. Akan muncul pill kecil untuk memunculkan toolbar kembali.
- **Mode Renderer (Auto / WebGL2):** secara default memakai **Auto** (WebGPU jika didukung iPadOS, atau fallback ke WebGL2). Jika tampilan kanvas bermasalah di iPad tertentu, tekan tombol **WebGL2** di bar atas.
- **Buka & Simpan File:**
  - Gunakan tombol **Open** di dalam aplikasi atau buka file `.xlsx` / `.pdf` / `.docx` dari aplikasi **Files** → **Share / Open in Craft Suite**.
  - Saat menekan **Save / Download / Export** di dalam aplikasi, iPadOS akan langsung membuka dialog native **Save to Files**.
