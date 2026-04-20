require 'uri'
require 'net/http'
require 'zlib'
require 'stringio'
require_relative '../base_scraper'

class CineplexNeufahrnScraper < BaseScraper
  CINEMA_NAME     = 'Cineplex Neufahrn'
  CINEMA_BASE_URL = 'https://www.cineplex.de'
  CINEMA_URL      = 'https://www.cineplex.de/neufahrn/programm?centerFilters=&movieFilters=&releaseFilters=&performancesFilters=today&auditoriumsFilters='

  TODAY_TEXT      = 'HEUTE'
  SHOWTIME_REGEX  = /\d{1,2}:\d{2}/

  def scrape
    require 'nokogiri'
    movies = []
    today_date = Date.today.to_s
    today_compact = Date.today.strftime('%d.%m')

    begin
      log("Scraping #{CINEMA_URL}")
      html = fetch_html(CINEMA_URL)
      doc  = Nokogiri::HTML(html)

      sections = doc.css('[data-testid="screening-section"]')
      log("Found #{sections.length} screening sections")

      sections.each do |section|
        title_el = section.at_css('[data-testid="description-section"] h2')
        next unless title_el

        title = title_el.text.strip
        next if title.empty?

        entries = section.css('[data-testid="screening-entry"]').select do |entry|
          label = entry.at_css('[data-testid="tag"] span')&.text.to_s.strip.upcase
          label.include?(TODAY_TEXT) || label.include?(today_compact)
        end
        next if entries.empty?

        showtimes = entries.flat_map { |e| e.text.scan(SHOWTIME_REGEX) }.uniq.sort

        poster_url  = absolute_url(section.at_css('img[class*="FilmCard_film-card__image"]')&.[]('src'))
        details_url = absolute_url(section.at_css('[data-testid="description-section"] a[href*="/film/"]')&.[]('href'))
        ticket_links = entries.map { |e| e.at_css('a[href*="tickets.cineplex.de"]')&.[]('href') }.compact.uniq

        movie_data = format_movie(
          title:    title,
          showtimes: showtimes,
          date:     today_date,
          language: parse_language(entries.map(&:text).join(' ')),
          cinema:   CINEMA_NAME
        )

        movie_data[:poster_url]   = poster_url   if poster_url
        movie_data[:details_link] = details_url  if details_url
        movie_data[:ticket_link]  = ticket_links.first if ticket_links.any?
        movie_data[:ticket_links] = ticket_links        if ticket_links.any?

        movies << movie_data
      end

      movies = deduplicate(movies)
    rescue StandardError => e
      log("Error: #{e.message}")
      log(e.backtrace.first(3).join("\n"))
    end

    log("Scraped #{movies.length} movies")
    movies
  end

  private

  def fetch_html(url)
    uri = URI(url)
    req = Net::HTTP::Get.new(uri)
    req['User-Agent']      = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    req['Accept']          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    req['Accept-Encoding'] = 'gzip, deflate'
    req['Accept-Language'] = 'de-DE,de;q=0.9'

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }

    body = res.body
    if res['Content-Encoding'] == 'gzip'
      body = Zlib::GzipReader.new(StringIO.new(body)).read
    end
    body.force_encoding('UTF-8')
  end

  def deduplicate(movies)
    grouped = {}
    movies.each do |m|
      key = m[:title].to_s.downcase.strip
      if grouped[key]
        grouped[key][:showtimes] = (grouped[key][:showtimes] + m[:showtimes]).uniq.sort
        grouped[key][:poster_url] ||= m[:poster_url]
      else
        grouped[key] = m
      end
    end
    grouped.values
  end

  def absolute_url(url)
    return nil if url.nil? || url.to_s.empty?
    return url if url.to_s.start_with?('http://', 'https://')
    URI.join(CINEMA_BASE_URL, url).to_s
  rescue URI::InvalidURIError
    nil
  end
end
