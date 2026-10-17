#!/bin/bash
# SPDX-License-Identifier: MIT
# mouth_profile.sh: profile the bacteria among the read pairs that did not align to the
# human genome. In a saliva or cheek-swab sample, that is the mouth microbiome.
#
#   bash mouth_profile.sh --db FILE --taxdir DIR [options]
#
# Run it in the genome folder (the one with the BAM and its index). Needs samtools,
# sylph 1.0 or newer, and sylph-tax. Writes:
#   mouth_report.txt   the report
#   mouth_work/        the sylph sketch of the reads, the sylph profile, the taxonomy profile
# While it runs it puts the unaligned reads back into pairs and writes them as FASTQ into
# mouth_work/ (up to about 100 bytes per read at the peak; it checks free space first),
# and deletes them when the run ends. Running it again reuses the sketch, unless the BAM
# or --fraction has changed since (then it rebuilds it) or --redo is given.
# The report contains no read names, sample names, or names of your files or folders.
#
# Options:
#   --db FILE          sylph database, e.g. gtdb-r232-c200-dbv2.syl2db
#   --taxdir DIR       folder filled by: sylph-tax --no-config download --download-to DIR
#   --sylph-tax FILE   the sylph-tax program, e.g. a venv's bin/sylph-tax (default: on PATH)
#   --taxonomy NAME    sylph-tax taxonomy name (default: taken from the database file name,
#                      e.g. GTDB_r232)
#   --fraction F       use only this fraction of the unaligned pairs, from 0.0001 to 1,
#                      e.g. 0.25 (default: all)
#   --threads N        threads (default: all cores)
#   --redo             re-extract and re-sketch even if a sketch exists in mouth_work/
#   --keep-fastq       keep the FASTQ files instead of deleting them after sketching
#                      (they are raw reads, including some human DNA; keep them private)
#   -h, --help         this help
#
# What it reports: the most abundant genera and species, how many species, a diversity
# index, the detection floor (how common a bacterium must be to be found reliably with this
# many reads), and a short list of species linked in the research literature to gum disease
# or tooth decay. A one-time sample gives a snapshot, not a diagnosis.

set -u
VERSION="v0.1.0, 2026-10-16"

DB=""; TAXDIR=""; SYLPHTAX=""; TAXNAME=""; FRACTION=""; THREADS=""; REDO=0; KEEP=0; MADE_FASTQ=0
while [ $# -gt 0 ]; do
  case "$1" in
    --db|--taxdir|--sylph-tax|--taxonomy|--fraction|--threads)
      if [ $# -lt 2 ]; then echo "$1 needs a value" >&2; exit 2; fi
      case "$1" in
        --db) DB="$2" ;; --taxdir) TAXDIR="$2" ;; --sylph-tax) SYLPHTAX="$2" ;;
        --taxonomy) TAXNAME="$2" ;; --fraction) FRACTION="$2" ;; --threads) THREADS="$2" ;;
      esac
      shift 2 ;;
    --redo) REDO=1; shift ;;
    --keep-fastq) KEEP=1; shift ;;
    -h|--help) awk 'NR > 2 && /^#/ { sub(/^# ?/, ""); print; next } NR > 2 { exit }' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# Check the required paths before writing anything, so a typo does not wipe an earlier report.
[ -n "$DB" ] && [ -n "$TAXDIR" ] || { echo "need --db FILE and --taxdir DIR (try --help)" >&2; exit 2; }
[ -f "$DB" ] || { echo "database not found: $DB" >&2; exit 2; }
[ -d "$TAXDIR" ] || { echo "taxonomy folder not found: $TAXDIR" >&2; exit 2; }
if [ -n "$FRACTION" ]; then
  awk -v f="$FRACTION" 'BEGIN { exit !(f ~ /^(0*\.[0-9]+|0*1(\.0*)?|\.[0-9]+)$/ && f + 0 >= 0.0001 && f + 0 <= 1) }' \
    || { echo "--fraction must be a number from 0.0001 to 1, e.g. 0.25 (got: $FRACTION)" >&2; exit 2; }
  FRACTION=$(awk -v f="$FRACTION" 'BEGIN { printf "%g", f + 0 }')   # 0.10 and 0.1 are the same
  [ "$FRACTION" = 1 ] && FRACTION=""                                  # 1 means all of them
