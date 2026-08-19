-- 002: idempotency / transaction locks for weapon place & retrieve (idempotent)
CREATE TABLE IF NOT EXISTS `kotzu_tx_locks` (
    `idempotency_key` CHAR(64) NOT NULL,
    `uid` CHAR(36) NULL,
    `action` VARCHAR(16) NOT NULL,
    `state` VARCHAR(24) NOT NULL,
    `actor_citizenid` VARCHAR(64) NOT NULL,
    `item_name` VARCHAR(64) NULL,
    `item_metadata` LONGTEXT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`idempotency_key`),
    KEY `idx_state` (`state`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;
