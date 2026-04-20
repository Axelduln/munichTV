require 'ferrum'
require_relative '../ferrum_base_scraper'

class MathaeserScraper < FerrumBaseScraper
  CINEMA_NAME = 'Mathäser'
  BASE_URL = 'https://www.mathaeser.de/mm/programm/tagesprogramm-'
  
  # Generate URL for specific date (defaults to today)
  def cinema_url(date = Date.today)
    "#{BASE_URL}#{date.strftime('%Y-%m-%d')}"
  end
  
  def scrape
    movies = []
    browser = create_browser
    url = cinema_url  # Will use today's date
    
    begin
      log("Scraping #{url}")
      browser.go_to(url)
      # Page loads with date-specific content, no wait needed
      
      # 1. Find all movie containers
      movie_cards = browser.css('section.bg-2.movie.mb-2')
      
      log("Found #{movie_cards.length} movie cards")
      
      movie_cards.each do |card|
        # 2. Movie title
        title = safe_text(card, 'h2.hl--1.hidden-min-sm')
        next if title.nil? || title.empty?

        # 3a. Poster
        img_elem = card.at_css('img.img-fluid')
        poster_url = img_elem ? img_elem['src'] : nil
        
        # 3. Showtimes - filter out unbookable/past events
        showtimes = []
        
        card.css('.prog2__wrap').each do |wrap|
          time_elem = wrap.at_css('.prog2__time')
          next unless time_elem
          
          # Check if showtime has "nicht mehr buchbar" message (not bookable)
          buy_text_elem = wrap.at_css('.buy__text')
          if buy_text_elem
            buy_text = buy_text_elem.text.strip
            # Skip if it says not bookable (filters out future days auto-loaded)
            next if buy_text.length > 30  # Long messages indicate unbookable
          end
          
          time = parse_time(time_elem.text)
          showtimes << time if time
        end
        
        showtimes.uniq!  # Remove duplicates
        
        # 4. Optional: Language - TODO: Find selector
        language = parse_language(safe_text(card, '.REPLACE-WITH-LANGUAGE-SELECTOR'))
        
        # 5. Optional: Duration - TODO: Find selector
        duration = parse_duration(safe_text(card, '.REPLACE-WITH-DURATION-SELECTOR'))
        
        movie_data = format_movie({
          title: title,
          showtimes: showtimes,
          language: language,
          duration: duration,
          date: Date.today.to_s,
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
