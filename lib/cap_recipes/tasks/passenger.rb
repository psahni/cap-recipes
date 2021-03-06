require 'cap_recipes/tasks/with_scope.rb'

Capistrano::Configuration.instance(true).load do
  set :base_ruby_path, '/usr'  

  # ===============================================================
  # DEPLOYMENT SCRIPTS
  # ===============================================================

  namespace :deploy do
    
    desc "Default deploy action" 
    task :default, :roles => :web do
      with_role(:web) do
        update
        restart
      end
    end

    # ===============================================================
    # SERVER MANAGEMENT
    # ===============================================================

    desc "Stops the phusion passenger server"
    task :stop, :roles => :web do
      puts "Stopping rails web server"
      apache.stop
    end

    desc "Starts the phusion passenger server"
    task :start, :roles => :web do
      puts "Starting rails web server"
      apache.start
    end

    desc "Restarts the phusion passenger server"
    task :restart, :roles => :web do
      puts "Restarting the application"
      run "touch #{current_path}/tmp/restart.txt"
    end

    desc "Update code on server, apply migrations, and restart passenger server"
    task :with_migrations, :roles => :web do
      with_role(:web) do
        deploy.update
        deploy.migrate
        deploy.restart
      end
    end

    # ===============================================================
    # UTILITY TASKS
    # ===============================================================

    desc "Copies the shared/config/database yaml to release/config/"
    task :copy_config, :roles => :web do
      puts "Copying database configuration to release path"
      sudo "ln -s #{shared_path}/config/database.yml #{release_path}/config/database.yml"
    end

    desc "Repair permissions to allow user to perform all actions"
    task :repair_permissions, :roles => :web do
      puts "Applying correct permissions to allow for proper command execution"
      sudo "chmod -R 744 #{current_path}/log #{current_path}/tmp"
      sudo "chown -R #{user}:#{user} #{current_path}"
      sudo "chown -R #{user}:#{user} #{current_path}/tmp"
    end

    desc "Displays the production log from the server locally"
    task :tail, :roles => :web do
      stream "tail -f #{shared_path}/log/production.log"
    end
    
  end
  
  # ===============================================================
  # INSTALLATION
  # ===============================================================
  
  namespace :install do
    
    desc "Updates all installed ruby gems"
    task :gems, :roles => :web do
      sudo "gem update"
    end
    
    desc "Installs Phusion Passenger"
    task :passenger, :roles => :web do
      puts 'Installing passenger module'
      install.passenger_apache_module
      install.config_passenger
    end
  
    desc "Setup Passenger Module"
    task :passenger_apache_module, :roles => :web do
      sudo "#{base_ruby_path}/bin/gem install passenger --no-ri --no-rdoc"
      input = ''
      run "sudo #{base_ruby_path}/bin/passenger-install-apache2-module" do |ch, stream, out|
        next if out.chomp == input.chomp || out.chomp == ''
        print out
        ch.send_data(input = $stdin.gets) if out =~ /(Enter|ENTER)/
      end
    end

    desc "Configure Passenger"
    task :config_passenger, :roles => :web do
      version = 'ERROR' # default
    
      # passenger (2.X.X, 1.X.X)
      run("gem list | grep passenger") do |ch, stream, data|
        version = data.sub(/passenger \(([^,]+).*?\)/,"\\1").strip
      end

      puts "  passenger version #{version} configured"

      passenger_config =<<-EOF
        LoadModule passenger_module #{base_ruby_path}/lib/ruby/gems/1.8/gems/passenger-#{version}/ext/apache2/mod_passenger.so
        PassengerRoot #{base_ruby_path}/lib/ruby/gems/1.8/gems/passenger-#{version}
        PassengerRuby #{base_ruby_path}/bin/ruby
      EOF
    
      put passenger_config, "/tmp/passenger"
      sudo "mv /tmp/passenger /etc/apache2/conf.d/passenger"
      apache.restart
    end
    
  end

  # ===============================================================
  # MAINTENANCE TASKS
  # ===============================================================
  namespace :sweep do
    desc "Clear file-based fragment and action caching"
    task :log, :roles => :web  do
      puts "Sweeping all the log files"
      run "cd #{current_path} && #{sudo} rake log:clear RAILS_ENV=production"
    end

    desc "Clear file-based fragment and action caching"
    task :cache, :roles => :web do
      puts "Sweeping the fragment and action cache stores"
      run "cd #{release_path} && #{sudo} rake tmp:cache:clear RAILS_ENV=production"
    end    
  end

  # ===============================================================
  # TASK CALLBACKS
  # ===============================================================
  after "deploy:update_code", "deploy:copy_config" # copy database.yml file to release path
  after "deploy:update_code", "sweep:cache" # clear cache after updating code
  after "deploy:restart"    , "deploy:repair_permissions" # fix the permissions to work properly
end
