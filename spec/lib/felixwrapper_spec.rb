require 'spec_helper'
require 'rubygems'

  describe Felixwrapper do
    
    # FELIX1 = 
    
    before(:all) do
      @felix_params = {
        :quiet => false,
        :felix_home => "/path/to/felix",
        :felix_port => 8080,
        :startup_wait => 0,
        :java_opts => ["-Xms1024m", "-Xmx1024m", "-XX:MaxPermSize=256m"]
      }
    end

    context "config" do
      it "loads the application felix.yml first" do
        YAML.expects(:load_file).with('./config/felix.yml').once.returns({})
        config = Felixwrapper.load_config
      end

      it "falls back on the distributed felix.yml" do
        fallback_seq = sequence('fallback sequence')
        YAML.expects(:load_file).in_sequence(fallback_seq).with('./config/felix.yml').raises(Exception)
        YAML.expects(:load_file).in_sequence(fallback_seq).with { |value| value =~ /felix.yml/ }.returns({})
        config = Felixwrapper.load_config
      end

      it "supports per-environment configuration" do
        ENV['environment'] = 'test'
        YAML.expects(:load_file).with('./config/felix.yml').once.returns({:test => {:a => 2 }, :default => { :a => 1 }})
        config = Felixwrapper.load_config
        config[:a].should == 2
      end

      it "falls back on a 'default' environment configuration" do
        ENV['environment'] = 'test'
        YAML.expects(:load_file).with('./config/felix.yml').once.returns({:default => { :a => 1 }})
        config = Felixwrapper.load_config
        config[:a].should == 1
      end
    end
    
    context "instantiation" do
      it "can be instantiated" do
        ts = Felixwrapper.instance
        ts.class.should eql(Felixwrapper)
      end

      it "can be configured with a params hash" do
        ts = Felixwrapper.configure(@felix_params) 
        ts.quiet.should == false
        ts.felix_home.should == "/path/to/felix"
        ts.port.should == 8080
        ts.startup_wait.should == 0
      end

      # passing in a hash is no longer optional
      it "raises an error when called without a :felix_home value" do
          lambda { ts = Felixwrapper.configure }.should raise_exception
      end

      it "should override nil params with defaults" do
        felix_params = {
          :quiet => nil,
          :felix_home => '/path/to/felix',
          :felix_port => nil,
          :startup_wait => nil
        }

        ts = Felixwrapper.configure(felix_params) 
        ts.quiet.should == true
        ts.felix_home.should == "/path/to/felix"
        ts.port.should == 8080
        ts.startup_wait.should == 60
      end
      
      it "passes all the expected values to felix during startup" do
        ts = Felixwrapper.configure(@felix_params) 
        command = ts.felix_command
