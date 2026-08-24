-- 005: DB-level uniqueness for the item instance on a LIVE display (idempotent).
--
-- The in-memory guard (Repo.SerialInUse) is authoritative per server process.
-- This index makes the invariant hold at the database level too, which matters
-- for multi-server clusters sharing one DB and for any restart race.
--
-- `item_serial` is populated ONLY for live weapon displays and set to NULL on
-- soft-delete; MySQL/MariaDB allow unlimited NULLs in a UNIQUE index, so a
-- retrieved weapon's serial becomes free to place again.
ALTER TABLE `kotzu_displays`
    ADD COLUMN IF NOT EXISTS `item_serial` VARCHAR(64) NULL AFTER `item_metadata`;

-- backfill live weapon rows from their stored metadata (best effort; rows whose
-- JSON has no serial simply stay NULL)
UPDATE `kotzu_displays`
SET `item_serial` = JSON_UNQUOTE(JSON_EXTRACT(`item_metadata`, '$.serial'))
WHERE `deleted_at` IS NULL
  AND `display_type` LIKE 'weapon\_%'
  AND `item_metadata` IS NOT NULL
  AND `item_serial` IS NULL
  AND JSON_VALID(`item_metadata`)
  AND JSON_EXTRACT(`item_metadata`, '$.serial') IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS `uq_item_serial` ON `kotzu_displays` (`item_serial`);
