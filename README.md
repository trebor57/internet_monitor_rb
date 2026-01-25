# Internet Monitor for AllStarLink ASL3+

A robust internet connectivity monitoring service for AllStarLink mobile nodes that automatically detects internet connection status and provides local audio announcements.

## Features

- Automatic connectivity monitoring with configurable check intervals
- Comprehensive connectivity testing (ping and DNS)
- Local audio announcements via AllStarLink
- Automatic log rotation
- Network recovery attempts
- Systemd service integration

## Installation

Download and install the latest release:

```bash
cd /tmp
wget https://github.com/hardenedpenguin/internet_monitor_rb/releases/download/v1.0.1/internet-monitor_1.0.1-1_all.deb
sudo dpkg -i internet-monitor_1.0.1-1_all.deb
sudo apt-get install -f  # Fix any dependency issues
```

## Configuration

Edit `/etc/internet-monitor.conf` and set your `NODE_NUMBER`:

```bash
sudo nano /etc/internet-monitor.conf
```

Start and enable the service:

```bash
sudo systemctl start internet-monitor
sudo systemctl enable internet-monitor
```

## Configuration Options

- `NODE_NUMBER`: Your AllStarLink node number (required)
- `CHECK_INTERVAL`: How often to check connectivity in seconds (default: 180, minimum: 30)
- `PING_HOSTS`: Space-separated list of servers to ping (default: "1.1.1.1 8.8.8.8 208.67.222.222")
- `SOUND_DIR`: Directory containing audio files (default: "/usr/share/asterisk/sounds/custom")
- `LOG_FILE`: Path to log file (default: "/var/log/internet-monitor.log")
- `ASTERISK_CLI`: Path to Asterisk CLI executable (default: "/usr/sbin/asterisk")
- `MAX_LOG_SIZE`: Maximum log file size in bytes before rotation (default: 10485760 = 10MB)
- `LOG_RETENTION`: Number of rotated log files to keep (default: 5)

## Service Management

```bash
sudo systemctl start internet-monitor    # Start the service
sudo systemctl stop internet-monitor     # Stop the service
sudo systemctl enable internet-monitor   # Enable auto-start on boot
sudo systemctl status internet-monitor   # Check service status
```

## Security

This application has been hardened against command injection vulnerabilities. All system commands use safe argument arrays instead of string interpolation. Configuration values are validated before use.

## Troubleshooting

### Service won't start
- Check that `/etc/internet-monitor.conf` exists and has a valid `NODE_NUMBER`
- Verify required commands are available: `ping`, `systemctl`, `ip`
- Check systemd logs: `journalctl -u internet-monitor -n 50`

### Audio not playing
- Verify Asterisk is running: `systemctl status asterisk`
- Check that sound files exist in the configured `SOUND_DIR`
- Verify node number is correct in configuration

### Network reconnection not working
- Ensure NetworkManager is installed and active
- Check that the service has necessary permissions
- Review logs for specific error messages

## License

This project is licensed under the GNU General Public License v3.0.
