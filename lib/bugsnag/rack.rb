module Bugsnag
  class Rack
    def initialize(app)
      @app = app

      # Automatically set the release_stage
      Bugsnag.configuration.release_stage = ENV['RACK_ENV'] if ENV['RACK_ENV']

      # Automatically set the project_root if possible
      if Bugsnag.configuration.project_root.nil? || Bugsnag.configuration.project_root.empty?
        if defined?(settings)
          Bugsnag.configuration.project_root = settings.root
        else
          caller.each do |c|
            if c =~ /[\/\\]config.ru$/
              Bugsnag.configuration.project_root = File.dirname(c.split(":").first)
              break
            end
          end
        end
      end
    end

    def call(env)
      begin
        response = @app.call(env)
      rescue Exception => raised
        Bugsnag.auto_notify(raised, self.class.bugsnag_request_data(env))
        raise
      end

      if env['rack.exception']
        Bugsnag.auto_notify(env['rack.exception'], self.class.bugsnag_request_data(env))
      end

      response
    end

    class << self
      def bugsnag_request_data(env)
        request = ::Rack::Request.new(env)

        session = env["rack.session"]
        params = env["action_dispatch.request.parameters"] || request.params
        user_id = session[:session_id] || session["session_id"] rescue nil

        {
          :user_id => user_id,
          :context => Bugsnag::Helpers.param_context(params) || Bugsnag::Helpers.request_context(request),
          :meta_data => {
            :request => {
              :url => request.url,
              :controller => params[:controller],
              :action => params[:action],
              :params => bugsnag_filter_if_filtering(env, Bugsnag::Helpers.cleanup_hash(params.to_hash)),
            },
            :session => bugsnag_filter_if_filtering(env, Bugsnag::Helpers.cleanup_hash(session)),
            :environment => bugsnag_filter_if_filtering(env, Bugsnag::Helpers.cleanup_hash(env))
          }
        }
      end

      private
      def bugsnag_filter_if_filtering(env, hash)
        @params_filters ||= env["action_dispatch.parameter_filter"]
        Bugsnag::Helpers.apply_filters(hash, @params_filters)
      end
    end
  end
end
