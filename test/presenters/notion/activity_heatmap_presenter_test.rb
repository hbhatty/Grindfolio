require "test_helper"

class Notion::ActivityHeatmapPresenterTest < ActiveSupport::TestCase
  Connection = Struct.new(
    :tracking_started_on,
    :last_synced_through_on,
    :historical_imported_at
  ) do
    def historical_imported_at?
      historical_imported_at.present?
    end
  end

  test "shows zero only through the latest synchronized date" do
    calendar = ActivityHeatmapCalendar.new(today: Date.new(2026, 8, 31))
    presenter = Notion::ActivityHeatmapPresenter.new(
      connection: Connection.new(Date.new(2026, 8, 26), Date.new(2026, 8, 30)),
      calendar:,
      applications: {}
    )

    cells = presenter.cells.index_by(&:date)
    untracked = cells.fetch(Date.new(2026, 8, 25))
    zero = cells.fetch(Date.new(2026, 8, 30))
    unsynchronized = cells.fetch(Date.new(2026, 8, 31))

    assert_equal "untracked", untracked.state
    assert_nil untracked.application_count
    assert_equal "zero", zero.state
    assert_equal 0, zero.application_count
    assert_equal "unsynchronized", unsynchronized.state
    assert_nil unsynchronized.application_count
    assert_predicate unsynchronized, :selected
  end
end
