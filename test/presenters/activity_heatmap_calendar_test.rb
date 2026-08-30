require "test_helper"

class ActivityHeatmapCalendarTest < ActiveSupport::TestCase
  test "covers only the current calendar year in correctly aligned weeks" do
    calendar = ActivityHeatmapCalendar.new(today: Date.new(2026, 8, 29))

    assert_equal Date.new(2026, 1, 1), calendar.start_date
    assert_equal Date.new(2026, 12, 31), calendar.end_date
    assert_equal 365, calendar.dates.count
    assert_equal 241, calendar.dates_through_today.count
    assert_equal Date.new(2026, 8, 29), calendar.dates_through_today.last
    assert_equal 0, calendar.week_for(Date.new(2026, 1, 1))
    assert_equal 1, calendar.week_for(Date.new(2026, 1, 4))
    assert_equal 53, calendar.week_count
  end

  test "allows the fifty-four columns required by some leap years" do
    calendar = ActivityHeatmapCalendar.new(today: Date.new(2028, 8, 29))

    assert_equal 366, calendar.dates.count
    assert_equal 53, calendar.week_for(Date.new(2028, 12, 31))
    assert_equal 54, calendar.week_count
  end
end
