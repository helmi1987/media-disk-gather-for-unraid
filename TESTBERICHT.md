# Testbericht: media-disk-gather-for-unraid (V10.2 → V11.0)

Repo: https://github.com/helmi1987/media-disk-gather-for-unraid (Stand 8444f47 «Update README»)
Getestet: `consolidate_master.sh`, `setup_consolidate.sh`, README — 17.9.2026

## Vorgehen

Statische Analyse (`bash -n`, shellcheck 0.9), dann Funktionstests in einer simulierten Unraid-Umgebung: vier physische «Disks» (`/mnt/disk1`, `/mnt/disk2`, `/mnt/disk10`, `/mnt/cache`) auf ext4 und ein mergerfs-Union als `/mnt/user` in shfs-Reihenfolge (Cache zuerst). Darauf 17 Film-/Serien-Szenarien (Sidecars auf anderer Disk, identische und ungleiche Duplikate, Cache-only-Ordner, disk1/disk10, Exclude-Datei, Sonderzeichen, verschachtelte leere Ordner, Rechte `nobody:users`), dazu Randfälle (volle Disk, rsync-Fehler, nicht löschbarer Ordner, ungültige Konfiguration, fehlendes Log-Verzeichnis) und eine Laufzeitmessung mit 5'000 bis 100'000 Dateien. Alles ist als wiederholbare Testsuite beigelegt (`test-suite/`), die gegen das Original und die korrigierte Version lief.

Ergebnis: Original 13 von 31 Tests bestanden, korrigierte Version 31 von 31. Die 18 Fehlschläge des Originals gehen auf die Befunde unten zurück.

## Befunde

Schweregrad: **K** = Datenverlust möglich, **H** = falsches Ergebnis / Hänger, **M** = Robustheit, **N** = kosmetisch.

