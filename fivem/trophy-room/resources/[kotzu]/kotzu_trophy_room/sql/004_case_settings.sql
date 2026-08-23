-- 004: display case style + per-display settings (auto-rotate etc.) (idempotent)
ALTER TABLE `kotzu_displays`
    ADD COLUMN IF NOT EXISTS `case_style` VARCHAR(16) NULL AFTER `platform`,
    ADD COLUMN IF NOT EXISTS `settings` LONGTEXT NULL AFTER `permissions`;
