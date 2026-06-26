# 🔔 GLPI Teams Healthcheck

> Supervision automatisée de **GLPI** avec envoi d'**alertes Microsoft Teams** — script Bash, déclenché par cron, avec mécanisme anti-spam.

Ce projet met en place un script de contrôle qui surveille en continu une instance **GLPI** (disponibilité web, services système, collecteur mail, erreurs applicatives) et envoie une alerte dans un canal **Microsoft Teams** uniquement lorsque l'état change — évitant ainsi le spam d'alertes répétées.

---

## 🎯 Objectif

Permettre à une équipe (DSI, support, exploitation) d'être **prévenue automatiquement** en cas de problème sur GLPI, sans surveillance manuelle, tout en respectant les bonnes pratiques de sécurité (aucun secret en clair).

Le script :

- surveille **GLPI**, ses **services** (Apache, MariaDB) et son **collecteur mail** ;
- analyse les **erreurs PHP** récentes du log GLPI ;
- **journalise** localement les contrôles (audit, diagnostic) ;
- envoie des **alertes Teams** via un webhook Power Automate ;
- évite les alertes répétées grâce à un **anti-spam par machine à états** ;
- notifie également le **retour à la normale**.

---

## 🧱 Architecture

```
        Cron Linux (toutes les 5 min)
                  │
                  ▼
        glpi_healthcheck.sh
        ├── Test HTTP de GLPI
        ├── Vérification Apache / MariaDB
        ├── Contrôle du collecteur mail
        ├── Analyse des erreurs PHP
        ├── Comparaison avec l'état précédent (anti-spam)
        └── Envoi du webhook (si changement d'état)
                  │
                  ▼
          Flux Power Automate
                  │
                  ▼
      Canal Teams « Supervision-GLPI »
```

---

## 🛠️ Technologies

| Domaine        | Outils / technologies                          |
|----------------|------------------------------------------------|
| Scripting      | Bash                                           |
| Planification  | Cron                                           |
| Supervision    | GLPI, Apache, MariaDB                          |
| Base de données| MySQL / MariaDB (`mysql` CLI, `.my.cnf`)       |
| Intégration    | Webhook, Microsoft Teams, Power Automate       |
| Sécurité       | Permissions Unix, moindre privilège, secrets externalisés |

---

## ✅ Prérequis

- Un serveur **Linux** (Debian/Ubuntu) hébergeant **GLPI**
- **Apache2** et **MariaDB** installés
- Les paquets `curl` et `mysql-client`
- Un accès à **Microsoft Teams** avec les droits de créer un flux Power Automate
- Un accès `root` (ou `sudo`) sur le serveur

---

## 🟣 Partie 1 — Créer le webhook Microsoft Teams

### 1.1 Accéder au canal

1. Ouvrez **Microsoft Teams**.
2. Sélectionnez l'**équipe** concernée (ex. *DSI*, *Informatique*).
3. Choisissez le **canal** qui recevra les alertes (ex. `Supervision-GLPI`).

### 1.2 Ajouter un flux de travail (webhook entrant)

