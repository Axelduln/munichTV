require 'sinatra'
require 'json'
require 'date'
require_relative 'db/database'
require_relative 'scrapers/base_scraper'
require_relative 'scrapers/ferrum_base_scraper'
require_relative 'scrapers/blockbuster/mathaeser_scraper'
require_relative 'scrapers/blockbuster/cinemaxx_scraper'
require_relative 'scrapers/mixed/cineplex_neufahrn_scraper'
require_relative 'scrapers/mixed/museum_lichtspiel_scraper'
require_relative 'scrapers/blockbuster/royal_scraper'
require_relative 'scrapers/blockbuster/gloria_scraper'
require_relative 'scrapers/blockbuster/astor_scraper'
require_relative 'scrapers/mixed/cinema_muenchen_ov_scraper'
require_relative 'scrapers/mixed/rio_filmpalast_scraper'
require_relative 'scrapers/arthouse/monopol_scraper'
require_relative 'scrapers/arthouse/neues_rottmann_scraper'
require_relative 'scrapers/arthouse/cadillac_veranda_scraper'
require_relative 'scrapers/arthouse/werkstattkino_scraper'
require_relative 'scrapers/arthouse/filmmuseum_scraper'
require_relative 'scrapers/arthouse/arena_filmtheater_scraper'
require_relative 'scrapers/arthouse/theatiner_scraper'
require_relative 'scrapers/arthouse/city_atelier_scraper'
# require_relative 'scrapers/arthouse/gasteig_hp8_scraper'

DB = Database.instance

# Pre-warm Chrome at startup so it's ready when scrapers need it
begin
  FerrumBaseScraper.new.send(:create_browser)
  puts "[startup] Chrome pre-warmed successfully"
rescue => e
  puts "[startup] Chrome pre-warm failed: #{e.message}"
end

def json(data)
  content_type :json
  JSON.generate(data)
end

before do
  headers 'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => ['GET', 'POST', 'OPTIONS'],
          'Access-Control-Allow-Headers' => 'Content-Type'
end

options '*' do
  200
end

CINEMAS = {
  'mathaeser' => MathaeserScraper,
  'cinemaxx' => CinemaXXScraper,
  'royal' => RoyalScraper,
  'astor' => AstorScraper,
  'gloria' => GloriaScraper,
  'museum_lichtspiel' => MuseumLichtspielScraper,
  'cinema_muenchen_ov' => CinemaMuenchenOvScraper,
  'rio_filmpalast' => RioFilmpalastScraper,
  'cineplex_neufahrn' => CineplexNeufahrnScraper,
  'theatiner' => TheatinerScraper,
  'monopol' => MonopolScraper,
  'city_atelier' => CityAtelierScraper,
  'neues_rottmann' => NeuesRottmannScraper,
  'werkstattkino' => WerkstattkinoScraper,
  'cadillac_veranda' => CadillacVerandaScraper,
  'filmmuseum' => FilmmuseumScraper,
  # 'gasteig_hp8' => GasteigHp8Scraper,
  'arena_filmtheater' => ArenaFilmtheaterScraper
}.freeze

CINEMA_CATEGORIES = {
  'blockbuster' => ['mathaeser', 'cinemaxx', 'royal', 'astor', 'gloria'],
  'mixed' => ['museum_lichtspiel', 'cinema_muenchen_ov', 'astor', 'cineplex_neufahrn'],
  'arthouse' => [
    'theatiner',
    'city_atelier',
    'neues_rottmann',
    'werkstattkino',
    'cadillac_veranda',
    'filmmuseum',
    'arena_filmtheater'
  ]
}.freeze

DB.seed_cinemas(CINEMAS, CINEMA_CATEGORIES)

get '/' do
  json({
    status: 'ok',
    service: 'Munich Cinema Scraper',
    available_cinemas: CINEMAS.keys,
    categories: CINEMA_CATEGORIES,
    has_todays_data: DB.has_todays_data?,
    last_scrape: DB.last_scrape_time
  })
end