| Nr | S | Befund (reproduziert) | Ursache | Behebung in V11 |
|---|---|---|---|---|
| 1 | K | Vollständige 8-MB-Kopie auf disk1 wurde gelöscht, 1-MB-Fragment auf disk2 blieb («Foxtrot»). Gleicher Mechanismus: vollständige Cache-Kopie gelöscht, verkürzte Array-Kopie blieb («Quebec»). | Gewichtung nimmt für alle Kopien die Grösse aus `/mnt/user` (Grössenunterschiede unsichtbar); bei Gleichstand gewinnt die Reihenfolge von `${!disk_tally[@]}` (Hash, nicht Inhalt); `rm -f` ohne jeden Vergleich. | Physische Grösse jeder Kopie; Gleichstand deterministisch (kleinste Disk-Nummer); vor dem Löschen Vergleich (`DUP_CHECK=size` oder `cmp`); ungleiche Kopien werden nie gelöscht, sondern als KONFLIKT gemeldet und geloggt. |
| 2 | K | Gleichnamige Datei in einem tieferen Unterordner (`Filme/Box/Filme/Alpha (2020)/…`, ebenso ein zweiter Share wie `/mnt/user/Backup/Filme`) gilt als Kopie → falsche Ziel-Disk, echte Datei gelöscht. | `get_physical_paths_from_index` matcht per Suffix `*"$rel_path"` statt `<Disk-Root><rel_path>`. | Index im Speicher: rel-Pfad wird je Disk-Root exakt abgeschnitten, Lookup über assoziatives Array. |
| 3 | K | `DRYRUN=1` (oder `y`, `yes`, `ja`) in der ini → «1: command not found» und **scharfer Lauf ohne `--run`** (Dateien wurden tatsächlich verschoben/gelöscht). `DRYRUN=yes` startet den Befehl `yes` → Endlosausgabe. | `if $DRYRUN` führt den Wert als Befehl aus; Setup prüft die Eingabe nicht. | Beide Scripts akzeptieren nur `true`/`false` (Abbruch mit Meldung), Vergleich per `[[ … == true ]]`. |
| 4 | H | Sidecars auf disk10 werden nicht zum Film auf disk1 geholt («Echo»); bei disk1/disk10-Duplikaten bleibt die falsche Kopie. | `"$p" == "$target_disk"*` ohne Slash: `/mnt/disk1` matcht `/mnt/disk10…19`, `/mnt/disk2` matcht `disk20…28`; `"/mnt/disk"*` matcht auch `/mnt/disks` (Unassigned Devices). | Disk-Root wird pro Datei aus dem Index geführt und exakt verglichen; Standardmuster `/mnt/disk[0-9]*`. |
| 5 | H | Deep Clean läuft endlos, sobald ein leerer Ordner nicht löschbar ist (Mountpoint, immutable, Disk nach XFS-Fehler read-only): 713 Durchgänge in 20 s. | Schleife zählt gefundene statt gelöschte Ordner (`rmdir … 2>/dev/null` wird nicht ausgewertet). | Nur erfolgreiche `rmdir` zählen; Fehlschläge einmal melden, loggen, überspringen. |
| 6 | H | Neu angelegte Zielordner sind `root:root 0755` statt wie die Quelle `nobody:users 0777` («Show One/Season 02») → Docker-Container (99:100) und SMB-User können dort nicht mehr schreiben. | `mkdir -p` ohne Übernahme der Attribute. | Ordnerkette wird mit `chown/chmod --reference` des Quellordners angelegt. |
| 7 | H | `--include-cache` holt Ordner, die **nur** auf dem Cache liegen, nicht («Delta»), zählt sie auch nicht («Cache ignoriert: 0»); README verspricht «alles zum Array schieben». | Ohne Array-Tally ist `target_disk` leer → stiller `return`. | Option `CACHE_ONLY_TARGET=most-free` (Array-Disk mit meistem Platz) oder `skip` (zählen, liegen lassen). |
| 8 | H | Laufzeit: 5'000 Dateien 83 s, 10'000 172 s, 20'000 373 s, überlinear – eine reale Bibliothek mit 100'000 Dateien läge bei Stunden. | Pro Datei 2× `grep` über den ganzen Index plus mehrere Subshells (`stat`, `cut`, `basename`, `df`). | Index einmalig per `find -printf` in assoziative Arrays; keine Forks pro Datei. Neu: 5'000 → 2.3 s, 20'000 → 9 s, 100'000 → 44 s. |
| 9 | M | Scharfer Modus: Moves, die an `MIN_FREE_GB` scheitern, erscheinen weder auf der Konsole noch im Log (nur «FEHLGESCHLAGEN: 8»). rsync-Fehler werden trotzdem als «Verschoben» gezählt. Exit-Code immer 0. | Konsolenausgabe nur `if $DRYRUN`; `SUMMARY_MOVED` wird vor dem rsync gefüllt. | Zähler erst nach Erfolg; eigene Zähler für voll/rsync/Konflikt/rmdir; Logzeilen; Exit-Code 0/1/2. |
| 10 | M | Setup schreibt `consolidate.ini` ins **aktuelle** Verzeichnis, der Master liest sie **neben dem Script** → aus anderem Ordner gestartet läuft der Master mit Standardwerten. | `INI_FILE="consolidate.ini"` vs. `$SCRIPT_DIR/consolidate.ini`. | Setup verwendet ebenfalls `SCRIPT_DIR`. |
| 11 | M | Setup: `/mnt/user/Meine Filme` wird zu zwei Einträgen; `256GB` als Freiplatz → Arithmetikfehler im Master; leere Eingaben werden akzeptiert; `read` ohne `-r`. | Keine Validierung, Array unquoted geschrieben. | Pfade mit `;` trennen, Einträge einzeln gequotet; Prüffunktionen mit Wiederholung; `read -r`. |
| 12 | M | Exclude-Datei: Ordner-Einträge sind wirkungslos («Hotel»-nfo wurde trotz Ordner in der Liste verschoben). | Nur exakte Dateipfad-Treffer. | Ordner-Einträge (existierendes Verzeichnis oder `/` am Ende) wirken als Präfix. |
| 13 | M | Fehlendes Log-Verzeichnis im scharfen Modus: 25× «No such file or directory», Lauf ohne Protokoll. | Log-Pfad wird nie geprüft/angelegt. | Ordner wird angelegt, sonst Abbruch vor dem ersten Move. |
| 14 | M | Kein Schutz gegen Parallelstart (User-Scripts-Cron + manuell) und keine Erkennung des Unraid-Movers (Mover kopiert gerade → Script sieht zwei Kopien und löscht/verschiebt). Fester Index-Dateiname `/tmp/consolidate_file_index.txt`. | – | `flock`; Mover-Pidfile/`pgrep` → scharfer Lauf bricht ab, Dryrun warnt; Index nur im Speicher. |
| 15 | M | Dryrun zeigt im Deep Clean nur die unterste Ebene (2 statt 15 Ordner) und rechnet geplante Moves nicht in den Platz-Check ein. | Dryrun stoppt nach Durchgang 1; `df` sieht geplante Moves nicht. | Simulation über eine «weg»-Menge (geplant verschobene/gelöschte Dateien); reservierter Platz je Disk im Dryrun. |
| 16 | N | Retry-Queue trennt mit `\|` → Pfad mit `\|` bricht. Unbenutzte Funktionen `log_always`, `log_verbose`. shellcheck: SC2155 (13×), SC2086, SC2162 (7×). Unbekannte Argumente (`--rnu`) werden still ignoriert; kein `--dryrun`, um `DRYRUN=false` zu übersteuern. | – | Drei Arrays statt Trennzeichen; aufgeräumt, shellcheck sauber; Argumentprüfung, `--dryrun`, `--help`. |

