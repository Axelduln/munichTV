require 'net/http'
require 'json'
require_relative '../base_scraper'

class AstorScraper < BaseScraper
  CINEMA_NAME = 'Astor Film Lounge'
  API_URL = 'https://backend.premiumkino.de/v1/de/muenchen/program'

  def scrape
    data = fetch_program
    today = Date.today.to_s

    todays_performances = data['performances'].select { |p| p['cinemaDay'].to_s.start_with?(today) }
    movie_index = data['movies'].each_with_object({}) { |m, h| h[m['id']] = m }

    todays_performances
      .group_by { |p| p['movieId'] }
      .filter_map { |movie_id, performances| build_movie(movie_index[movie_id], performances) }
  end

  private

  def fetch_program
    uri = URI(API_URL)
    response = Net::HTTP.get_response(uri)
    JSON.parse(response.body)
  end

  def build_movie(movie, performances)
    return nil unless movie

    showtimes = performances.map { |p| parse_time(p['begin']) }.compact.uniq.sort
    return nil if showtimes.empty?

    translation = movie['translations']&.find { |t| t['language'] == 'de' } ||
                  movie['translations']&.first

    language = parse_language(performances.first['language'].to_s)

    movie_data = format_movie(
      title:       movie['name'],
      showtimes:   showtimes,
      date:        Date.today.to_s,
      language:    language,
      duration:    movie['minutes'] ? "#{movie['minutes']} min" : nil,
      description: translation&.dig('descShort'),
      cinema:      CINEMA_NAME
    )

    poster_src = movie.dig('poster', 'src')
    movie_data[:poster_url]   = "https://cdn.premiumkino.de#{poster_src}_w900.webp" if poster_src
    movie_data[:details_link] = "https://muenchen.premiumkino.de/film/#{movie['slug']}" if movie['slug']

    ticket_links = performances.map { |p| "https://muenchen.premiumkino.de/vorstellung/#{p['id']}" }
    if ticket_links.any?
      movie_data[:ticket_link]  = ticket_links.first
      movie_data[:ticket_links] = ticket_links
    end

    event_ids = performances.map { |p| p['id'] }.compact
    if event_ids.any?
      movie_data[:event_id]  = event_ids.first
      movie_data[:event_ids] = event_ids
    end

    movie_data
  end
end
