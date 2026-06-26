#!/bin/bash
#
# glpi_healthcheck.sh
# ---------------------------------------------------------------------------
# Supervision de GLPI avec alertes Microsoft Teams.
#
# Vérifie GLPI (HTTP), les services Apache et MariaDB, le collecteur mail
# et les erreurs PHP, puis envoie une alerte dans un canal Teams UNIQUEMENT
# en cas de changement d'état (mécanisme anti-spam basé sur un fichier d'état).
#
# Exécution : via cron, une exécution par appel (voir README).
# Auteur    : Nathan Drancourt
# Licence   : MIT
# ---------------------------------------------------------------------------

####################################
# CONFIG
####################################

GLPI_URL="http://x.x.x.x/glpi"
GLPI_LOG_DIR="/var/www/html/glpi/files/_log"
HOSTNAME=$(hostname)

STATE_DIR="/var/lib/glpi_healthcheck"
WEBHOOK="https://VOTRE_WEBHOOK_TEAMS_ICI"

mkdir -p "$STATE_DIR"

DATE=$(date "+%Y-%m-%d %H:%M:%S")
NOW=$(date +%s)

CRITICAL=""
WARNING=""

####################################
# 1) TEST HTTP
####################################

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$GLPI_URL")

####################################
# 2) SERVICES CRITIQUES
####################################

APACHE_DOWN=0
DB_DOWN=0

systemctl is-active --quiet apache2 || APACHE_DOWN=1
systemctl is-active --quiet mariadb || DB_DOWN=1

if [ "$APACHE_DOWN" -eq 1 ]; then
  CRITICAL+=$'❌ Apache arrêté → GLPI inaccessible\n'
fi

if [ "$DB_DOWN" -eq 1 ]; then
  CRITICAL+=$'❌ MariaDB arrêtée → base HS\n'
fi

# Corrélation forte : si Apache est tombé ET que le HTTP échoue,
# on remplace les messages par une seule alerte synthétique.
if [ "$APACHE_DOWN" -eq 1 ] && [ "$HTTP_CODE" != "200" ]; then
  CRITICAL=$'❌ GLPI totalement indisponible (Web + HTTP KO)\n'
fi

####################################
# 3) COLLECTEUR MAIL
####################################

LAST_MAIL_RUN=$(mysql -N -s glpi -e "
SELECT UNIX_TIMESTAMP(lastrun)
FROM glpi_crontasks
WHERE name LIKE '%mail%' LIMIT 1;" 2>/dev/null)

if [ -n "$LAST_MAIL_RUN" ] && [ $((NOW - LAST_MAIL_RUN)) -gt 600 ]; then
  WARNING+=$'⚠️ Collecteur mail inactif\n'
fi

####################################
# 4) ERREURS GLPI IMPORTANTES
####################################

ERRORS=$(tail -n 20 "$GLPI_LOG_DIR/php-errors.log" 2>/dev/null | \
grep -iE "critical|fatal|sql|exception")

if [ -n "$ERRORS" ]; then

  TOP=$(echo "$ERRORS" | \
  sed 's/\[.*\] //g' | \
  sort | uniq -c | sort -nr | head -3)

  while read -r count line; do
    WARNING+="• ${line} (${count})"$'\n'
  done <<< "$TOP"

fi

####################################
# 5) CONSTRUCTION DU MESSAGE
####################################

MESSAGE=""

if [ -n "$CRITICAL" ]; then
  MESSAGE+=$'🔴 CRITIQUE\n--------------------------------\n'
  MESSAGE+="$CRITICAL"
fi

if [ -n "$WARNING" ]; then
  MESSAGE+=$'\n🟠 WARNING\n--------------------------------\n'
  MESSAGE+="$WARNING"
fi

if [ -z "$CRITICAL" ] && [ -z "$WARNING" ]; then
  MESSAGE="✅ GLPI OK - aucun problème"
fi

MESSAGE+=$'\n🕒 '"$DATE"

####################################
# 6) DETECTION D'EVENEMENT (ANTI-SPAM)
####################################

if [ -n "$CRITICAL" ]; then
  CURRENT_STATE="CRITICAL"
elif [ -n "$WARNING" ]; then
  CURRENT_STATE="WARNING"
else
  CURRENT_STATE="OK"
fi

LAST_STATE=$(cat "$STATE_DIR/last_state" 2>/dev/null)

SEND=0

# Envoi uniquement s'il y a un changement d'état
if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then
  SEND=1
fi

# Notification de retour à la normale
if [ "$CURRENT_STATE" = "OK" ] && [ "$LAST_STATE" != "OK" ] && [ -n "$LAST_STATE" ]; then
  MESSAGE="✅ GLPI rétabli - tous les services sont OK"
  MESSAGE+=$'\n🕒 '"$DATE"
  SEND=1
fi

####################################
# 7) ENVOI VERS TEAMS
####################################

if [ "$SEND" -eq 1 ]; then

  # Échappement minimal pour produire un JSON valide
  MESSAGE_CLEAN=$(printf '%s' "$MESSAGE" | sed ':a;N;$!ba;s/\n/\\n/g')
  MESSAGE_CLEAN=$(printf '%s' "$MESSAGE_CLEAN" | sed 's/"/\\"/g')

  JSON="{\"alert\":\"$MESSAGE_CLEAN\"}"

  curl -s -X POST "$WEBHOOK" \
    -H "Content-Type: application/json" \
    -d "$JSON"

  echo "$CURRENT_STATE" > "$STATE_DIR/last_state"

fi

exit 0