1. À droite du nom du canal, cliquez sur **⋯ (Plus d'options)**.
2. Cliquez sur **Flux de travail**.
3. Recherchez et sélectionnez un modèle d'**envoi d'alertes via webhook**.

### 1.3 Récupérer l'URL du webhook

Teams génère une URL de la forme :

```
https://<votre-environnement>.environment.api.powerplatform.com/.../triggers/manual/paths/invoke?...&sig=<signature>
```

Copiez cette URL : elle sera utilisée par le script.

> ⚠️ **Sécurité** : cette URL est **confidentielle**. Elle permet de publier dans le canal sans authentification. En cas de fuite, **supprimez le webhook et recréez-en un**. Ne la committez **jamais** dans Git.

---

## 🟣 Partie 2 — Configurer le flux Power Automate

Le flux déclenché par le webhook reçoit un corps JSON de la forme :

```json
{ "alert": "Contenu du message d'alerte" }
```

Configurez le flux pour :

1. **Déclencheur** : réception d'une requête HTTP (le webhook).
2. **Action** : publier un message dans le canal Teams.
3. **Contenu du message** : utilisez le champ `alert` reçu dans le corps de la requête.

---

## 🟣 Partie 3 — Déployer le script

### 3.1 Installer le script

Sur le serveur GLPI :

```bash
sudo nano /usr/local/bin/glpi_healthcheck.sh
```

Collez le contenu de [`glpi_healthcheck.sh`](glpi_healthcheck.sh), puis adaptez les variables de la section `CONFIG` :

```bash
GLPI_URL="http://<ip-ou-domaine>/glpi"
WEBHOOK="https://VOTRE_WEBHOOK_TEAMS_ICI"
```

### 3.2 Définir les droits

```bash
sudo chmod 750 /usr/local/bin/glpi_healthcheck.sh
sudo chown root:root /usr/local/bin/glpi_healthcheck.sh
```

> `chmod 750` = exécution réservée au propriétaire (`root`) et à son groupe. Principe de **moindre privilège**.

---

## 🟣 Partie 4 — Journal local et anti-spam

### 4.1 Fichier de journal

```bash
sudo touch /var/log/glpi_healthcheck.log
sudo chmod 640 /var/log/glpi_healthcheck.log
sudo chown root:adm /var/log/glpi_healthcheck.log
```

Ce fichier sert à l'**audit**, au **diagnostic** et de **preuve d'exécution**.

### 4.2 Dossier d'état (anti-spam)

```bash
sudo mkdir -p /var/lib/glpi_healthcheck
sudo chmod 700 /var/lib/glpi_healthcheck
sudo chown root:root /var/lib/glpi_healthcheck
```

Ce dossier stocke l'état du dernier contrôle (`last_state`) pour éviter de renvoyer la même alerte en boucle.

---

## 🟣 Partie 5 — Accès MySQL sécurisé (collecteur mail)

Pour contrôler le collecteur mail via la base, le script lit ses identifiants depuis un fichier de configuration MySQL — **jamais depuis le script lui-même**.

```bash
sudo cp .my.cnf.example /root/.my.cnf
sudo nano /root/.my.cnf      # renseignez le vrai mot de passe
sudo chmod 600 /root/.my.cnf
```

Contenu (voir [`.my.cnf.example`](.my.cnf.example)) :

```ini
[client]
user=glpi
password=CHANGEZ_MOI
```

> ✅ Aucun mot de passe dans le script. ✅ Bonne pratique de sécurité.

---

## 🟣 Partie 6 — Tests

### 6.1 Test manuel

```bash
sudo /usr/local/bin/glpi_healthcheck.sh
```

Vérifiez que le script s'exécute sans erreur. Si tout est OK, aucune alerte n'est envoyée à Teams (c'est normal : l'anti-spam n'envoie qu'en cas de changement d'état).

### 6.2 Test réel (simulation de panne)

```bash
sudo systemctl stop mariadb
sudo /usr/local/bin/glpi_healthcheck.sh
```

Une alerte **doit apparaître** dans Teams — **une seule fois** (anti-spam actif). Relancez le service ensuite :

```bash
sudo systemctl start mariadb
sudo /usr/local/bin/glpi_healthcheck.sh
```

Un message de **rétablissement** doit alors être envoyé.

---

## 🟣 Partie 7 — Mise en production (cron)

```bash
sudo crontab -e
```

Ajoutez la ligne suivante :

```cron
*/5 * * * * /usr/local/bin/glpi_healthcheck.sh
```

> ✅ Exécution toutes les 5 minutes. ✅ Supervision continue. ✅ Aucun spam.

---

## 🔒 Sécurité — points clés

- Aucun mot de passe en clair dans le script (externalisé dans `/root/.my.cnf`, droits `600`).
- L'URL du webhook n'est **jamais** committée (placeholder `VOTRE_WEBHOOK_TEAMS_ICI`).
- Permissions restrictives sur le script, le log et le dossier d'état.
- Le fichier `.gitignore` empêche toute publication accidentelle des secrets.

---

## 📄 Licence

Distribué sous licence **MIT**. Voir le fichier [`LICENSE`](LICENSE).

## 👤 Auteur

**Nathan Drancourt** — Administrateur Systèmes & Réseaux
GitHub : [@ImNvthan](https://github.com/ImNvthan)
