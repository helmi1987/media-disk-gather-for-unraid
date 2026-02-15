# Unraid Media Consolidator & Cleaner (V10.2)

Ein hochentwickeltes Bash-Script-Set für Unraid-Systeme. Es dient dazu, zersplitterte Medienbibliotheken (Filme, Serien) zu konsolidieren, zusammengehörige Dateien ("Sidecars" wie NFOs, Bilder) auf derselben Disk zusammenzuführen und verwaiste leere Ordnerstrukturen tiefenrein zu entfernen.

- - -

## Features (V10.2)

### Smart Weight Logic (Intelligente Gewichtung)

Das Script analysiert, auf welcher **Array-Disk** (`/mnt/disk*`) bereits die grösste Datenmenge (in Bytes) eines Films oder einer Serie liegt.

*   **Neu in V10.2:** Der Cache wird bei der Ziel-Ermittlung ignoriert. Das verhindert, dass der Cache als "Ziel" gewinnt, nur weil dort gerade viele neue Dateien liegen. Der Datenfluss geht immer Richtung Array.

### Cache Handling (Mover-Trennung)

*   **Standard:** Dateien auf dem Cache werden ignoriert und nicht verschoben. Das Script überlässt diese Aufgabe dem nativen Unraid Mover.
*   **Optional:** Mit dem Parameter `--include-cache` kann erzwungen werden, dass auch Dateien vom Cache auf das Array verschoben werden.
*   **Duplikate:** Wenn eine Datei sicher auf dem Array liegt und _zusätzlich_ auf dem Cache existiert (Duplikat), wird die Cache-Kopie gelöscht, um Platz zu sparen (unabhängig vom Mover-Setting).

### Deep Clean (Rekursive Tiefenreinigung)

Nach der Verschiebung startet Phase 3:

*   Loop-Reinigung: Das Script durchsucht die Disks in Schleifen nach leeren Ordnern, bis alles sauber ist.
*   Root-Protection: Kritische Basis-Ordner (z.B. `/mnt/disk1/Filme`) werden **niemals** gelöscht.

- - -

## Voraussetzungen

*   OS: Unraid (getestet auf Version 6.x / 7.x)
*   Zugriff: Terminal (SSH) oder das "User Scripts" Plugin.
*   Tools: `rsync` und `find` (Standardmässig in Unraid enthalten).

- - -

## Installation

### 1\. Verzeichnis erstellen

Erstelle einen Ordner auf deinem Cache oder USB-Stick, damit die Scripte Reboot-sicher sind.

```
mkdir -p /mnt/user/system/scripts/consolidate/
cd /mnt/user/system/scripts/consolidate/
```

### 2\. Dateien platzieren

Kopiere deine beiden Script-Dateien in diesen Ordner:

*   `consolidate_master.sh`
*   `setup_consolidate.sh`

### 3\. Berechtigungen setzen

Mache die Scripte ausführbar:

```
chmod +x consolidate_master.sh setup_consolidate.sh
```

- - -

## Konfiguration

Du musst keine Textdateien manuell bearbeiten. Nutze den integrierten Assistenten, um die Datei `consolidate.ini` zu erstellen.

Setup starten:

```
./setup_consolidate.sh
```

Der Assistent führt dich durch folgende Schritte:

1.  Quellverzeichnisse: Welche User-Shares sollen aufgeräumt werden?
2.  Logdatei: Wo soll das Protokoll gespeichert werden?
3.  Array-Disks: Wo sollen die Daten dauerhaft liegen? (Standard: `/mnt/disk*`)
4.  Cache/Pools: Wo liegen temporäre oder neue Daten? (z.B. `/mnt/cache`)
5.  Exclude-Datei: Pfad zu einer Datei mit Ausschlusskriterien (optional).
6.  Mindestspeicherplatz: Wieviel Platz muss auf einer Disk frei bleiben? (Standard: 256 GB)

- - -

## Nutzung

### 1\. Test-Lauf (Dryrun)

Führe das Script ohne Argumente aus. Dies ist der Standardmodus. Es werden keine Dateien bewegt oder gelöscht.

```
./consolidate_master.sh
```

### 2\. Ernstfall (Live Mode)

Nur Array aufräumen (Standard):

```
./consolidate_master.sh --run
```

Array aufräumen UND Cache leeren (alles zum Array schieben):

```
./consolidate_master.sh --run --include-cache
```

- - -

## Fehlerbehebung

**Fehler: "Keine Ordner auf den Disks gefunden!"**  
Prüfe in der Config, ob die Pfade korrekt geschrieben sind (Gross-/Kleinschreibung beachten).

**Fehler: "FULL ... Zu wenig Platz"**  
Die Ziel-Disk hat weniger freien Speicher als in MIN\_FREE\_GB definiert. Das Script überspringt diese Datei und versucht es am Ende des Laufs erneut (Retry-Queue).

- - -

## Haftungsausschluss

Dieses Script manipuliert Dateien (Verschieben/Löschen) auf Systemebene. Obwohl umfangreiche Sicherheitsmechanismen (Dryrun, Space-Check, Root-Protection) eingebaut sind:

Die Nutzung erfolgt auf eigene Gefahr. Stelle sicher, dass du regelmässige Backups deiner wichtigen Daten hast!