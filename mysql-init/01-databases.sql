-- Create both databases for development setup
CREATE DATABASE IF NOT EXISTS `kp_scrapping` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `kp_penelitian_dosen` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Grant permissions to academic_user for both databases
GRANT ALL PRIVILEGES ON `kp_scrapping`.* TO 'academic_user'@'%';
GRANT ALL PRIVILEGES ON `kp_penelitian_dosen`.* TO 'academic_user'@'%';
FLUSH PRIVILEGES;