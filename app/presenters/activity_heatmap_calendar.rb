class ActivityHeatmapCalendar
  attr_reader :today, :start_date, :end_date

  def initialize(today:)
    @today = today
    @start_date = today.beginning_of_year
    @end_date = today.end_of_year
  end

  def dates
    start_date..end_date
  end

  def dates_through_today
    start_date..today
  end

  def week_for(date)
    (start_date.wday + (date - start_date).to_i) / 7
  end

  def week_count
    week_for(end_date) + 1
  end
end