fi

REPORT="$PWD/mouth_report.txt"
: > "$REPORT" 2>/dev/null || { echo "cannot write mouth_report.txt in this folder" >&2; exit 2; }
W=mouth_work
mkdir -p "$W" || { echo "cannot make $W/" >&2; exit 2; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mouth.XXXXXX") || { echo "cannot make a temp folder" >&2; exit 2; }
cleanup() {
  rm -rf "$TMP"
  rm -f "$W"/collate_tmp*
  # only the FASTQ files this run wrote, so files kept by an earlier --keep-fastq run stay
  if [ "$KEEP" = 0 ] && [ "$MADE_FASTQ" = 1 ]; then rm -f "$W/pairs_R1.fq.gz" "$W/pairs_R2.fq.gz" "$W/pairs_single.fq.gz" "$W/pairs_other.fq.gz"; fi
}
trap cleanup EXIT
trap 'echo; echo "stopped"; exit 130' INT TERM HUP

say()  { printf '%s\n' "$*" | tee -a "$REPORT"; }
sec()  { say ""; say "== $* =="; }
info() { say "  $*"; }
die()  { say "  [STOP] $*"; exit 1; }
# the useful line of a tool's log: a Rust panic message, an error line, or the last line
why()  { awk '/panicked at/ { getline m; print m; f = 1; exit } /[Ee]rror/ && !e { e = $0 } { l = $0 } END { if (!f) print (e != "" ? e : l) }' "$1"; }
num()  { awk -v n="$1" 'BEGIN { s = sprintf("%.0f", n); o = ""; while (length(s) > 3) { o = "," substr(s, length(s) - 2) o; s = substr(s, 1, length(s) - 3) } print s o }'; }

say "mouth_profile $VERSION"
say "Bacteria among the unaligned reads (sylph + GTDB)"

# --- inputs ----------------------------------------------------------------------------
sec "Inputs"
command -v samtools >/dev/null 2>&1 || die "samtools not found."
command -v sylph >/dev/null 2>&1 || die "sylph not found (on a Mac: brew install sylph)."
SYV=$(sylph --version 2>/dev/null | awk '{ print $2 }')
[ -n "$SYLPHTAX" ] || SYLPHTAX=$(command -v sylph-tax 2>/dev/null)
[ -n "$SYLPHTAX" ] && [ -f "$SYLPHTAX" ] || die "sylph-tax not found; give its path with --sylph-tax (for example a venv's bin/sylph-tax)."
# sylph-tax is a Python script whose first line names the venv's python. That line breaks
# when the folder path contains a space, so run it with the python next to it instead.
STX=("$SYLPHTAX")
PYB="$(dirname "$SYLPHTAX")/python"
if [ -x "$PYB" ] && head -1 "$SYLPHTAX" | grep -q '^#!.*python'; then STX=("$PYB" "$SYLPHTAX"); fi
"${STX[@]}" --version >/dev/null 2>&1 || die "sylph-tax does not run: $("${STX[@]}" --version 2>&1 | tail -1)"
[ -n "$DB" ] || die "no database given; use --db FILE (for example gtdb-r232-c200-dbv2.syl2db)."
[ -f "$DB" ] || die "database not found: $DB"
DBSZ=$(wc -c < "$DB" | tr -d ' ')
if head -c 300 "$DB" | grep -qiE '<html|<!doctype|moved permanently'; then
  die "the database file ($DBSZ bytes) is a web page, not a database: the download saved a redirect notice. Delete it and download again with curl -L."
fi
case "$(basename "$DB")" in
  gtdb*) [ "$DBSZ" -lt 100000000 ] && die "the database file is only $DBSZ bytes; a GTDB database is many GB, so the download is incomplete. Resume it with curl -L -C - (see the README)." ;;
esac
case "$DB" in
  *.syl2db) awk -v v="$SYV" 'BEGIN { split(v, x, "."); exit !((x[1] + 0) >= 1) }' || die "a .syl2db database needs sylph 1.0 or newer; this is sylph $SYV." ;;
