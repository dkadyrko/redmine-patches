# add cron
# path to project: /home/user_name/projects/myrailsapp
# path to rake: /usr/local/bin/rake (To find the full path for your rake executable, run which rake.)
# 0 17 * * 1-5 TZ="Europe/Moscow" cd /home/user_name/projects/myrailsapp && /usr/local/bin/rake timelog:check
namespace :timelog do
  task check: :environment do
    REQUIRED_HOURS_PER_DAY = 8
    VACATION = 'vacation'
    DAY_OFF = 'day_off'
    SICK_DAY = 'sick_day'
    TRANSFER = 'working_day_transfer'
    ALL_VACATIONS = [VACATION, DAY_OFF, SICK_DAY, TRANSFER]

    current_date = Date.current
    users = User.beltech_ipus_by_city('Minsk') + User.beltech_ipus_by_city('Grodno')

    if current_date.wday == 5
      work_days_in_week = (current_date.beginning_of_week..current_date).to_a
      users_timelog_check(users, work_days_in_week)
    end

    month_period = current_date.all_month.to_a
    work_days_in_month = month_period.reject { |day| day.wday == 6 || day.wday == 7 }
    if current_date == work_days_in_month.last
      users_timelog_check(users, work_days_in_month)
    end
  end

  def users_timelog_check(users, work_days)
    users.each do |user|
      user_time_entries = TimeEntry.where(user_id: user.id, spent_on: work_days)
      logged_days = user_time_entries.group_by(&:spent_on).map(&:first)
      logged_hours = user_time_entries.sum(:hours) || 0

      work_days_count = work_days.count
      if logged_days.count < work_days_count || logged_hours < work_days_count * REQUIRED_HOURS_PER_DAY
        ALL_VACATIONS.each do |vacation|
          additional_logged_days, additional_logged_hours = user_vacations(user, vacation, work_days)

          logged_days += additional_logged_days
          logged_hours += additional_logged_hours
        end

        if logged_days.count < work_days_count || logged_hours < work_days_count * REQUIRED_HOURS_PER_DAY
          send_notification_emails(user)
        end
      end
    end
  end

  def user_vacations(user, entry_type, date_period)
    user_requests = UserRequest.where(request_by: user.id, approve_result: 'approved', request_type: entry_type)

    if entry_type == TRANSFER
      user_requests_per_week = user_requests.select { |request| date_period.include?(request.start_date) }
      additional_logged_days = user_requests_per_week.map(&:start_date)
      additional_logged_hours = user_requests_per_week.count * REQUIRED_HOURS_PER_DAY
    else
      additional_logged_days = user_requests.inject([]) do |result, request|
        result += (request.start_date..request.end_date).to_a & date_period
      end
      additional_logged_hours = user_requests.inject(0) do |result, request|
        additional_days = (request.start_date..request.end_date).to_a & date_period
        result + additional_days.count * REQUIRED_HOURS_PER_DAY
      end
    end
    [additional_logged_days, additional_logged_hours]
  end

  def send_notification_emails(user)
    # to      = user.mail
    to      = "#{user.login}@redmine.plansource.com"
    from    = 'redmine@redmine.plansource.com'
    cc      = EmailNotification::BELTECH_PM_EMAILS
    subject = 'issues #133981'
    message = 'issues #133981'

    ActionMailer::Base.mail(to: to, from: from, cc: cc, subject: subject, body: message).deliver
  end

end
