# Felixwrapper is a Singleton class, so you can only create one felix instance at a time.
require 'loggable'
require 'singleton'
require 'fileutils'
require 'shellwords'
require 'socket'
require 'timeout'
require 'childprocess'
require 'active_support/core_ext/hash'
require 'net/http'

#Dir[File.expand_path(File.join(File.dirname(__FILE__),"tasks/*.rake"))].each { |ext| load ext } if defined?(Rake)

class Felixwrapper
  
  include Singleton
  include Loggable
  
  attr_accessor :port         # What port should felix start on? Default is 8080
  attr_accessor :felix_home   # Where is felix located? 
  attr_accessor :startup_wait # After felix starts, how long to wait until starting the tests? 
  attr_accessor :quiet        # Keep quiet about felix output?
  attr_accessor :base_path    # The root of the application. Used for determining where log files and PID files should go.
  attr_accessor :java_opts    # Options to pass to java (ex. ["-Xmx512mb", "-Xms128mb"])
  attr_accessor :port         # The port felix should listen on
  
  # configure the singleton with some defaults
  def initialize(params = {})
    if defined?(Rails.root)
      @base_path = Rails.root
    else
      @base_path = "."
    end

    logger.debug 'Initializing felixwrapper'
  end
  
  # Methods inside of the class << self block can be called directly on Felixwrapper, as class methods. 
  # Methods outside the class << self block must be called on Felixwrapper.instance, as instance methods.
  class << self
    
    def version
      @version ||= File.read(File.join(File.dirname(__FILE__), '..', 'VERSION')).chomp
    end

    def load_config
      if defined? Rails 
        config_name =  Rails.env 
        app_root = Rails.root
      else 
        config_name =  ENV['environment']
        app_root = ENV['APP_ROOT']
        app_root ||= '.'
      end
      filename = "#{app_root}/config/felix.yml"
      begin
        file = YAML.load_file(filename)
      rescue Exception => e
        logger.warn "Didn't find expected felixwrapper config file at #{filename}, using default file instead."
        file ||= YAML.load_file(File.join(File.dirname(__FILE__),"../config/felix.yml"))
        #raise "Unable to load: #{file}" unless file
      end
      config = file.with_indifferent_access
      config[config_name] || config[:default]
    end
    

    # Set the felix parameters. It accepts a Hash of symbols. 
    # @param [Hash<Symbol>] params
    # @param [Symbol] :felix_home Required. Where is felix located? 
    # @param [Symbol] :felix_port What port should felix start on? Default is 8080
    # @param [Symbol] :startup_wait After felix starts, how long to wait before running tests? If you don't let felix start all the way before running the tests, they'll fail because they can't reach felix.
    # @param [Symbol] :quiet Keep quiet about felix output? Default is true. 
    # @param [Symbol] :java_opts A list of options to pass to the jvm 
    def configure(params = {})
      felix_server = self.instance
      felix_server.reset_process!
      felix_server.quiet = params[:quiet].nil? ? true : params[:quiet]
      if defined?(Rails.root)
       base_path = Rails.root
      elsif defined?(APP_ROOT)
       base_path = APP_ROOT
      else
       raise "You must set either Rails.root, APP_ROOT or pass :felix_home as a parameter so I know where felix is" unless params[:felix_home]
      end
      felix_server.felix_home = params[:felix_home] || File.expand_path(File.join(base_path, 'felix'))
      ENV['FELIX_HOME'] = felix_server.felix_home
      felix_server.port = params[:felix_port] || 8080
      felix_server.startup_wait = params[:startup_wait] || 5
      felix_server.java_opts = params[:java_opts] || []
      return felix_server
    end
   
     
    # Wrap the tests. Startup felix, yield to the test task, capture any errors, shutdown
    # felix, and return the error. 
    # @example Using this method in a rake task
    #   require 'felixwrapper'
    #   desc "Spin up felix and run tests against it"
    #   task :newtest do
    #     felix_params = { 
    #       :felix_home => "/path/to/felix", 
    #       :quiet => false, 
    #       :felix_port => 8983, 
    #       :startup_wait => 30
    #     }
    #     error = Felixwrapper.wrap(felix_params) do   
    #       Rake::Task["rake:spec"].invoke 
    #       Rake::Task["rake:cucumber"].invoke 
    #     end 
    #     raise "test failures: #{error}" if error
    #   end
    def wrap(params)
      error = false
      felix_server = self.configure(params)

      begin
        felix_server.start
        yield
      rescue
        error = $!
        puts "*** Error starting felix: #{error}"
      ensure
        # puts "stopping felix server"
        felix_server.stop
      end

      return error
    end
    
    # Convenience method for configuring and starting felix with one command
    # @param [Hash] params: The configuration to use for starting felix
    # @example 
    #    Felixwrapper.start(:felix_home => '/path/to/felix', :felix_port => '8983')
    def start(params)
       Felixwrapper.configure(params)
       Felixwrapper.instance.start
       return Felixwrapper.instance
    end
    
    # Convenience method for configuring and starting felix with one command. Note
    # that for stopping, only the :felix_home value is required (including other values won't 
    # hurt anything, though). 
    # @param [Hash] params: The felix_home to use for stopping felix
    # @return [Felixwrapper.instance]
    # @example 
    #    Felixwrapper.stop_with_params(:felix_home => '/path/to/felix')
    def stop(params)
       Felixwrapper.configure(params)
       Felixwrapper.instance.stop
       return Felixwrapper.instance
    end
    
    # Determine whether the felix at the given felix_home is running
    # @param [Hash] params: :felix_home is required. Which felix do you want to check the status of?
    # @return [Boolean]
    # @example
    #    Felixwrapper.is_felix_running?(:felix_home => '/path/to/felix')
    def is_felix_running?(params)      
      Felixwrapper.configure(params)
      pid = Felixwrapper.instance.pid
      return false unless pid
      true
    end
    
    # Return the pid of the specified felix, or return nil if it isn't running
    # @param [Hash] params: :felix_home is required.
    # @return [Fixnum] or [nil]
    # @example
    #    Felixwrapper.pid(:felix_home => '/path/to/felix')
    def pid(params)
      Felixwrapper.configure(params)
      pid = Felixwrapper.instance.pid
      return nil unless pid
      pid
    end
    
    # Check to see if the port is open so we can raise an error if we have a conflict
    # @param [Fixnum] port the port to check
    # @return [Boolean]
    # @example
    #  Felixwrapper.is_port_open?(8983)
    def is_port_in_use?(port)
      begin
        Timeout::timeout(1) do
          begin
            s = TCPSocket.new('127.0.0.1', port)
            s.close
            return true
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            return false
          rescue
            return false
          end
        end
      rescue Timeout::Error
      end

      return false
    end
    
    # Check to see if the pid is actually running. This only works on unix. 
    def is_pid_running?(pid)
      begin
        return Process.getpgid(pid) != -1
      rescue Errno::ESRCH
        return false
      end
    end
    
    def is_responding?(port)
      begin
        Timeout::timeout(1) do
          begin
            response = Net::HTTP.get_response(URI.parse("http://localhost:#{port}/login.html"))
            return true if "200" == response.code
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            return false
          rescue
            return false
          end
        end
      rescue Timeout::Error
      end

      return false
    end
          

    end #end of class << self
    
        
   # What command is being run to invoke felix? 
   def felix_command
