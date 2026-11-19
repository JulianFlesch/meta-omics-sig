nextflow.enable.dsl = 2

// fetchngs samplesheet -> per-layer read samplesheet for metatdenovo / ampliseq (--target
// reads), detaxizer (--target detaxizer) or mag (--target mag).
//
// The conversion itself is scripts/converters/fetchngs_to_reads_samplesheet.py, staged into
// the task as an input (Nextflow binds only bin/ into containers, so a bin/ symlink would not
// resolve); this file only wires it into Nextflow. See that script's docstring for the sample
// renaming (from collection_date, never sample_alias) and the mag-specific group/platform
// columns.

include { validateParameters; paramsHelp } from 'plugin/nf-schema'

params.fetchngs_samplesheet = null
params.strategy             = 'RNA-Seq'
params.target               = 'reads'
params.prefix               = 'LMO'
params.group                = '0'

process FETCHNGS_TO_SAMPLESHEET {
    tag "${strategy} -> ${target}"
    publishDir params.outdir, mode: 'copy'

    input:
    path converter   // scripts/converters/fetchngs_to_reads_samplesheet.py
    // Staged under a fixed name: fetchngs' own output is also called samplesheet.csv,
    // and with the default staging name the script's write to samplesheet.csv would
    // follow the input symlink and overwrite fetchngs' published file.
    path fetchngs_samplesheet, stageAs: 'input_samplesheet.csv'
    val strategy
    val target
    val prefix
    val group

    output:
    path 'samplesheet.csv', emit: samplesheet

    script:
    """
    python3 ${converter} \\
        input_samplesheet.csv samplesheet.csv \\
        --strategy '${strategy}' --target '${target}' --prefix '${prefix}' --group '${group}'
    """

    stub:
    """
    touch samplesheet.csv
    """
}

workflow {
    if (params.help) {
        log.info paramsHelp(command: "nextflow run main.nf --fetchngs_samplesheet <samplesheet.csv> --strategy WGS --target mag --outdir <dir>")
        exit 0
    }
    validateParameters()

    FETCHNGS_TO_SAMPLESHEET(
        file("${projectDir}/../../../scripts/converters/fetchngs_to_reads_samplesheet.py", checkIfExists: true),
        file(params.fetchngs_samplesheet, checkIfExists: true),
        params.strategy,
        params.target,
        params.prefix,
        params.group,
    )
}
