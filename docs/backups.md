# Backups

Extrudle's data is one SQLite database, `storage/production.sqlite3`, on the
server's `extrudle_storage` volume. On the real deploy, [Litestream](https://litestream.io)
streams every change to a Cloudflare R2 bucket within seconds. Any moment in
the last 30 days can be restored.

The queue, cache and cable databases aren't backed up: they rebuild themselves.

## How it runs

- The Docker image includes Litestream 0.3.13 (`Dockerfile`).
- `bin/docker-entrypoint` runs only when `LITESTREAM_BUCKET` is set, which is the real deploy (`config/deploy.yml`). It:
  1. restores the database from R2 if there isn't one yet (a new server, or a lost volume)
  2. runs `db:prepare`
  3. runs the app under `litestream replicate`, which streams every change and passes stop signals on to the app
- The settings are in `config/litestream.yml`: the bucket path `extrudle/production.sqlite3`, a daily snapshot, and 30 days kept (`retention: 720h`).
- Every night at 4am, `BackupRestoreCheckJob` restores the latest backup to a temporary file and checks it:
  - SQLite's integrity check
  - row counts for the main tables, compared with the live ones

  The result shows under **Users › Backups**, and **Check now** runs it on demand.

## Setting it up (once)

1. In Cloudflare, go to **R2** and create a bucket called `extrudle-backups`. Keep it private.
2. Under **R2 › Manage API tokens**, create a token with **Object Read & Write** on that bucket only. Note the access key ID and secret.
3. Note the account's S3 endpoint: `https://<account id>.r2.cloudflarestorage.com`.
4. Put these in the shell you deploy from, or in your password manager:
   ```sh
   export LITESTREAM_ACCESS_KEY_ID=...
   export LITESTREAM_SECRET_ACCESS_KEY=...
   export LITESTREAM_ENDPOINT=https://<account id>.r2.cloudflarestorage.com
   # export LITESTREAM_BUCKET=extrudle-backups   # the default
   ```
5. Deploy with `DEPLOY_HOST` set, so it's the real deploy rather than the preview (see `config/deploy.yml`).
6. Check **Users › Backups** after a few minutes and press **Check now**.

## Restoring

### The whole server is lost

Set up a new server and deploy as usual. On first start the entrypoint finds no database, restores the latest backup from R2, and carries on from there. Nothing else is needed.

### Go back to an earlier moment (e.g. a bad import)

1. Stop the app: `bin/kamal app stop`
2. Restore to a new file, at the time you want (UTC):
   ```sh
   bin/kamal app exec --reuse "litestream restore -config /rails/config/litestream.yml \
     -timestamp 2026-12-01T09:30:00Z -o /rails/storage/restored.sqlite3 /rails/storage/production.sqlite3"
   ```
3. Check it: `bin/kamal app exec --reuse "sqlite3 /rails/storage/restored.sqlite3 'PRAGMA integrity_check;'"` should print `ok`.
4. Keep the current database, then swap the restored one in:
   ```sh
   bin/kamal app exec --reuse "sh -c 'cd /rails/storage && mv production.sqlite3 production-before-restore.sqlite3 && rm -f production.sqlite3-wal production.sqlite3-shm && mv restored.sqlite3 production.sqlite3'"
   ```
5. Start the app: `bin/kamal app boot`. Litestream starts a new backup generation from the restored database.

To see which backups (generations) exist: `bin/kamal app exec --reuse "litestream generations -config /rails/config/litestream.yml /rails/storage/production.sqlite3"`.

## Practising a restore

`bin/backup-drill` does the whole thing locally with Docker, using the same Litestream version:

1. copies a database
2. backs it up to a folder (standing in for R2)
3. restores it
4. checks the integrity and that every table's row count matches

```sh
bin/backup-drill                          # the development database
bin/backup-drill path/to/a/copy.sqlite3   # e.g. a copy taken from the server
```

Run it after changing anything in this file, `config/litestream.yml` or the entrypoint.
