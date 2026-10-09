# Unraid Media Consolidator & Cleaner (V11.0)

Ein Bash-Script-Set für Unraid-Systeme. Es dient dazu, zersplitterte Medienbibliotheken (Filme, Serien) zu konsolidieren, zusammengehörige Dateien ("Sidecars" wie NFOs, Bilder) auf derselben Disk zusammenzuführen und verwaiste leere Ordnerstrukturen tiefenrein zu entfernen.

- - -

## Features (V11.0)

### Smart Weight Logic (Intelligente Gewichtung)

Das Script analysiert, auf welcher **Array-Disk** (`/mnt/disk[0-9]*`) bereits die grösste Datenmenge (in Bytes) eines Films oder einer Serie liegt, und zieht die restlichen Dateien des Ordners dorthin.

*   Der Cache wird bei der Ziel-Ermittlung ignoriert. Der Datenfluss geht immer Richtung Array.
*   Gezählt wird die **physische** Grösse jeder Kopie. Bei Gleichstand gewinnt die Disk mit der kleineren Nummer (deterministisch).
*   Disk-Namen werden exakt verglichen (`disk1` ist nicht `disk10`).

### Was als "Ordner" gilt

*   Eine Einheit ist immer der Ordner **direkt unter dem Share**, z.B. `/mnt/user/Filme/Film (2020)` oder `/mnt/user/Serien/Serie`. Alle Dateien darin (inkl. Unterordner wie `Season 01` oder `*.trickplay`) landen gemeinsam auf einer Disk.
*   Eine ganze Serie kommt damit auf **eine** Disk. Ist diese zu voll, wird nicht auf die zweitbeste Disk ausgewichen (siehe "VOLL" unter Fehlerbehebung).
*   Lose Dateien direkt im Share-Root (z.B. `/mnt/user/Filme/film.mkv`) werden **nie** verarbeitet.

### Duplikate – nur identische Kopien werden gelöscht

Liegt eine Datei auf der Ziel-Disk und zusätzlich auf einer anderen Disk oder auf dem Cache, wird die zweite Kopie nur gelöscht, wenn sie **identisch** ist:

*   `DUP_CHECK=size` (Standard): gleiche Grösse.
*   `DUP_CHECK=cmp`: zusätzlich Byte-für-Byte-Vergleich (langsam, aber sicher).
*   Ungleiche Kopien (z.B. abgebrochene Kopiervorgänge) werden **nie** gelöscht, sondern als **Konflikt** gemeldet und protokolliert.

### Cache Handling (Mover-Trennung)

*   **Standard:** Dateien auf dem Cache werden ignoriert und nicht verschoben. Das Script überlässt diese Aufgabe dem nativen Unraid Mover. Identische Cache-Duplikate einer Array-Datei werden trotzdem entfernt.
*   **Optional:** Mit `--include-cache` werden auch Dateien vom Cache auf das Array verschoben. Ordner, die **nur** auf dem Cache liegen, landen dabei auf der Array-Disk mit dem meisten freien Platz (`CACHE_ONLY_TARGET=most-free`) oder bleiben liegen (`CACHE_ONLY_TARGET=skip`).
*   Läuft der Unraid-Mover gerade, bricht ein scharfer Lauf ab (Dryrun warnt nur).

### Deep Clean (Rekursive Tiefenreinigung)

Nach der Verschiebung startet Phase 3:

*   Loop-Reinigung: Das Script durchsucht die Array- und Cache-Disks (nur innerhalb der `BASE_DIRS`) in Schleifen nach leeren Ordnern, bis alles sauber ist. Nicht löschbare Ordner (z.B. Mountpoints, schreibgeschützte Disks) werden gemeldet und übersprungen – kein Endlos-Loop.
*   Root-Protection: Die Share-Wurzeln auf den Disks (z.B. `/mnt/disk1/Filme`) werden **niemals** gelöscht.
*   Im Dryrun wird das Ergebnis simuliert: auch Ordner, die erst durch die geplanten Verschiebungen leer würden, werden angezeigt.

### Weitere Sicherheitsmechanismen

