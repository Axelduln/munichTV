require 'ferrum'
require_relative '../ferrum_base_scraper'

# Template for creating new cinema scrapers
# Copy this file and rename to: cinema_name_scraper.rb
# Then customize the constants and selectors

class CinemaXXScraper < FerrumBaseScraper
  CINEMA_URL = 'https://www.cinemaxx.de/kinoprogramm/munchen/jetzt-im-kino'
  CINEMA_NAME = 'CinemaXX München'
  
  def scrape
    movies = []
    browser = create_browser
    
    begin
      log("Scraping #{CINEMA_URL}")
      browser.go_to(CINEMA_URL)
      wait_for_load(browser, duration: 2)
      
      # 1. Find all movie containers
      movie_cards = browser.css('.showing-listing__item')
      
      log("Found #{movie_cards.length} movie cards")
      
      # 2. Loop through each movie
      movie_cards.each do |card|
        # Extract title (required)
        title = safe_text(card, '.film-heading__title')
        next if title.nil? || title.empty?
        
        # Extract showtimes (array of times)
        showtime_elements = card.css('.session-time')
        showtimes = parse_times(showtime_elements)
        
        # Extract language (optional)
        language_text = safe_text(card, '.language')  # ⚠️ CHANGE SELECTOR
        language = parse_language(language_text)
        
        # Extract duration (optional)
        duration_text = safe_text(card, '.duration')  # ⚠️ CHANGE SELECTOR
        duration = parse_duration(duration_text)
        
        # Extract genre (optional)
        genre = safe_text(card, '.genre')  # ⚠️ CHANGE SELECTOR
        
        # Extract description (optional)
        description = safe_text(card, '.description')  # ⚠️ CHANGE SELECTOR
        
        # Extract date (optional, defaults to today)
        date_text = safe_text(card, '.date')  # ⚠️ CHANGE SELECTOR
        date = parse_date(date_text) if date_text
        
        # Extract poster
        img_elem = card.at_css('img[loading="lazy"]')
        poster_url = img_elem ? img_elem['src'] : nil

        # Add movie to results using the format_movie helper
        movie_data = format_movie({
          title: title,
          showtimes: showtimes,
          language: language,
          duration: duration,
          genre: genre,
          description: description,
          date: date,
          cinema: CINEMA_NAME
        })
        movie_data[:poster_url] = poster_url if poster_url
        movies << movie_data
      end
      
    rescue StandardError => e
      log("Error: #{e.message}")
      log(e.backtrace.first(3).join("\n"))
    ensure
      browser.quit if browser
    end
    
    log("Scraped #{movies.length} movies")
    movies
  end
end

# HOW TO USE THIS TEMPLATE:
#
# 1. Copy this file into a category folder (for example):
#    scrapers/blockbuster/cinemaxx_scraper.rb
#
# 2. Rename the class: TemplateScraper → CinemaXXScraper
#
# 3. Update constants:
#    CINEMA_URL = 'https://www.cinemaxx.de/muenchen'
#    CINEMA_NAME = 'CinemaXX München'
#
# 4. Open the website in Chrome and inspect HTML
#    - Right-click → Inspect
#    - Find the movie cards container
#    - Find selectors for title, showtimes, language, etc.
#
# 5. Replace all the CSS selectors marked with ⚠️
#
# 6. Test the scraper:
#    docker-compose restart
#    curl http://localhost:4567/scrape/cinemaxx | jq .
#
# 7. Register in app.rb:
#    require_relative 'scrapers/blockbuster/cinemaxx_scraper'
#    CINEMAS = {
#      'cinemaxx' => CinemaXXScraper,
#      ...
#    }
#
# HELPER METHODS AVAILABLE (from BaseScraper):
#
# - create_browser() → creates browser instance
# - format_movie(data) → formats movie hash consistently
# - parse_time(str) → extracts time like "14:30"
# - parse_times(elements) → extracts array of times
# - parse_date(str) → converts to YYYY-MM-DD format
# - parse_language(str) → normalizes to OV/DE/OmU
# - parse_duration(str) → formats as "120 min"
# - safe_text(element, selector) → safely get text
# - safe_attr(element, attr, selector) → safely get attribute
# - wait_for_load(browser, duration: 2) → wait for page
# - log(message) → log with scraper class name
