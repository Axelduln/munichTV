# Munich Movies

A kiosk system that shows today's movie showtimes from Munich cinemas. Visitors scan a QR code to browse films by category (Blockbuster / Mixed / Arthouse), see results, and view film details.

## How it works

A CPEE workflow orchestrates the session:
1. Starts the Sinatra app, waits for it to be ready, then checks if today's showtimes are already scraped — triggers scraping if not
2. Displays a landing page with three QR codes (one per category)
3. Visitor scans a QR on their phone → CPEE fetches movies → displays results
4. Visitor scans a movie QR → detail page with poster, description, showtimes
5. Visitor scans back → returns to landing
6. 60s idle timeout resets the session

## Architecture

```
Kiosk (CPEE Frame)
  landing.html / results.html / detail.html
      |
      | QR scan → send.php → PUT callback
      v
CPEE (cpee.org, instance 47)
  process2_cinema_dashboard.xml
      |
      | HTTP
      v
Sinatra API (lehre server, port 63826)
  app.rb
      |
      +-- SQLite (db/movies.db)
      +-- Scrapers (18 cinemas)
            Ferrum/Chrome  →  blockbuster cinemas
            HTTP/Nokogiri  →  arthouse & mixed cinemas
            Kinoheld API   →  most arthouse cinemas
            Cineamo API    →  Neues Rottmann
```

## Tech stack

- Ruby 2.7 / Sinatra 3.1 / SQLite3
- Ferrum 0.13 (headless Chrome via remote debugging)
- Nokogiri / net/http
- CPEE workflow engine
- PHP relay for QR callback shortening

## Structure

```
app.rb                        Sinatra API
db/database.rb                DB helpers
scrapers/                     All cinema scrapers
  base_scraper.rb             Base class (HTTP)
  ferrum_base_scraper.rb      Base class (headless Chrome)
  blockbuster/
  mixed/
  arthouse/
frames/                       Kiosk HTML/PHP
  landing.html
  results.html
  detail.html
  send.php
  store_cb.php
cpee/                         CPEE process definitions
  process1_scraper_orchestrator.xml
  process2_cinema_dashboard.xml
```

## Cinemas covered

**Blockbuster:** Mathäser, CinemaxX, Royal München, Astor, Gloria  
**Mixed:** Museum Lichtspiel, Cinema München OV, Cineplex Neufahrn, Astor  
**Arthouse:** Theatiner, City-Atelier, Neues Rottmann, Werkstattkino, Cadillac/Veranda, Filmmuseum, Arena Filmtheater, Monopol

---

## Using the app

### Start / stop

```bash
curl https://lehre.bpm.in.tum.de/~ge82bob/start_app.php
curl https://lehre.bpm.in.tum.de/~ge82bob/stop.php
```

### Trigger scrapes manually

The cron daemon is down — trigger scrapes via localhost to bypass nginx timeout:

```bash
ssh lehre "curl -s localhost:63826/scrape/category/blockbuster"
ssh lehre "curl -s localhost:63826/scrape/category/mixed"
ssh lehre "curl -s localhost:63826/scrape/category/arthouse"
```

Each takes several minutes. Check status:

```bash
curl -s "https://lehre.bpm.in.tum.de/ports/63826/admin/scrape_status"
```

### Reset scrape data

Delete the database on the server to force a fresh scrape next time the CPEE process starts:

```bash
ssh lehre "rm ~/public_html/db/movies.db"
```

---

## Updating or adding a scraper

### Update an existing scraper

Edit the scraper file locally, then deploy:

```bash
scp scrapers/<subdir>/<scraper>.rb lehre:~/public_html/scrapers/<subdir>/<scraper>.rb
```

Restart the app if it's running, then trigger a manual scrape to test.

### Add a new scraper

1. **Create the scraper file** in the appropriate subdirectory (`blockbuster/`, `mixed/`, or `arthouse/`).
   - Extend `BaseScraper` for HTTP/Nokogiri scrapers
   - Extend `FerrumBaseScraper` for scrapers that need a headless browser
   - Implement a `scrape` method that returns an array of movies via `format_movie`

2. **Register it in `app.rb`** — add an entry to the `CINEMAS` hash:
   ```ruby
   cinema_key: { name: 'Display Name', scraper: 'subdir/cinema_key_scraper' }
   ```
   And add it to the relevant category in `CINEMA_CATEGORIES`:
   ```ruby
   'blockbuster' => ['cinema_key', ...]
   ```

3. **Deploy** both the scraper file and `app.rb`:
   ```bash
   scp app.rb lehre:~/public_html/app.rb
   scp scrapers/<subdir>/<scraper>.rb lehre:~/public_html/scrapers/<subdir>/<scraper>.rb
   ```

4. **Test** with a targeted scrape:
   ```bash
   ssh lehre "curl -s localhost:63826/scrape/cinema_key"
   ```

### `format_movie` fields

All scrapers return movies using `format_movie` from `BaseScraper`:

```ruby
format_movie(
  title:        'Film Title',
  language:     'DE',           # or 'OV', 'OmU'
  duration:     '120 min',
  poster_url:   'https://...',
  description:  '...',
  showtimes:    ['18:00', '20:30'],
  ticket_link:  'https://...',
  details_link: 'https://...',
  cinema:       cinema_key,
  display_name: 'Display Name'
)
```

