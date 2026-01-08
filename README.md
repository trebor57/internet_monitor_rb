# Internet Monitor for AllStarLink ASL3+ (Ruby Implementation)

A robust internet connectivity monitoring service designed specifically for AllStarLink mobile nodes. This Ruby implementation provides automatic internet connection monitoring with audio announcements.

## Features

- **Automatic Monitoring**: Checks internet connectivity every 3 minutes (configurable)
- **Comprehensive Connectivity Testing**: Tests both ping connectivity and DNS resolution
- **Local Audio Announcements**: Uses AllStarLink's audio system to announce status changes
- **Multiple Ping Targets**: Tests connectivity against multiple reliable servers
- **Automatic Log Rotation**: Logs are automatically rotated when they exceed 10MB
- **Network Recovery**: Automatically attempts to restart NetworkManager when connectivity is lost
- **Systemd Service**: Runs as a background service with automatic startup
- **Debian Package**: Full Debian package support for easy installation

## Building the Debian Package

### Prerequisites

```bash
sudo apt-get install build-essential debhelper devscripts ruby
```

### Build the Package

```bash
# Build the package
dpkg-buildpackage -us -uc -b

# Or use debuild (recommended)
debuild -us -uc -b
```

The package will be created in the parent directory as `internet-monitor_1.0.0-1_all.deb`.

### Install the Package

```bash
sudo dpkg -i ../internet-monitor_1.0.0-1_all.deb

# If there are dependency issues, fix them with:
sudo apt-get install -f
```

## Configuration

After installation, edit `/etc/internet-monitor.conf` and set your `NODE_NUMBER`:

```bash
sudo nano /etc/internet-monitor.conf
```

Then start and enable the service:

```bash
sudo systemctl start internet-monitor
sudo systemctl enable internet-monitor
```

## Configuration Options

The configuration file `/etc/internet-monitor.conf` supports:

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
# Start the service
sudo systemctl start internet-monitor

# Stop the service
sudo systemctl stop internet-monitor

# Enable auto-start on boot
sudo systemctl enable internet-monitor

# Check service status
sudo systemctl status internet-monitor

# View logs
sudo journalctl -u internet-monitor -f
```

## File Locations

- **Service Script**: `/usr/sbin/internet_monitor.rb`
- **Configuration**: `/etc/internet-monitor.conf`
- **Service File**: `/etc/systemd/system/internet-monitor.service`
- **Log File**: `/var/log/internet-monitor.log`
- **Audio Files**: `/usr/share/asterisk/sounds/custom/internet-yes.ul` and `internet-no.ul`

## Troubleshooting

### Check if the service is running
```bash
sudo systemctl status internet-monitor
```

### View recent logs
```bash
sudo journalctl -u internet-monitor -n 50
```

### Test connectivity manually
```bash
ping -c 3 1.1.1.1
```

### Verify audio files exist
```bash
ls -la /usr/share/asterisk/sounds/custom/internet-*.ul
```

## License

This project is licensed under the GNU General Public License v3.0.

## Authors

- **Freddie Mac (KD5FMU)** - Original concept and development
- **Jory A. Pratt** - Enhanced implementation and reliability improvements

## Acknowledgments

- AllStarLink community for feedback and testing
- Based on the original bash implementation from [Internet-Monitor-ASL3](https://github.com/KD5FMU/Internet-Monitor-ASL3)
