# frozen_string_literal: true

require "rails_helper"

RSpec.describe E6aiFavoritesSource do
  let(:scrape_path) { Dir.mktmpdir("e6ai-favorites") }

  after { FileUtils.rm_rf(scrape_path) }

  def source_for(user_id, path: scrape_path) = described_class.new(user_id, scrape_path: path)

  def write_page(user_id, page, post_ids)
    dir = File.join(scrape_path, user_id.to_s)
    FileUtils.mkdir_p(dir)
    Zlib::GzipWriter.open(File.join(dir, format("%06d.json.gz", page))) do |gz|
      gz.write({ user_id: user_id, page: page, limit: 320, http_status: 200, post_ids: post_ids }.to_json)
    end
  end

  it "returns a finished crawl in order, without duplicates" do
    write_page(42, 1, (1..320).to_a)
    write_page(42, 2, [320, 321])
    expect(source_for(42).scraped).to have_attributes(source: "scrape", post_ids: (1..321).to_a)
  end

  it "is nil unless the crawl finished the user with at least one readable favorite" do
    write_page(1, 1, (1..320).to_a)              # more pages may follow
    write_page(2, 1, (1..320).to_a)
    write_page(2, 3, [1])                        # page 2 missing
    write_page(3, 1, [])                         # empty or hidden
    write_page(4, 1, [1, "2"])                   # invalid post ID
    FileUtils.mkdir_p(File.join(scrape_path, "5"))
    File.binwrite(File.join(scrape_path, "5", "000001.json.gz"), "not gzip")
    expect([1, 2, 3, 4, 5, 6].map { |id| source_for(id).scraped }).to all(be_nil)
    expect(source_for(1, path: nil).scraped).to be_nil
  end
end
