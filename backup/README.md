# Encrypted Backblaze B2 backup

The supplied script backs up the Compose definition, `.env`, and all service
configuration. It intentionally excludes `data/` (media libraries, torrents,
caches, and rip output), Git metadata, Firecrawl artifacts, and the B2 access
credentials used to bootstrap the backup itself.

## One-time setup

1. Create a dedicated B2 bucket and a bucket-restricted application key with
   read/write/delete capability. Use the B2 S3 endpoint for that bucket's
   region.
2. Copy `restic.env.example` to `restic.env`, enter the key ID, application
   key, and repository URL, then run `chmod 600 restic.env`.
3. Generate a strong Restic repository password, store it in your password
   manager, save it (with no trailing newline requirement) as
   `backup/restic-password`, then run `chmod 600 restic-password`.
4. Initialize and test:

   ```sh
   ./scripts/backup-init.sh
   ./scripts/backup.sh
   ```

The repository password is not backed up by this job. Losing it makes the
encrypted B2 backup unrecoverable. The B2 access key is also deliberately
excluded: it is an operational bootstrap secret, not data needed to restore
the media stack.

## Schedule

The systemd templates run daily at 03:15 and catch up after downtime. Install
them only after the manual backup succeeds:

```sh
sudo install -m 0644 systemd/media-extract-backup.service /etc/systemd/system/
sudo install -m 0644 systemd/media-extract-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now media-extract-backup.timer
systemctl list-timers media-extract-backup.timer
```

Check logs with `journalctl -u media-extract-backup.service`.