#        command.should include("-Dfelix.port=#{@felix_params[:felix_port]}")
#        command.should include("-Xmx1024m")
	command.should include("bin/start_matterhorn.sh")
      end

      it "has a pid if it has been started" do
        felix_params = {
          :felix_home => '/tmp'
        }
        ts = Felixwrapper.configure(felix_params) 
        Felixwrapper.any_instance.stubs(:process).returns(stub('proc', :start => nil, :pid=>5454))
        ts.stop
        ts.start
        ts.pid.should eql(5454)
        ts.stop
      end
      
      it "can pass params to a start method" do
        felix_params = {
          :felix_home => '/tmp', :felix_port => 8777
        }
        ts = Felixwrapper.configure(felix_params) 
        ts.stop
        Felixwrapper.any_instance.stubs(:process).returns(stub('proc', :start => nil, :pid=>2323))
        swp = Felixwrapper.start(felix_params)
        swp.pid.should eql(2323)
        swp.pid_file.should eql("_tmp.pid")
        swp.stop
      end
      
      it "checks to see if its pid files are stale" do
        @pending
      end
      
      # return true if it's running, otherwise return false
      it "can get the status for a given felix instance" do
        # Don't actually start felix, just fake it
        Felixwrapper.any_instance.stubs(:process).returns(stub('proc', :start => nil, :pid=>12345))
        
        felix_params = {
          :felix_home => File.expand_path("#{File.dirname(__FILE__)}/../../felix")
        }
        Felixwrapper.stop(felix_params)
        Felixwrapper.is_felix_running?(felix_params).should eql(false)
        Felixwrapper.start(felix_params)
        Felixwrapper.is_felix_running?(felix_params).should eql(true)
        Felixwrapper.stop(felix_params)
      end
      
      it "can get the pid for a given felix instance" do
        # Don't actually start felix, just fake it
        Felixwrapper.any_instance.stubs(:process).returns(stub('proc', :start => nil, :pid=>54321))
        felix_params = {
          :felix_home => File.expand_path("#{File.dirname(__FILE__)}/../../felix")
        }
        Felixwrapper.stop(felix_params)
        Felixwrapper.pid(felix_params).should eql(nil)
        Felixwrapper.start(felix_params)
        Felixwrapper.pid(felix_params).should eql(54321)
        Felixwrapper.stop(felix_params)
      end
      
      it "can pass params to a stop method" do
        felix_params = {
          :felix_home => '/tmp', :felix_port => 8777
        }
        Felixwrapper.any_instance.stubs(:process).returns(stub('proc', :start => nil, :pid=>2323))
        swp = Felixwrapper.start(felix_params)
        (File.file? swp.pid_path).should eql(true)
        
        swp = Felixwrapper.stop(felix_params)
        (File.file? swp.pid_path).should eql(false)
      end
      
      it "knows what its pid file should be called" do
        ts = Felixwrapper.configure(@felix_params) 
        ts.pid_file.should eql("_path_to_felix.pid")
      end
      
      it "knows where its pid file should be written" do
        ts = Felixwrapper.configure(@felix_params) 
        ts.pid_dir.should eql(File.expand_path("#{ts.base_path}/tmp/pids"))
      end
      
      it "writes a pid to a file when it is started" do
        felix_params = {
          :felix_home => '/tmp'
        }
        ts = Felixwrapper.configure(felix_params) 
        Felixwrapper.any_instance.stubs(:process).returns(stub('proc', :start => nil, :pid=>2222))
        ts.stop
        ts.pid_file?.should eql(false)
        ts.start
        ts.pid.should eql(2222)
        ts.pid_file?.should eql(true)
        pid_from_file = File.open( ts.pid_path ) { |f| f.gets.to_i }
        pid_from_file.should eql(2222)
      end
      
    end # end of instantiation context
    
    context "logging" do
      it "has a logger" do
        ts = Felixwrapper.configure(@felix_params) 
        ts.logger.should be_kind_of(Logger)
      end
      
    end # end of logging context 
    
    context "wrapping a task" do
      it "wraps another method" do
        Felixwrapper.any_instance.stubs(:start).returns(true)
        Felixwrapper.any_instance.stubs(:stop).returns(true)
        error = Felixwrapper.wrap(@felix_params) do            
        end
        error.should eql(false)
      end
      
      it "configures itself correctly when invoked via the wrap method" do
        Felixwrapper.any_instance.stubs(:start).returns(true)
        Felixwrapper.any_instance.stubs(:stop).returns(true)
        error = Felixwrapper.wrap(@felix_params) do 
          ts = Felixwrapper.instance 
          ts.quiet.should == @felix_params[:quiet]
          ts.felix_home.should == "/path/to/felix"
          ts.port.should == 8080
          ts.startup_wait.should == 0     
        end
        error.should eql(false)
      end
      
      it "captures any errors produced" do
        Felixwrapper.any_instance.stubs(:start).returns(true)
        Felixwrapper.any_instance.stubs(:stop).returns(true)
        error = Felixwrapper.wrap(@felix_params) do 
          raise "this is an expected error message"
        end
        error.class.should eql(RuntimeError)
        error.message.should eql("this is an expected error message")
      end
      
    end # end of wrapping context

    context "quiet mode", :quiet => true do
      it "inherits the current stderr/stdout in 'loud' mode" do
        ts = Felixwrapper.configure(@felix_params.merge(:quiet => false))
        process = ts.process
        process.io.stderr.should == $stderr
        process.io.stdout.should == $stdout
      end

      it "redirect stderr/stdout to a log file in quiet mode" do
        ts = Felixwrapper.configure(@felix_params.merge(:quiet => true))
        process = ts.process
        process.io.stderr.should_not == $stderr
        process.io.stdout.should_not == $stdout
      end
    end
  end
