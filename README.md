*This project has been created as part of the 42 curriculum by tsargsya.*

# Inception

## Description

Inception broadens system administration skills through Docker. The project builds a small multi-service infrastructure with Docker Compose, custom images, an isolated network, persistent named volumes, and secrets stored outside the Git repository.

## MariaDB initialization recovery

MariaDB has two separate initialization states:

1. `/var/lib/mysql/mysql` indicates that MariaDB's system tables exist.
2. `/var/lib/mysql/.inception_initialized` indicates that the project-specific SQL initialization completed successfully.

The two checks are intentionally independent. A container can stop after `mariadb-install-db` creates the system tables but before the WordPress database, application user, privileges, and root password are fully configured. Checking only for the `mysql` directory would incorrectly treat that partially initialized volume as complete.

When the system tables are missing, the entrypoint creates them with `mariadb-install-db`. When the `.inception_initialized` marker is missing, it starts a temporary local MariaDB server and executes the idempotent SQL initialization again. The marker is created only after the SQL command completes and the temporary server shuts down successfully.

This design makes a failed cold start recoverable without deleting the persistent volume or rebuilding the image.
