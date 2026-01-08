#!/usr/bin/env ruby
# frozen_string_literal: true

# Enhanced Internet Monitor Script for AllStarLink ASL3+
# Ruby version based on the original bash implementation
# Copyright (C) 2026 Jory A. Pratt, W5GLE <geekypenguin@gmail.com>
# Released under the GNU General Public License v3.0

require 'fileutils'

# Global flag for graceful shutdown
$running = true
Signal.trap('TERM') { $running = false }
Signal.trap('INT') { $running = false }

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
    raise "Invalid NODE_NUMBER: #{@node_number}" unless @node_number.is_a?(Integer) && @node_number >= 1
    raise "Invalid CHECK_INTERVAL: #{@check_interval} (minimum 30 seconds)" unless @check_interval.is_a?(Integer) && @check_interval >= 30
  end
end

# Logger class with rotation
class Logger
  LEVELS = %w[info warn error].freeze

  def initialize(config)
    @config = config
    @log_file = config.log_file
    FileUtils.mkdir_p(File.dirname(@log_file))
    LEVELS.each { |level| define_singleton_method(level) { |msg| log(level.upcase, msg) } }
  end

  def log(level, message)
    rotate_if_needed
    entry = "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] [#{level}] #{message}\n"
    File.write(@log_file, entry, mode: 'a')
    puts "[#{level}] #{message}"
  end

  private

  def rotate_if_needed
    return unless File.exist?(@log_file) && File.size(@log_file) > @config.max_log_size

    (@config.log_retention - 1).downto(1) do |i|
      FileUtils.mv("#{@log_file}.#{i}", "#{@log_file}.#{i + 1}") if File.exist?("#{@log_file}.#{i}")
    end
    FileUtils.mv(@log_file, "#{@log_file}.1") if File.exist?(@log_file)
    FileUtils.touch(@log_file)
  end
end

# Audio player class
class AudioPlayer
  def initialize(config, logger)
    @logger = logger
    @asterisk_cli = config.asterisk_cli
    @node = config.node_number
    @sound_dir = config.sound_dir
  end

  def play(audio_file)
    full_path = File.join(@sound_dir, "#{audio_file.chomp('.ul')}.ul")
    return false unless File.exist?(full_path)

    if @asterisk_cli && File.executable?(@asterisk_cli)
      filename = File.basename(full_path, '.ul')
      system("#{@asterisk_cli} -rx \"rpt localplay #{@node} #{filename}\" >/dev/null 2>&1")
      @logger.info("Played audio: #{filename}")
      true
    else
      @logger.warn('Asterisk CLI not available, skipping audio playback')
      false
    end
  end
end

# Connectivity tester class
class ConnectivityTester
  DNS_COMMANDS = [
    'getent hosts google.com',
    'host google.com',
    'nslookup google.com',
    'dig +short google.com'
  ].freeze

  def initialize(config, logger)
    @logger = logger
    @ping_hosts = config.ping_hosts
  end

  def has_internet?
    ping_test && dns_test
  end

  private

  def ping_test(timeout = 3)
    @ping_hosts.any? { |host| !host.empty? && system("ping -c 1 -W #{timeout} #{host} >/dev/null 2>&1") }
  rescue StandardError => e
    @logger.error("Ping test error: #{e.message}")
    false
  end

  def dns_test
    DNS_COMMANDS.any? { |cmd| system("#{cmd} >/dev/null 2>&1") } || (@logger.warn('DNS resolution failed') && false)
  rescue StandardError => e
    @logger.error("DNS test error: #{e.message}")
    false
  end
end

