require 'net/http'
require 'json'
require 'time'
require_relative '../base_scraper'

class CinemaMuenchenOvScraper < BaseScraper
  CINEMA_NAME = 'Cinema München'
  PROGRAM_URL = 'https://cinema-muenchen.com/showtimes/?time=today'
  JS_VAR_PREFIX = 'var pmkinoFrontVars = '

  def scrape
    html = fetch_html
    data = extract_program_data(html)
    movies_data = data.dig('apiData', 'movies', 'items') || {}

    movies_data.values.filter_map { |movie| build_movie(movie) }
  end

  private

  def fetch_html
    uri = URI(PROGRAM_URL)
    response = Net::HTTP.get_response(uri)
    raise "Request failed with #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def extract_program_data(html)
    start_index = html.index(JS_VAR_PREFIX)
    raise 'pmkinoFrontVars not found in page' if start_index.nil?

    json_start = html.index('{', start_index)
    raise 'JSON start not found' if json_start.nil?

    json_end = find_matching_brace(html, json_start)
    raise 'JSON end not found' if json_end.nil?

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

  def build_movie(movie)
    all_performances = movie['performances'] || []
    today = berlin_today
    performances = all_performances.select { |p| utc_ms_to_berlin_date(p['timeUtc']) == today }
    return nil if performances.empty?

    showtimes = performances.map { |p| utc_ms_to_berlin_time(p['timeUtc']) }.compact.uniq.sort
    return nil if showtimes.empty?

    language = parse_language_from_attributes(performances.first['attributes'] || [])

    movie_data = format_movie(
      title:       movie['title'],
      showtimes:   showtimes,
      date:        today,
      language:    language,
      duration:    movie['length'] ? "#{movie['length']} min" : nil,
      description: movie['description'],
      cinema:      CINEMA_NAME
    )

    poster_url = movie.dig('images', 'poster', 'url')
    movie_data[:poster_url] = poster_url if poster_url

    event_ids = performances.map { |p| p['id'] }.compact
    if event_ids.any?
      movie_data[:event_id]  = event_ids.first
      movie_data[:event_ids] = event_ids
    end

    movie_data
  end

  # Returns current date string in Europe/Berlin time without any gems.
  # CET = UTC+1, CEST = UTC+2 (last Sunday of March to last Sunday of October).
  def berlin_today
    utc_ms_to_berlin_date(Time.now.utc.to_i * 1000)
  end

  def berlin_offset_seconds
    now_utc = Time.now.utc
    year = now_utc.year

    cest_start = last_sunday_of_month(year, 3, 2)  # last Sunday of March, 02:00 UTC
    cest_end   = last_sunday_of_month(year, 10, 1) # last Sunday of October, 01:00 UTC

    now_utc >= cest_start && now_utc < cest_end ? 7200 : 3600
  end

  def last_sunday_of_month(year, month, hour_utc)
    # Find last day of month, then step back to Sunday
    last_day = Time.utc(year, month, days_in_month(year, month), hour_utc)
    last_day - (last_day.wday * 86400)
  end

  def days_in_month(year, month)
    month == 2 ? (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28) :
      [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
  end

  def utc_ms_to_berlin_date(time_utc_ms)
    return nil if time_utc_ms.nil?

    Time.at(time_utc_ms / 1000 + berlin_offset_seconds).utc.strftime('%Y-%m-%d')
  end

  def utc_ms_to_berlin_time(time_utc_ms)
    return nil if time_utc_ms.nil?

    Time.at(time_utc_ms / 1000 + berlin_offset_seconds).utc.strftime('%H:%M')
  end

  def parse_language_from_attributes(attributes)
    names = attributes.map { |a| a['name'].to_s.upcase }
    return 'OV'  if names.any? { |n| n == 'OV' }
    return 'OmU' if names.any? { |n| n.match?(/OMU|OV\/.*UT|SUBTITL/) }

    'DE'
  end
end
