require 'logger'

module Vorax
  
  # Provides custom logger
  class VoraxLogger < Logger
    def initialize(*args)
      super(*args)

      if ENV['VORAX_DEBUG']
      	@level = Logger::DEBUG
      	Vorax.logger = self
      else
      	@level = Logger::ERROR
      end

      # log formatter
      @formatter = proc do | severity, time, progname, msg | 
        "#{time} - #{severity} - #{progname} : #{msg} \n"
      end
    end

    def _parent_add(severity, message, progname)
      Logger.instance_method(:add).bind(self).call(severity, message, progname)
    end
    
    def add(severity, message = nil, progname = nil)
      if message.nil?
        if block_given?
          message = yield
        end
      end

      if progname.nil?
        progname = "vorax.sqlplus"
      end
      
      # remove unwanted flooding messages from ChildProcess
      if message =~ /\[\{:pid=>nil, :status=>nil\}\]/
        true
      else
        super(severity, message, progname)
      end
    end

    alias log add

    def debug(message)
      add(Logger::DEBUG, message, "vorax.sqlplus")
    end
  end

  # /dev/null logger
  class NullLoger < Logger
    def initialize(*args)
    end

    def add(*args, &block)
    end
  end
end