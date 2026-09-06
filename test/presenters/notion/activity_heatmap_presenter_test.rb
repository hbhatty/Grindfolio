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
  Application = Struct.new(:company_name, :role, :current_status, :status_changes)
  StatusChange = Struct.new(:notion_application, :from_status, :to_status)


  test "shows zero only through the latest synchronized date" do
    calendar = ActivityHeatmapCalendar.new(today: Date.new(2026, 8, 31))
    presenter = Notion::ActivityHeatmapPresenter.new(
      connection: Connection.new(Date.new(2026, 8, 26), Date.new(2026, 8, 30)),
      calendar:,
      applications: {},
      status_changes: {}
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


  test "assigns semantic tones to first observed application statuses" do
    date = Date.new(2026, 8, 26)
    expected_tones = {
      "Applied" => "positive",
      "Offer received" => "positive",
      "Interview scheduled" => "progress",
      "Phone screen" => "progress",
      "Rejected" => "negative",
      "Declined" => "negative",
      "Withdrawn" => "neutral",
      nil => "neutral"
    }
    presenter = Notion::ActivityHeatmapPresenter.new(
      connection: Connection.new(date, date),
      calendar: ActivityHeatmapCalendar.new(today: date),
      applications: {
        date => expected_tones.keys.map { |status| Application.new("Example Company", nil, status) }
      },
      status_changes: {}
    )

    details = presenter.cells.index_by(&:date).fetch(date).application_details

    assert_equal(
      expected_tones,
      details.to_h { |application| [ application.fetch(:status), application.fetch(:status_tone) ] }
    )
  end

  test "keeps the first observed status on the submission date and exposes later changes separately" do
    applied_on = Date.new(2026, 8, 20)
    changed_on = Date.new(2026, 8, 25)
    application = Application.new("IBM", "Software Developer", "Rejected", [])
    change = StatusChange.new(application, "Applied", "Rejected")
    application.status_changes << change
    presenter = Notion::ActivityHeatmapPresenter.new(
      connection: Connection.new(applied_on, changed_on),
      calendar: ActivityHeatmapCalendar.new(today: changed_on),
      applications: {
        applied_on => [ application ]
      },
      status_changes: {
        changed_on => [ change ]
      }
    )

    submission = presenter.cells.index_by(&:date).fetch(applied_on)
    cell = presenter.cells.index_by(&:date).fetch(changed_on)

    assert_equal 1, submission.application_count
    assert_equal "Applied", submission.application_details.first.fetch(:status)
    assert_equal "positive", submission.application_details.first.fetch(:status_tone)

    assert_equal "zero", cell.state
    assert_equal 0, cell.application_count
    assert_equal 1, cell.status_change_count
    assert_equal "August 25, 2026: 0 applications; synchronized; 1 application change detected", cell.aria_label
    assert_equal(
      [
        {
          company_name: "IBM",
          role: "Software Developer",
          from_status: "Applied",
          from_status_tone: "positive",
          to_status: "Rejected",
          to_status_tone: "negative"
        }
      ],
      cell.status_change_details
    )
  end
end
