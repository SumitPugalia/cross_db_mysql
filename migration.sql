
CREATE DATABASE IF NOT EXISTS xdb_mysql_test;
USE xdb_mysql_test;

## People Table
DROP TABLE IF EXISTS people;
CREATE TABLE IF NOT EXISTS `people` (
 `id`           INT UNSIGNED NOT NULL,
 `first_name`   VARCHAR(12),
 `last_name`    VARCHAR(30),
 `age`          INT UNSIGNED,
 `address`      VARCHAR(100),
 `birthdate`    DATE,
 `created_at`   DATETIME,
 `height`       FLOAT,
 `description`   VARCHAR(100),
 `profile_image` BLOB,
 `is_blocked`    TINYINT,
 `status`        VARCHAR(40),
 `weird_field1`  VARCHAR(100),
 `weird_field2`  VARCHAR(100),
 `weird_field3`  VARCHAR(100),
  PRIMARY KEY(`ID`)
);

## People Table
DROP TABLE IF EXISTS autoincrement;
CREATE TABLE IF NOT EXISTS `autoincrement` (
 `id`  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  PRIMARY KEY(`ID`)
);
