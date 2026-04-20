# Munich Movies — Documentation

_Last updated: 2026-04-20_

## Deployment

App runs on the lehre server at `lehre.bpm.in.tum.de`, port 63826.

```bash
# Stop / start the app
curl https://lehre.bpm.in.tum.de/~ge82bob/stop.php
curl https://lehre.bpm.in.tum.de/~ge82bob/start_app.php

# Deploy changes (scp to server)
scp app.rb lehre:~/public_html/app.rb
scp scrapers/<file> lehre:~/public_html/scrapers/<subdir>/<file>
scp frames/<file> lehre:~/public_html/frames/<file>

# Trigger scrapes manually (bypass nginx timeout via localhost)
ssh lehre "curl -s localhost:63826/scrape/category/blockbuster"
ssh lehre "curl -s localhost:63826/scrape/category/mixed"
ssh lehre "curl -s localhost:63826/scrape/category/arthouse"

# Check scrape status
curl -s "https://lehre.bpm.in.tum.de/ports/63826/admin/scrape_status"
```

Server directory layout:
```
~/public_html/
  app.rb
  scrapers/
    base_scraper.rb
    ferrum_base_scraper.rb
    blockbuster/
    mixed/
    arthouse/
  frames/
    landing.html  results.html  detail.html
    send.php  store_cb.php
    tmp/          ← must exist, chmod 777
```

## CPEE

Process file: `processhub/process2_cinema_dashboard.xml`.
Scraping file: `processhub/process2_scraper_orchestrator.xml`.

**Data elements:** `all_movies`, `category`, `selected_movie`, `page_num`, `page_result`, `needs_scraping`, `running`, `timer`, `favourite_cinema`


**Idle timeout:** The timer branch runs a pre-test loop (`data.timer == true`). Each iteration sets `data.timer = false`, waits 60s, then re-checks. Any UI task completing sets `data.timer = true`, resetting the window. If no activity for 60s, the loop exits and sets `data.running = false`, ending the session.

## API endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/admin/scrape_status` | `{ needs_scraping: bool, ... }` |
| POST | `/admin/scrape_all` | Scrape all cinemas |
| GET | `/scrape/category/:category` | Scrape full category (slow) |
| GET | `/scrape/scrape_blockbuster` | Blockbuster movies from DB |
| GET | `/scrape/scrape_mixed` | Mixed movies from DB |
| GET | `/scrape/scrape_arthouse` | Arthouse movies from DB |

Movies are returned with a nested `cinemas` array `display_name` and `showtimes` are inside each cinema object, not at the top level.

## Scrapers

**Ferrum (headless Chrome):** Mathäser, CinemaxX, Royal, Gloria  
**HTTP/Nokogiri:** Cineplex Neufahrn (Next.js SSR), Museum Lichtspiel, Cinema München OV  
**Kinoheld GraphQL API:** Astor, Theatiner, Monopol, City-Atelier, Werkstattkino, Cadillac/Veranda, Filmmuseum, Arena Filmtheater  
**Cineamo API:** Neues Rottmann (`api.cineamo.com/showings?cinemaId=721`)

Chrome setup: `FerrumBaseScraper` spawns Chrome externally on port 9222 and connects Ferrum via the remote debugging URL. A shared singleton browser is reused across scrapers; `browser.quit` resets state instead of killing the process.

## Frames / QR flow

```
landing.html loads
  → stores CPEE callback URL via store_cb.php (returns 6-char token)
  → QR encodes: send.php?info=<category>&token=<token>

User scans QR on phone
  → send.php resolves token → PUTs value=<category> to CPEE callback
  → CPEE fetches movies → stores in data.all_movies → displays results.html

results.html / detail.html
  → read data.all_movies from CPEE: <instance_url>/properties/dataelements/all_movies
```

All QR codes use `correctLevel: QRCode.CorrectLevel.L`. QR codes never encode external URLs.