*   Neu angelegte Zielordner übernehmen Besitzer und Rechte des Quellordners (auf Unraid typischerweise `nobody:users 0777`), damit Docker-Container und SMB-Benutzer weiterhin schreiben können.
*   Die Konfiguration wird beim Start geprüft (`DRYRUN` nur `true`/`false`, `MIN_FREE_GB` nur Zahlen, `BASE_DIRS` nur unter `/mnt/user/`). Ungültige Werte führen zum Abbruch statt zu einem unbeabsichtigten scharfen Lauf.
*   Sperrdatei: es läuft immer nur eine Instanz.
*   Zusammenfassung und Exit-Code (`0` ok, `1` Konfigfehler, `2` Lauf mit Fehlern/Konflikten) eignen sich für Benachrichtigungen über das User-Scripts-Plugin.

- - -

## Voraussetzungen

*   OS: Unraid (getestet auf Version 6.x / 7.x, bash ≥ 4.4)
*   Zugriff: Terminal (SSH) oder das "User Scripts" Plugin.
*   Tools: `rsync`, `find`, `flock` (Standardmässig in Unraid enthalten).

- - -

## Installation

### 1\. Verzeichnis erstellen

Erstelle einen Ordner auf einem Share (z.B. `system`), damit die Scripte Reboot-sicher sind.

```
mkdir -p /mnt/user/system/scripts/consolidate/
cd /mnt/user/system/scripts/consolidate/
```

### 2\. Dateien platzieren

Kopiere deine beiden Script-Dateien in diesen Ordner:

*   `consolidate_master.sh`
*   `setup_consolidate.sh`

### 3\. Berechtigungen setzen

```
chmod +x consolidate_master.sh setup_consolidate.sh
```

- - -

## Konfiguration

Nutze den Assistenten, um die Datei `consolidate.ini` zu erstellen. Sie wird immer neben die Scripte geschrieben, egal aus welchem Ordner du den Assistenten startest.

```
./setup_consolidate.sh
```

Existiert bereits eine `consolidate.ini`, werden deren Werte als Vorgabe angeboten. Ungültige Eingaben werden abgewiesen und neu abgefragt.

Der Assistent führt dich durch folgende Schritte:

1.  Quellverzeichnisse: Welche User-Shares sollen aufgeräumt werden? Mehrere mit `;` trennen (Leerzeichen in Pfaden sind erlaubt).
2.  Logdatei: Wo soll das Protokoll gespeichert werden? (Standard: `/mnt/user/PlexMedia/consolidate.log`, Ordner wird beim scharfen Lauf angelegt)
3.  Array-Disks: Wo sollen die Daten dauerhaft liegen? (Standard: `/mnt/disk[0-9]*`)
4.  Cache/Pools: Wo liegen temporäre oder neue Daten? (z.B. `/mnt/cache /mnt/nvme`)
5.  Exclude-Datei: Pfad zu einer Datei mit Ausnahmen (optional). Eine Datei **oder ein Ordner** pro Zeile, als `/mnt/user/...`- oder `/mnt/diskN/...`-Pfad.
6.  Mindestspeicherplatz: Wieviel Platz muss auf einer Disk frei bleiben? (Standard: 256 GB)
7.  Dryrun-Standardmodus: `true` oder `false`.
8.  Verhalten für Cache-only-Ordner bei `--include-cache`: `most-free` oder `skip`.
9.  Duplikat-Prüfung: `size` oder `cmp`.

Einzelne Werte lassen sich für einen Lauf per Umgebungsvariable überschreiben, z.B. `CONSOLIDATE_DUP_CHECK=cmp ./consolidate_master.sh --run` (Liste: `./consolidate_master.sh --help`).

Verfügbare Umgebungsvariablen: `CONSOLIDATE_DRYRUN`, `CONSOLIDATE_MOVE_CACHE`, `CONSOLIDATE_MIN_FREE_GB`, `CONSOLIDATE_CACHE_ONLY_TARGET`, `CONSOLIDATE_DUP_CHECK`, `CONSOLIDATE_LOGFILE`.

Kommandozeilen-Argumente (`--run`, `--dryrun`, `--include-cache`) haben Vorrang vor Umgebungsvariablen, diese vor der `consolidate.ini`.

### Beispiel `consolidate.ini`

```
# consolidate.ini – erzeugt von setup_consolidate.sh (V11)
BASE_DIRS=('/mnt/user/Filme' '/mnt/user/Serien')
LOGFILE='/mnt/user/system/logs/consolidate.log'

# Disks
ARRAY_PATTERN='/mnt/disk[0-9]*'
CACHE_PATTERN='/mnt/cache'

EXCLUDE_FILE='/mnt/user/system/scripts/consolidate/exclude.txt'
DRYRUN=true
MIN_FREE_GB=256

# most-free | skip   (Cache-only-Ordner bei --include-cache)
CACHE_ONLY_TARGET='most-free'
# size | cmp         (wann ist eine zweite Kopie ein löschbares Duplikat)
DUP_CHECK='size'
```

