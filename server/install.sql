-- Replace mac_ with the existing CMS table prefix. No CMS tables are changed.
CREATE TABLE IF NOT EXISTS mac_xb_sessions (
  token_hash CHAR(64) NOT NULL PRIMARY KEY,
  user_id INT UNSIGNED NOT NULL,
  password_stamp CHAR(64) NOT NULL,
  expires_at BIGINT NOT NULL,
  INDEX(user_id), INDEX(expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS mac_xb_rate (
  bucket CHAR(64) NOT NULL PRIMARY KEY,
  hits INT UNSIGNED NOT NULL DEFAULT 0,
  expires_at BIGINT NOT NULL,
  INDEX(expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS mac_xb_progress (
  user_id INT UNSIGNED NOT NULL,
  vod_id INT UNSIGNED NOT NULL,
  episode INT UNSIGNED NOT NULL,
  line_name VARCHAR(100) NOT NULL DEFAULT '',
  position_ms BIGINT UNSIGNED NOT NULL DEFAULT 0,
  updated_at BIGINT NOT NULL,
  PRIMARY KEY(user_id, vod_id), INDEX(user_id, updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS mac_xb_danmaku (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id INT UNSIGNED NOT NULL,
  vod_id INT UNSIGNED NOT NULL,
  episode INT UNSIGNED NOT NULL,
  position_ms BIGINT UNSIGNED NOT NULL,
  content VARCHAR(240) NOT NULL,
  status TINYINT UNSIGNED NOT NULL DEFAULT 0,
  created_at BIGINT NOT NULL,
  INDEX(vod_id,episode,status,position_ms), INDEX(user_id,created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
