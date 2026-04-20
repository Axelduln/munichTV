require 'uri'
require_relative '../ferrum_base_scraper'

class GloriaScraper < FerrumBaseScraper
	CINEMA_NAME = 'Gloria Palast'
	BASE_URL = 'https://www.gloria-palast.de'

	def scrape
		browser = create_browser
		movies = []
		target_date = Date.today

		begin
			url = program_url(target_date)
			log("Scraping #{url}")
			browser.go_to(url)
			wait_for_load(browser, duration: 2)

			movie_sections = wait_for_movie_sections(browser)
			log("Found #{movie_sections.length} movie sections")

			movie_sections.each do |section|
				movie_data = extract_movie(section, target_date)
				movies << movie_data if movie_data
			end
		rescue StandardError => e
			log("Error: #{e.message}")
			log(e.backtrace.first(3).join("\n"))
		ensure
			browser.quit if browser
		end

		log("Scraped #{movies.length} movies")
		movies
	end

	private

	def program_url(date)
		"#{BASE_URL}/gp/programm/tagesprogramm-#{date.strftime('%Y-%m-%d')}"
	end

	def wait_for_movie_sections(browser, timeout_seconds: 12)
		start_time = Time.now

		while Time.now - start_time < timeout_seconds
			sections = browser.css('section.movie')
			return sections if sections.any?

			sleep 0.5
		end

		browser.css('section.movie')
	end

	def extract_movie(section, target_date)
		title = section.css('h2 .hl-link').map { |node| node.text.to_s.strip }.find { |text| !text.empty? }
		return nil if title.nil? || title.empty?

		showtime_nodes = section.css('a.prog2__time')
		showtimes = showtime_nodes.map { |node| parse_time(node.text) }.compact.uniq.sort
		return nil if showtimes.empty?

		poster_url = absolute_url(safe_attr(section, 'src', 'a[href*="/filmdetail/"] img'))

		details_link = absolute_url(safe_attr(section, 'href', 'a.hl-link'))
		details_link ||= absolute_url(safe_attr(section, 'href', 'a[href*="/filmdetail/"]'))

		ticket_links = showtime_nodes.map { |node| absolute_url(safe_attr(node, 'href')) }.compact.uniq
		event_ids = ticket_links.map { |url| extract_event_id(url) }.compact.uniq

		movie_data = format_movie(
			title: title,
			showtimes: showtimes,
			date: target_date.to_s,
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

	def absolute_url(url)
		return nil if url.nil? || url.empty?
		return url if url.start_with?('http://', 'https://')

		URI.join(BASE_URL, url).to_s
	rescue URI::InvalidURIError
		nil
	end

	def extract_event_id(url)
		return nil if url.nil? || url.empty?

		match = url.match(%r{/vorstellung/([A-Z0-9]+)}i)
		match && match[1]
	end
end
