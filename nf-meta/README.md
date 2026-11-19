# nf-meta: the whole chain as one metapipeline

[`metaomics.yaml`](../metaomics.yaml) at the repository root runs the pipeline chain from
[RUNS.md](../RUNS.md) end to end with [nf-meta](https://github.com/bmds-tue/nf-meta), instead of
one pipeline at a time by hand. It uses the same dataset (the 12 LMO pilot runs in
[runs/01_fetchngs/ids.csv](../runs/01_fetchngs/ids.csv)), the same pipeline versions and the
same parameters as the manual runs (`runs/NN_*/params.yml`). The converters in
[scripts/converters/](../scripts/converters/) become pipeline steps.

This is an addition, not a replacement: the manual runs and their Seqera provenance in
[RUNS.md](../RUNS.md) stay the record. The metapipeline is a way to rerun the same chain in one
command and compare its outputs with those runs.

```
r01 fetchngs 1.12.0
 ├─ c01_mt_reads ─────► r02 metatdenovo ─► c02_mt_proteins ─► r03 proteinfamilies ─► r07 proteinannotator
 ├─ c01_mt_detaxizer ─► r04 detaxizer ───────────────────────────────────────────► r09 taxprofiler
 │                        └─► c04_mt_filtered_reads ─► x01 metatdenovo           (not run manually)
 ├─ c01_mg_reads ─────► r05 mag ─────────► c05_mg_proteins ─► r06 proteinfamilies ─► x02 proteinannotator (not run manually)
 └─ c01_amp_reads ────► r08 ampliseq
```

Step ids carry the run numbers from [RUNS.md](../RUNS.md):
- `rNN`: the manual run with that number.
- `cNN`: connectors; `NN` is the run they read from.
- `xNN`: edges that have no manual run to compare against.

## Layout

| Path | What |
|---|---|
| [`../metaomics.yaml`](../metaomics.yaml) | The metapipeline |
| `connectors/<name>/` | One small Nextflow pipeline per converter: `main.nf`, `nextflow.config`, `nextflow_schema.json`, `test/` (nf-test) |
| `connectors/base.config` | Shared by all connectors: nf-schema, profiles, nf-core institutional configs, the `python:3.12-slim` container |
| `connectors/fetch_references/` | Not a step: a standalone pipeline that downloads, verifies and unpacks the reference inputs (see [Reference data](#reference-data)) |
| [`inputs.example.yaml`](inputs.example.yaml) | The reference inputs as laid out by `fetch_references`, for `--inputs-file` |
| `configs/` | Per-step Nextflow configs for the workarounds the manual runs needed (`nf_config:` in the metapipeline) |
| [`run_m3c.sh`](run_m3c.sh) | SLURM head job for the M3C cluster |

The connectors run the converter scripts in `scripts/converters/` unchanged; there is no copy.
Each connector hands its script to the task as an input file, because Nextflow mounts only a
pipeline's own `bin/` into containers. A `bin/` symlink to `scripts/converters/` would not
resolve there.

The connectors add only wiring around the scripts, with one exception. `mag_to_proteinfamilies`
creates the pooled FASTA, and the script records it at its work-directory path. The connector
rewrites that path to the published copy, keeping the script's `\r\n` line endings.

The `configs/` files carry the fixes documented for the manual runs:

| Config | Workaround | Documented in |
|---|---|---|
| `fetchngs.config` | wget 1.18 image for `SRA_FASTQ_FTP` (no `/etc/resolv.conf` in 1.20.1) | [runs/01_fetchngs/README.md](../runs/01_fetchngs/README.md) |
| `ampliseq.config` | pull the Docker image for `FORMAT_TAXONOMY` | [runs/08_ampliseq/README.md](../runs/08_ampliseq/README.md) |
| `proteinannotator.config` | bind the pressed InterProScan `data/` over the container's copy | [runs/07_proteinannotator/README.md](../runs/07_proteinannotator/README.md), [AGENTS.md](../AGENTS.md) |
| `metatdenovo.config` | give `MEGAHIT_INTERLEAVED` CPUs: its only label, `process_high_memory`, sets none, so MEGAHIT ran with `-t 1` | not in run 02's notes; with the same pipeline defaults, it likely also ran on one thread there |
| `global.config` | overwrite reports on resume | [runs/01_fetchngs/README.md](../runs/01_fetchngs/README.md) |

## Run

From the repository root:

```bash
# Read by the Nextflow launcher itself, so a config file can't set them:
export NXF_SYNTAX_PARSER=v1         # fetchngs 1.12.0 and detaxizer 1.3.0 don't parse otherwise
export NXF_OPTS="-Xms2g -Xmx16g"    # r06_proteinfamilies_mg head JVM (proteinfamilies#191)

nf-meta validate metaomics.yaml
nf-meta run metaomics.yaml --dry-run -p m3c --inputs-file lmo-inputs.yaml
nf-meta run metaomics.yaml -p m3c --inputs-file lmo-inputs.yaml -o nf-meta-out
```

`-o` is the run directory: results under `out/<step>/`, the Nextflow work directory, and the
state `--resume` uses. `nf-meta-out/` is gitignored, and so is a `lmo-inputs.yaml` you
keep next to it. Keep both out of commits: they contain absolute paths.

The reference databases the manual runs downloaded by hand are inputs without a default:
`phix_fasta`, `taxprofiler_databases`, `sylph_taxonomy`, `pfam_db`, `funfam_db` and
`interproscan_db`. Their descriptions in `metaomics.yaml` give each one's URL and checksum.
Without `--inputs-file`, nf-meta asks for them.

On M3C, submit [`run_m3c.sh`](run_m3c.sh) instead (edit its paths first).

## Reference data

All six reference inputs, about 46 GB and ~60 GB unpacked, can be fetched with
`connectors/fetch_references`, a standalone Nextflow pipeline:

```bash
nextflow run nf-meta/connectors/fetch_references/main.nf -profile m3c --outdir /shared/meta-omics-refs
sed 's#/refs#/shared/meta-omics-refs#' nf-meta/inputs.example.yaml > lmo-inputs.yaml
```

It reads `assets/references.tsv`: fixed URLs and pinned checksums.

| Reference | Input | Checksum source |
|---|---|---|
| phiX174 NC_001422.1 | `phix_fasta` | sha256 recorded here, two downloads agree |
| Kraken2 PlusPF-16 2026-06-26, sylph GTDB r232 c200 | `taxprofiler_databases` | sha256 recorded here |
| sylph-tax GTDB r232 metadata | `sylph_taxonomy` | md5 from Zenodo |
| Pfam 38.0 | `pfam_db` | md5 from EBI's `md5_checksums` |
| FunFam v4.3.0 | `funfam_db` | sha256 recorded here; byte count = Content-Length, gzip CRC ok |
| InterProScan 5.59-91.0 | `interproscan_db` | md5 from EBI's `.md5` file; sha256 recorded here |

What the pipeline does:
- **Verification:** files are checked while they download. A mismatch fails the task and stores
  nothing.
- **Dropped transfers:** resumed with HTTP Range requests. download.cathdb.info cuts FunFam off
  after a few MB every time.
- **InterProScan:** the release is pressed with its own `setup.py`, inside the container that
  proteinannotator's INTERPROSCAN module uses.
- **Taxprofiler sheet:** `taxprofiler_databases.csv` is written with absolute paths into `--outdir`,
  in the format of [runs/09_taxprofiler/README.md](../runs/09_taxprofiler/README.md).
- **Caching:** outputs are written with Nextflow's `storeDir`, so whatever is already in `--outdir`
  is not downloaded again. Delete `<outdir>/<name>/` to force a fresh download.
- **Provenance:** each reference directory has a `SOURCE.json`. `references.tsv` next to them lists
  every URL, size and checksum, and which checksums were verified.

Files downloaded by hand work just as well. Check them against the checksums in the input
descriptions.

References this metapipeline does not pin:
- **NMPFams and metagRoot:** proteinannotator downloads these itself from unversioned "latest"
  links, as in run 07. The files are at
  `https://pavlopoulos-lab.org/envofams/databases/hmmer/{nmpfamsdb,metagroot}.hmm.gz`. To pin
  them, add rows to `references.tsv` and pass them as `nmpfams_db` / `metagroot_db`.
- **BUSCO lineages** (r05 mag): fetched by BUSCO at run time.

## Tests

From a connector's folder: `nf-test test test/main.nf.test`.

- **Converters:** every test checks that the connector's output is **byte-identical to calling
  the script in `scripts/converters/` directly** on the same input.
- **fetchngs fixture:** a fetchngs 1.12.0-shaped samplesheet built from the real ENA metadata of
  the 12 runs (`test/make_testdata.py`). It reproduces the sample names and sheets documented in
  `runs/` for runs 02, 04, 05 and 08.
- **fetch_references:** tested with `file://` fixtures. `bin/fetch_reference.py --selftest`
  covers dropped transfers, Range resumes and checksum failures against a local HTTP server.

The converters' own `--selftest` still applies, as described in [Home.md](../Home.md).

## Pinning the connectors

The connectors are local pipelines in `metaomics.yaml` (`path: nf-meta/connectors/<name>`).
`nf-meta validate` flags these as not reproducible, because they depend on this checkout. For a
shared run, push, then replace each `path:` with the commit:

```yaml
    url: https://github.com/JulianFlesch/meta-omics-sig
    version: <full 40-character commit hash>
    main_script: nf-meta/connectors/<name>/main.nf
```

With `-main-script`, Nextflow (checked on 26.10) uses the `nextflow.config`, `bin/` and
`projectDir` next to that script, not those at the repository root. nf-meta looks for
`nextflow_schema.json` next to the script too. Nextflow clones the whole repository, so the
connectors still find `scripts/converters/`.

## Comparing with the manual runs: expected differences

- **Absolute paths** in samplesheets depend on the launch directory.
- **Pooled FASTA bytes:** gzip writes a timestamp into its header, so compare
  `LMO_MG_pooled.faa.gz` decompressed.
- **Thread counts:** MEGAHIT and mmseqs results can depend on them. Resource configs are site
  configs, not part of this metapipeline.
- **Read order in the co-assembly:** metatdenovo 1.4.0 passes the six libraries to MEGAHIT in
  the order they arrive, which differs between runs.
- **Reference numbers** to compare against, from [RUNS.md](../RUNS.md):
  - r02: 198,252 proteins
  - r03: 405 families
  - r05: 160 bins and 2,513,059 proteins
  - c05: 1,073,177 IDs recurring across samples before prefixing
  - r06: 5,864 families
  - r08: 1,755 ASVs
  - r04: 172 phiX pairs out of 161,043,840
