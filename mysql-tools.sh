#!/bin/bash

# Copyright The KubeDB Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eou pipefail

# ref: https://stackoverflow.com/a/7069755/244009
# ref: https://jonalmeida.com/posts/2013/05/26/different-ways-to-implement-flags-in-bash/
# ref: http://tldp.org/LDP/abs/html/comparison-ops.html

show_help() {
  echo "mysql-tools.sh - run tools"
  echo " "
  echo "mysql-tools.sh COMMAND [options]"
  echo " "
  echo "options:"
  echo "-h, --help                         show brief help"
  echo "    --data-dir=DIR                 path to directory holding db data (default: /var/data)"
  echo "    --host=HOST                    database host"
  echo "    --user=USERNAME                database username"
  echo "    --database=DATABASE            name of database"
  echo "    --bucket=BUCKET                name of bucket"
  echo "    --folder=FOLDER                name of folder in bucket"
  echo "    --snapshot=SNAPSHOT            name of snapshot"
  echo "    --enable-analytics=ENABLE_ANALYTICS   send analytical events to Google Analytics (default true)"
}

RETVAL=0
DEBUG=${DEBUG:-}
DB_HOST=${DB_HOST:-}
DB_PORT=${DB_PORT:-3306}
DB_USER=${DB_USER:-}
DB_PASSWORD=${DB_PASSWORD:-}
DB_DATABASE=${DB_DATABASE:-}
DB_BUCKET=${DB_BUCKET:-}
DB_FOLDER=${DB_FOLDER:-}
DB_SNAPSHOT=${DB_SNAPSHOT:-}
DB_DATA_DIR=${DB_DATA_DIR:-/var/data}
OSM_CONFIG_FILE=/etc/osm/config
ENABLE_ANALYTICS=${ENABLE_ANALYTICS:-true}

op=$1
shift

while test $# -gt 0; do
  case "$1" in
    -h | --help)
      show_help
      exit 0
      ;;
    --data-dir*)
      if [ -z "$DB_DATA_DIR" ]; then
        export DB_DATA_DIR=$(echo $1 | sed -e 's/^[^=]*=//g')
      fi
      shift
      ;;
    --host*)
      if [ -z "$DB_HOST" ]; then
        export DB_HOST=$(echo $1 | sed -e 's/^[^=]*=//g')
      fi
      shift
      ;;
    --user*)
      if [ -z "$DB_USER" ]; then
        export DB_USER=$(echo $1 | sed -e 's/^[^=]*=//g')
      fi
      shift
      ;;
    --database*)
      if [ -z "$DB_DATABASE" ]; then
        export DB_DATABASE=$(echo $1 | sed -e 's/^[^=]*=//g')
      fi
      shift
      ;;
    --bucket*)
      if [ -z "$DB_BUCKET" ]; then
        export DB_BUCKET=$(echo $1 | sed -e 's/^[^=]*=//g')
      fi
      shift
      ;;
    --folder*)
      if [ -z "$DB_FOLDER" ]; then
        export DB_FOLDER=$(echo $1 | sed -e 's/^[^=]*=//g')
      fi
      shift
      ;;
    --snapshot*)
      if [ -z "$DB_SNAPSHOT" ]; then
        export DB_SNAPSHOT=$(echo $1 | sed -e 's/^[^=]*=//g')
      fi
      shift
      ;;
    --analytics* | --enable-analytics*)
      if [ -z "$ENABLE_ANALYTICS" ]; then
        export ENABLE_ANALYTICS=$(echo $1 | sed -e 's/^[^=]*=//g')
      fi
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      show_help
      exit 1
      ;;
  esac
done

if [ -n "$DEBUG" ]; then
  env | sort | grep DB_*
  echo ""
fi

# Wait for mysql to start
# ref: http://unix.stackexchange.com/a/5279
while ! nc -zv $DB_HOST $DB_PORT </dev/null; do
  echo "Waiting... database is not ready yet"
  sleep 5
done

# cleanup data dump dir
mkdir -p "$DB_DATA_DIR"
cd "$DB_DATA_DIR"
rm -rf *

case "$op" in
  backup)
    echo "Dumping database......"
    mysqldump -u ${DB_USER} --password=${DB_PASSWORD} -h ${DB_HOST} --set-gtid-purged=off --databases ${DB_DATABASE} > dumpfile.sql

    echo "Uploading dump file to the backend......."
    osm push --enable-analytics="$ENABLE_ANALYTICS" --osmconfig="$OSM_CONFIG_FILE" -c "$DB_BUCKET" "$DB_DATA_DIR" "$DB_FOLDER/$DB_SNAPSHOT"

    echo "Backup successful"
    ;;
  restore)
    echo "Pulling backup file from the backend"
    osm pull --enable-analytics="$ENABLE_ANALYTICS" --osmconfig="$OSM_CONFIG_FILE" -c "$DB_BUCKET" "$DB_FOLDER/$DB_SNAPSHOT" "$DB_DATA_DIR"

    echo "Inserting data into database........"
    mysql -u "$DB_USER" --password=${DB_PASSWORD} -h "$DB_HOST" "$@" -f <dumpfile.sql

    echo "Recovery successful"
    ;;
  *)
    (10)
    echo $"Unknown op!"
    RETVAL=1
    ;;
esac
exit "$RETVAL"
