# Setup

1. Clone this repo to the target machine:
   ```sh
   git clone https://github.com/felds/s3-backup.git /opt/s3-backup
   ```

2. Create an instance script somewhere on the machine (e.g. `~/backup-myapp.sh`) following [the template](instance-script.md), then make it executable:
   ```sh
   chmod +x ~/backup-myapp.sh
   ```

3. Schedule it to run periodically.

   **With cron:**
   ```
   0 3 * * * /bin/bash ~/backup-myapp.sh
   ```

   **With systemd timers** (for systems without cron):

   Create the unit files under your user's systemd directory:

   **`~/.config/systemd/user/backup-myapp.service`**
   ```ini
   [Unit]
   Description=Backup myapp

   [Service]
   Type=oneshot
   ExecStart=/bin/bash /home/user/backup-myapp.sh
   ```

   **`~/.config/systemd/user/backup-myapp.timer`**
   ```ini
   [Unit]
   Description=Run backup-myapp daily at 3am

   [Timer]
   OnCalendar=*-*-* 03:00:00
   Persistent=true

   [Install]
   WantedBy=timers.target
   ```

   Enable lingering so your user's services start at boot without an active session, then enable the timer:
   ```sh
   loginctl enable-linger $USER
   systemctl --user daemon-reload
   systemctl --user enable --now backup-myapp.timer
   ```

   `Persistent=true` ensures the backup runs on next boot if the machine was off at the scheduled time.

   **Verifying the setup:**
   ```sh
   # Check the timer is active and see when it will next run
   systemctl --user status backup-myapp.timer

   # List all user timers
   systemctl --user list-timers

   # Check the last run's output and exit status
   journalctl --user -u backup-myapp.service -n 50

   # Run the backup manually
   systemctl --user start backup-myapp.service
   ```

4. Ensure the EC2 instance (or IAM user) has the required [IAM permissions](iam-policy.md).