esac
[ -n "$TAXDIR" ] && [ -d "$TAXDIR" ] || die "taxonomy folder not found; check the --taxdir path (the folder is filled by: sylph-tax --no-config download --download-to DIR)."
if [ -z "$TAXNAME" ]; then
  R=$(basename "$DB" | grep -o 'r2[0-9][0-9]' | head -1)
  [ -n "$R" ] || die "cannot tell the GTDB release from the database name; give it with --taxonomy (for example GTDB_r232)."
  TAXNAME="GTDB_$R"
fi
if [ -z "$THREADS" ]; then THREADS=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4); fi
info "samtools $(samtools --version | awk 'NR == 1 { print $2 }'), sylph $SYV, taxonomy $TAXNAME, $THREADS threads"

N=0; BAM=""
for f in *.bam; do [ -f "$f" ] && { N=$((N + 1)); BAM="$f"; }; done
[ "$N" = 1 ] || die "need exactly one BAM in this folder (found $N); run it in the folder with your genome's BAM."
[ -f "$BAM.bai" ] || [ -f "$BAM.csi" ] || [ -f "${BAM%.bam}.bai" ] || [ -f "${BAM%.bam}.csi" ] || die "the BAM has no index; make one with: samtools index YOUR.bam"
UNPLACED=$(samtools idxstats "$BAM" 2>/dev/null | awk -F'\t' '$1 == "*" { print $4 }')
[ -n "$UNPLACED" ] || die "could not read the BAM index."
info "BAM: unplaced unaligned reads $(num "$UNPLACED")"

# --- 1. unaligned pairs -> sketch ------------------------------------------------------
sec "1. Unaligned read pairs"
SKETCH="$W/pairs_R1.fq.gz.paired.sylsp"
# v1/v2 sketch: built before the reads were sorted into pairs, so most pairs were missing
[ -f "$W/unaligned_R1.fq.gz.paired.sylsp" ] && rm -f "$W/unaligned_R1.fq.gz.paired.sylsp" && info "removed an older, incomplete sketch from $W/"
# The sketch is reused only if it was made from this BAM (same size and unaligned-read
# count) with the same --fraction; the record of that sits next to it, without file names.
SRC="$W/sketch_source.txt"
SIG="bam_bytes=$(wc -c < "$BAM" | tr -d ' ') unaligned=$UNPLACED fraction=${FRACTION:-1}"
REBUILD=1
if [ "$REDO" = 0 ] && [ -s "$SKETCH" ]; then
  if [ ! -f "$SRC" ]; then info "no record of which BAM the sketch in $W/ came from; rebuilding it"
  elif [ "$(cat "$SRC")" = "$SIG" ]; then REBUILD=0
  else info "the BAM or --fraction has changed since the sketch in $W/ was made; rebuilding it"; fi
fi
if [ "$REBUILD" = 0 ]; then
  info "using the existing sketch in $W/ (use --redo to rebuild it)"
