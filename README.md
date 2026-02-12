# Unraid Media Consolidator & Cleaner (V10)

Ein hochentwickeltes Bash-Script-Set für Unraid-Systeme. Es dient dazu, zersplitterte Medienbibliotheken (Filme, Serien) zu konsolidieren, zusammengehörige Dateien ("Sidecars" wie NFOs, Bilder) auf derselben Disk zusammenzuführen und verwaiste leere Ordnerstrukturen tiefenrein zu entfernen.

---

## Features (V10)

### Smart Weight Logic (Intelligente Gewichtung)

Das Script verschiebt Dateien nicht blind nach der grössten Datei. Es analysiert, auf welcher Disk bereits die **grösste Datenmenge** (in Bytes) eines Films oder einer Serie liegt.

* Beispiel: Eine Serie liegt zu 90% auf disk1, aber eine neue Episode landete auf disk2. Das Script erkennt disk1 als "Heimat" und verschiebt die Episode dorthin.

### Deep Clean (Rekursive Tiefenreinigung)

Nach der Verschiebung startet Phase 3:

* Loop-Reinigung: Das Script durchsucht die Disks in Schleifen nach leeren Ordnern. Es läuft so lange, bis keine leeren Ordner mehr gefunden werden (löst tief verschachtelte Strukturen auf).
* Root-Protection: Kritische Basis-Ordner (z.B. `/mnt/disk1/Filme`) werden **niemals** gelöscht, selbst wenn sie leer sind. Die Share-Struktur bleibt intakt.

### Sicherheits-Funktionen

* Space-Check: Vor jedem Verschieben wird geprüft, ob auf der Ziel-Disk noch genug freier Speicherplatz ist (konfigurierbarer Puffer, Standard 256 GB).
* Retry-Queue: Ist eine Disk voll, wird die Datei übersprungen und am Ende des Laufs erneut versucht (falls zwischenzeitlich Platz frei wurde).
* Targeted Scan: Es werden nur explizit erlaubte Ordner gescannt. Systemordner wie docker, appdata oder system werden physikalisch ignoriert.
* Dryrun-Standard: Standardmässig läuft das Script im Simulationsmodus.

---

## Voraussetzungen

* OS: Unraid (getestet auf Version 6.x / 7.x)
* Zugriff: Terminal (SSH) oder das "User Scripts" Plugin.
* Tools: `rsync` und `find` (Standardmässig in Unraid enthalten).

---

## Installation

### 1. Verzeichnis erstellen

Erstelle einen Ordner auf deinem Cache oder USB-Stick, damit die Scripte Reboot-sicher sind.

```
mkdir -p /mnt/user/system/scripts/consolidate/
cd /mnt/user/system/scripts/consolidate/
```

### 2. Dateien platzieren

Kopiere deine beiden Script-Dateien in diesen Ordner:

* `consolidate_master.sh`
* `setup_consolidate.sh`

### 3. Berechtigungen setzen

Mache die Scripte ausführbar:

```
chmod +x consolidate_master.sh setup_consolidate.sh
```

---

## Konfiguration

Du musst keine Textdateien manuell bearbeiten. Nutze den integrierten Assistenten, um die Datei `consolidate.ini` zu erstellen.

Setup starten:

```
./setup_consolidate.sh
```

Der Assistent führt dich durch folgende Schritte:

1. Quellverzeichnisse: Welche User-Shares sollen aufgeräumt werden?
2. Logdatei: Wo soll das Protokoll gespeichert werden?
3. Array-Disks: Wo sollen die Daten dauerhaft liegen? (Standard: `/mnt/disk*`)
4. Cache/Pools: Wo liegen temporäre oder neue Daten? (z.B. `/mnt/cache`)
5. Exclude-Datei: Pfad zu einer Datei mit Ausschlusskriterien (optional).
6. Mindestspeicherplatz: Wieviel Platz muss auf einer Disk frei bleiben? (Standard: 256 GB)

---

## Nutzung

### 1. Test-Lauf (Dryrun)

Führe das Script ohne Argumente aus. Dies ist der Standardmodus. Es werden keine Dateien bewegt oder gelöscht.

```
./consolidate_master.sh
```

### 2. Ernstfall (Live Mode)

Wenn der Dryrun sauber aussieht, starte den scharfen Modus:

```
./consolidate_master.sh --run
```

---

## Fehlerbehebung

**Fehler: "Keine Ordner auf den Disks gefunden!"**  
Prüfe in der Config, ob die Pfade korrekt geschrieben sind (Gross-/Kleinschreibung beachten).

**Fehler: "FULL ... Zu wenig Platz"**  
Die Ziel-Disk hat weniger freien Speicher als in MIN_FREE_GB definiert. Das Script überspringt diese Datei. Du musst Platz schaffen oder das Limit in der Config senken.

**Warum wird mein Haupt-Ordner nicht gelöscht, obwohl er leer ist?**  
Das ist die "Root Protection". Das Script löscht niemals die oberste Ebene deiner Shares (z.B. `/mnt/disk1/Filme`), damit Unraid keine Probleme mit den Freigaben bekommt.

---

## Haftungsausschluss

Dieses Script manipuliert Dateien (Verschieben/Löschen) auf Systemebene. Obwohl umfangreiche Sicherheitsmechanismen (Dryrun, Space-Check, Root-Protection) eingebaut sind:

**Die Nutzung erfolgt auf eigene Gefahr. Stelle sicher, dass du regelmässige Backups deiner wichtigen Daten hast!**