# Network manager class
class NetworkManager
  NETWORK_MANAGERS = [
    ['systemctl is-active --quiet NetworkManager', 'NetworkManager'],
    ['systemctl is-active --quiet systemd-networkd', 'systemd-networkd'],
    ['which netplan >/dev/null 2>&1', 'netplan']
  ].freeze

  def initialize(logger)
    @logger = logger
    @last_restart_attempt = 0
    @restart_cooldown = 300
    @consecutive_failures = 0
  end

  def detect_network_manager
    NETWORK_MANAGERS.find { |cmd, _| system("#{cmd} 2>/dev/null") }&.last || 'unknown'
  end

  def try_reconnect
    current_time = Time.now.to_i
    time_since_last_restart = current_time - @last_restart_attempt

    if @last_restart_attempt != 0 && time_since_last_restart < @restart_cooldown
      @logger.warn("In cooldown period. Next restart attempt in #{@restart_cooldown - time_since_last_restart} seconds")
      return false
    end

    @logger.warn("Attempting to reconnect network... (Attempt after #{time_since_last_restart} seconds)")
    @last_restart_attempt = current_time
    nm_type = detect_network_manager
    @logger.info("Detected network manager: #{nm_type}")

    return false unless nm_type == 'NetworkManager'

    if restart_networkmanager
      @logger.info('Network reconnection successful')
      @consecutive_failures = 0
      @restart_cooldown = 300
      true
    else
      @logger.error('Network reconnection failed')
      @consecutive_failures += 1
      if @consecutive_failures >= 3
        @restart_cooldown = [@restart_cooldown * 2, 3600].min
        @logger.warn("Increased cooldown to #{@restart_cooldown} seconds after #{@consecutive_failures} consecutive failures")
      end
      false
    end
  end

  private

  def restart_networkmanager
    @logger.info('Attempting NetworkManager restart via systemctl...')
    return false unless system('systemctl stop NetworkManager 2>&1')

    @logger.info('NetworkManager stopped successfully')
    sleep 5
    return false unless system('systemctl start NetworkManager 2>&1')

    @logger.info('NetworkManager start command issued')
    sleep 10
    verify_networkmanager_status
  end

  def verify_networkmanager_status
    return false unless system('systemctl is-active --quiet NetworkManager')
    return false if system('systemctl is-failed --quiet NetworkManager')

    sleep 2
    if system('ip link show | grep -q "state UP"')
      @logger.info('Network interfaces are up')
      true
    else
      @logger.warn('No network interfaces are up yet')
      false
    end
  end
end

# Main monitor class
class InternetMonitor
  REQUIRED_COMMANDS = %w[ping systemctl ip date].freeze

  def initialize
    @config = Config.new
    @logger = Logger.new(@config)
    @audio_player = AudioPlayer.new(@config, @logger)
    @connectivity_tester = ConnectivityTester.new(@config, @logger)
    @network_manager = NetworkManager.new(@logger)
    @network_ok = false
  end

  def validate_commands
    missing = REQUIRED_COMMANDS.reject { |cmd| system("which #{cmd} >/dev/null 2>&1") }
    raise "Missing required commands: #{missing.join(', ')}" unless missing.empty?
  end

  def run
    validate_commands
    @logger.warn("Asterisk CLI not found at #{@config.asterisk_cli}, audio playback will be disabled") unless @config.asterisk_cli && File.executable?(@config.asterisk_cli)

    @logger.info("Internet monitor started for node #{@config.node_number}")
    @logger.info("Check interval: #{@config.check_interval} seconds")
    @logger.info("Ping hosts: #{@config.ping_hosts.join(' ')}")

    while $running
      if @connectivity_tester.has_internet?
        unless @network_ok
          @audio_player.play('internet-yes')
          @logger.info('Internet reconnected. AllStarLink node should be back on the network!')
        end
        @network_ok = true
      else
        if @network_ok
          @audio_player.play('internet-no')
          @logger.warn('Internet lost. AllStarLink node is offline!')
        end
        @network_ok = false
        @network_manager.try_reconnect
      end

      break unless $running
      sleep(@config.check_interval)
    end

    @logger.info('Internet monitor stopped gracefully')
  end
end

# Main execution
begin
  InternetMonitor.new.run
rescue StandardError => e
  STDERR.puts "ERROR: #{e.message}"
  STDERR.puts e.backtrace.join("\n")
  exit 1
end
