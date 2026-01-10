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
wget https://github.com/hardenedpenguin/internet_monitor_rb/releases/download/v1.0.0/internet-monitor_1.0.0-1_all.deb
sudo dpkg -i internet-monitor_1.0.0-1_all.deb
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

## License

This project is licensed under the GNU General Public License v3.0.
