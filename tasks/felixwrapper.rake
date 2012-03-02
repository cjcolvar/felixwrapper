# Note: These rake tasks are here mainly as examples to follow. You're going to want
# to write your own rake tasks that use the locations of your felix instances. 

require 'felixwrapper'

namespace :felixwrapper do
  
  felix = {
    :felix_home => File.expand_path("#{File.dirname(__FILE__)}/../felix"),
    :felix_port => "8080", :java_opts=>["-Xms1024m -Xmx1024m -XX:MaxPermSize=256m"]
  }
  
  desc "Return the status of felix"
  task :status do
    status = Felixwrapper.is_felix_running?(felix) ? "Running: #{Felixwrapper.pid(felix)}" : "Not running"
    puts status
  end
  
  desc "Start felix"
  task :start do
    Felixwrapper.start(felix)
    puts "felix started at PID #{Felixwrapper.pid(felix)}"
  end
  
  desc "stop felix"
  task :stop do
    Felixwrapper.stop(felix)
    puts "felix stopped"
  end
  
  desc "Restarts felix"
  task :restart do
    Felixwrapper.stop(felix)
    Felixwrapper.start(felix)
  end

  desc "Init Hydrant configuration" 
  task :init => [:environment] do
    if !ENV["environment"].nil? 
      RAILS_ENV = ENV["environment"]
    end
    
    FELIX_HOME = File.expand_path(File.dirname(__FILE__) + '/../../felix')
    
    FELIX_PARAMS = {
      :quiet => ENV['HYDRA_CONSOLE'] ? false : true,
      :felix_home => FELIX_HOME_TEST,
      :felix_port => 8080,
    }

    # If Matterhorn connection is not already initialized, initialize it using Rubyhorn defaults
    Rubyhorn.init unless Thread.current[:repo]  
  end

  desc "Copies the default Matterhorn config for the bundled felix"
  task :config_matterhorn => [:init] do
    FileList['matterhorn/conf/*'].each do |f|  
      cp("#{f}", FELIX_PARAMS[:felix_home] + '/conf/', :verbose => true)
    end
  end
  
  desc "Copies the default Matterhorn configs into the bundled felix"
  task :config do
    Rake::Task["felix:config_matterhorn"].invoke
  end
end