Die Datei wird beim Start eingelesen (`source`) und anschliessend geprüft. Fehlt sie, laufen die Standardwerte aus dem Script.

### Exclude-Datei

Eine Zeile pro Eintrag. Leere Zeilen und Zeilen mit `#` am Anfang werden ignoriert, Windows-Zeilenenden sind erlaubt.

*   **Datei:** exakter Pfad, als `/mnt/user/...` oder `/mnt/diskN/...`.
*   **Ordner:** Pfad mit `/` am Ende oder ein existierendes Verzeichnis. Alles darunter wird ignoriert.

```
# ganzer Ordner
/mnt/user/Filme/Mein Film (2020)/
# einzelne Datei auf einer bestimmten Disk
/mnt/disk3/Serien/Serie/Season 01/folder.jpg
```

Ignorierte Dateien zählen in der Zusammenfassung unter "Ignoriert (Exclude)". Fehlt die Datei, läuft das Script ohne Ausnahmen weiter (Warnung).

- - -

## Nutzung

### 1\. Test-Lauf (Dryrun)

Führe das Script ohne Argumente aus. Dies ist der Standardmodus. Es werden keine Dateien bewegt oder gelöscht, und es wird nichts ins Log geschrieben.

```
./consolidate_master.sh
```

`--dryrun` erzwingt den Testmodus auch dann, wenn in der `consolidate.ini` `DRYRUN=false` steht.

### 2\. Ernstfall (Live Mode)

Der scharfe Lauf startet nach 2 Sekunden Wartezeit (Abbruch mit Ctrl-C möglich).

Nur Array aufräumen (Standard):

```
./consolidate_master.sh --run
```

Array aufräumen UND Cache leeren (alles zum Array schieben):

```
./consolidate_master.sh --run --include-cache
```

Hinweis: Nicht gleichzeitig mit dem Unraid-Mover laufen lassen – das Script bricht in dem Fall ab.

### Optionen

| Argument | Wirkung |
|---|---|
| *(keins)* | Modus aus `DRYRUN` der `consolidate.ini` (Standard: Dryrun) |
| `--run` | Scharfer Lauf: verschieben und löschen |
| `--dryrun`, `--dry-run` | Dryrun erzwingen |
| `--include-cache` | Dateien vom Cache/Pool aufs Array holen |
| `-h`, `--help` | Hilfe anzeigen |

Unbekannte Argumente führen zum Abbruch.

### Ablauf

1.  **Phase 1 – Indexierung:** Alle Dateien der `BASE_DIRS` auf allen Array- und Cache-Disks werden einmalig erfasst (im Speicher).
2.  **Phase 2 – Verarbeitung:** Pro Ordner Ziel-Disk bestimmen, fehlende Dateien verschieben (`rsync`), identische Duplikate löschen. Danach Retry für Dateien, die wegen voller Disk übersprungen wurden.
3.  **Phase 3 – Deep Clean:** Leere Ordner auf den physischen Disks entfernen.

### Zusammenfassung

| Zeile | Bedeutung |
|---|---|
| Verschoben | Dateien, die auf die Ziel-Disk verschoben wurden |
| Duplikate gelöscht | Identische zweite Kopien, die entfernt wurden |
| Ignoriert (Exclude) | Dateien, die per Exclude-Datei übersprungen wurden |
| Cache ignoriert | Dateien, die nur auf dem Cache liegen und ohne `--include-cache` (bzw. mit `CACHE_ONLY_TARGET=skip`) liegen bleiben |
| Leere Ordner gelöscht | Entfernte leere Ordner aus Phase 3 |
| Konflikte | Ungleiche Kopien, nichts gelöscht |
| Nicht verschoben (Disk voll) | Auch nach dem Retry kein Platz auf der Ziel-Disk |
| Fehler (rsync/rm/mkdir) | Fehlgeschlagene Dateioperationen |
| Leere Ordner nicht löschbar | z.B. Mountpoints, schreibgeschützte Disks |

