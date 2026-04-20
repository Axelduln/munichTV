require 'date'
require 'json'
require 'sqlite3'

class Database
  DB_FILE = 'db/movies.db'

  CINEMAS_TABLE_SQL = <<~SQL.freeze
    CREATE TABLE cinemas (
      cinema_key TEXT PRIMARY KEY,
      display_name TEXT NOT NULL,
      category TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      is_favorite INTEGER NOT NULL DEFAULT 0
    )
  SQL

  MOVIES_TABLE_SQL = <<~SQL.freeze
    CREATE TABLE movies (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      scrape_date DATE NOT NULL,
      cinema_key TEXT NOT NULL,
      title TEXT NOT NULL,
      title_normalized TEXT NOT NULL,
      showtimes TEXT NOT NULL,
      description TEXT,
      language TEXT,
      duration TEXT,
      poster_url TEXT,
      details_link TEXT,
      ticket_link TEXT,
      event_id TEXT
    )
  SQL

  def self.instance
    @instance ||= new
  end

  def initialize
    @db = SQLite3::Database.new(DB_FILE)
    @db.results_as_hash = true
    setup_schema
  end

  def setup_schema
    ensure_table_schema('cinemas', CINEMAS_TABLE_SQL, %w[cinema_key display_name category is_active is_favorite])
    ensure_table_schema(
      'movies',
      MOVIES_TABLE_SQL,
      %w[id scrape_date cinema_key title title_normalized showtimes description language duration poster_url details_link ticket_link event_id]
    )
    create_indexes
  end

  def reset_movies(date = nil)
    if date.nil?
      @db.execute('DELETE FROM movies')
    else
      @db.execute('DELETE FROM movies WHERE scrape_date = ?', [date.to_s])
    end
  end

  def seed_cinemas(cinema_map, category_map)
    category_by_cinema = build_category_lookup(category_map)

    @db.transaction do
      cinema_map.each_key do |cinema_key|
        display_name = humanize_cinema_key(cinema_key)
        category = category_by_cinema[cinema_key] || 'uncategorized'

        @db.execute(
          'INSERT OR IGNORE INTO cinemas (cinema_key, display_name, category, is_active, is_favorite) VALUES (?, ?, ?, 1, 0)',
          [cinema_key, display_name, category]
        )

        @db.execute(
          'UPDATE cinemas SET display_name = ?, category = ?, is_active = 1 WHERE cinema_key = ?',
          [display_name, category, cinema_key]
        )
      end
    end
  end

  def save_movies(cinema_key, movies, date = Date.today)
    @db.transaction do
      @db.execute('DELETE FROM movies WHERE cinema_key = ? AND scrape_date = ?', [cinema_key, date.to_s])

      movies.each do |movie|
        title = movie_value(movie, :title)
        next if title.nil? || title.empty?

        @db.execute(
          <<~SQL,
            INSERT INTO movies (
              scrape_date,
              cinema_key,
              title,
              title_normalized,
              showtimes,
              description,
              language,
              duration,
              poster_url,
              details_link,
              ticket_link,
              event_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          [
            date.to_s,
            cinema_key,
            title,
            normalize_title(title),
            JSON.generate(movie_value(movie, :showtimes) || []),
            movie_value(movie, :description),
            movie_value(movie, :language),
            movie_value(movie, :duration),
            movie_value(movie, :poster_url),
            movie_value(movie, :details_link),
            movie_value(movie, :ticket_link),
            movie_value(movie, :event_id)
          ]
        )
      end
    end
  end

  def normalize_title(title)
    title.to_s
         .downcase
         .gsub(/[[:punct:]]+/, ' ')
         .gsub(/\s+/, ' ')
         .strip
  end

  def set_cinema_favorite(cinema_key, is_favorite)
    @db.execute(
      'UPDATE cinemas SET is_favorite = ? WHERE cinema_key = ?',
      [is_favorite ? 1 : 0, cinema_key]
    )
  end

  def get_cinemas(category: nil, favorites_only: false, active_only: true)
    conditions = []
    parameters = []

    if category
      conditions << 'category = ?'
      parameters << category
    end

    conditions << 'is_favorite = 1' if favorites_only
    conditions << 'is_active = 1' if active_only

    where_clause = conditions.empty? ? '' : "WHERE #{conditions.join(' AND ')}"
    rows = @db.execute(
      "SELECT cinema_key, display_name, category, is_active, is_favorite FROM cinemas #{where_clause} ORDER BY is_favorite DESC, display_name ASC",
      parameters
    )

    rows.map { |row| format_cinema(row) }
  end

  def get_movies_by_date(date = Date.today)
    rows = @db.execute(
      'SELECT * FROM movies WHERE scrape_date = ? ORDER BY cinema_key ASC, title_normalized ASC',
      [date.to_s]
    )

    rows.map { |row| format_movie(row) }
  end

  def get_movies_by_cinema(cinema_key, date = Date.today)
    rows = @db.execute(
      <<~SQL,
        SELECT m.*, c.display_name, c.category, c.is_favorite
        FROM movies m
        LEFT JOIN cinemas c ON c.cinema_key = m.cinema_key
        WHERE m.cinema_key = ? AND m.scrape_date = ?
        ORDER BY m.title_normalized ASC
      SQL
      [cinema_key, date.to_s]
    )

    rows.map { |row| format_feed_row(row) }
  end

  def get_movies_by_category(cinemas_list, date = Date.today)
    return [] if cinemas_list.empty?

    placeholders = cinemas_list.map { '?' }.join(',')
    rows = @db.execute(
      <<~SQL,
        SELECT m.*, c.display_name, c.category, c.is_favorite
        FROM movies m
        LEFT JOIN cinemas c ON c.cinema_key = m.cinema_key
        WHERE m.cinema_key IN (#{placeholders}) AND m.scrape_date = ?
        ORDER BY COALESCE(c.is_favorite, 0) DESC, COALESCE(c.display_name, m.cinema_key) ASC, m.title_normalized ASC
      SQL
      [*cinemas_list, date.to_s]
    )

    rows.map { |row| format_feed_row(row) }
  end

  def get_category_feed(category, date = Date.today, favorites_first: true)
    order_clause = if favorites_first
                     'c.is_favorite DESC, c.display_name ASC, m.title_normalized ASC'
                   else
                     'c.display_name ASC, m.title_normalized ASC'
                   end

    rows = @db.execute(
      <<~SQL,
        SELECT m.*, c.display_name, c.category, c.is_favorite
        FROM movies m
        INNER JOIN cinemas c ON c.cinema_key = m.cinema_key
        WHERE c.category = ? AND c.is_active = 1 AND m.scrape_date = ?
        ORDER BY #{order_clause}
      SQL
      [category, date.to_s]
    )

    rows.map { |row| format_feed_row(row) }
  end

  def get_aggregated_feed(category, date = Date.today, favorites_first: true)
    aggregate_movies(get_category_feed(category, date, favorites_first: favorites_first))
  end

  def aggregate_movies(rows)
    rows.group_by { |row| row['title_normalized'] }.values.map do |movie_rows|
      canonical_row = pick_canonical_movie_row(movie_rows)

      {
        'title' => canonical_row['title'],
        'title_normalized' => canonical_row['title_normalized'],
        'description' => canonical_row['description'],
        'language' => canonical_row['language'],
        'duration' => canonical_row['duration'],
        'poster_url' => canonical_row['poster_url'],
        'cinemas' => movie_rows.map do |row|
          {
            'cinema' => row['cinema'],
            'cinema_key' => row['cinema_key'],
            'display_name' => row['display_name'],
            'category' => row['category'],
            'is_favorite' => row['is_favorite'],
            'showtimes' => parse_showtimes(row['showtimes']),
            'ticket_link' => row['ticket_link'],
            'details_link' => row['details_link'],
            'event_id' => row['event_id']
          }.compact
        end
      }.compact
    end.sort_by { |row| row['title_normalized'] }
  end

  def has_todays_data?
    count = @db.get_first_value('SELECT COUNT(*) FROM movies WHERE scrape_date = ?', [Date.today.to_s])
    count.to_i > 0
  end

  def last_scrape_time
    has_todays_data? ? Date.today.to_s : nil
  end

  private

  def ensure_table_schema(table_name, create_sql, expected_columns)
    existing_columns = table_columns(table_name)

    if existing_columns.empty?
      @db.execute(create_sql)
      return
    end

    return if existing_columns == expected_columns

    @db.execute("DROP TABLE IF EXISTS #{table_name}")
    @db.execute(create_sql)
  end

  def table_columns(table_name)
    @db.execute("PRAGMA table_info(#{table_name})").map { |column| column['name'] || column[1] }
  end

  def create_indexes
    @db.execute('CREATE INDEX IF NOT EXISTS idx_cinemas_category ON cinemas(category, is_active, is_favorite)')
    @db.execute('CREATE INDEX IF NOT EXISTS idx_movies_date_cinema ON movies(scrape_date, cinema_key)')
    @db.execute('CREATE INDEX IF NOT EXISTS idx_movies_date_title_norm ON movies(scrape_date, title_normalized)')
  end

  def build_category_lookup(category_map)
    category_map.each_with_object({}) do |(category, cinema_keys), lookup|
      cinema_keys.each do |cinema_key|
        lookup[cinema_key] = category
      end
    end
  end

  def humanize_cinema_key(cinema_key)
    cinema_key.to_s.split('_').map(&:capitalize).join(' ')
  end

  def movie_value(movie, key)
    movie[key] || movie[key.to_s]
  end

  def format_movie(row)
    {
      'cinema' => row['cinema_key'],
      'cinema_key' => row['cinema_key'],
      'title' => row['title'],
      'title_normalized' => row['title_normalized'],
      'showtimes' => parse_showtimes(row['showtimes']),
      'description' => row['description'],
      'language' => row['language'],
      'duration' => row['duration'],
      'poster_url' => row['poster_url'],
      'details_link' => row['details_link'],
      'ticket_link' => row['ticket_link'],
      'event_id' => row['event_id']
    }.compact
  end

  def format_feed_row(row)
    format_movie(row).merge(
      {
        'display_name' => row['display_name'],
        'category' => row['category'],
        'is_favorite' => row['is_favorite'].to_i == 1
      }.compact
    )
  end

  def format_cinema(row)
    {
      'cinema_key' => row['cinema_key'],
      'display_name' => row['display_name'],
      'category' => row['category'],
      'is_active' => row['is_active'].to_i == 1,
      'is_favorite' => row['is_favorite'].to_i == 1
    }
  end

  def parse_showtimes(value)
    return value if value.is_a?(Array)
    return [] if value.nil? || value.empty?

    JSON.parse(value)
  rescue JSON::ParserError
    []
  end

  def pick_canonical_movie_row(rows)
    rows.find do |row|
      row['description'] || row['poster_url'] || row['language'] || row['duration']
    end || rows.first
  end
end
