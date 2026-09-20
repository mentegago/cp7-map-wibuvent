# Comipara 7 Booth Map

Aplikasi Flutter web untuk melihat peta booth creator di acara Comipara 7.

## Data

- Peta booth dibundel di `data/map.json`.
- Katalog awal dikonversi dari Cardinal API oleh `tools/convert_cardinal_data.py`.
- Pembaruan katalog runtime diambil dari `https://cp7-config.nnt.gg` menggunakan katalog v1 yang sama.

Untuk memperbarui data awal dari Cardinal:

```bash
python tools/convert_cardinal_data.py
```

Script tersebut mengonversi data Cardinal ke `catalog-initial.json` serta `fandoms-initial.json`; model Flutter tetap memakai schema aplikasi v1.