else
  NEED=$(awk -v n="$UNPLACED" -v f="${FRACTION:-1}" 'BEGIN { printf "%.0f", n * f * 100 / 1024 }')   # KB
  FREE=$(df -k . | awk 'NR == 2 { print $4 }')
  if [ -n "$FREE" ] && [ "$FREE" -lt "$NEED" ]; then
    die "about $(awk -v k="$NEED" 'BEGIN { printf "%.1f", k / 1048576 }') GB of free space needed for the temporary files, $(awk -v k="$FREE" 'BEGIN { printf "%.1f", k / 1048576 }') GB free. Free some space or use --fraction 0.25."
  fi
  rm -f "$SKETCH" "$SRC"
  SUB=""
  if [ -n "$FRACTION" ]; then
    SUB="-s $(awk -v f="$FRACTION" 'BEGIN { printf "%.4f", 42 + f }')"
    info "using a fraction $FRACTION of the pairs (pairs stay together)"
  fi
  info "extracting pairs where neither read aligned (both unmapped) and putting mates back together ..."
  MADE_FASTQ=1
  # In the BAM the two reads of an unaligned pair are usually far apart, so collate them first.
  # shellcheck disable=SC2086
  samtools view -u -@ "$THREADS" -f 12 -F 0x900 $SUB "$BAM" '*' 2>/dev/null \
    | samtools collate -O -u -l 1 -@ "$THREADS" - "$W/collate_tmp" 2> "$TMP/co.log" \
    | samtools fastq -@ "$THREADS" -n -c 1 -1 "$W/pairs_R1.fq.gz" -2 "$W/pairs_R2.fq.gz" \
        -s "$W/pairs_single.fq.gz" -0 "$W/pairs_other.fq.gz" - 2> "$TMP/fq.log" \
    || die "extracting reads failed: $(why "$TMP/fq.log") $(why "$TMP/co.log")"
  NREADS=$(awk '/processed [0-9]+ reads/ { for (i = 1; i <= NF; i++) if ($i == "processed") print $(i + 1) }' "$TMP/fq.log" | tail -1)
  NSING=$(awk '/discarded [0-9]+ singletons/ { for (i = 1; i <= NF; i++) if ($i == "discarded") print $(i + 1) }' "$TMP/fq.log" | tail -1)
  info "reads extracted: $(num "${NREADS:-0}"); reads without their mate, left out: $(num "${NSING:-0}")"
  awk -v n="${NREADS:-0}" -v s="${NSING:-0}" 'BEGIN { exit !(n > 0 && s / n > 0.05) }' \
    && info "[WARN] more than 5% of reads had no mate; the profile uses the paired ones only"
  [ "${NREADS:-0}" -gt 1000 ] || die "too few unaligned read pairs to profile ($(num "${NREADS:-0}") reads). The BAM may have had its unaligned reads removed, or the sample may not be saliva or a cheek swab."
  info "sketching (sylph) ..."
  sylph sketch -1 "$W/pairs_R1.fq.gz" -2 "$W/pairs_R2.fq.gz" -d "$W" -t "$THREADS" > "$TMP/sk.log" 2>&1 \
    || die "sylph sketch failed: $(why "$TMP/sk.log")"
  [ -s "$SKETCH" ] || die "sylph sketch wrote no sketch."
  printf '%s\n' "$SIG" > "$SRC"
  if [ "$KEEP" = 0 ]; then info "sketch written; the temporary FASTQ files will be deleted"; fi
fi

# --- 2. profile ------------------------------------------------------------------------
sec "2. Profile"
info "matching against $(basename "$DB") ..."
sylph profile "$DB" "$SKETCH" -u -t "$THREADS" -o "$W/sylph_profile.tsv" > "$TMP/pr.log" 2>&1 \
  || die "sylph profile failed: $(why "$TMP/pr.log")"
NG=$(awk 'NR > 1' "$W/sylph_profile.tsv" | wc -l | tr -d ' ')
[ "$NG" -gt 0 ] || die "sylph found no genomes from the database in these reads."
rm -f "$W"/tax-*.sylphmpa
"${STX[@]}" --no-config --taxonomy-dir "$TAXDIR" taxprof "$W/sylph_profile.tsv" -t "$TAXNAME" -o "$W/tax-" --overwrite > "$TMP/tx.log" 2>&1 \
  || die "sylph-tax failed: $(why "$TMP/tx.log")"
MPA=""
for f in "$W"/tax-*.sylphmpa; do [ -f "$f" ] && { MPA="$f"; break; }; done
[ -n "$MPA" ] || die "sylph-tax wrote no profile."
info "taxonomy profile: $MPA"

# Species rows: "species <tab> genus <tab> relative abundance (%)". GTDB suffixes such as
# _A or _B (sub-groups of one classic species) are kept in the name but dropped in "key".
awk -F'\t' '$1 ~ /\|s__/ && $1 !~ /\|t__/ {
    n = split($1, t, "|"); sp = substr(t[n], 4); g = ""
    for (i = 1; i <= n; i++) if (substr(t[i], 1, 3) == "g__") g = substr(t[i], 4)
    key = sp; gsub(/_[A-Z]+( |$)/, " ", key); sub(/ +$/, "", key)
    gk = g; sub(/_[A-Z]+$/, "", gk)
    printf "%s\t%s\t%s\t%s\n", sp, gk, $2, key }' "$MPA" > "$TMP/species.tsv"

# --- 3. report -------------------------------------------------------------------------
sec "3. What is there"
awk -F'\t' '{ n++; p = $3 / 100; if (p > 0) H -= p * log(p) }
  END { printf "  species detected: %d; Shannon diversity %.2f (higher means more even and diverse)\n", n, H }' "$TMP/species.tsv" | tee -a "$REPORT"
