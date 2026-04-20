require 'ferrum'
require 'uri'
require_relative '../ferrum_base_scraper'

class RoyalScraper < FerrumBaseScraper
  CINEMA_NAME = 'Royal München'
  CINEMA_URL = 'https://royal-muenchen.de/filmprogramm/'

  def scrape
    movies = []
    browser = create_browser

    begin
      log("Scraping #{CINEMA_URL}")
      browser.go_to(CINEMA_URL)
      wait_for_load(browser, duration: 2)

      movie_rows = wait_for_movie_rows(browser)
      log("Found #{movie_rows.length} movie rows")

      movie_rows.each do |row|
        title = safe_text(row, 'h3.wpti-movie-title')
        title = safe_text(row, 'a.wpti-title-link') if title.nil? || title.empty?
        next if title.nil? || title.empty?

        poster_url = safe_attr(row, 'src', 'a.wpti-poster-link img')

        date_headers = row.css('.wpti-date-header').map { |header| safe_text(header) }
        today_index = date_headers.find_index { |header_text| header_text&.match?(/\bheute\b/i) }
        next if today_index.nil?

        date_time_columns = row.css('.wpti-date-times')
        today_block = date_time_columns[today_index]
        next if today_block.nil?

        time_links = today_block.css('a.wpti-time-button')

        showtimes = parse_times(time_links).uniq
        next if showtimes.empty?

        ticket_links = time_links.map { |link| absolute_url(safe_attr(link, 'href')) }.compact.uniq
        event_ids = ticket_links.map { |link| extract_event_id(link) }.compact.uniq

        movie_data = format_movie({
          title: title,
          showtimes: showtimes,
          date: Date.today.to_s,
          cinema: CINEMA_NAME
        })

        movie_data[:poster_url] = poster_url if poster_url
        movie_data[:ticket_link] = ticket_links.first if ticket_links.any?
        movie_data[:ticket_links] = ticket_links if ticket_links.any?
        movie_data[:event_id] = event_ids.first if event_ids.any?
        movie_data[:event_ids] = event_ids if event_ids.any?

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

  private

  def wait_for_movie_rows(browser, timeout_seconds: 12)
    start_time = Time.now
    rows = []

    while Time.now - start_time < timeout_seconds
      rows = browser.css('.wpti-movie-row')
      return rows if rows.any?

      sleep 0.5
    end

    rows
  end

  def absolute_url(url)
    return nil if url.nil? || url.empty?
    return url if url.start_with?('http://', 'https://')

    URI.join(CINEMA_URL, url).to_s
  rescue URI::InvalidURIError
    url
  end

  def extract_event_id(url)
    return nil if url.nil? || url.empty?

    match = url.match(/[?&]eventID=(\d+)/i)
    match && match[1]
  end
end