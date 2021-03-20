#!/bin/bash

root_path=$(pwd);
exist_config_file=$(ls $root_path/config.cnf 2> /dev/null |wc -l);


if [ "$exist_config_file" != "1" ]
then
  echo "config file not fount \"config.cnf\"";
  exit 2
fi

export MYSQL_PWD=$(awk '/^password/ {print $3; exit}' config.cnf)
proxy_user=$(awk '/^user/ {print $3; exit}' config.cnf)
proxy_port=$(awk '/^port/ {print $3; exit}' config.cnf)
proxy_host=$(awk '/^host/ {print $3; exit}' config.cnf)
username=$(awk '/^db_user/ {print $3; exit}' config.cnf)

TABLE=""
DATABASE=""
COLUMN=""
FORMAT_TYPE=""
FORMAT_RULE="";

MSG_NOT_ALLOWED="Consulta não permitida devido a informações sensíveis, entre em contato pelo e-mail: ronaldo.rodrigues@tecnofit.com.br"

TEXT_SMALL_MASK='\1CONCAT(LEFT(\2:column, 1), REPEAT("*", CHAR_LENGTH(\2:column)-2), RIGHT(\2:column, 1))\3 :column\4'
TEXT_REGULAR_MASK='\1CONCAT(LEFT(\2:column, 2), REPEAT("*", CHAR_LENGTH(\2:column)-4), RIGHT(\2:column, 2))\3 :column\4'
TEXT_MEDIUM_MASK='\1CONCAT(LEFT(\2:column, 4), REPEAT("*", CHAR_LENGTH(\2:column)-8), RIGHT(\2:column, 4))\3 :column\4'
TEXT_LONG_MASK='\1CONCAT(LEFT(\2:column, 8), REPEAT("*", CHAR_LENGTH(\2:column)-16), RIGHT(\2:column, 8))\3 :column\4'
PASSWORD_MASK='\1REPEAT("*", CHAR_LENGTH(\2:column))\3 :column\4'
EMAIL_MASK='\1CONCAT(LEFT(\2:column,IF(CHAR_LENGTH(SUBSTRING_INDEX(\2:column, "@", 1))<9,2,3)),REPEAT("*", CHAR_LENGTH(SUBSTRING_INDEX(\2:column, "@", 1))-IF(CHAR_LENGTH(SUBSTRING_INDEX(\2:column,"@",1))<9,3,5)),RIGHT(SUBSTRING_INDEX(\2:column, "@", 1), IF(CHAR_LENGTH(SUBSTRING_INDEX(\2:column,"@",1))<9,1,2)),"@",SUBSTRING_INDEX(\2:column, "@", -1))\3 :column\4'
CPF_MASK='\1CONCAT(LEFT(\2:column,3),REPEAT("*",6),RIGHT(\2:column,2))\3 :column\4'
RG_MASK='\1CONCAT(LEFT(\2:column, 2),REPEAT("*", CHAR_LENGTH(\2:column)-4),RIGHT(\2:column,2))\3 :column\4'
PHONE_BR_MASK='\1CONCAT("(",LEFT(REPLACE(REPLACE(\2:column, "(", ""), ")", ""),2),") ",REPEAT("*",5),RIGHT(\2:column,4))\3 :column\4'
CEP_MASK='\1CONCAT(LEFT(REPLACE(REPLACE(\2:column, ".", ""), "-", ""),2), "***-", RIGHT(\2:column, 3))\3 :column\4'
CREDIT_CARD_MASK='\1CONCAT(LEFT(REPLACE(\2:column, "-", ""), 4), "-****-****-", RIGHT(REPLACE(\2:column, "-", ""), 4))\3 :column\4'
UUID_MASK='\1CONCAT(LEFT(REPLACE(\2:column, "-", ""),8), "-****-****-****-", RIGHT(REPLACE(\2:column, "-", ""),12))\3 :column\4'


which mysqladmin >/dev/null 2>&1

if [ $? -ne 0 ]
then
  echo "mysql client is not found in path, please install..."
  exit 2
fi

if [ $# -eq 0 ]
then
  echo "$0 requires options:"
  echo "       -c to specify a column,"
  echo "       -d to specify the schema"
  echo "       -o to specify obfuscation format"
  echo "          example -o 'text' or 'text:small' or 'text:regular' or 'text:medium' or 'text:long' or 'password' or 'email' or 'cpf' or 'rg' or 'cep' or 'card:credit' or 'phone' or 'uuid' and 'phone:br'"
  echo "       -t to specify a table where select * is not allowed"
  exit 1
fi

while getopts ":d:c:o:t:" opt
do
  case $opt in
     c)
        echo "column: $OPTARG"
        COLUMN=$OPTARG
        ;;
     d)
        echo "schema: $OPTARG"
        DATABASE=$OPTARG
        ;;
     o)
        echo "obfuscation required using format : $OPTARG"
        FORMAT_TYPE=$OPTARG
        ;;
     t)
        echo "table: $OPTARG"
        TABLE=$OPTARG
        ;;
     \?)
        echo "Invalid option: -$OPTARG"
        exit 1
        ;;
     :)
        echo "Option -$OPTARG requires an argument."
        exit 1
        ;;
   esac
done

