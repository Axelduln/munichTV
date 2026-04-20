# Base class for all cinema scrapers
class BaseScraper
  require 'date'
  
  # Override this in subclasses
  def scrape
    raise NotImplementedError, "Subclass must implement scrape method"
  end
  
  protected
  
  # Create a browser instance with standard options
  def create_browser
    require 'ferrum'
    Ferrum::Browser.new(
      headless: true,
      timeout: 30,
      browser_options: { 
        'no-sandbox': nil,
        'disable-gpu': nil,
        'ignore-certificate-errors': nil  # Ignore SSL certificate errors
      }
    )
  end
  
  # Standard movie format that all scrapers should return
  # Returns array of hashes with this structure:
  # {
  #   title: "Movie Title",
  #   original_title: "Original Title (if different)",
  #   showtimes: ["14:00", "17:30", "20:15"],
  #   date: "2025-11-25",
  #   language: "OV" or "DE" or "OmU",
  #   genre: "Drama",
  #   duration: "120 min",
  #   director: "Director Name",
  #   description: "Movie description...",
  #   cinema: "Cinema Name"
  # }
  def format_movie(data)
    {
      title: data[:title],
      original_title: data[:original_title],
      showtimes: data[:showtimes] || [],
      date: data[:date] || Date.today.to_s,
      language: data[:language],
      genre: data[:genre],
      duration: data[:duration],
      director: data[:director],
      description: data[:description],
      cinema: data[:cinema]
    }.compact  # Remove nil values
  end
  
  # Parse time string to standard format (HH:MM)
  def parse_time(time_str)
    return nil if time_str.nil? || time_str.empty?
    time_str.strip.match(/\d{1,2}:\d{2}/)&.[](0)
  end
  
  # Parse times from array of elements
  def parse_times(elements)
    elements.map { |el| parse_time(el.text) }.compact
  end
  
  # Parse date string to ISO format (YYYY-MM-DD)
  def parse_date(date_str)
    return Date.today.to_s if date_str.nil? || date_str.empty?
    
    # Try different date formats
    begin
      # German format: "08.12.2025"
      if date_str.match?(/\d{1,2}\.\d{1,2}\.\d{4}/)
        day, month, year = date_str.scan(/\d+/)
        return Date.new(year.to_i, month.to_i, day.to_i).to_s
      end
      
      # ISO format: "2025-12-08"
      if date_str.match?(/\d{4}-\d{2}-\d{2}/)
        return date_str
      end
      
      # Fallback to Date.parse
      Date.parse(date_str).to_s
    rescue
      Date.today.to_s
    end
  end
  
  # Extract text safely from element
  def safe_text(element, selector = nil)
    return nil if element.nil?
    
    text = if selector
      element.at_css(selector)&.text
    else
      element.text
    end
    
    # Clean up whitespace, newlines, and tabs
    text&.gsub(/\s+/, ' ')&.strip
  end
  
  # Extract attribute safely from element
  def safe_attr(element, attribute, selector = nil)
    return nil if element.nil?
    
    if selector
      element.at_css(selector)&.attribute(attribute)
    else
      element.attribute(attribute)
    end
  end
  
  # Normalize language strings
  def parse_language(lang_str)
    return nil if lang_str.nil? || lang_str.empty?
    
    lang = lang_str.strip.upcase
    
    # Common patterns
    return 'OV' if lang.match?(/OV|ORIGINAL|ENGLISH/)
    return 'OmU' if lang.match?(/OMU|UNTERTITEL|SUBTITLES/)
    return 'DE' if lang.match?(/DEUTSCH|GERMAN|DE/)

    nil
  end
  
  # Extract duration and normalize format
  def parse_duration(duration_str)
    return nil if duration_str.nil? || duration_str.empty?
    
    # Extract numbers from string
    minutes = duration_str.scan(/\d+/).first
    return nil if minutes.nil?
    
    "#{minutes} min"
  end
  
  # Wait for page to load (use in scrapers if needed)
  def wait_for_load(browser, duration: 2)
    sleep duration
  rescue
    # Fallback if sleep fails
  end
  
  # Log scraping progress
  def log(message)
    puts "[#{self.class.name}] #{message}"
  end
end
