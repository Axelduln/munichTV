require 'json'
require 'net/http'
require 'uri'
require_relative '../base_scraper'

class MuseumLichtspielScraper < BaseScraper
  CINEMA_NAME = 'Museum Lichtspiele'
  PROGRAM_URL = 'https://www.museum-lichtspiele.de/programm'
  IMAGE_BASE_URL = 'https://www.museum-lichtspiele.de/images/Breite_235px_RGB/'
  DETAIL_BASE_URL = 'https://www.museum-lichtspiele.de/detail'
  PROGRAM_PREFIX = 'var programm = '

  def scrape
    target_date = Date.today
    log("Scraping #{PROGRAM_URL}")

    html = fetch_program_html
    program = extract_program_data(html)
    movies = build_movies(program, target_date)

    log("Scraped #{movies.length} movies")
    movies
  rescue StandardError => e
    log("Error: #{e.message}")
    log(e.backtrace.first(3).join("\n"))
    []
  end

  private

  def fetch_program_html
    uri = URI(PROGRAM_URL)
    response = Net::HTTP.get_response(uri)
    raise "Request failed with #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def extract_program_data(html)
    start_index = html.index(PROGRAM_PREFIX)
    raise 'Embedded program data not found' if start_index.nil?

    json_start = html.index('{', start_index)
    raise 'Program JSON start not found' if json_start.nil?

    json_end = find_matching_brace(html, json_start)
    raise 'Program JSON end not found' if json_end.nil?

    JSON.parse(html[json_start..json_end])
  end

  def find_matching_brace(text, start_index)
    depth = 0
    in_string = false
    escaped = false

    text.chars.each_with_index do |char, index|
      next if index < start_index

      if escaped
        escaped = false
        next
      end

      if char == '\\'
        escaped = true if in_string
        next
      end

      if char == '"'
        in_string = !in_string
        next
      end

      next if in_string

      depth += 1 if char == '{'
      depth -= 1 if char == '}'

      return index if depth.zero?
    end

    nil
  end

  def build_movies(program, target_date)
    target_key = "datum_#{target_date}"

    program.fetch('filme', {}).values.filter_map do |film|
      next unless film.is_a?(Hash)

      facts = film.fetch('filmfakten', {})
      shows = normalize_shows(film.dig('vorstellungen', 'termine', target_key))
      next if shows.empty?

      title = facts['titel']
      next if title.nil? || title.empty?

      showtimes = shows.map { |show| parse_time(show['zeit']) }.compact.uniq.sort
      next if showtimes.empty?

      ticket_links = shows.map { |show| show['link_fixticket'] }.compact.uniq
      event_ids = ticket_links.map { |link| extract_show_id(link) }.compact.uniq
      details_link = build_details_link(facts)
      poster_url = build_poster_url(facts)

      movie_data = format_movie(
        title: title,
        showtimes: showtimes,
        date: target_date.to_s,
        language: parse_language(facts['Versionsmarker']),
        duration: parse_duration(facts['laufzeit']),
        description: facts['inhalt'],
        cinema: CINEMA_NAME
      )

      movie_data[:poster_url] = poster_url if poster_url
      movie_data[:details_link] = details_link if details_link
      movie_data[:ticket_link] = ticket_links.first if ticket_links.any?
      movie_data[:ticket_links] = ticket_links if ticket_links.any?
      movie_data[:event_id] = event_ids.first if event_ids.any?
      movie_data[:event_ids] = event_ids if event_ids.any?
      movie_data
    end
  end

  def normalize_shows(raw_shows)
    case raw_shows
    when Array
      raw_shows.select { |show| show.is_a?(Hash) }
    when Hash
      [raw_shows]
    else
      []
    end
  end

  def build_details_link(facts)
    id = facts['idf']
    title_slug = facts['titel'].to_s.gsub(/[\s\/]+/, '_')
    return nil if id.nil? || title_slug.empty?

    "#{DETAIL_BASE_URL}/#{id}/#{title_slug}"
  end

  def build_poster_url(facts)
    poster_id = facts.dig('plakat_ids', 'id')
    return nil if poster_id.nil? || poster_id.empty?

    URI.join(IMAGE_BASE_URL, poster_id).to_s
  rescue URI::InvalidURIError
    nil
  end

  def extract_show_id(url)
    return nil if url.nil? || url.empty?

    match = url.match(/[?&]showId=(\d+)/i)
    match && match[1]
  end
end