Die Zeilen ab "Konflikte" erscheinen nur, wenn ihr Wert grösser als 0 ist. Im Dryrun sind alle Werte geplant, nicht ausgeführt.

Exit-Codes: `0` ok, `1` Konfig-/Startfehler, `2` Lauf mit Fehlern oder Konflikten, `130` Abbruch per Ctrl-C/Signal.

### Automatisierung (User Scripts Plugin)

Im User-Scripts-Plugin ein neues Script anlegen und den Master mit absolutem Pfad aufrufen, z.B.:

```
#!/bin/bash
/mnt/user/system/scripts/consolidate/consolidate_master.sh --run
```

Zeitplan so wählen, dass er nicht mit dem Mover-Zeitplan überlappt. Eine parallele zweite Instanz wird per Sperrdatei verhindert.

- - -

## Fehlerbehebung

**Fehler: "Keine Ordner auf den Disks gefunden!"**  
Prüfe in der Config, ob die Pfade korrekt geschrieben sind (Gross-/Kleinschreibung beachten).

**"VOLL" / "Nicht verschoben (Disk voll)"**  
Die Ziel-Disk hat weniger freien Speicher als in `MIN_FREE_GB` definiert. Das Script überspringt diese Datei, versucht es am Ende des Laufs erneut (Retry-Queue) und protokolliert den Fehlschlag.

**"KONFLIKT (ungleich, behalten)"**  
Zwei Kopien derselben Datei haben unterschiedliche Grösse/Inhalt (z.B. abgebrochener Kopiervorgang). Das Script löscht nichts – prüfe die Kopien von Hand.

**"Der Unraid-Mover läuft gerade"**  
Warte, bis der Mover fertig ist, und starte das Script erneut.

**"Es läuft bereits eine Instanz von consolidate_master.sh"**  
Eine andere Instanz hält die Sperrdatei (`/var/run/consolidate_master.lock`, Fallback `/tmp/consolidate_master.lock`). Warte, bis sie fertig ist.

**"Keine Array-Disks gefunden"** / **"... ist gleichzeitig Array- und Cache-Pfad"**  
`ARRAY_PATTERN` bzw. `CACHE_PATTERN` prüfen. Die Muster dürfen sich nicht überschneiden.

**"/mnt/user/... fehlt – wird übersprungen"**  
Der Share existiert nicht (Schreibweise?) oder das Array ist nicht gestartet.

**"Logdatei ... kann nicht angelegt werden"**  
Pfad von `LOGFILE` prüfen. Im scharfen Lauf wird der Ordner angelegt; schlägt das fehl, bricht das Script vor dem ersten Move ab.

**Dateien vom Cache tauchen nicht auf ("Cache ignoriert" > 0)**  
Ohne `--include-cache` werden Dateien, die nur auf dem Cache liegen, absichtlich nicht verschoben. Das übernimmt der Unraid-Mover. Bleiben Dateien dauerhaft auf dem Cache, die Cache-Einstellung des Shares (Primary/Secondary Storage, Mover-Richtung) prüfen oder das Script mit `--include-cache` laufen lassen.

- - -

## Weitere Dateien

*   `TESTBERICHT.md`: Befunde und Testergebnisse von V10.2 zu V11.0.
*   `media-disk-gather-v11.0.zip`: Release-Paket V11.0 inkl. Testsuite (`test-suite/`) und Patch `v10.2-to-v11.0.patch`.

- - -

## Haftungsausschluss

Dieses Script manipuliert Dateien (Verschieben/Löschen) auf Systemebene. Obwohl umfangreiche Sicherheitsmechanismen (Dryrun, Space-Check, Duplikat-Prüfung, Root-Protection, Mover-Check) eingebaut sind:

Die Nutzung erfolgt auf eigene Gefahr. Stelle sicher, dass du regelmässige Backups deiner wichtigen Daten hast!

## Lizenz

Copyright (C) 2026 helmi1987

Dieses Programm ist freie Software: Du kannst es unter den Bedingungen der
GNU General Public License, Version 3, wie von der Free Software Foundation
veröffentlicht, weitergeben und/oder verändern.

Es wird in der Hoffnung verbreitet, dass es nützlich ist, aber **ohne jede
Garantie** – sogar ohne die implizite Garantie der Marktreife oder der Eignung
für einen bestimmten Zweck. Details stehen in der Datei [LICENSE](LICENSE)
(GNU GPL v3, SPDX: `GPL-3.0-or-later`).