if [ "$FORMAT_TYPE" != "" ]; then
  case "$FORMAT_TYPE" in
    "text:small")
      FORMAT_RULE=$TEXT_SMALL_MASK
      ;;
    "text:regular")
      FORMAT_RULE=$TEXT_REGULAR_MASK
      ;;
    "text")
      FORMAT_RULE=$TEXT_REGULAR_MASK
      ;;
    "text:medium")
      FORMAT_RULE=$TEXT_MEDIUM_MASK
      ;;
    "text:long")
      FORMAT_RULE=$TEXT_LONG_MASK
      ;;
    "password")
      FORMAT_RULE=$PASSWORD_MASK
      ;;
    "email")
      FORMAT_RULE=$EMAIL_MASK
      ;;
    "cpf")
      FORMAT_RULE=$CPF_MASK
      ;;
    "rg")
      FORMAT_RULE=$RG_MASK
      ;;
    "phone")
      FORMAT_RULE=$PHONE_BR_MASK
      ;;
    "phone:br")
      FORMAT_RULE=$PHONE_BR_MASK
      ;;
    "cep")
      FORMAT_RULE=$CEP_MASK
      ;;
    "card:credit")
      FORMAT_RULE=$CREDIT_CARD_MASK
      ;;
    "uuid")
      FORMAT_RULE=$UUID_MASK
      ;;
    *)
      echo "Invalid format: $FORMAT_TYPE"
      exit 1
      ;;
  esac
fi

if [ "$FORMAT_RULE" != "" ]; then
  if [ "$COLUMN" == "" ]; then
    echo "Option -c requires an argument."
    exit 1
  fi

  FORMAT_RULE=$(echo $FORMAT_RULE | sed -e "s/:column/${COLUMN}/g")

  mysql -BN -u ${proxy_user} -h ${proxy_host} -P${proxy_port} \
  -e "INSERT INTO mysql_query_rules
      (active,schemaname,username,match_pattern,replace_pattern,apply,re_modifiers)
      VALUES
      (1,'${DATABASE}','${username}','\`*${COLUMN}*\`','${COLUMN}',0,'caseless,global');"

#  mysql -BN -u ${proxy_user} -h ${proxy_host} -P${proxy_port} \
#  	-e "INSERT INTO mysql_query_rules
#        (active,schemaname,username,match_pattern,replace_pattern,apply,re_modifiers)
#        VALUES
#        (1,'${DATABASE}','${username}','(\(?)(\`?\w+\`?\.)?${COLUMN}(\)?)(?= ?+[^=])([ ,\n])','${FORMAT_RULE}',0,'caseless,global');"


  mysql -BN -u ${proxy_user} -h ${proxy_host} -P${proxy_port} \
  	-e "INSERT INTO mysql_query_rules
        (active,schemaname,username,match_pattern,replace_pattern,apply,re_modifiers)
        VALUES
        (1,'${DATABASE}','${username}','(\(?)(\`?\w+\`?\.)?${COLUMN}(\)?)(?= ?+[^=])(?= ?+[^RLIKE])(?= ?+[^REGEXP])(?= ?+[^LIKE])(?= ?+[^MATCH])(?= ?+[^BETWEEN])(?= ?+[^IS])(?= ?+[^<])(?= ?+[^>])(?= ?+[^\!])([ ,\n])','${FORMAT_RULE}',0,'caseless,global');"

  mysql -BN -u ${proxy_user} -h ${proxy_host} -P${proxy_port} \
    -e "INSERT INTO mysql_query_rules
        (active,schemaname,username,match_pattern,replace_pattern,apply,re_modifiers)
        VALUES
        (1,'${DATABASE}','${username}','\)(\)?) ${COLUMN}\s+(\w),',')\1 \2,',1,'caseless,global'),
        (1,'${DATABASE}','${username}','\)(\)?) ${COLUMN}\s+(.*)\s+from',')\1 \2 from',1,'caseless,global');"
fi

if [ "$TABLE" != "" ]; then

  mysql -BN -u ${proxy_user} -h ${proxy_host} -P${proxy_port} \
    -e "INSERT INTO mysql_query_rules (active,schemaname,username,match_pattern,error_msg,re_modifiers)
    VALUES (1,'${DATABASE}','${username}','^SELECT\s+\*.*\s+FROM.*${TABLE}',
    '${MSG_NOT_ALLOWED}','caseless,global' );"

  mysql -BN -u ${proxy_user} -h ${proxy_host} -P${proxy_port} \
    -e "INSERT INTO mysql_query_rules (active,schemaname,username,match_pattern,error_msg,re_modifiers)
    VALUES (1,'${DATABASE}','${username}','^SELECT\s+${TABLE}\.\*.*\s+FROM.*\s+${TABLE}',
    '${MSG_NOT_ALLOWED}','caseless,global' );"

  mysql -BN -u ${proxy_user} -h ${proxy_host} -P${proxy_port} \
    -e "INSERT INTO mysql_query_rules (active,schemaname,username,match_pattern,error_msg,re_modifiers)
    VALUES (1,'${DATABASE}','${username}','^SELECT\s+(\w+)\.\*.*\s+FROM.*\s+${TABLE}\s+(as\s+)?(\1)',
    '${MSG_NOT_ALLOWED}','caseless,global' );"
fi

mysql -BN -u ${proxy_user} -h ${proxy_host} -P${proxy_port} \
-e "SET mysql-query_processor_regex=1; LOAD MYSQL VARIABLES TO RUNTIME; LOAD MYSQL QUERY RULES TO RUNTIME;"