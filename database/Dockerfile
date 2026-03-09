FROM mysql:8.0

# Copy SQL initialization script into the entrypoint directory.
# MySQL automatically runs all .sql files here on first startup.
COPY init.sql /docker-entrypoint-initdb.d/init.sql
