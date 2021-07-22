#!/bin/bash

# Copyright (C) July 2021 Mark Tompsett
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see http://www.gnu.org/licenses/.

# This bash file is designed to use mdb-tools to extract a database from
# MS-Access and get it into an MySQL format. It uses some perl scripts
# which are also under GPL v3.

echoerr() { echo "$@" 1>&2; }

fix_files_exist_check() {
    files=$(find fix_*.sql 2> /dev/null | wc -l)
    if [[ "$files" != "0" ]]; then
        return 1; # Exists
    else
        return 0;
    fi
}

gz_files_exist_check() {
    files=$(find *.gz 2> /dev/null | wc -l)
    if [[ "$files" != "0" ]]; then
        return 1; # Exists
    else
        return 0;
    fi
}

if [[ "$1" == "" ]]; then
    echo Missing required Access DB file name.
    exit 1
fi
if [[ "$2" == "" ]]; then
    echo Missing required MySQL DB name.
    exit 1
fi

SOURCE_DB=$1
OUTPUT1_SQL=create_DB.sql
OUTPUT2_SQL=create_tables.sql
OUTPUT_DB=$2

if [[ ! -f ${SOURCE_DB} ]]; then
    echo Missing required database: "${SOURCE_DB}"
    exit 1;
fi

# Clean up, so overwriting is simpler.
touch ${OUTPUT1_SQL}
rm ${OUTPUT1_SQL}
touch ${OUTPUT2_SQL}
rm ${OUTPUT2_SQL}
touch SQL-files.tar
rm SQL-files.tar
touch split_placeholder.sql
touch split_placeholder.sql.gz
rm split_*.sql split_*.sql.gz

echo "Installing default libraries..."
apt-get update -q 2>&1 > /dev/null
RESULT=$?
if [[ "${RESULT}" == "0" ]]; then
    apt-get install -q -y sudo 2>&1 > /dev/null
    echo Succeeded installing sudo.
    MYSQL_OPTIONS="-u ${MYSQL_USER} -p${MYSQL_PASSWORD}"
    MYSQL_ROOT_OPTIONS="-u root -p${MYSQL_ROOT_PASSWORD}"
else
    echo Failed installing sudo.
    echo Assuming you are running locally.
    MYSQL_OPTIONS=""
    MYSQL_ROOT_OPTIONS=""
fi
echo Installing Modern::Perl perl library...
sudo apt-get install -q -y libmodern-perl-perl 2>&1 > /dev/null
echo Installing File::Slurp perl library...
sudo apt-get install -q -y libfile-slurp-perl 2>&1 > /dev/null
echo Installing Text::Trim perl library...
sudo apt-get install -q -y libtext-trim-perl 2>&1 > /dev/null
echo Installing Data::Dumper perl library...
sudo apt-get install -q -y libdata-dump-perl 2>&1 > /dev/null
echo Installing mdb tools...
sudo apt-get install -q -y mdbtools 2>&1 > /dev/null

echo "Creating the database..."
echo "DROP DATABASE IF EXISTS \`${OUTPUT_DB}\`;" > "${OUTPUT1_SQL}"
echo "CREATE DATABASE \`${OUTPUT_DB}\`;" >> "${OUTPUT1_SQL}"
if [[ "${RESULT}" == "0" ]]; then
    {
    echo "CREATE USER IF NOT EXISTS user IDENTIFIED BY '${MYSQL_PASSWORD}';";
    echo "GRANT ALL PRIVILEGES ON \`${OUTPUT_DB}\`.* TO 'user'@'%';";
    echo "FLUSH PRIVILEGES;"
    } >> ${OUTPUT1_SQL}
fi
echo >> "${OUTPUT1_SQL}"
sudo chown 1000.1000 "${OUTPUT1_SQL}"

echo "USE ${OUTPUT_DB};" > "${OUTPUT2_SQL}"
echo >> "${OUTPUT2_SQL}"
sudo chown 1000.1000 "${OUTPUT2_SQL}"

echo "Creating the tables..."
mdb-schema "${SOURCE_DB}"  > "SCHEMA_${OUTPUT_DB}.sql"

echo "Removing tabs..."
tr "\t" " " < "SCHEMA_${OUTPUT_DB}.sql" > "SCHEMA_${OUTPUT_DB}.tmp"
mv "SCHEMA_${OUTPUT_DB}.tmp" "SCHEMA_${OUTPUT_DB}.sql"