post '/admin/share_selection' do
  title = params[:selected_movie]
  category = params[:category]
  cinemas = CINEMA_CATEGORIES[category] || []
  movies = DB.aggregate_movies(DB.get_movies_by_category(cinemas))
  match = movies.find { |m| m['title_normalized'] == title }
  cinemas_data = match ? match['cinemas'].map { |c| { name: c['display_name'], showtimes: c['showtimes'] } } : []
  data = {
    selected_movie: title,
    category: category,
    cinemas: cinemas_data,
    timestamp: Time.now.to_s
  }
  File.write('/srv/gruppe/students/ge82bob/public_html/selection.json', JSON.generate(data))
  json({ ok: true })
end

get '/admin/scrape_status' do
  json({
    needs_scraping: !DB.has_todays_data?,
    has_data: DB.has_todays_data?,
    last_scrape: DB.last_scrape_time,
    date: Date.today.to_s
  })
end

get '/scrape/scrape_blockbuster' do
  favorites = params[:favorites]&.split(',')&.map(&:strip) || []
  cinemas = (CINEMA_CATEGORIES['blockbuster'] + favorites).uniq
  movies = DB.aggregate_movies(DB.get_movies_by_category(cinemas))
  json(movies)
end

get '/scrape/scrape_mixed' do
  favorites = params[:favorites]&.split(',')&.map(&:strip) || []
  cinemas = (CINEMA_CATEGORIES['mixed'] + favorites).uniq
  movies = DB.aggregate_movies(DB.get_movies_by_category(cinemas))
  json(movies)
end

get '/scrape/scrape_arthouse' do
  favorites = params[:favorites]&.split(',')&.map(&:strip) || []
  cinemas = (CINEMA_CATEGORIES['arthouse'] + favorites).uniq
  movies = DB.aggregate_movies(DB.get_movies_by_category(cinemas))
  json(movies)
end

post '/admin/scrape_all' do
  results = {}
  errors = {}

  CINEMAS.each do |cinema_name, scraper_class|
    next if scraper_class.nil?

    begin
      scraper = scraper_class.new
      movies = scraper.scrape
      DB.save_movies(cinema_name, movies)
      results[cinema_name] = { count: movies.length, status: 'success' }
    rescue StandardError => e
      errors[cinema_name] = e.message
      results[cinema_name] = { status: 'failed', error: e.message }
    end
  end

  json({
    scraped_at: Time.now.iso8601,
    date: Date.today.to_s,
    results: results,
    errors: errors.empty? ? nil : errors
  })
end

get '/scrape/:cinema' do
  cinema_name = params[:cinema]

  unless CINEMAS.key?(cinema_name)
    halt 404, json({ error: "Cinema '#{cinema_name}' not found" })
  end

  scraper_class = CINEMAS[cinema_name]

  unless scraper_class
    halt 501, json({ error: "Scraper for '#{cinema_name}' not yet implemented" })
  end

  begin
    scraper = scraper_class.new
    movies = scraper.scrape
    DB.save_movies(cinema_name, movies)

    json({
      cinema: cinema_name,
      scraped_at: Time.now.iso8601,
      movie_count: movies.length,
      movies: movies
    })
  rescue StandardError => e
    halt 500, json({
      error: 'Scraping failed',
      message: e.message,
      backtrace: e.backtrace.first(5)
    })
  end
end

get '/scrape/category/:category' do
  category = params[:category]

  unless CINEMA_CATEGORIES.key?(category)
    halt 404, json({ error: "Category '#{category}' not found" })
  end

  results = {}
  errors = {}

  CINEMA_CATEGORIES[category].each do |cinema_name|
    scraper_class = CINEMAS[cinema_name]

    if scraper_class.nil?
      errors[cinema_name] = 'Not yet implemented'
      next
    end

    begin
      scraper = scraper_class.new
      results[cinema_name] = scraper.scrape
      DB.save_movies(cinema_name, results[cinema_name])
    rescue StandardError => e
      errors[cinema_name] = e.message
    end
  end

  json({
    category: category,
    scraped_at: Time.now.iso8601,
    results: results,
    errors: errors.empty? ? nil : errors
  })
end
