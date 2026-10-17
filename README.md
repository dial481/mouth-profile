# Mouth Profile

Profiles the mouth bacteria in a human whole-genome sequencing (WGS) sample.

A saliva or cheek-swab WGS kit sequences everything in the tube. The reads that don't align to the human genome are mostly the bacteria that were in your mouth. They sit in the BAM as unaligned reads and are usually ignored. `mouth_profile.sh` pulls those read pairs out of the BAM, profiles them with [sylph](https://github.com/bluenote-1577/sylph) against the [GTDB](https://gtdb.ecogenomic.org) database, and writes a plain-text report.

Everything runs on your own computer. The script makes no network connections; the only downloads are the one-time install steps below.

It gives you a snapshot, not a diagnosis.

## Contents

- [What you need](#what-you-need)
- [Install, step by step](#install-step-by-step)
- [Get your data ready](#get-your-data-ready)
- [Run](#run)
- [Reading the report](#reading-the-report)
- [Privacy](#privacy)
- [Troubleshooting](#troubleshooting)
- [Validation](#validation)
- [Limitations](#limitations)
- [Words used here](#words-used-here)
- [Citing](#citing)
- [References](#references)
- [License](#license)

## What you need

- **A computer:** a Mac or a Linux computer, with about 8 GB of RAM. Peak use was 4.2 GB in the eight full-depth test runs where it was measured.
  - On an Apple Silicon Mac with macOS 15 or newer, Homebrew installs sylph ready-made.
  - On an Intel Mac, or on macOS 14, Homebrew builds sylph from source. That should work, but it takes longer and installs the Rust compiler first; it hasn't been tested. On an Intel Mac, conda is the quicker route (see [Other ways to install](#other-ways-to-install)).
- **An internet connection,** for the one-time install. Running the tool needs none.
- **Disk space:**
  - your BAM, typically tens of GB for a 30x genome (and, if you start from a CRAM, room for the BAM made from it)
  - about 25 GB for the tools and the database
  - temporary space while the reads are extracted: up to about 100 bytes per unaligned read, so about 10 GB per 100 million reads. The script checks the free space before it starts and deletes the temporary files when it's done with them.
- **Your genome data:** a paired-end WGS BAM file from a saliva or cheek-swab sample, plus its index. See [Get your data ready](#get-your-data-ready).
- **Time:**
  - the install takes about an hour or a bit more on a 50 Mbit/s connection, most of it the 20 GB database download
  - a run takes from minutes to hours, depending on how many unaligned reads your BAM has

## Install, step by step

These steps are for a Mac. Linux works the same way once Homebrew is installed; see [Other ways to install](#other-ways-to-install).

Each step ends with a check. If a check doesn't give the expected result, stop there and see [Troubleshooting](#troubleshooting).

### 1. Open Terminal

Open **Applications > Utilities > Terminal**. You can also press Cmd-Space, type `Terminal` and press Return. You type (or paste) each command below into this window and press Return.

### 2. Install Homebrew

Homebrew is a free installer for command-line tools. If you already have it, skip to step 3.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

- It first asks for the password of your Mac user account, which must be an administrator account. Nothing shows on screen while you type the password; that's normal.
- Then it explains what it will do and waits for you to press Return.
- If Apple's command-line tools are missing, it installs them too. They include git and Python, which later steps need.
- If it ends with **Next steps**, run the commands it shows. They let Terminal find `brew`.

**Check:** `brew --version` prints a version number.

### 3. Install samtools and sylph

samtools reads BAM files. sylph identifies the bacteria.

```bash
brew install samtools sylph
```

**Check:**
- `samtools --version | head -1` prints a version.
- `sylph --version` prints `sylph 1.0.0` or newer.

### 4. Make a tools folder and add the script

```bash
mkdir -p ~/mouth-tools
```

`~` means your home folder, so this makes a folder called `mouth-tools` there.

Download `mouth_profile.sh` from this repository: on GitHub, open the file and use the download button. It lands in your Downloads folder. Move it into the tools folder:

```bash
mv ~/Downloads/mouth_profile.sh ~/mouth-tools/
```

If macOS asks whether Terminal may access your Downloads folder, click **Allow**.

**Check:** `ls ~/mouth-tools` shows `mouth_profile.sh`.

### 5. Install sylph-tax

sylph-tax turns sylph's genome matches into species names. It isn't on PyPI, so it's installed from GitHub. It goes into its own Python environment (a "venv") inside the tools folder, so nothing is installed system-wide.

```bash
cd ~/mouth-tools
python3 -m venv sylph-venv
sylph-venv/bin/pip install git+https://github.com/bluenote-1577/sylph-tax
```

pip may print a notice that a newer version of pip is available. That's harmless.

**Check:** `~/mouth-tools/sylph-venv/bin/sylph-tax --version` prints a version.

### 6. Download the taxonomy files

These are about 80 MB, in 14 files.

```bash
cd ~/mouth-tools
mkdir -p sylph-taxonomy
sylph-venv/bin/sylph-tax --no-config download --download-to sylph-taxonomy
```

If it stops with an error partway through (for example "Connection reset"), run the last command again.

**Check:** `ls ~/mouth-tools/sylph-taxonomy` lists the files, including `gtdb_r232_metadata.tsv.gz`.

### 7. Download the database

This is the GTDB r232 sylph database: 20 GB, the long download. `caffeinate -i` keeps the Mac awake until it finishes. Keep `-L`: some download mirrors redirect, and without it curl saves a small redirect page instead of the database.

```bash
cd ~/mouth-tools
caffeinate -i curl -L -o gtdb-r232-c200-dbv2.syl2db https://storage.googleapis.com/sylph-stuff/gtdb-r232-c200-dbv2.syl2db
```

If the download is interrupted, resume it instead of starting over. The `-C -` tells curl to continue where it left off:

```bash
cd ~/mouth-tools
caffeinate -i curl -L -C - -o gtdb-r232-c200-dbv2.syl2db https://storage.googleapis.com/sylph-stuff/gtdb-r232-c200-dbv2.syl2db
```

**Check:** `ls -l ~/mouth-tools/gtdb-r232-c200-dbv2.syl2db` shows `20044737329` bytes.

### Done

`~/mouth-tools` now holds:
- `mouth_profile.sh`
- the `sylph-venv` folder
- the `sylph-taxonomy` folder
- `gtdb-r232-c200-dbv2.syl2db`

### Other ways to install

- **conda:** `conda install -c conda-forge -c bioconda samtools sylph sylph-tax` replaces steps 2, 3 and 5. If you installed into a named conda environment, activate it first (`conda activate NAME`) in every new Terminal window. In step 6, use `sylph-tax` without the `sylph-venv/bin/` part. When you run the script, leave out `--sylph-tax`.
- **Linux:** install Homebrew's prerequisites first. On Debian or Ubuntu, run `sudo apt-get install build-essential procps curl file git python3-venv`. Then follow steps 2 to 7, leaving out `caffeinate -i`. Homebrew installs sylph ready-made on Linux.
- **Other systems:** see [sylph's install instructions](https://github.com/bluenote-1577/sylph).
- **A space in a folder path:** the venv's `sylph-tax` command fails with "bad interpreter". Run it as `sylph-venv/bin/python sylph-venv/bin/sylph-tax ...` instead. The script works around this on its own.

## Get your data ready

### 1. Put your files in one folder

From your sequencing provider, download the **BAM** file and its **index**, a small file ending in `.bai` (sometimes `.csi`). Put both in one folder of their own:

```bash
mkdir -p ~/genome
mv ~/Downloads/YOUR.bam ~/Downloads/YOUR.bam.bai ~/genome/
cd ~/genome
ls
```

- **Use your real file names.** `YOUR.bam` stands for your file's actual name, here and in the commands below. The index may be named `YOUR.bai` or `YOUR.bam.csi` instead; use its real name too. `ls` shows what's in the folder.
- **The folder must contain exactly one BAM.**
- **If your files are somewhere else,** such as an external drive, type `cd ` (with a space) in Terminal and drag the folder from Finder onto the window. That fills in its path, with any spaces escaped. Press Return.

### 2. Check it's the right kind of sample

The sample should come from saliva or a cheek swab. A blood sample contains few mouth bacteria.

### 3. If you have a CRAM instead of a BAM, convert it

samtools needs the reference FASTA that the CRAM was made with; your provider names it.

```bash
samtools view -b -T reference.fa -o YOUR.bam YOUR.cram
```

Then make the index in step 4.

### 4. If there's no index, make one

```bash
samtools index YOUR.bam
```

This reads the whole BAM, so it can take a while.

### 5. Check that the unaligned reads are still there

Most pipelines keep the unaligned reads in the BAM, but some remove them to save space.

```bash
samtools idxstats YOUR.bam | tail -1
```

The last line starts with `*`, and its last number is the count of unaligned reads. For example, `*  0  0  48213377` means 48,213,377 unaligned reads. If the count is 0, this tool has nothing to work with.

## Run

Go to the folder with your BAM, then run the script:

```bash
cd ~/genome
caffeinate -i bash ~/mouth-tools/mouth_profile.sh \
  --db ~/mouth-tools/gtdb-r232-c200-dbv2.syl2db \
  --taxdir ~/mouth-tools/sylph-taxonomy \
  --sylph-tax ~/mouth-tools/sylph-venv/bin/sylph-tax
```

On Linux, leave out `caffeinate -i`.

### While it runs

- **Long quiet spell:** after "extracting pairs ...", it can be quiet for a long time while it reads the BAM. That's normal.
- **Keep the Terminal window open:** closing it stops the run.
- **Keep the Mac awake:** `caffeinate -i` stops the Mac from going to sleep on its own, but closing the lid still puts it to sleep. Keep the lid open, and plug in a laptop. If the Mac does sleep, the run pauses and carries on when it wakes.
- **Finished:** the run is done when the last line starts with `Report: mouth_report.txt`. To read the report, run `open mouth_report.txt` (on Linux, `less mouth_report.txt`).
- **Stopped with an error:** a run that fails ends with a line starting `[STOP]`. Look up the message in [Troubleshooting](#troubleshooting).

The script writes two things into your genome folder:

- `mouth_report.txt`: the report. It's also printed to the screen.
- `mouth_work/`: the sylph sketch of the reads (a compact summary of them), the sylph profile and the taxonomy profile.

### Running it again

A second run reuses the sketch in `mouth_work/`, so it takes about a minute instead of redoing the extraction. The script rebuilds the sketch by itself if the BAM in the folder or the `--fraction` setting has changed, or if the record that ties the sketch to the BAM is missing. Add `--redo` to rebuild it anyway.

### Options

| Option | What it does |
|---|---|
| `--db FILE` | the sylph database (required) |
| `--taxdir DIR` | the sylph-tax taxonomy folder (required) |
| `--sylph-tax FILE` | the sylph-tax program; default: the one on your PATH |
| `--taxonomy NAME` | sylph-tax taxonomy name; default: worked out from the database file name, e.g. `GTDB_r232` |
| `--fraction F` | use only this fraction of the unaligned pairs, from `0.0001` to `1`, e.g. `0.25`, for a quick or low-disk run. `1` means all of them. |
| `--threads N` | threads; default: all cores |
| `--redo` | re-extract and re-sketch even if a matching sketch exists |
| `--keep-fastq` | keep the extracted FASTQ files instead of deleting them. They are raw reads, including some human DNA, so keep them private. |
| `-h`, `--help` | show the built-in help |

## Reading the report

The report starts with the tool versions and the number of unaligned reads, then has four numbered sections.

1. **Unaligned read pairs:** how many reads were extracted, and how many were left out because their mate was missing. On a repeat run, this section says the saved sketch was reused instead.
2. **Profile:** the database the reads were matched against.
3. **What is there:**
   - **Species count and Shannon diversity.** Shannon diversity is higher when there are more species in more even amounts. The three full-depth saliva and tongue samples in the tests ranged from about 2.1 to 4.7. With fewer reads, fewer species are found and the value drops.
   - **Detection floor.** How common a bacterium must be to be found reliably with this many reads (see [How the floor is worked out](#how-the-floor-is-worked-out)).
   - **Top genera and top species,** as shares of the bacteria found. The genus totals are the steadier numbers. Close relatives, such as the many *Streptococcus* species, can trade places between runs.
4. **Species linked to gum disease or tooth decay** ("section 4"), with each one's share or "not detected".

Excerpt from a public saliva sample (ENA DRR658765, 11.8 M reads):

```
  species detected: 280; Shannon diversity 4.40 (higher means more even and diverse)
  detection floor: about 0.028% (in tests, every genus and every section 4 species above
    the floor was found; below it, some are found and some are missed)

  Top genera (% of the bacteria found):
     27.73%  Streptococcus
     15.32%  Rothia
      8.88%  Pauljensenia
  ...
  gum disease, "red complex"
    Porphyromonas gingivalis                   2.332%
    Tannerella forsythia                       2.023%
    Treponema denticola                        0.837%
```

**Species names** follow GTDB, which renamed or split some familiar species (see [Limitations](#limitations)). Suffixes such as `_A` mark sub-groups of one classic species.

### The section 4 list

| Group | Species |
|---|---|
| gum disease, "red complex" | *Porphyromonas gingivalis*, *Tannerella forsythia*, *Treponema denticola* |
| gum disease, other | *Aggregatibacter actinomycetemcomitans*, *Filifactor alocis*, *Porphyromonas endodontalis*, *Prevotella intermedia*, *Parvimonas micra*, *Campylobacter rectus*, *Treponema socranskii*, *Selenomonas sputigena*, *Fusobacterium nucleatum*, *F. animalis*, *F. polymorphum*, *F. vincentii* |
| tooth decay | *Streptococcus mutans*, *Streptococcus sobrinus*, *Scardovia wiggsiae* |

Where each comes from:

| Source | Species |
|---|---|
| Socransky et al. 1998, the plaque "complexes" | the red complex, plus *P. intermedia*, *P. micra*, *C. rectus* and the *Fusobacterium nucleatum* group |
| Pérez-Chaparro et al. 2014, a systematic review of newer periodontal pathogens | *F. alocis*, *P. endodontalis*, *S. sputigena* |
| Takeuchi et al. 2001, a study of periodontitis patients' plaque and saliva | *T. socranskii* |
| Könönen and Müller 2014, a review of the microbiology of aggressive periodontitis | *A. actinomycetemcomitans* |
| Loesche 1986, a review of *S. mutans* and tooth decay | *S. mutans*, *S. sobrinus* |
| Tanner et al. 2011, a study of severe early childhood caries | *S. wiggsiae* |

These are research associations, not a diagnosis. Several of these species are normal at low levels in healthy mouths; what matters is how much, together with a dental exam.

### How the floor is worked out

In sylph's output, each bacterium's share is its read coverage divided by the summed coverage of everything found. That means a bacterium at a given coverage shows up at a predictable share. The floor is the share that 0.2x coverage works out to.

The 0.2x was chosen on dilution series of a mock community and one saliva sample (see [Validation](#validation)). A first try at 0.1x missed 5 genera and 1 section 4 species, all less than twice that floor. The 0.2x threshold was then checked on two mouth samples that played no part in choosing it.

The floor is not a hard cutoff:

- Some bacteria below it are found too.
- The closest calls sit just under it. In the calibration saliva series, one genus at 0.96x the floor was missed; in the held-out samples, the largest misses were at 0.83x and 0.77x of the floor.

On a thin sample (floor above 0.1%), the report warns that low-level species, including the gum-disease ones, can be missed. With almost no bacterial reads (floor 50% or more), it says so instead of printing a floor.

## Privacy

- **The report** (`mouth_report.txt`) contains no read names, sample names, or names of your files or folders when the run finishes normally. If a run stops with an error, the message from the failing tool is included, and that can contain a path.
- **`mouth_work/`** holds the sketch: hashed fragments of the unaligned reads. Those reads can include some human DNA that failed to align. Keep this folder private.
  - Next to the sketch, `sketch_source.txt` records the BAM's size and unaligned-read count. The script uses that record to tell whether the sketch matches the BAM; it has no names in it.
  - With `--keep-fastq`, this folder also keeps the raw reads.
- **The script never sends anything anywhere.**

Don't put your BAM, `mouth_work/` or reports in a public repository.

## Troubleshooting

| Message or problem | What to do |
|---|---|
| `command not found: brew` | Homebrew isn't on your PATH yet. On an Apple Silicon Mac, run `echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile` and then `eval "$(/opt/homebrew/bin/brew shellenv)"`. These are the commands Homebrew shows under **Next steps** in [step 2](#2-install-homebrew). |
| `samtools not found` / `sylph not found` | Do [step 3](#3-install-samtools-and-sylph). |
| `need --db FILE and --taxdir DIR` | Give both options; see [Run](#run). |
| `database not found` | Check the `--db` path; see [step 7](#7-download-the-database). |
| `taxonomy folder not found` | Check the `--taxdir` path, and that [step 6](#6-download-the-taxonomy-files) finished. |
| `the database file (N bytes) is a web page` | The download saved a redirect notice instead of the database. Delete the file and download again with `curl -L`. |
| `the database file is only N bytes` | The download is incomplete. Resume it as shown in [step 7](#7-download-the-database). |
| `a .syl2db database needs sylph 1.0 or newer` | Update sylph: `brew upgrade sylph` (with conda: `conda update sylph`). |
| `cannot tell the GTDB release from the database name` | The database file was renamed. Add `--taxonomy GTDB_r232`. |
| `sylph-tax not found` / `sylph-tax does not run` | Point `--sylph-tax` at `~/mouth-tools/sylph-venv/bin/sylph-tax`, or redo [step 5](#5-install-sylph-tax). |
| `bad interpreter` when running sylph-tax yourself | The folder path contains a space; see [Other ways to install](#other-ways-to-install). |
| `need exactly one BAM in this folder` | Run the script in the folder with your genome's BAM, and move any other BAMs out. |
| `the BAM has no index` | Run `samtools index YOUR.bam`. |
| `too few unaligned read pairs to profile` | The BAM has few or no unaligned reads; see [Get your data ready](#get-your-data-ready). |
| `about N GB of free space needed` | Free some space, or use `--fraction 0.25`. |
| `[WARN] more than 5% of reads had no mate` | Some mates are missing from the BAM. The profile uses the complete pairs. |
| `[WARN] thin sample` | Few bacterial reads, so rarer species can be missed. The floor tells you how rare. |
| `[WARN] very few bacterial reads` | Too few bacterial reads to estimate a floor. Only the most abundant bacteria show up, and the shares are rough. |
| `--fraction must be a number from 0.0001 to 1` | Give the fraction as a decimal, e.g. `0.25` for a quarter. Nothing was changed. |
| `no record of which BAM the sketch in mouth_work/ came from; rebuilding it` | The record next to the sketch is missing, so the script rebuilds the sketch to be safe. Nothing to do. |
| The run seems stuck after "extracting pairs ..." | It's reading the BAM; give it time. See [While it runs](#while-it-runs). |
| The run paused while the Mac slept | Keep the lid open and use `caffeinate -i`; see [While it runs](#while-it-runs). |

## Validation

Everything below used this script on public data, with 2 threads and the database above. Each test's FASTQs were wrapped into an unaligned BAM. The dilution series and the shuffle test below ran the whole script, from BAM extraction to report. The even mock and the plaque samples were re-reported from sketches made by an earlier version with the same extraction code. Re-running gave the same genomes and abundances.

In those wrapped BAMs the two reads of a pair sit next to each other. In a real aligned BAM they are scattered, and the script puts them back together. To test that step, the tongue sample's 6 M reads were shuffled into random order and run again: the profile was identical, with the same 210 species at the same shares.

Further checks:

- **macOS shell tools:** the script was run on Linux under bash 3.2.57 (the version macOS ships) and the BWK awk ("one true awk", which macOS also ships). The reports matched the runs under a current bash.
- **samtools versions:** the tests used samtools 1.21. Version 1.24, Homebrew's current one, prints the same output lines the script reads.
- **Sketch reuse:**
  - A repeat run with the same BAM and `--fraction` reused the sketch; `0.1` and `0.10` count as the same.
  - A changed BAM, a changed `--fraction`, a missing record or `--redo` made it rebuild.
  - So did a run after an interrupted rebuild.
  - An invalid `--fraction` was rejected before anything was touched.

### Mock communities with known composition

Expected values are Zymo's theoretical genome-copy shares for the bacteria. The two yeasts in the mix aren't in GTDB, so they're left out.

**ZymoBIOMICS D6300, even mix** (ENA ERR2984773, 17.6 M reads): all 8 bacteria found, with no other species reported.

| Species | Expected % | Found % |
|---|---:|---:|
| Limosilactobacillus fermentum | 21.8 | 19.4 |
| Staphylococcus aureus | 15.4 | 12.7 |
| Enterococcus faecalis | 14.8 | 14.7 |
| Listeria monocytogenes | 14.1 | 13.6 |
| Bacillus subtilis (GTDB: *Bacillus spizizenii*) | 10.4 | 10.8 |
| Salmonella enterica | 8.8 | 10.2 |
| Escherichia coli (GTDB: placeholder genus G047199115) | 8.6 | 9.7 |
| Pseudomonas aeruginosa | 6.2 | 8.9 |

**ZymoBIOMICS D6310, log mix** (ENA ERR2935805, first 10 M pairs), at four read depths made with `--fraction`:

| Species | Expected % | 20 M reads | 2 M | 200 k | 20 k |
|---|---:|---:|---:|---:|---:|
| *Detection floor* | | *0.036* | *0.35* | *3.0* | *32* |
| Listeria monocytogenes | 94.96 | 94.11 | 94.30 | 95.61 | 94.59 |
| Pseudomonas aeruginosa | 4.21 | 5.12 | 4.98 | 4.39 | 5.41 |
| Bacillus subtilis (GTDB: *B. spizizenii*) | 0.70 | 0.65 | 0.63 | - | - |
| Salmonella enterica | 0.059 | 0.053 | - | - | - |
| Escherichia coli (GTDB placeholder genus) | 0.058 | 0.054 | 0.094 | - | - |
| Limosilactobacillus fermentum | 0.015 | 0.011 | - | - | - |
| Enterococcus faecalis | 0.001 | - | - | - | - |
| Staphylococcus aureus | 0.0001 | - | - | - | - |

At every depth, every species above the floor was found and nothing outside the mix was reported. Some species below the floor were found too. At 2,000 reads (`--fraction 0.0001`) it found only *Listeria*, and the report said there were too few bacterial reads to estimate a floor rather than printing one.

### Detection floor on real mouth samples

Each sample was run at full depth and at 30%, 10%, 3% and 1% of its reads. The full-depth run served as the reference. The test: is every genus, and every section 4 species, that the reference puts above a diluted run's floor still found in that diluted run?

| Sample (ENA) | Role | Reads at full depth | Genera above the floor, found | Section 4 species above the floor, found |
|---|---|---:|---:|---:|
| Saliva (DRR658765) | used to set the floor | 11.8 M | 107 of 107 | 17 of 17 |
| Saliva, care-home resident (DRR502076) | held out | 17.4 M | 48 of 48 | 4 of 4 |
| Tongue, healthy adult (ERR981244, first 3 M pairs) | held out | 6.0 M | 75 of 75 | none above the floor |

Counts are summed over the four diluted depths, where the floor ranged from about 0.08% to 3.8%. At genus level the diluted profiles stayed close to full depth (Bray-Curtis similarity 0.83 to 0.98).

The held-out check of section 4 is thin. The only section 4 species above the floor in those samples were the tooth-decay species *S. mutans* and *Scardovia wiggsiae*; none of the gum-disease species was tested there. For the gum-disease species, the evidence is the calibration saliva sample, which had the red complex and several others.

The species level is less stable. Many mouth species have close relatives in the database, most of all *Streptococcus*. As the read count falls, reads can be credited to a relative instead, so a species "disappears" and a relative "appears" at about the same share. The genus total stays put. That's why the report calls the genus totals steadier. The same can happen at low levels among the four *Fusobacterium* names in section 4, which are close relatives.

### Sample type

Each full-depth profile was compared at genus level with the MetaPhlAn profiles of the Human Microbiome Project metagenomes (690 samples; Human Microbiome Project Consortium 2012; Segata et al. 2012).

- **Score:** the median Bray-Curtis similarity to the HMP samples from each site. n is how many HMP samples that site has.
- **Site names:** cheek = buccal mucosa, gum = attached gingiva, tongue = tongue dorsum, tonsils = palatine tonsils.
- **Genus names:** GTDB genus splits were mapped back to the older names before comparing, for example *Hoylesella* to *Prevotella* and *Schaalia* to *Actinomyces*.

| Sample (ENA) | Reads | Best-matching HMP sites |
|---|---:|---|
| Tongue, healthy adult (ERR981244, first 3 M pairs) | 6.0 M | tonsils 0.59 (n=6), tongue 0.57 (n=128), saliva 0.50 (n=3) |
| Saliva (DRR658765) | 11.8 M | saliva 0.54 (n=3), tonsils 0.49 (n=6), tongue 0.48 (n=128) |
| Saliva, care-home resident (DRR502076) | 17.4 M | cheek 0.62 (n=107), gum 0.59 (n=6), saliva 0.43 (n=3) |

The HMP has only three saliva samples, so the saliva comparison is weak. One saliva sample looked most like a cheek swab, probably because saliva and cheek communities dominated by *Streptococcus* overlap. The script doesn't guess the sample type, and this comparison can't reliably tell spit from cheek.

### Periodontitis plaque (rough check only)

Three public periodontitis plaque samples (DRR033621-23) turned out to be **RNA** (metatranscriptome) data, with only 0.6-1.2 M reads. The script flagged all three as thin samples (floor 1.9-18%) and found only 3-22 species. Those species were still the classic periodontitis set: *Porphyromonas gingivalis* at 47% in one patient, plus *Filifactor alocis*, *Parvimonas micra*, *Peptostreptococcus stomatis* and *Fusobacterium*.

## Limitations

- **Species names follow GTDB, not the older NCBI names.** Some familiar species appear split or renamed:
  - *Hoylesella* and *Segatella* (formerly *Prevotella*)
  - *Schaalia* and *Pauljensenia* (formerly *Actinomyces*)
  - *Bacillus spizizenii*
  - *Fusobacterium nucleatum*, partly split into *F. animalis*, *F. polymorphum* and *F. vincentii*

  Some genera have placeholder names, and some species carry suffixes such as `_A`.
- **Close relatives can trade places.** Within groups such as the *Streptococcus mitis* group, the exact species name is less reliable than the genus total.
- **The sample type matters.** Cheek swab, saliva and plaque carry different communities. Gum-disease species live mainly below the gum line, so a cheek swab can miss them even when they are present in the mouth.
- **Bacteria not in the database can't be found.** Anything less than about 95% similar to every GTDB genome is invisible.
- **This is DNA from one day.** It counts genomes, not activity, and a single sample is a snapshot.
- **The section 4 species are research associations.** Several are normal at low levels in healthy mouths. Pair the report with a dental exam; it doesn't replace one.

## Words used here

- **`~`:** your home folder. `~/mouth-tools` is a folder called `mouth-tools` inside it.
- **PATH:** the list of folders Terminal searches for programs. Homebrew's **Next steps** add its folder to it.
- **BAM:** the file of your sequencing reads, each with where it aligned on the human genome.
- **CRAM:** a smaller, compressed form of a BAM.
- **Index (`.bai`, `.csi`):** a small companion file that lets tools jump around inside the BAM.
- **FASTQ:** a plain file of reads, without alignment information.
- **FASTA:** a plain file of reference sequences, such as the human genome.
- **Read:** one short stretch of sequenced DNA. Paired-end sequencing reads each DNA fragment from both ends, giving two reads called mates.
- **Unaligned reads:** reads that didn't match the human genome. In a saliva or cheek sample, they're mostly bacteria.
- **Coverage:** how many times, on average, each letter of a genome was read. At 0.2x, each letter was read 0.2 times on average, so roughly a fifth of the genome was read at least once.
- **Sketch:** sylph's compact summary of the reads, used to match them against the database.
- **Genus, species:** a genus is a group of closely related species, for example the genus *Streptococcus* and the species *Streptococcus mutans*.
- **GTDB:** the Genome Taxonomy Database, the naming system and genome collection this tool uses.

## Citing

mouth_profile is a wrapper around other tools: samtools extracts the reads, sylph does the profiling and GTDB supplies the taxonomy. If you use the results in published work, please cite them (see [References](#references)):

- samtools: Danecek et al. 2021
- sylph: Shaw and Yu 2025
- GTDB: Parks et al. 2022

## References

- Danecek P, Bonfield JK, Liddle J, et al. Twelve years of SAMtools and BCFtools. *GigaScience* 2021;10(2):giab008. doi:10.1093/gigascience/giab008
- Human Microbiome Project Consortium. Structure, function and diversity of the healthy human microbiome. *Nature* 2012;486(7402):207-214. doi:10.1038/nature11234
- Könönen E, Müller HP. Microbiology of aggressive periodontitis. *Periodontol 2000* 2014;65(1):46-78. doi:10.1111/prd.12016
- Loesche WJ. Role of *Streptococcus mutans* in human dental decay. *Microbiol Rev* 1986;50(4):353-380. doi:10.1128/mr.50.4.353-380.1986
- Parks DH, Chuvochina M, Rinke C, Mussig AJ, Chaumeil PA, Hugenholtz P. GTDB: an ongoing census of bacterial and archaeal diversity through a phylogenetically consistent, rank normalized and complete genome-based taxonomy. *Nucleic Acids Res* 2022;50(D1):D785-D794. doi:10.1093/nar/gkab776
- Pérez-Chaparro PJ, Gonçalves C, Figueiredo LC, et al. Newly identified pathogens associated with periodontitis: a systematic review. *J Dent Res* 2014;93(9):846-858. doi:10.1177/0022034514542468
- Segata N, Waldron L, Ballarini A, Narasimhan V, Jousson O, Huttenhower C. Metagenomic microbial community profiling using unique clade-specific marker genes. *Nat Methods* 2012;9(8):811-814. doi:10.1038/nmeth.2066
- Shaw J, Yu YW. Rapid species-level metagenome profiling and containment estimation with sylph. *Nat Biotechnol* 2025;43(8):1348-1359. doi:10.1038/s41587-024-02412-y
- Socransky SS, Haffajee AD, Cugini MA, Smith C, Kent RL. Microbial complexes in subgingival plaque. *J Clin Periodontol* 1998;25(2):134-144. doi:10.1111/j.1600-051x.1998.tb02419.x
- Takeuchi Y, Umeda M, Sakamoto M, Benno Y, Huang Y, Ishikawa I. *Treponema socranskii*, *Treponema denticola*, and *Porphyromonas gingivalis* are associated with severity of periodontal tissue destruction. *J Periodontol* 2001;72(10):1354-1363. doi:10.1902/jop.2001.72.10.1354
- Tanner AC, Mathney JM, Kent RL, et al. Cultivable anaerobic microbiota of severe early childhood caries. *J Clin Microbiol* 2011;49(4):1464-1474. doi:10.1128/jcm.02427-10

## License

MIT. See [LICENSE](LICENSE).