echo "Attempting to read remapping file..."
FIELD_NAMES=()
FIELD_TYPES=()
FIELD_NEW_TYPES=()
if [[ -f field_type.remap ]]; then
    OLD_IFS=$IFS
    while IFS=':' read -r -a array; do
        FIELD_NAMES+=("${array[0]}")
        FIELD_TYPES+=("${array[1]}")
        FIELD_NEW_TYPES+=("${array[2]}")
    done < <(grep -v "^#" field_type.remap)
    IFS=$OLD_IFS
    FIELD_COUNT=$(grep -v "^#" field_type.remap | wc -l)
else
    FIELD_COUNT=0
fi

if [[ ${FIELD_COUNT} -gt 0 ]]; then
    echo "Read ${FIELD_COUNT} fields to remap."
else
    echo "There are no field requiring remapping."
fi

echo "Converting the data types and schema format to MySQL..."
while read -r LINE; do
    # Turn the spaced table names into _'d versions
    LINE=$(echo "${LINE}" | sed -r -e "s#(\[)(.*?) (.*)(\])#\1\2_\3\4#g")

    # Fix the [] quoting. -- // is a global replace, / would be single.
    LINE=${LINE//\[/\`}
    LINE=${LINE//\]/\`}

    # Some particular fields were the wrong data type in Access
    if [[ ${FIELD_COUNT} -gt 0 ]]; then
        for COUNT in $( seq 1 "${FIELD_COUNT}" ); do
            if [[ "${LINE}" == *"${FIELD_NAMES[${COUNT}-1]}"* ]]; then
                OLD_TYPE="${FIELD_TYPES[${COUNT}-1]}"
                NEW_TYPE="${FIELD_NEW_TYPES[${COUNT}-1]}"
                echoerr Changing "${FIELD_NAMES[${COUNT}-1]}" from "${OLD_TYPE}" to "${NEW_TYPE}"
                LINE=${LINE//"${OLD_TYPE}"/"${NEW_TYPE}"}
            fi
        done
    fi

    # Fix the "Long Integer" to INT, and other data types
    LINE=${LINE// Long Integer/ INT}
    LINE=${LINE// Single/ FLOAT}
    LINE=${LINE// Currency/ DOUBLE}
    LINE=${LINE// Boolean/ TINYINT(1)}
    LINE=${LINE// Text/ VARCHAR}
    LINE=${LINE// DateTime/ DateTime}
    LINE=${LINE// Date/ Date}
    echo "${LINE}"
done < <(cat "SCHEMA_${OUTPUT_DB}.sql") >> "${OUTPUT2_SQL}"
rm "SCHEMA_${OUTPUT_DB}.sql"

echo "Generate SQL to fill the tables..."
while read -r TABLE; do
    mdb-export -I mysql "${SOURCE_DB}" "${TABLE}";
done < <(mdb-tables -1 "${SOURCE_DB}")  > "DATA_${OUTPUT_DB}.sql"

echo "Fix the fields ending in \\"
sed -e "s#\\\\\"#\"#g" < "DATA_${OUTPUT_DB}.sql" > "DATA2_${OUTPUT_DB}.sql"
rm "DATA_${OUTPUT_DB}.sql"
mv "DATA2_${OUTPUT_DB}.sql" "DATA_${OUTPUT_DB}.sql"

echo "Fix the fields ending in \`"
sed -e "s#\`\"#\"#g" < "DATA_${OUTPUT_DB}.sql" > "DATA2_${OUTPUT_DB}.sql"
rm "DATA_${OUTPUT_DB}.sql"
mv "DATA2_${OUTPUT_DB}.sql" "DATA_${OUTPUT_DB}.sql"

# Some table names may have spaces.
echo "Fix the spaced table names in the data..."
grep -i "^insert into" "DATA_${OUTPUT_DB}.sql" | cut -f2 -d"\`" | grep " " | sort -u > SPACED_TABLES
while read -r BAD_TABLE; do
    GOOD_TABLE=${BAD_TABLE// /_}
    echo "-- ${BAD_TABLE} -> ${GOOD_TABLE}"
    sed -e "s#${BAD_TABLE}#${GOOD_TABLE}#g" < "DATA_${OUTPUT_DB}.sql" > "DATA2_${OUTPUT_DB}.sql"
    mv "DATA2_${OUTPUT_DB}.sql" "DATA_${OUTPUT_DB}.sql"
done < <(cat SPACED_TABLES)
rm SPACED_TABLES

echo "Fix the dates from mm/dd/yy to yyyy-mm-dd..."
./fix_dates_sql.pl "DATA_${OUTPUT_DB}.sql" "${OUTPUT_DB}"

echo "Split the data..."
./split_the_SQL_data.pl "DATA_${OUTPUT_DB}.sql" "${OUTPUT_DB}"
rm "DATA_${OUTPUT_DB}.sql"

# Make sure everything is 1000.1000
sudo chown 1000.1000 ./*

# PHPMyAdmin only accepts 2MB files. Zipping to meet size requirements.
echo "Zipping up Large SQL files..."
LARGE_FILES=$(find . -size +1500k -name "*.sql" -exec ls {} \+)
for FILE_NAME in ${LARGE_FILES}; do
    echo "Zipping ${FILE_NAME}... "
    gzip -f "${FILE_NAME}"
done

gz_files_exist_check
GZ_FILES_EXIST=$?
if [[ $GZ_FILES_EXIST -eq 1 ]]; then
    sudo chown 1000.1000 ./*.gz
fi

# A single tar file is easier to transfer to others.
echo "Generating TAR file to send..."
fix_files_exist_check
FIX_FILES_EXIST=$?
tar -cf SQL-files.tar "${OUTPUT1_SQL}" "${OUTPUT2_SQL}" split_*.sql
if [[ $FIX_FILES_EXIST -eq 1 ]]; then
    tar -rf SQL-files.tar fix_*.sql
fi
if [[ $GZ_FILES_EXIST -eq 1 ]]; then
    tar -rf SQL-files.tar split_*.gz
fi
sudo chown 1000.1000 SQL-files.tar

ANSWER="ASK"
while [[ "${ANSWER}" != "Y" && "${ANSWER}" != "y" &&
         "${ANSWER}" != "N" && "${ANSWER}" != "n" ]]; do
    read -r -p "Imported the data into a local MySQL database? (YyNn) " ANSWER
done
if [[ "${ANSWER}" == "N" || "${ANSWER}" == "n" ]]; then
    # Don't need generating SQL files hanging around
    rm -f "$OUTPUT1_SQL" "$OUTPUT2_SQL" split_*.sql split_*.gz
    exit 0;
fi

echo "Now actually import everything into MySQL (many, many minutes!)..."
# pv is useful for seeing progress, since this is a long process
sudo apt-get install -q -y pv 2>&1 > /dev/null

echo Creating an empty DB called "${OUTPUT_DB}"...
pv "$OUTPUT1_SQL" | sudo mysql $MYSQL_ROOT_OPTIONS

echo Creating an empty tables in "${OUTPUT_DB}"...
pv "$OUTPUT2_SQL" | sudo mysql $MYSQL_OPTIONS

for SQL_DATA_FILE in split_*.sql; do
    echo "${SQL_DATA_FILE}" data is being imported...
    pv "${SQL_DATA_FILE}" | sudo mysql $MYSQL_OPTIONS
done

if [[ $GZ_FILES_EXISTS -eq 1 ]]; then
    for SQL_DATA_FILE in split_*.sql.gz; do
        echo "${SQL_DATA_FILE}" data is being imported...
        zcat "${SQL_DATA_FILE}" | pv | sudo mysql $MYSQL_OPTIONS
    done
fi

echo "Running MySQL Cleaning up scripts..."
if [[ $FIX_FILES_EXIST -eq 1 ]]; then
    for SQL_SCRIPT in fix_*sql; do
        DATABASE_NAME=$(grep "USE .*;" "${SQL_SCRIPT}" | cut -f2 -d" " | cut -f1 -d";")
        if [[ "${DATABASE_NAME}" == "${OUTPUT_DB}" ]]; then
            echo Running "${SQL_SCRIPT}"
            pv "${SQL_SCRIPT}" | sudo mysql $MYSQL_OPTIONS
        else
            echo Uses "${DATABASE_NAME}", but generated "${OUTPUT_DB}". Skipping "${SQL_SCRIPT}"...
        fi
    done
fi

# Don't need generating SQL files hanging around, because tar file exists.
rm -f "${OUTPUT1_SQL}" "${OUTPUT2_SQL}" split_*.sql split_*.gz 2>&1 > /dev/null
