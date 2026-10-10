# MonetLoader Third-Party Room Chat

Room chat lintas server SA-MP, menggunakan MonetLoader Android + mimgui + `requests` + `cjson`, Netlify Functions, dan Supabase Postgres REST API.

> **Status:** proyek contoh siap dikonfigurasi dan diuji. Belum diuji di perangkat/game kamu. Kompatibilitas `requests`, `cjson`, `mimgui`, dan API chat bergantung pada build MonetLoader yang terpasang.

## Fitur
- Command `/room` untuk membuka/menutup UI.
- Buat room global atau join lewat Room ID.
- Nickname diambil dari SA-MP jika fungsi `sampGetPlayerNickname` tersedia.
- Kirim dan polling pesan baru.
- Validasi room, nickname, panjang pesan, dan JSON.
- Cooldown server-side per IP per room (best-effort per instance) serta cooldown client.
- Kunci Supabase hanya disimpan di environment Netlify, tidak dimasukkan ke Lua.

## 1. Siapkan Supabase
1. Buat project gratis di Supabase.
2. Buka **SQL Editor**, jalankan `supabase/schema.sql`.
3. Ambil Project URL dari Project Settings → API.
4. Ambil **service_role key** dari API keys. Jangan pernah menaruh key ini di script Lua atau membagikannya.

## 2. Deploy backend ke Netlify
1. Buat repository GitHub baru dan unggah isi folder proyek ini.
2. Import repository tersebut ke Netlify.
3. Build command boleh kosong; publish directory isi `public` atau `.` sesuai pengaturan Netlify. Functions otomatis ada di `netlify/functions`.
4. Pada Netlify → Site configuration → Environment variables, tambahkan:
   - `SUPABASE_URL` = URL project Supabase, misalnya `https://xxxx.supabase.co`
   - `SUPABASE_SERVICE_ROLE_KEY` = service_role key
5. Deploy ulang setelah menambahkan environment variables.
6. Endpoint akan tersedia di `https://NAMA-SITUS.netlify.app/.netlify/functions/chat`.
7. Tes endpoint dengan GET:
   `https://NAMA-SITUS.netlify.app/.netlify/functions/chat?room=LOBBY&after=0`

Catatan: ini endpoint fungsi Netlify langsung, jadi tidak membutuhkan `netlify.toml` rewrite.

## 3. Konfigurasi Lua
Buka `monetloader/thirdparty_room_chat.lua`, ubah:
`local API_BASE = 'https://NAMA-SITUS.netlify.app/.netlify/functions/chat'`
menjadi URL Netlify kamu.

Letakkan file ke:
`Android/media/<package-game-kamu>/monetloader/thirdparty_room_chat.lua`

Library yang diperlukan:
- `mimgui`
- `ffi`
- `requests`
- `cjson`

Pada beberapa paket MonetLoader, library tambahan dipasang di `.../monetloader/lib/`. Jangan unduh library acak; gunakan paket library yang cocok dengan build MonetLoader kamu.

## 4. Cara pakai
1. Masuk server SA-MP dan ketik `/room`.
2. Masukkan Room ID, misalnya `LOBBY`, lalu tekan **Join**.
3. Untuk membuat room baru, ketik ID yang belum pernah dipakai lalu tekan **Create / Join**. Room tidak perlu didaftarkan sebelumnya; ID adalah ruang logis.
4. Ketik pesan lalu tekan **Send**.
5. Pengguna lain dengan endpoint yang sama dan Room ID yang sama dapat membaca pesan yang sama.

## 5. Uji backend
Kirim pesan dengan curl:
```sh
curl -X POST 'https://NAMA-SITUS.netlify.app/.netlify/functions/chat' \
  -H 'Content-Type: application/json' \
  -d '{"action":"send","room":"LOBBY","nickname":"Tester","message":"Halo room!"}'
```
Ambil pesan:
```sh
curl 'https://NAMA-SITUS.netlify.app/.netlify/functions/chat?room=LOBBY&after=0'
```

## Batasan keamanan dan operasional
- Room global: siapa pun yang mengetahui ID dapat membaca dan mengirim pesan. Jangan kirim data pribadi.
- Nickname SA-MP tidak terverifikasi; pengguna dapat memalsukannya. Ini bukan sistem autentikasi.
- Cooldown berbasis memori fungsi adalah best-effort dan dapat reset saat instance berganti. Untuk komunitas besar, pindahkan rate limit ke RPC/Redis yang atomik.
- Supabase dan Netlify memiliki batas gratis dan dapat berubah; periksa dashboard pemakaian. Paket gratis Netlify saat ini berbasis kredit bulanan. Dokumentasi: https://www.netlify.com/pricing/ dan https://docs.netlify.com/build/functions/usage-and-billing/
- Jika `requests`/HTTPS tidak tersedia di build MonetLoader, client tidak dapat menghubungi backend sampai library HTTP yang kompatibel dipasang.
