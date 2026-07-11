#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
  SELECT 'CREATE DATABASE evolution_api_dev'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'evolution_api_dev')\gexec
EOSQL
