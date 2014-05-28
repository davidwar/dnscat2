# ui_session_interactive.rb
# By Ron Bowes
# Created July 4, 2013

require 'ui_interface'

class UiSessionInteractive < UiInterface
  attr_accessor :local_id
  attr_accessor :session

  MAX_HISTORY_LENGTH = 10000

  def initialize(local_id, session, ui)
    super()

    @local_id = local_id
    @session  = session
    @ui = ui

    if(!@ui.get_option("auto_command").nil? && @ui.get_option("auto_command").length > 0)
      @session.queue_outgoing(@ui.get_option("auto_command") + "\n")
    end
  end

  def to_s()
    if(active?())
      idle = Time.now() - @last_seen
      if(idle > 60)
        return "session %d :: %s :: [idle for over a minute; probably dead]" % [@local_id, @session.name]
      elsif(idle > 5)
        return "session %d :: %s :: [idle for %d seconds]" % [@local_id, @session.name, idle]
      else
        return "session %d :: %s" % [@local_id, @session.name]
      end
    else
      return "session %d :: %s :: [closed]" % [@local_id, @session.name]
    end
  end

  def attach()
    super

    if(!active?())
      Log.WARNING("This session is closed!")
      return false
    end

    return true
  end

  def go
    line = Readline::readline("", true)

    if(line.nil?)
      return
    end

    # Add the newline that Readline strips
    line = line + "\n"

    # Queue our outgoing data
    @session.queue_outgoing(line)
  end

  def feed(data)
    seen()

    print(data)

  end

  def output(str)
    # I don't think this is necessary
    raise(DnscatException, "I don't think I use this")
  end

  def error(str)
    puts("")
    puts("ERROR: #{str}")
  end

  def ack(data)
    seen()
    #display(data, '[OUT]')
  end
end