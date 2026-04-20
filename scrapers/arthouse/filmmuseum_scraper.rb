require 'net/http'
require 'json'
require_relative '../base_scraper'

class FilmmuseumScraper < BaseScraper
  CINEMA_NAME = 'Filmmuseum München'
  CINEMA_ID   = 1377
  API_URL     = 'https://next-live.kinoheld.de/graphql'
  QUERY       = <<~GQL
    query($cinemaId: ID!, $dates: [Date!]!) {
      shows(cinemaId: $cinemaId, dates: $dates) {
        data {
          id
          beginning
          deeplink
          audioLanguage { name }
          subtitleLanguage { name }
          movie {
            id
            title
            duration
            shortDescription
            thumbnailImage { url }
            urlSlug
          }
        }
      }
    }
  GQL

  def scrape
    today = Date.today.to_s
    shows = fetch_shows(today)

    shows
      .group_by { |s| s.dig('movie', 'id') }
      .filter_map { |_movie_id, movie_shows| build_movie(movie_shows) }
  end

  private

  def fetch_shows(date)
    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
    request.body = JSON.generate(
      query:     QUERY,
      variables: { cinemaId: CINEMA_ID, dates: [date] }
    )

    response = http.request(request)
    raise "Request failed with #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    data.dig('data', 'shows', 'data') || []
  end

  def build_movie(shows)
    movie = shows.first['movie']
    return nil unless movie

    showtimes = shows.map { |s| parse_time(s['beginning']) }.compact.uniq.sort
    return nil if showtimes.empty?

    language = parse_show_language(shows.first)

    movie_data = format_movie(
      title:       movie['title'],
      showtimes:   showtimes,
      date:        Date.today.to_s,
      language:    language,
      duration:    movie['duration'] ? "#{movie['duration']} min" : nil,
      description: movie['shortDescription'],
      cinema:      CINEMA_NAME
    )

    poster_url = movie.dig('thumbnailImage', 'url')
    movie_data[:poster_url] = poster_url if poster_url

    deeplinks = shows.map { |s| s['deeplink'] }.compact
    if deeplinks.any?
      movie_data[:ticket_link]  = deeplinks.first
      movie_data[:ticket_links] = deeplinks
    end

    event_ids = shows.map { |s| s['id'] }.compact
    if event_ids.any?
      movie_data[:event_id]  = event_ids.first
      movie_data[:event_ids] = event_ids
    end

    movie_data
  end

  def parse_show_language(show)
    audio    = show.dig('audioLanguage', 'name').to_s.upcase
    subtitle = show.dig('subtitleLanguage', 'name').to_s.upcase

    return 'OmU' if subtitle.include?('GERMAN') || subtitle.include?('DEUTSCH')
    return 'OV'  if !audio.empty? && !audio.include?('GERMAN') && !audio.include?('DEUTSCH')

    'DE'
  end
end
