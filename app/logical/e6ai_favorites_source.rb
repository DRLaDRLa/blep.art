# frozen_string_literal: true

# Public favorites of one e6ai.net user, newest first, from the public favorites crawl.
#
# e6ai.net is no longer available, so the crawl is the only source. It saved one gzipped
# JSON file per page; a user's list is complete when the last page is shorter than a full page.
class E6aiFavoritesSource
  PAGE_LIMIT = 320

  # Raised with a message meant for the user.
  class Error < StandardError; end

  Result = Struct.new(:source, :post_ids, keyword_init: true)

  attr_reader :user_id

  def initialize(user_id, scrape_path: Danbooru.config.e6ai_favorites_scrape_path)
    @user_id = Integer(user_id)
    @scrape_path = scrape_path
  end

  def not_found_message
    "There is no saved copy of public favorites for e6ai.net user #{user_id}. " \
      "Only favorites that were public when e6ai.net closed could be saved."
  end

  # The crawled list when the crawl finished this user with at least one favorite, otherwise nil.
  def scraped
    return nil if @scrape_path.blank?
    dir = File.join(@scrape_path, user_id.to_s)
    return nil unless Dir.exist?(dir)
    files = Dir.children(dir).grep(/\A\d+\.json\.gz\z/).sort
    return nil if files.empty?

    pages = files.map { |name| JSON.parse(Zlib::GzipReader.open(File.join(dir, name), &:read)) }
    contiguous = pages.each_with_index.all? do |page, i|
      page.is_a?(Hash) && page["page"] == i + 1 && page["http_status"] == 200 && valid_ids?(page["post_ids"])
    end
    return nil unless contiguous && pages.last["post_ids"].size < PAGE_LIMIT

    ids = pages.flat_map { |page| page["post_ids"] }.uniq
    ids.empty? ? nil : Result.new(source: "scrape", post_ids: ids)
  rescue StandardError => e
    Rails.logger.warn("E6aiFavoritesSource: crawl for user #{user_id} unreadable: #{e.class}: #{e.message}")
    nil
  end

  private

  def valid_ids?(ids)
    ids.is_a?(Array) && ids.size <= PAGE_LIMIT && ids.all? { |id| id.is_a?(Integer) && id >= 1 }
  end
end
