require 'net/http'
require 'json'
require_relative '../base_scraper'

class CityAtelierScraper < BaseScraper
  CINEMA_NAME = 'City Atelier'
  BASE_URL    = 'https://www.city-kinos.de'

  def scrape
    today = Date.today.to_s
    html  = fetch_html(today)
    films = extract_films(html)

    films.filter_map { |film| build_movie(film, today) }
  end

  private

  def fetch_html(date)
    uri = URI("#{BASE_URL}/filme?sort=Popularity&date=#{date}&tab=daily&sessionsExpanded=false&film=")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    response = http.get(uri.request_uri)
    raise "Request failed with #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def extract_films(html)
    match = html.match(/<script id="__NEXT_DATA__" type="application\/json">(.*?)<\/script>/m)
    raise '__NEXT_DATA__ not found' unless match

    data = JSON.parse(match[1])
    data.dig('props', 'pageProps', 'films') || []
  end

  def build_movie(film, today)
    fields   = film['fields'] || {}
    sessions = (fields['sessions'] || []).select { |s| s.dig('fields', 'startTime').to_s.start_with?(today) }
    return nil if sessions.empty?

    showtimes = sessions.map { |s| parse_time(s.dig('fields', 'startTime')) }.compact.uniq.sort
    return nil if showtimes.empty?

    language = parse_format(sessions.first.dig('fields', 'formats') || [])

    movie_data = format_movie(
      title:       fields['title'],
      showtimes:   showtimes,
      date:        today,
      language:    language,
      duration:    fields['runtime'] ? "#{fields['runtime']} min" : nil,
      description: fields['tagline'],
      cinema:      CINEMA_NAME
    )

    poster_url = fields.dig('heroImage', 'fields', 'image', 'fields', 'file', 'url')
    movie_data[:poster_url]   = "https:#{poster_url}" if poster_url
    movie_data[:details_link] = "#{BASE_URL}/filme/#{fields['slug']}" if fields['slug']

    movie_data
  end

  def parse_format(formats)
    tags = formats.map(&:upcase)
    return 'OmU' if tags.any? { |t| t.include?('OMU') || t.include?('OMEU') }
    return 'OV'  if tags.include?('OV')

    'DE'
  end
end