# Detection floor. A species' share is its coverage divided by the summed coverage of all
# species found, so a bacterium at coverage C shows up at 100 * C / sum %. The floor is the
# share that 0.2x coverage corresponds to, set on dilution series of a public mock community
# and a public saliva sample and checked on two held-out mouth samples (README): every genus,
# and every section 4 species, above the floor was found. Printed to 2 significant figures.
FLOOR=$(awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "True_cov") c = i; next }
  c && $c + 0 > 0 { s += $c }
  END { if (s > 0) { v = sprintf("%.2g", 100 * 0.2 / s) + 0
        e = log(v) / log(10) + 1e-9; fe = (e >= 0 || e == int(e)) ? int(e) : int(e) - 1
        d = 1 - fe; if (d < 0) d = 0; printf ("%." d "f"), v } }' "$W/sylph_profile.tsv")
if [ -n "$FLOOR" ] && awk -v f="$FLOOR" 'BEGIN { exit !(f >= 50) }'; then
  info "[WARN] very few bacterial reads: too few to estimate a detection floor; only the most"
  info "  abundant bacteria can show up, and the shares below are rough"
  FLOOR=""
elif [ -n "$FLOOR" ]; then
  info "detection floor: about ${FLOOR}% (in tests, every genus and every section 4 species above"
  info "  the floor was found; below it, some are found and some are missed)"
  awk -v f="$FLOOR" 'BEGIN { exit !(f > 0.1) }' \
    && info "[WARN] thin sample: few bacterial reads, so bacteria below ${FLOOR}% can be missed," \
    && info "  including the gum-disease species at the low levels they usually have"
fi
say ""
say "  Top genera (% of the bacteria found):"
awk -F'\t' '{ a[$2] += $3 } END { for (g in a) printf "%.2f\t%s\n", a[g], g }' "$TMP/species.tsv" | sort -t"$(printf '\t')" -k1,1gr | head -15 \
  | awk -F'\t' '{ printf "    %6.2f%%  %s\n", $1, $2 }' | tee -a "$REPORT"
say ""
say "  Top species (close relatives, such as the many Streptococcus species, can trade places"
say "  between runs; the genus totals above are steadier):"
sort -t"$(printf '\t')" -k3,3gr "$TMP/species.tsv" | head -25 | awk -F'\t' '{ printf "    %6.2f%%  %s\n", $3, $1 }' | tee -a "$REPORT"

sec "4. Species linked to gum disease or tooth decay"
info "(Research associations, mostly from dental plaque studies, not a diagnosis. Several are"
info "normal at low levels in healthy mouths; what matters is how much, and dental findings.)"
cat > "$TMP/markers.tsv" <<'TSV'
gum disease, "red complex"|Porphyromonas gingivalis
gum disease, "red complex"|Tannerella forsythia
gum disease, "red complex"|Treponema denticola
gum disease, other|Aggregatibacter actinomycetemcomitans
gum disease, other|Filifactor alocis
gum disease, other|Porphyromonas endodontalis
gum disease, other|Prevotella intermedia
gum disease, other|Parvimonas micra
gum disease, other|Campylobacter rectus
gum disease, other|Treponema socranskii
gum disease, other|Selenomonas sputigena
gum disease, other|Fusobacterium nucleatum
gum disease, other|Fusobacterium animalis
gum disease, other|Fusobacterium polymorphum
gum disease, other|Fusobacterium vincentii
tooth decay|Streptococcus mutans
tooth decay|Streptococcus sobrinus
tooth decay|Scardovia wiggsiae
TSV
awk 'FILENAME == ARGV[1] { split($0, a, "\t"); ab[a[4]] += a[3]; next }
  { split($0, m, "|"); g = m[1]; if (g != last) { printf "  %s\n", g; last = g }
    if (m[2] in ab) printf "    %-40s %7.3f%%\n", m[2], ab[m[2]]; else printf "    %-40s not detected\n", m[2] }' \
  "$TMP/species.tsv" "$TMP/markers.tsv" | tee -a "$REPORT"
if [ -n "$FLOOR" ]; then
  info "(\"not detected\": absent, rarer than about ${FLOOR}% (the floor for this many reads), or too"
  info " different from every genome in the database.)"
else
  info "(\"not detected\": absent, too rare for this many reads, or not in the database.)"
fi

say ""
say "Report: mouth_report.txt; full profile: $MPA"
