-- 003: audit log (idempotent)
CREATE TABLE IF NOT EXISTS `kotzu_display_audit` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `uid` CHAR(36) NULL,
    `actor_citizenid` VARCHAR(64) NOT NULL,
    `action` VARCHAR(32) NOT NULL,
    `detail` LONGTEXT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_uid` (`uid`),
    KEY `idx_actor` (`actor_citizenid`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;
