require 'timelogcontroller_patch'

module RedminePatches
  module TimelogControllerOverride

    def self.included(base)
      base.send(:include, InstanceMethods)

      base.class_eval do
        alias_method :create, :create_fixed
      end
    end

    module InstanceMethods
      def create_fixed
        @time_entry ||= TimeEntry.new(:project => @project, :issue => @issue, :user => User.current, :spent_on => User.current.today)
        @time_entry.safe_attributes = params[:time_entry]
        if @time_entry.project && !User.current.allowed_to?(:log_time, @time_entry.project)
          render_403
          return
        end

        if params[:log_type].blank? || params[:log_type] == 'T'
          call_hook(:controller_timelog_edit_before_save, { :params => params, :time_entry => @time_entry })
          if @time_entry.save

            users_ids = (User.beltech_ipus_by_city('Minsk') + User.beltech_ipus_by_city('Grodno')).map(&:id)
            date_check = @time_entry.spent_on.in_time_zone < @time_entry.created_on.to_date.beginning_of_week.in_time_zone

            if users_ids.include?(@time_entry.user_id) && date_check
              user = User.find_by(id: @time_entry.user_id)
              # to      = user.mail
              to      = "#{user.login}@redmine.plansource.com"
              from    = 'redmine@redmine.plansource.com'
              cc      = EmailNotification::BELTECH_PM_EMAILS
              subject = 'issues #133981'
              message = 'issues #133981'

              ActionMailer::Base.mail(to: to, from: from, cc: cc, subject: subject, body: message).deliver
            end

            respond_to do |format|
              format.html {
                flash[:notice] = l(:notice_successful_create)
                if params[:continue]
                  options = {
                    :time_entry => {
                      :project_id => params[:time_entry][:project_id],
                      :issue_id => @time_entry.issue_id,
                      :activity_id => @time_entry.activity_id
                    },
                    :back_url => params[:back_url]
                  }
                  if params[:project_id] && @time_entry.project
                    redirect_to new_project_time_entry_path(@time_entry.project, options)
                  elsif params[:issue_id] && @time_entry.issue
                    redirect_to new_issue_time_entry_path(@time_entry.issue, options)
                  else
                    redirect_to new_time_entry_path(options)
                  end
                else
                  redirect_back_or_default project_time_entries_path(@time_entry.project)
                end
              }
              format.api  { render :action => 'show', :status => :created, :location => time_entry_url(@time_entry) }
            end
          else
            respond_to do |format|
              format.html { render :action => 'new' }
              format.api  { render_validation_errors(@time_entry) }
            end
          end
        else
          errorMsg = validateMatterial
          if errorMsg.blank?
            saveMatterial if params[:log_type] == 'M' || params[:log_type] == 'A'
            saveExpense if params[:log_type] == 'E'
          else
            respond_to do |format|
              format.html {
                flash[:error] = errorMsg
                render :action => 'new'

              }
            end
          end
        end
      end
    end
  end
end

TimelogController.send(:include, RedminePatches::TimelogControllerOverride)
