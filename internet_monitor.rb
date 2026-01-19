#!/usr/bin/env ruby
# frozen_string_literal: true

# Enhanced Internet Monitor Script for AllStarLink ASL3+
# Ruby version based on the original bash implementation
# Copyright (C) 2026 Jory A. Pratt, W5GLE <geekypenguin@gmail.com>
# Released under the GNU General Public License v3.0

require 'fileutils'
require 'resolv'

# Signal handler class for graceful shutdown
class SignalHandler
  attr_reader :running

  def initialize
    @running = true
    Signal.trap('TERM') { @running = false }
    Signal.trap('INT') { @running = false }
  end
end

# Configuration class
class Config
  CONFIG_FILE = '/etc/internet-monitor.conf'
  CONFIG_MAP = {
    'NODE_NUMBER' => [:node_number, ->(v) { v.to_i }],
    'CHECK_INTERVAL' => [:check_interval, ->(v) { v.to_i }],
    'PING_HOSTS' => [:ping_hosts, ->(v) { v.split }],
    'SOUND_DIR' => [:sound_dir, ->(v) { v }],
    'LOG_FILE' => [:log_file, ->(v) { v }],
    'ASTERISK_CLI' => [:asterisk_cli, ->(v) { v }],
    'MAX_LOG_SIZE' => [:max_log_size, ->(v) { v.to_i }],
    'LOG_RETENTION' => [:log_retention, ->(v) { v.to_i }]
  }.freeze

  attr_accessor :node_number, :check_interval, :ping_hosts, :sound_dir,
                :log_file, :asterisk_cli, :max_log_size, :log_retention

  def initialize
    set_defaults
    load_config
    validate
  end

  private

  def set_defaults
    @node_number = 12345
    @check_interval = 180
    @ping_hosts = %w[1.1.1.1 8.8.8.8 208.67.222.222]
    @sound_dir = '/usr/share/asterisk/sounds/custom'
    @log_file = '/var/log/internet-monitor.log'
    @asterisk_cli = '/usr/sbin/asterisk'
    @max_log_size = 10_485_760
    @log_retention = 5
  end

  def load_config
    return unless File.exist?(CONFIG_FILE)

    File.readlines(CONFIG_FILE).each do |line|
      line = line.strip
      next if line.empty? || line.start_with?('#')
      raise "Invalid characters in configuration file: #{CONFIG_FILE}" if line.match?(/[;&|<>]/)

      key, value = line.split('=', 2).map(&:strip)
      next unless key && value && CONFIG_MAP[key]

      value = value.gsub(/^["']|["']$/, '')
      attr_name, converter = CONFIG_MAP[key]
      instance_variable_set("@#{attr_name}", converter.call(value))
    end
  end

  def validate
    raise "Invalid NODE_NUMBER: #{@node_number}" unless @node_number.is_a?(Integer) && @node_number >= 1 && @node_number <= 999_999_999

    unless @check_interval.is_a?(Integer) && @check_interval >= 30 && @check_interval <= 3600
      raise "Invalid CHECK_INTERVAL: #{@check_interval} (must be between 30 and 3600 seconds)"
    end

    # Validate ping hosts
    raise "PING_HOSTS cannot be empty" if @ping_hosts.nil? || @ping_hosts.empty?
    @ping_hosts.each do |host|
      raise "Invalid ping host: #{host}" if host.nil? || host.strip.empty?
    end

    # Validate file paths
    raise "SOUND_DIR cannot be empty" if @sound_dir.nil? || @sound_dir.strip.empty?
    raise "LOG_FILE cannot be empty" if @log_file.nil? || @log_file.strip.empty?
    raise "ASTERISK_CLI cannot be empty" if @asterisk_cli.nil? || @asterisk_cli.strip.empty?

    # Validate log settings
    raise "MAX_LOG_SIZE must be positive" unless @max_log_size.is_a?(Integer) && @max_log_size > 0
    raise "LOG_RETENTION must be between 1 and 100" unless @log_retention.is_a?(Integer) && @log_retention >= 1 && @log_retention <= 100
  end
end

# Custom logger class with rotation (renamed to avoid conflict with Ruby's Logger)
class InternetMonitorLogger
  LEVELS = %w[debug info warn error].freeze

  def initialize(config)
    @config = config
    @log_file = config.log_file
    begin
      FileUtils.mkdir_p(File.dirname(@log_file))
    rescue StandardError => e
      raise "Cannot create log directory: #{e.message}"
    end
    LEVELS.each { |level| define_singleton_method(level) { |msg| log(level.upcase, msg) } }
  end

  def log(level, message)
    rotate_if_needed
    entry = "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] [#{level}] #{message}\n"
    begin
      File.open(@log_file, 'a') do |f|
        f.write(entry)
        f.fsync
      end
    rescue StandardError => e
      # Fallback to stderr if file writing fails
      STDERR.puts "[#{level}] #{message} (log write failed: #{e.message})"
      return
    end
    puts "[#{level}] #{message}"
  end

  private

  def rotate_if_needed
    return unless File.exist?(@log_file) && File.size(@log_file) > @config.max_log_size

    begin
      # Rotate log files: move .1 to .2, .2 to .3, etc.
      (@config.log_retention - 1).downto(1) do |i|
        old_file = "#{@log_file}.#{i}"
        new_file = "#{@log_file}.#{i + 1}"
        FileUtils.mv(old_file, new_file) if File.exist?(old_file)
      end
      # Move current log to .1
      FileUtils.mv(@log_file, "#{@log_file}.1") if File.exist?(@log_file)
      FileUtils.touch(@log_file)
    rescue StandardError => e
      # Log rotation failure shouldn't stop the application
      STDERR.puts "Log rotation failed: #{e.message}"
    end
  end
end

# Audio player class for AllStarLink audio announcements
class AudioPlayer
  def initialize(config, logger)
    @logger = logger
    @asterisk_cli = config.asterisk_cli
    @node = config.node_number
    @sound_dir = config.sound_dir
  end

  def play(audio_file)
    base_name = audio_file.chomp('.ulaw')
    full_path = File.join(@sound_dir, "#{base_name}.ulaw")
    return false unless File.exist?(full_path)

    if @asterisk_cli && File.executable?(@asterisk_cli)
      filename = base_name
      # Validate inputs to prevent command injection
      # Only allow alphanumeric, dots, dashes, and underscores in filename
      safe_filename = filename.gsub(/[^a-zA-Z0-9._-]/, '')
      safe_node = @node.to_i.to_s # Ensure node is a valid integer string
      
      # Reject if validation removed characters (potential injection attempt)
      if safe_filename != filename || safe_node != @node.to_s
        @logger.warn("Invalid characters in audio filename or node number, skipping playback")
        return false
      end
      
      # Asterisk CLI requires the command as a single string argument
      # Since we've validated inputs, it's safe to construct the command string
      asterisk_cmd = "rpt localplay #{safe_node} #{safe_filename}"
      # Use safe command execution - asterisk CLI with validated arguments
      system(@asterisk_cli, '-rx', asterisk_cmd, out: File::NULL, err: File::NULL)
      @logger.info("Played audio: #{filename}")
      true
    else
      @logger.warn('Asterisk CLI not available, skipping audio playback')
      false
    end
  end
end

# Connectivity tester class for ping and DNS testing
class ConnectivityTester
  DNS_TEST_HOST = 'google.com'.freeze

  def initialize(config, logger)
    @logger = logger
    @ping_hosts = config.ping_hosts
  end

  def has_internet?
    ping_test && dns_test
  end

  private

  # Test connectivity using ping with safe command execution
  def ping_test(timeout = 3)
    @ping_hosts.any? do |host|
      next false if host.nil? || host.strip.empty?

      # Use safe command execution with argument array
      system('ping', '-c', '1', '-W', timeout.to_s, host, out: File::NULL, err: File::NULL)
    end
  rescue StandardError => e
    @logger.error("Ping test error: #{e.message}")
    false
  end

  # Test DNS resolution using Ruby's Resolv library (more secure than shell commands)
  def dns_test
    begin
      Resolv.getaddress(DNS_TEST_HOST)
      @logger.debug("DNS resolution successful for #{DNS_TEST_HOST}")
      true
    rescue Resolv::ResolvError => e
      @logger.warn("DNS resolution failed for #{DNS_TEST_HOST}: #{e.message}")
      false
    rescue StandardError => e
      @logger.error("DNS test error: #{e.message}")
      false
    end
  end
end

# Network manager class for detecting and restarting network services
class NetworkManager
  # Network manager detection commands (using safe command execution)
  NETWORK_MANAGERS = [
    [['systemctl', 'is-active', '--quiet', 'NetworkManager'], 'NetworkManager'],
    [['systemctl', 'is-active', '--quiet', 'systemd-networkd'], 'systemd-networkd'],
    [['which', 'netplan'], 'netplan']
  ].freeze

  def initialize(logger)
    @logger = logger
    @last_restart_attempt = 0
    @restart_cooldown = 300 # Initial cooldown: 5 minutes
    @consecutive_failures = 0
  end

  # Detect which network manager is active on the system
  def detect_network_manager
    NETWORK_MANAGERS.find do |cmd_array, _|
      system(*cmd_array, out: File::NULL, err: File::NULL)
    end&.last || 'unknown'
  end

  # Attempt to reconnect network with cooldown period to prevent rapid restart attempts
  def try_reconnect
    current_time = Time.now.to_i
    time_since_last_restart = current_time - @last_restart_attempt

    # Enforce cooldown period to prevent excessive restart attempts
    if @last_restart_attempt != 0 && time_since_last_restart < @restart_cooldown
      @logger.warn("In cooldown period. Next restart attempt in #{@restart_cooldown - time_since_last_restart} seconds")
      return false
    end

    @logger.warn("Attempting to reconnect network... (Attempt after #{time_since_last_restart} seconds)")
    @last_restart_attempt = current_time
    nm_type = detect_network_manager
    @logger.info("Detected network manager: #{nm_type}")

    # Only attempt restart for NetworkManager (most common on mobile systems)
    return false unless nm_type == 'NetworkManager'

    if restart_networkmanager
      @logger.info('Network reconnection successful')
      @consecutive_failures = 0
      @restart_cooldown = 300 # Reset to initial cooldown
      true
    else
      @logger.error('Network reconnection failed')
      @consecutive_failures += 1
      # Exponential backoff: increase cooldown after 3 consecutive failures (max 1 hour)
      if @consecutive_failures >= 3
        @restart_cooldown = [@restart_cooldown * 2, 3600].min
        @logger.warn("Increased cooldown to #{@restart_cooldown} seconds after #{@consecutive_failures} consecutive failures")
      end
      false
    end
  end

  private

  # Restart NetworkManager service using safe command execution
  def restart_networkmanager
    @logger.info('Attempting NetworkManager restart via systemctl...')
    
    # Stop NetworkManager
    unless system('systemctl', 'stop', 'NetworkManager', out: File::NULL, err: File::NULL)
      @logger.error('Failed to stop NetworkManager')
      return false
    end

    @logger.info('NetworkManager stopped successfully')
    sleep 5 # Wait for service to fully stop

    # Start NetworkManager
    unless system('systemctl', 'start', 'NetworkManager', out: File::NULL, err: File::NULL)
      @logger.error('Failed to start NetworkManager')
      return false
    end

    @logger.info('NetworkManager start command issued')
    sleep 10 # Wait for service to start and initialize
    verify_networkmanager_status
  end

  # Verify that NetworkManager is running and network interfaces are up
  def verify_networkmanager_status
    # Check if NetworkManager is active
    unless system('systemctl', 'is-active', '--quiet', 'NetworkManager', out: File::NULL, err: File::NULL)
      @logger.warn('NetworkManager is not active')
      return false
    end

    # Check if NetworkManager has failed
    if system('systemctl', 'is-failed', '--quiet', 'NetworkManager', out: File::NULL, err: File::NULL)
      @logger.warn('NetworkManager is in failed state')
      return false
    end

    sleep 2 # Give interfaces time to come up

    # Check if any network interfaces are up (using safe command execution)
    output = `ip link show 2>/dev/null`
    if output && output.include?('state UP')
      @logger.info('Network interfaces are up')
      true
    else
      @logger.warn('No network interfaces are up yet')
      false
    end
  end
end

# Main monitor class that orchestrates connectivity monitoring
class InternetMonitor
  REQUIRED_COMMANDS = %w[ping systemctl ip].freeze

  def initialize(signal_handler)
    @signal_handler = signal_handler
    @config = Config.new
    @logger = InternetMonitorLogger.new(@config)
    @audio_player = AudioPlayer.new(@config, @logger)
    @connectivity_tester = ConnectivityTester.new(@config, @logger)
    @network_manager = NetworkManager.new(@logger)
    @network_ok = false
  end

  # Validate that required system commands are available
  def validate_commands
    missing = REQUIRED_COMMANDS.reject do |cmd|
      system('which', cmd, out: File::NULL, err: File::NULL)
    end
    raise "Missing required commands: #{missing.join(', ')}" unless missing.empty?
  end

  # Main monitoring loop
  def run
    validate_commands
    @logger.warn("Asterisk CLI not found at #{@config.asterisk_cli}, audio playback will be disabled") unless @config.asterisk_cli && File.executable?(@config.asterisk_cli)

    @logger.info("Internet monitor started for node #{@config.node_number}")
    @logger.info("Check interval: #{@config.check_interval} seconds")
    @logger.info("Ping hosts: #{@config.ping_hosts.join(' ')}")
    @logger.debug("Log file: #{@config.log_file}")

    # Main monitoring loop - check connectivity at configured intervals
    while @signal_handler.running
      if @connectivity_tester.has_internet?
        # Internet is available
        unless @network_ok
          # State transition: offline -> online
          @audio_player.play('internet-yes')
          @logger.info('Internet reconnected. AllStarLink node should be back on the network!')
        end
        @network_ok = true
      else
        # Internet is not available
        if @network_ok
          # State transition: online -> offline
          @audio_player.play('internet-no')
          @logger.warn('Internet lost. AllStarLink node is offline!')
        end
        @network_ok = false
        # Attempt to reconnect network
        @network_manager.try_reconnect
      end

      break unless @signal_handler.running
      sleep(@config.check_interval)
    end

    @logger.info('Internet monitor stopped gracefully')
  end
end

# Main execution
begin
  signal_handler = SignalHandler.new
  monitor = InternetMonitor.new(signal_handler)
  monitor.run
rescue StandardError => e
  STDERR.puts "ERROR: #{e.message}"
  STDERR.puts e.backtrace.join("\n")
  exit 1
end