Unverändert (Design, jetzt dokumentiert): lose Dateien direkt im Share-Root werden nie verarbeitet; ein ganzer Serienordner landet auf einer Disk (kein Ausweichen auf die zweitbeste Disk, wenn die Ziel-Disk voll ist).

## Messwerte (Dryrun, je Film 5 Dateien, 1 Move pro Film)

| Dateien | V10.2 | V11.0 |
|---|---|---|
| 5'000 | 82.7 s | 2.3 s |
| 10'000 | 171.9 s | 4.5 s |
| 20'000 | 372.5 s | 9.0 s |
| 100'000 | nicht abgewartet (Trend: Stunden) | 44.4 s |

## Verhaltensänderungen in V11.0, die du kennen solltest

Ungleiche Kopien werden nicht mehr gelöscht, sondern als Konflikt gemeldet (Exit-Code 2) – nach dem ersten Lauf lohnt sich ein Blick auf diese Zeilen. `--include-cache` holt jetzt auch Cache-only-Ordner aufs Array (Disk mit meistem Platz; per `CACHE_ONLY_TARGET=skip` abschaltbar). Ordner-Einträge in der Exclude-Datei wirken jetzt. Das Standardmuster für Array-Disks ist `/mnt/disk[0-9]*`. Der Dryrun schreibt nichts ins Log. Im Setup werden mehrere Shares mit `;` getrennt. Bestehende `consolidate.ini`-Dateien bleiben lesbar (neue Schlüssel sind optional), nur `DRYRUN` muss `true`/`false` sein. Optionen sind per Umgebungsvariable (`CONSOLIDATE_…`) für einen Lauf übersteuerbar; `--help` zeigt alles.

## Grenzen des Tests

Die Union wurde mit mergerfs simuliert, nicht mit Unraids shfs; das Script liest `/mnt/user` in V11 gar nicht mehr für die Dateiliste (nur noch für Exclude-Prüfungen und Existenz der Shares), was diese Abhängigkeit weiter verkleinert. Mover-Erkennung (`/var/run/mover.pid`, `pgrep mover`) und `df --output` wurden mit Attrappen bzw. GNU-coreutils getestet, nicht auf einem echten Unraid. Empfehlung: auf deinem Server zuerst den Dryrun laufen lassen und die Zeilen «KONFLIKT» und «Cache ignoriert» ansehen, bevor `--run` kommt.

## Lieferumfang

`consolidate_master.sh`, `setup_consolidate.sh`, `README.md`, `README.html` (V11.0), `v10.2-to-v11.0.patch` (Diff gegen das Repo), `test-suite/` (Fixture-Generator, Testsuite, Benchmark-Generator, Ergebnisprotokolle beider Versionen). Die Suite braucht root, mergerfs und rsync und legt `/mnt/disk1`, `/mnt/disk2`, `/mnt/disk10`, `/mnt/cache`, `/mnt/user` an – also nicht auf dem Unraid selbst laufen lassen, sondern in einer VM oder einem Container.
