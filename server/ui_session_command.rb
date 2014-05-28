##
# ui_session_command.rb
# By Ron Bowes
# Created May, 2014
#
# See LICENSE.txt
##

require 'command_packet_stream'
require 'command_packet'
require 'parser'
require 'shellwords'
require 'ui_handler'

class UiSessionCommand < UiInterface
  attr_reader :session
  attr_reader :local_id

  include Parser
  include UiHandler

  def kill_me()
    puts()
    puts("Are you sure you want to kill this session? [Y/n]")
    if($stdin.gets[0].downcase == 'n')
      puts("You might want to use ^z or the 'suspend' command")
    else
      @ui.kill_session(@local_id)
      @ui.detach_session()
    end
  end


  def register_commands()
    register_alias('q',       'quit')
    register_alias('exit',    'quit')
    register_alias('run',     'exec')
    register_alias('execute', 'exec')
    register_alias('up',      'suspend')
    register_alias('back',    'suspend')
    register_alias('pause',   'suspend')

    register_command("quit",
      Trollop::Parser.new do
        banner("Closes and kills this command session")
      end,

      Proc.new do |opts|
        kill_me()
      end,
    )

    register_command("help",
      Trollop::Parser.new do
        banner("Shows a help menu")
      end,

      Proc.new do |opts|
        puts()
        puts("Available session commands:")
        @commands.keys.sort.each do |name|
          # Don't display the empty command
          if(name != "")
            puts("- #{name}")
          end
        end

        puts("For more information, --help can be passed to any command")
      end,
    )

    register_command("clear",
      Trollop::Parser.new do
        banner("Clears the display")
      end,
      Proc.new do |opts|
        0.upto(100) do puts() end
      end,
    )

    register_command("ping",
      Trollop::Parser.new do
        banner("Sends a 'ping' to the remote host to make sure it's still alive)")
        opt :size, "Size", :type => :integer, :required => false, :default => 256
      end,
      Proc.new do |opts|
        data = "A" * opts[:size]
        id = command_id()
        @pings[id] = data
        packet = CommandPacket.create_ping_request(id, data)
        @session.queue_outgoing(packet)
        puts("Ping request 0x%x sent! (0x%x bytes)" % [id, opts[:size]])
      end,
    )

    register_command("shell",
      Trollop::Parser.new do
        banner("Spawn a shell on the remote host")
        opt :name, "Name", :type => :string, :required => false, :default => nil
      end,

      Proc.new do |opts|
        name = opts[:name] || "executing a shell"

        packet = CommandPacket.create_shell_request(command_id(), name)
        @session.queue_outgoing(packet)
        puts("Sent request to execute a shell")
      end,
    )

    register_command("exec",
      Trollop::Parser.new do
        banner("Execute a program on the remote host")
        opt :command, "Command", :type => :string, :required => false, :default => nil
        opt :name,    "Name",    :type => :string, :required => false, :default => nil
      end,

      Proc.new do |opts, optarg|
        command = opts[:command] || optarg
        name    = opts[:name]    || ("executing %s" % command)

        if(command == "")
          puts("No command given!")
        else
          packet = CommandPacket.create_exec_request(command_id(), name, command)
          @session.queue_outgoing(packet)
          puts("Sent request to execute #{opts[:command]}")
        end
      end,
    )

    register_command("suspend",
      Trollop::Parser.new do
        banner("Go back to the main menu")
      end,

      Proc.new do |opts, optarg|
        @ui.detach_session()
      end,
    )

    register_command('sessions',
      Trollop::Parser.new do
        banner("Lists the current active sessions managed by this session")
        opt :all, "Show dead sessions", :type => :boolean, :required => false
      end,

      Proc.new do |opts, optval|
        puts("Sessions:")
        puts()
        display_uis(opts[:all])
      end,
    )

    register_command("session",
      Trollop::Parser.new do
        banner("Interact with a session")
        opt :i, "Interact with the chosen session", :type => :integer, :required => false
      end,

      Proc.new do |opts, optval|
        if(opts[:i].nil?)
          puts("Known sessions:")
          display_uis(false)
        else
          ui = @ui.get_by_local_id(opts[:i])
          if(ui.nil?)
            error("Session #{opts[:i]} not found!")
            display_uis(false)
          else
            @ui.attach_session(ui)
          end
        end
      end
    )
  end

  def initialize(local_id, session, ui)
    super()

    initialize_parser("dnscat [command: #{local_id}]> ")
    initialize_ui_handler()

    @local_id = local_id
    @session  = session
    @ui = ui
    @stream = CommandPacketStream.new()
    @command_id = 0x0001
    @pings = {}

    register_commands()

    puts("Welcome to a command session! Use 'help' for a list of commands or ^z for the main menu")
  end

  def handle_ping_response(packet)
    data = packet.data
    expected = @pings[packet.request_id]
    if(expected.nil?)
      puts("Unexpected ping response received")
    elsif(data == expected)
      puts("Ping response 0x%x received!" % packet.request_id)
      @pings.delete(packet.request_id)
    else
      puts("Ping response 0x%x was invalid!" % packet.request_id)
    end
  end

  # Handles any response that contains a new session id (shell and exec, initially)
  def handle_session_response(packet)
    # Globally create the session
    add_pending(packet.session_id)
  end

  def handle_shell_response(packet)
    handle_session_response(packet)
  end

  def handle_exec_response(packet)
    handle_session_response(packet)
  end

  def feed(data)
    @stream.feed(data, false) do |packet|
      if(packet.is_response?())
        if(packet.command_id == CommandPacket::COMMAND_PING)
          handle_ping_response(packet)
        elsif(packet.command_id == CommandPacket::COMMAND_SHELL)
          handle_shell_response(packet)
        elsif(packet.command_id == CommandPacket::COMMAND_EXEC)
          handle_exec_response(packet)
        else
          output("Didn't know how to handle command packet: %s" % packet.to_s)
        end
      else
        raise(DnscatException, "We got a command request packet somehow")
      end
    end
  end

  def output(str)
    puts()
    puts(str)

    if(attached?())
      print(">> ")
    end
  end

  def error(str)
    puts()
    puts("ERROR: %s" % str)

    if(attached?())
      print(">> ")
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

  def command_id()
    id = @command_id
    @command_id += 1
    return id
  end
end