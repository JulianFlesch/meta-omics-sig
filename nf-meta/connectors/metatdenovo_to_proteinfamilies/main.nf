nextflow.enable.dsl = 2

// metatdenovo outdir -> one-row nf-core/proteinfamilies samplesheet (sample,fasta).
//
// The conversion is scripts/converters/metatdenovo_to_proteinfamilies.py, staged into the task
// as an input (Nextflow binds only bin/ into containers, so a bin/ symlink would not resolve).
// It finds the protein FASTA for whichever ORF caller ran, refuses transdecoder's .pep.gz and
// more than one FASTA. It only points at a file metatdenovo already published (resolving the
// staged symlink to its real absolute path), so the sheet needs no rewriting afterwards.

include { validateParameters; paramsHelp } from 'plugin/nf-schema'

params.metatdenovo_outdir = null
params.sample             = 'LMO_MT_coassembly'

process METATDENOVO_TO_PROTEINFAMILIES {
    tag "${sample}"
    publishDir params.outdir, mode: 'copy'

    input:
    path converter   // scripts/converters/metatdenovo_to_proteinfamilies.py
    path metatdenovo_outdir, stageAs: 'input_metatdenovo_outdir'
    val sample

    output:
    path 'samplesheet.csv', emit: samplesheet

    script:
    """
    python3 ${converter} \\
        input_metatdenovo_outdir samplesheet.csv --sample '${sample}'
    """

    stub:
    """
    touch samplesheet.csv
    """
}

workflow {
    if (params.help) {
        log.info paramsHelp(command: "nextflow run main.nf --metatdenovo_outdir <dir> --sample LMO --outdir <dir>")
        exit 0
    }
    validateParameters()

    METATDENOVO_TO_PROTEINFAMILIES(
        file("${projectDir}/../../../scripts/converters/metatdenovo_to_proteinfamilies.py", checkIfExists: true),
        file(params.metatdenovo_outdir, type: 'dir', checkIfExists: true),
        params.sample,
    )
}
