require 'net/http'
require 'json'
require_relative '../base_scraper'

class NeuesRottmannScraper < BaseScraper
  CINEMA_NAME = 'Neues Rottmann Kino'
  CINEMA_ID   = 721
  POSTER_BASE = 'https://image.tmdb.org/t/p/w500'

  def scrape
    today = Date.today.to_s
    showings = fetch_showings(today)

    showings
      .group_by { |s| s['cineamoMovieId'] }
      .filter_map { |movie_id, shows| build_movie(movie_id, shows, today) }
  end

  private

  def fetch_showings(date)
    uri = URI("https://api.cineamo.com/showings?cinemaId=#{CINEMA_ID}&date=#{date}")
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.get(uri.request_uri, 'Accept' => 'application/json')
    end
    data = JSON.parse(res.body)
    data.dig('_embedded', 'showings') || []
  rescue StandardError => e
    log("Error fetching showings: #{e.message}")
    []
  end

  def fetch_movie(movie_id)
    uri = URI("https://api.cineamo.com/movies/#{movie_id}")
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.get(uri.request_uri, 'Accept' => 'application/json')
    end
    JSON.parse(res.body)
  rescue StandardError
    {}
  end

  def build_movie(movie_id, shows, today)
    details = fetch_movie(movie_id)

    title = details['title'] || shows.first['name']
    return nil if title.nil? || title.empty?

    showtimes = shows.map { |s| parse_utc_to_local(s['startDatetime']) }.compact.sort
    return nil if showtimes.empty?

    movie_data = format_movie(
      title:       title,
      showtimes:   showtimes,
      date:        today,
      language:    parse_show_language(shows.first),
      duration:    details['runtime'] ? "#{details['runtime']} min" : nil,
      description: details['overview'],
      cinema:      CINEMA_NAME
    )

    poster = details['posterPath']
    movie_data[:poster_url] = "#{POSTER_BASE}#{poster}" if poster

    ticket_links = shows.map { |s| s['onlineTicketUrl'] }.compact
    if ticket_links.any?
      movie_data[:ticket_link]  = ticket_links.first
      movie_data[:ticket_links] = ticket_links
    end

    event_ids = shows.map { |s| s['id']&.to_s }.compact
    if event_ids.any?
      movie_data[:event_id]  = event_ids.first
      movie_data[:event_ids] = event_ids
    end

    movie_data
  end

  # Convert UTC ISO datetime to Munich local time string (HH:MM)
  # Munich is UTC+2 in summer (CEST), UTC+1 in winter (CET)
  def parse_utc_to_local(datetime_str)
    return nil if datetime_str.nil?
    match = datetime_str.match(/T(\d{2}):(\d{2})/)
    return nil unless match

    hour, min = match[1].to_i, match[2].to_i

    # Determine DST offset for given date (last Sunday in March to last Sunday in October)
    date_match = datetime_str.match(/(\d{4})-(\d{2})-(\d{2})/)
    if date_match
      month = date_match[2].to_i
      offset = (month >= 4 && month <= 10) ? 2 : 1
    else
      offset = 2
    end

    local_hour = (hour + offset) % 24
    format('%02d:%02d', local_hour, min)
  end

  def parse_show_language(show)
    return 'OV'  if show['isOriginalLanguage']
    return 'OmU' if show['isSubtitled']
    return 'OV'  if show['language'].nil? && show['originalLanguage'] && show['originalLanguage'] != 'deu'
    'DE'
  end
end
