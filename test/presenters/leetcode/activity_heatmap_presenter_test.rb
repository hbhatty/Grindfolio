require "test_helper"

class Leetcode::ActivityHeatmapPresenterTest < ActiveSupport::TestCase
  test "keeps heatmap day states semantically distinct" do
    connection = Struct.new(:tracking_started_on).new(Date.new(2026, 8, 23))
    activity = Struct.new(:submission_count)
    presenter = Leetcode::ActivityHeatmapPresenter.new(
      connection:,
      today: Date.new(2026, 8, 25),
      start_date: Date.new(2026, 8, 22),
      end_date: Date.new(2026, 8, 26),
      activities: {
        Date.new(2026, 8, 24) => activity.new(0),
        Date.new(2026, 8, 25) => activity.new(7)
      }
    )

    untracked, unsynchronized, zero, active, future = presenter.cells

    assert_equal "untracked", untracked.state
    assert_nil untracked.submission_count
    assert_equal "August 22, 2026 — LeetCode date (UTC): not tracked", untracked.aria_label

    assert_equal "unsynchronized", unsynchronized.state
    assert_nil unsynchronized.submission_count
    assert_equal "August 23, 2026 — LeetCode date (UTC): not synchronized", unsynchronized.aria_label

    assert_equal "zero", zero.state
    assert_equal 0, zero.submission_count
    assert_equal "August 24, 2026 — LeetCode date (UTC): raw submission count 0; synchronized with no submissions", zero.aria_label
    assert_equal "LeetCode raw submission count: 0. This LeetCode date (UTC) was synchronized with no submissions.", zero.detail_message

    assert_equal "active", active.state
    assert_equal 7, active.submission_count
    assert_predicate active, :selected
    assert_equal "August 25, 2026 — LeetCode date (UTC): raw submission count 7; active", active.aria_label
    assert_equal "LeetCode raw submission count: 7. This activity belongs to the displayed LeetCode date (UTC).", active.detail_message

    assert_equal "future", future.state
    assert_nil future.submission_count
    assert_equal "August 26, 2026 — LeetCode date (UTC): future date", future.aria_label
    assert_equal "This LeetCode date (UTC) has not happened yet.", future.detail_message
  end
end
