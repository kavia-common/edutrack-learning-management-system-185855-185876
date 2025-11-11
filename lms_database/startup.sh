#!/bin/bash
set -euo pipefail

DB_NAME="myapp"
DB_USER="appuser"
DB_PASSWORD="dbuser123"
DB_PORT="5000"
VIS_HOST="0.0.0.0"
VIS_PORT="3020"

# Resolve script directory to handle relative paths correctly,
# even when invoked via sudo from other directories.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "Starting MySQL setup..."

# Helper: wait for a TCP port to be open
wait_for_tcp() {
  local host="$1"
  local port="$2"
  local retries="${3:-60}"
  local delay="${4:-2}"
  for i in $(seq 1 "$retries"); do
    if (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
      echo "✓ TCP ${host}:${port} is open"
      return 0
    fi
    echo "Waiting for ${host}:${port} to be ready... ($i/${retries})"
    sleep "$delay"
  done
  echo "✗ Timeout waiting for ${host}:${port}"
  return 1
}

# Helper: run a SQL file using available connection methods
run_sql_file() {
  local sql_file="$1"
  if [ ! -f "$sql_file" ]; then
    echo "SQL file not found: $sql_file"
    return 1
  fi

  # Prefer db_connection.txt if present
  if [ -f "${SCRIPT_DIR}/db_connection.txt" ]; then
    echo "Applying $sql_file using db_connection.txt..."
    $(cat "${SCRIPT_DIR}/db_connection.txt") < "$sql_file"
    return $?
  fi

  # Try socket as root
  if sudo mysqladmin ping --socket=/var/run/mysqld/mysqld.sock --silent 2>/dev/null; then
    echo "Applying $sql_file via MySQL socket as root..."
    sudo mysql --socket=/var/run/mysqld/mysqld.sock < "$sql_file"
    return $?
  fi

  # Try TCP as appuser
  echo "Applying $sql_file via TCP on port ${DB_PORT}..."
  mysql -u "${DB_USER}" -p"${DB_PASSWORD}" -h 127.0.0.1 -P "${DB_PORT}" "${DB_NAME}" < "$sql_file"
}

# Helper: apply migrations in order
apply_migrations() {
  echo "Applying migrations..."

  # Ensure migrations tracking table exists (avoid /dev/fd process substitution)
  if [ -f "${SCRIPT_DIR}/db_connection.txt" ]; then
    echo "Ensuring migrations table exists (via db_connection.txt)..."
    $(cat "${SCRIPT_DIR}/db_connection.txt") <<'EOSQL'
CREATE DATABASE IF NOT EXISTS myapp;
USE myapp;
CREATE TABLE IF NOT EXISTS _migrations (
  id INT NOT NULL AUTO_INCREMENT,
  filename VARCHAR(255) NOT NULL UNIQUE,
  applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
EOSQL
  else
    if sudo mysqladmin ping --socket=/var/run/mysqld/mysqld.sock --silent 2>/dev/null; then
      echo "Ensuring migrations table exists (via socket root)..."
      sudo mysql --socket=/var/run/mysqld/mysqld.sock <<'EOSQL'
CREATE DATABASE IF NOT EXISTS myapp;
USE myapp;
CREATE TABLE IF NOT EXISTS _migrations (
  id INT NOT NULL AUTO_INCREMENT,
  filename VARCHAR(255) NOT NULL UNIQUE,
  applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
EOSQL
    else
      echo "Ensuring migrations table exists (via TCP appuser)..."
      mysql -u "${DB_USER}" -p"${DB_PASSWORD}" -h 127.0.0.1 -P "${DB_PORT}" <<'EOSQL'
CREATE DATABASE IF NOT EXISTS myapp;
USE myapp;
CREATE TABLE IF NOT EXISTS _migrations (
  id INT NOT NULL AUTO_INCREMENT,
  filename VARCHAR(255) NOT NULL UNIQUE,
  applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
EOSQL
    fi
  fi

  local MIGRATIONS_DIR="${SCRIPT_DIR}/migrations"
  mkdir -p "$MIGRATIONS_DIR"

  # Iterate through sorted .sql files
  for f in $(ls "$MIGRATIONS_DIR"/*.sql 2>/dev/null | sort); do
    local base
    base="$(basename "$f")"
    # Check if already applied
    local chk
    chk=$(mysql -u "${DB_USER}" -p"${DB_PASSWORD}" -h 127.0.0.1 -P "${DB_PORT}" -N -e "SELECT COUNT(*) FROM ${DB_NAME}._migrations WHERE filename='${base}'" 2>/dev/null || echo "0")
    if [ "$chk" = "1" ]; then
      echo "Skipping already applied migration: $base"
      continue
    fi

    echo "Running migration: $base"
    if run_sql_file "$f"; then
      mysql -u "${DB_USER}" -p"${DB_PASSWORD}" -h 127.0.0.1 -P "${DB_PORT}" -e "INSERT INTO ${DB_NAME}._migrations (filename) VALUES ('${base}')" >/dev/null 2>&1 || true
      echo "Applied migration: $base"
    else
      echo "Failed to apply migration: $base"
      return 1
    fi
  done
}

# Helper: seed data if not already seeded
apply_seed() {
  echo "Applying seed data..."
  # Simple check: is there at least the admin user?
  local exists
  exists=$(mysql -u "${DB_USER}" -p"${DB_PASSWORD}" -h 127.0.0.1 -P "${DB_PORT}" -N -e "SELECT COUNT(*) FROM ${DB_NAME}.users WHERE email='admin@example.com'" 2>/dev/null || echo "0")
  if [ "$exists" != "0" ] && [ "$exists" -gt 0 ] 2>/dev/null; then
    echo "Seed appears to be already applied (admin exists). Skipping."
    return 0
  fi
  run_sql_file "${SCRIPT_DIR}/seed.sql"
}

# Check if MySQL is already running on the specified port
if sudo mysqladmin ping --socket=/var/run/mysqld/mysqld.sock --silent 2>/dev/null; then
    echo "MySQL is already running!"
    
    # Try to verify the database exists
    if sudo mysql --socket=/var/run/mysqld/mysqld.sock -e "USE ${DB_NAME};" 2>/dev/null; then
        echo "Database ${DB_NAME} is accessible."
    fi
    
    echo ""
    echo "Database: ${DB_NAME}"
    echo "Root user: root (password: ${DB_PASSWORD})"
    echo "App user: appuser (password: ${DB_PASSWORD})"
    echo "Port: ${DB_PORT}"
    echo ""
    
    # Check if connection info file exists
    if [ -f "${SCRIPT_DIR}/db_connection.txt" ]; then
        echo "To connect to the database, use:"
        echo "$(cat "${SCRIPT_DIR}/db_connection.txt")"
    else
        echo "To connect to the database, use:"
        echo "mysql -u root -p${DB_PASSWORD} -h localhost -P ${DB_PORT} ${DB_NAME}"
    fi

    # Apply migrations and seed on already-running server
    apply_migrations || { echo "Migration failed"; exit 1; }
    apply_seed || true

    # Ensure visualizer env is present
    mkdir -p "${SCRIPT_DIR}/db_visualizer"
    cat > "${SCRIPT_DIR}/db_visualizer/mysql.env" << EOF
export MYSQL_URL="mysql://localhost:${DB_PORT}/${DB_NAME}"
export MYSQL_USER="${DB_USER}"
export MYSQL_PASSWORD="${DB_PASSWORD}"
export MYSQL_DB="${DB_NAME}"
export MYSQL_PORT="${DB_PORT}"
EOF

    echo ""
    echo "Continuing to launch DB visualizer..."
else
  # Check if there's a MySQL process running on the specified port
  if pgrep -f "mysqld.*--port=${DB_PORT}" > /dev/null 2>&1; then
      echo "Found existing MySQL process on port ${DB_PORT}"
      echo "Attempting to verify connection..."
      
      # Try to connect via TCP
      if mysql -u root -p${DB_PASSWORD} -h 127.0.0.1 -P ${DB_PORT} -e "SELECT 1;" 2>/dev/null; then
          echo "MySQL is accessible on port ${DB_PORT}."
          apply_migrations || { echo "Migration failed"; exit 1; }
          apply_seed || true
      fi
  fi

  # Check if MySQL is running on default socket but different port
  if [ -S /var/run/mysqld/mysqld.sock ]; then
      echo "Found MySQL socket, checking if it's using port ${DB_PORT}..."
      CURRENT_PORT=$(sudo mysql --socket=/var/run/mysqld/mysqld.sock -e "SHOW VARIABLES LIKE 'port';" 2>/dev/null | grep port | awk '{print $2}')
      if [ "$CURRENT_PORT" = "${DB_PORT}" ]; then
          echo "MySQL is already running on port ${DB_PORT}!"
          apply_migrations || { echo "Migration failed"; exit 1; }
          apply_seed || true
      else
          echo "MySQL is running on different port ($CURRENT_PORT), stopping it first..."
          sudo mysqladmin shutdown --socket=/var/run/mysqld/mysqld.sock
          sleep 5
      fi
  fi

  # Initialize MySQL data directory if it doesn't exist
  if [ ! -d "/var/lib/mysql/mysql" ]; then
      echo "Initializing MySQL..."
      sudo mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql
  fi

  # Start MySQL server in background using sudo
  echo "Starting MySQL server..."
  sudo mysqld --user=mysql --datadir=/var/lib/mysql --socket=/var/run/mysqld/mysqld.sock --pid-file=/var/run/mysqld/mysqld.pid --port=${DB_PORT} &

  # Wait for MySQL to be ready
  echo "Waiting for MySQL to start..."
  sleep 2

  # Check if MySQL is running using socket
  for i in {1..30}; do
      if sudo mysqladmin ping --socket=/var/run/mysqld/mysqld.sock --silent 2>/dev/null; then
          echo "MySQL is ready!"
          break
      fi
      echo "Waiting... ($i/30)"
      sleep 2
  done

  # Configure database and user - Fix MySQL 8.0 authentication
  echo "Setting up database and fixing authentication..."
  sudo mysql --socket=/var/run/mysqld/mysqld.sock << EOF
-- Fix root user authentication for MySQL 8.0
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_PASSWORD}';

-- Create database
CREATE DATABASE IF NOT EXISTS ${DB_NAME};

-- Create a new user for remote connections
CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO 'appuser'@'%';

-- Grant privileges to root
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO 'root'@'localhost';

FLUSH PRIVILEGES;
EOF

  # Save connection command to a file
  echo "mysql -u ${DB_USER} -p${DB_PASSWORD} -h localhost -P ${DB_PORT} ${DB_NAME}" > "${SCRIPT_DIR}/db_connection.txt"
  echo "Connection command saved to db_connection.txt"

  # Save environment variables to a file
  mkdir -p "${SCRIPT_DIR}/db_visualizer"
  cat > "${SCRIPT_DIR}/db_visualizer/mysql.env" << EOF
export MYSQL_URL="mysql://localhost:${DB_PORT}/${DB_NAME}"
export MYSQL_USER="${DB_USER}"
export MYSQL_PASSWORD="${DB_PASSWORD}"
export MYSQL_DB="${DB_NAME}"
export MYSQL_PORT="${DB_PORT}"
EOF

  echo "Applying migrations and seed..."
  apply_migrations || { echo "Migration failed"; exit 1; }
  apply_seed || true

  echo "MySQL setup complete!"
  echo "Database: ${DB_NAME}"
  echo "Root user: root (password: ${DB_PASSWORD})"
  echo "App user: appuser (password: ${DB_PASSWORD})"
  echo "Port: ${DB_PORT}"
  echo ""
fi

# At this point MySQL is up and migrations/seed are applied. Ensure MySQL TCP 5000 is reachable.
wait_for_tcp "127.0.0.1" "${DB_PORT}" 60 2 || true

echo "Environment variables saved to db_visualizer/mysql.env"
echo "Launching DB visualizer on ${VIS_HOST}:${VIS_PORT} ..."

# Start the db visualizer
pushd "${SCRIPT_DIR}/db_visualizer" >/dev/null

# Source env for mysql connection variables
# shellcheck disable=SC1091
source "./mysql.env"

# Use npm start as defined in package.json; ensure HOST/PORT are passed and do not try to open browser
export HOST="${VIS_HOST}"
export PORT="${VIS_PORT}"
export BROWSER="none"

# Start the visualizer in foreground so the container keeps running
# If npm is not installed or fails, print error and exit non-zero
if command -v npm >/dev/null 2>&1; then
  echo "Starting visualizer with: PORT=${PORT} HOST=${HOST} BROWSER=${BROWSER} npm start"
  # Start npm; add small delay and readiness wait loop
  ( npm start & VIS_PID=$!
    # Wait for port 3020 to be ready before exiting subshell
    wait_for_tcp "127.0.0.1" "${PORT}" 60 2 || {
      echo "Warning: Visualizer did not open port ${PORT} in time."
    }
    # Keep the process in foreground by waiting on child
    wait ${VIS_PID}
  )
else
  echo "Error: npm is not installed in this environment. Cannot start db visualizer." >&2
  exit 1
fi

popd >/dev/null
