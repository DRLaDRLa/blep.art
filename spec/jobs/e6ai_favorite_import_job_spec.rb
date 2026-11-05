# frozen_string_literal: true

require "rails_helper"

RSpec.describe E6aiFavoriteImportJob do
  include_context "as member"

  let(:user) { create(:user) }
  let(:posts) { create_list(:post, 5) }
  let(:import) { E6aiFavoriteImport.create!(user: user, e6ai_user_id: 42) }
  let(:source) { instance_double(E6aiFavoritesSource, scraped: nil, not_found_message: "There is no saved copy") }
  let(:job) { described_class.new }

  before do
    allow(E6aiFavoritesSource).to receive(:new).with(42).and_return(source)
    allow(BulkIndexUpdateJob).to receive(:perform_async)
  end

  def result(ids) = E6aiFavoritesSource::Result.new(source: "scrape", post_ids: ids)

  # The order the favorites page shows: PostSets::Favorites sorts by created_at, newest first.
  def favorites_page_order = Favorite.where(user_id: user.id).order(created_at: :desc).pluck(:post_id)

  context "when the crawl has the list" do
    # newest first, as e6ai.net listed them. 999_999 is not on this site; posts[4] is mid-transfer.
    let(:newest_first) { [posts[2].id, 999_999, posts[4].id, posts[0].id, posts[3].id, posts[1].id] }

    before do
      allow(source).to receive(:scraped).and_return(result(newest_first))
      posts[4].update_columns(bit_flags: posts[4].bit_flags | Post.flag_value_for("favorites_transfer_in_progress"))
    end

    it "saves the favorites in e6ai.net's order, with every count and the search index updated" do
      Favorite.create!(user_id: user.id, post_id: posts[3].id)          # already a favorite
      Favorite.create!(user_id: create(:user).id, post_id: posts[0].id) # someone else's
      posts[0].update_columns(fav_count: 0)                              # a count that had drifted

      job.perform(import.id, 1)

      expect(favorites_page_order.excluding(posts[3].id)).to eq([posts[2].id, posts[0].id, posts[1].id])
      expect(Favorite.where(user_id: user.id).distinct.count(:created_at)).to eq(4)
      expect(import.reload).to have_attributes(status: "done", source: "scrape", imported_count: 3, already_count: 1, missing_count: 2)
      expect(posts[0].reload.fav_count).to eq(2) # recounted, not incremented
      expect(user.reload.favorite_count).to eq(4)
      expect(BulkIndexUpdateJob).to have_received(:perform_async).with("Post", contain_exactly(posts[0].id, posts[1].id, posts[2].id))
    end

    it "keeps the order across batches, and the newest when the list exceeds the favorite limit" do
      stub_const("E6aiFavoriteImportJob::BATCH_SIZE", 1)
      allow_any_instance_of(User).to receive(:favorite_limit).and_return(3) # rubocop:disable RSpec/AnyInstance
      job.perform(import.id, 1)
      expect(favorites_page_order).to eq([posts[2].id, posts[0].id, posts[3].id])
      expect(import.reload.over_limit_count).to eq(1)
    end

    it "still recounts the user's favorites when saving fails part way" do
      stub_const("E6aiFavoriteImportJob::BATCH_SIZE", 2)
      allow(BulkIndexUpdateJob).to receive(:perform_async).and_raise(StandardError, "queue unavailable")
      job.perform(import.id, 1)
      expect(import.reload).to have_attributes(status: "failed", error: E6aiFavoriteImportJob::GENERIC_ERROR)
      expect(Favorite.where(user_id: user.id).count).to eq(2) # the first batch, committed whole
      expect(user.reload.favorite_count).to eq(2)
    end

    it "leaves a restarted or finished import alone" do
      allow(source).to receive(:scraped) do
        import.update_columns(attempt: 2, status: "queued") # restarted while this job was running
        result(newest_first)
      end
      job.perform(import.id, 1)
      expect(import.reload).to have_attributes(attempt: 2, status: "queued", error: nil)
      expect(Favorite.where(user_id: user.id)).to be_empty

      job.perform(import.id, 1)                       # an old attempt
      import.update_columns(status: "done")
      job.perform(import.id, 2)                       # already finished
      expect(source).to have_received(:scraped).once
    end
  end

  it "fails with a message the user can act on, and no internal details" do
    job.perform(import.id, 1)
    expect(import.reload).to have_attributes(status: "failed", error: "There is no saved copy")

    import.update_columns(status: "queued")
    allow(source).to receive(:scraped).and_raise(Errno::ENOENT, "/home/blep/data/secret")
    job.perform(import.id, 1)
    expect(import.reload).to have_attributes(status: "failed", error: E6aiFavoriteImportJob::GENERIC_ERROR)
  end
end
