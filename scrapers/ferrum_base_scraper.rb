require 'net/http'
require 'json'
require_relative 'base_scraper'

# Base class for scrapers that require a headless browser (Ferrum/Chrome).
# Launches Chrome as an external process and connects Ferrum to it via the
# remote debugging port, avoiding Ferrum's unreliable process_timeout on this server.
class FerrumBaseScraper < BaseScraper
  CHROME_PORT = 9222
  @@shared_browser = nil
  @@browser_mutex = Mutex.new

  def create_browser
    @@browser_mutex.synchronize do
      @@shared_browser = launch_browser if @@shared_browser.nil?
      SharedBrowserProxy.new(@@shared_browser)
    end
  end

  private

  def chrome_running?
    uri = URI("http://localhost:#{CHROME_PORT}/json/version")
    JSON.parse(Net::HTTP.get(uri))
    true
  rescue
    false
  end

  def launch_browser
    require 'ferrum'

    unless chrome_running?
      pid = spawn(
        '/usr/bin/google-chrome',
        '--headless=new',
        '--no-sandbox',
        '--disable-gpu',
        "--remote-debugging-port=#{CHROME_PORT}",
        '--disable-blink-features=AutomationControlled',
        'about:blank',
        [:out, :err] => '/dev/null'
      )
      Process.detach(pid)

      # Wait up to 60s for Chrome to start
      60.times do
        break if chrome_running?
        sleep 1
      end
    end

    browser = Ferrum::Browser.new(
      url: "http://localhost:#{CHROME_PORT}",
      timeout: 60
    )
    browser.headers.set({
      "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
      "Accept-Language" => "en-GB,en-US;q=0.9,en;q=0.8",
      "Cache-Control" => "no-cache",
      "Pragma" => "no-cache",
      "Sec-Ch-Ua" => '"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"',
      "Sec-Ch-Ua-Mobile" => "?0",
      "Sec-Ch-Ua-Platform" => '"macOS"',
      "Sec-Fetch-Dest" => "document",
      "Sec-Fetch-Mode" => "navigate",
      "Sec-Fetch-Site" => "cross-site",
      "Sec-Fetch-User" => "?1",
      "Upgrade-Insecure-Requests" => "1",
      "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    })
    browser
  end

  # Wraps the shared browser so scraper ensure blocks calling browser.quit
  # reset state instead of killing the shared Chrome process.
  class SharedBrowserProxy
    def initialize(browser)
      @browser = browser
    end

    def quit
      @browser.reset rescue nil
    end

    def method_missing(method, *args, &block)
      @browser.send(method, *args, &block)
    end

    def respond_to_missing?(method, include_private = false)
      @browser.respond_to?(method, include_private) || super
    end
  end
end