#     ["java", java_variables, java_opts, "-jar", "bin/felix.jar"].flatten
#FIXME replace the following line with a fully configured call to java to start felix
     ["bin/start_matterhorn.sh"].flatten
   end

   def felix_stop_command
#FIXME replace the following line with a fully configured call to java to stop felix
     ["bin/shutdown_matterhorn.sh"].flatten
   end

   def java_variables
     ["-Dfelix.port=#{@port}"]
   end

   # Start the felix server. Check the pid file to see if it is running already, 
   # and stop it if so. After you start felix, write the PID to a file. 
   # This is the instance start method. It must be called on Felixwrapper.instance
   # You're probably better off using Felixwrapper.start(:felix_home => "/path/to/felix")
   # @example
   #    Felixwrapper.configure(params)
   #    Felixwrapper.instance.start
   #    return Felixwrapper.instance
   def start
     logger.debug "Starting felix with these values: "
     logger.debug "felix_home: #{@felix_home}"
     logger.debug "felix_command: #{felix_command.join(' ')}"
     
     # Check to see if we can start.
     # 1. If there is a pid, check to see if it is really running
     # 2. Check to see if anything is blocking the port we want to use     
     if pid
       if Felixwrapper.is_pid_running?(pid)
         raise("Server is already running with PID #{pid}")
       else
         logger.warn "Removing stale PID file at #{pid_path}"
         File.delete(pid_path)
       end
       if Felixwrapper.is_port_in_use?(self.port)
         raise("Port #{self.port} is already in use.")
       end
     end
     Dir.chdir(@felix_home) do
       process.start
     end
     FileUtils.makedirs(pid_dir) unless File.directory?(pid_dir)
     begin
       f = File.new(pid_path,  "w")
     rescue Errno::ENOENT, Errno::EACCES
       f = File.new(File.join(@base_path,'tmp',pid_file),"w")
     end
     f.puts "#{process.pid}"
     f.close
     logger.debug "Wrote pid file to #{pid_path} with value #{process.pid}"
     startup_wait!
   end

   # Wait for the felix server to start and begin listening for requests
   def startup_wait!
     begin
     Timeout::timeout(startup_wait) do
       sleep 1 until (Felixwrapper.is_port_in_use? self.port and Felixwrapper.is_responding? self.port)
     end 
     rescue Timeout::Error
       logger.warn "Waited #{startup_wait} seconds for felix to start, but it is not yet listening on port #{self.port}. Continuing anyway."
     end
   end
 
   def process
     @process ||= begin
        process = ChildProcess.build(*felix_command)
        if self.quiet
          process.io.stderr = File.open(File.expand_path("felixwrapper.log"), "w+")
          process.io.stdout = process.io.stderr
           logger.warn "Logging felixwrapper stdout to #{File.expand_path(process.io.stderr.path)}"
        else
          process.io.inherit!
        end
        process.detach = true

        process
      end
   end

   def reset_process!
     @process = nil
   end

   def stop_process
     @stop_process ||= begin
        stop_process = ChildProcess.build(*felix_stop_command)
        if self.quiet
          stop_process.io.stderr = File.open(File.expand_path("felixwrapper.log"), "w+")
          stop_process.io.stdout = process.io.stderr
          # logger.warn "Logging felixwrapper stdout to #{File.expand_path(process.io.stderr.path)}"
        else
          stop_process.io.inherit!
        end
        stop_process.detach = true

        stop_process
      end
   end

   # Instance stop method. Must be called on Felixwrapper.instance
   # You're probably better off using Felixwrapper.stop(:felix_home => "/path/to/felix")
   # @example
   #    Felixwrapper.configure(params)
   #    Felixwrapper.instance.stop
   #    return Felixwrapper.instance
   def stop    
     logger.debug "Instance stop method called for pid '#{pid}'"
     if pid
       if @process
         @process.stop
       else
         Process.kill("KILL", pid) rescue nil
       end

     Dir.chdir(@felix_home) do
       stop_process.start
     end

       begin
         File.delete(pid_path)
       rescue
       end
     end
   end
 

   # The fully qualified path to the pid_file
   def pid_path
     #need to memoize this, becasuse the base path could be relative and the cwd can change in the yield block of wrap
     @path ||= File.join(pid_dir, pid_file)
   end

   # The file where the process ID will be written
   def pid_file
     felix_home_to_pid_file(@felix_home)
   end
   
    # Take the @felix_home value and transform it into a legal filename
    # @return [String] the name of the pid_file
    # @example
    #    /usr/local/felix1 => _usr_local_felix1.pid
    def felix_home_to_pid_file(felix_home)
      begin
        felix_home.gsub(/\//,'_') << ".pid"
      rescue
        raise "Couldn't make a pid file for felix_home value #{felix_home}"
        raise $!
      end
    end

   # The directory where the pid_file will be written
   def pid_dir
     File.expand_path(File.join(@base_path,'tmp','pids'))
   end
   
   # Check to see if there is a pid file already
   # @return true if the file exists, otherwise false
   def pid_file?
      return true if File.exist?(pid_path)
      false
   end

   # the process id of the currently running felix instance
   def pid
      File.open( pid_path ) { |f| return f.gets.to_i } if File.exist?(pid_path)
   end
   
end

load File.join(File.dirname(__FILE__),"tasks/felixwrapper.rake") if defined?(Rake)
