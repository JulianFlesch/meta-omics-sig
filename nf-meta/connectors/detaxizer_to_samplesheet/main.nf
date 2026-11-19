nextflow.enable.dsl = 2

// detaxizer outdir -> sample,fastq_1,fastq_2 samplesheet of the filtered reads, for the
// pipelines detaxizer 1.3.0's --generate_pipeline_samplesheets cannot target (metatdenovo,
// ampliseq, viralmetagenome).
//
// The conversion is scripts/converters/detaxizer_to_reads_samplesheet.py, staged into the task
// as an input (Nextflow binds only bin/ into containers, so a bin/ symlink would not resolve).
// It reads filter/filtered/ (seqkit and bbmap naming), never filter/removed/, and refuses
// orphaned mates. It only points at files detaxizer already published, so no rewriting is
// needed.

include { validateParameters; paramsHelp } from 'plugin/nf-schema'

params.detaxizer_outdir = null

process DETAXIZER_TO_SAMPLESHEET {
    publishDir params.outdir, mode: 'copy'

    input:
    path converter   // scripts/converters/detaxizer_to_reads_samplesheet.py
    path detaxizer_outdir, stageAs: 'input_detaxizer_outdir'

    output:
    path 'samplesheet.csv', emit: samplesheet

    script:
    """
    python3 ${converter} input_detaxizer_outdir samplesheet.csv
    """

    stub:
    """
    touch samplesheet.csv
    """
}

workflow {
    if (params.help) {
        log.info paramsHelp(command: "nextflow run main.nf --detaxizer_outdir <dir> --outdir <dir>")
        exit 0
    }
    validateParameters()

    DETAXIZER_TO_SAMPLESHEET(
        file("${projectDir}/../../../scripts/converters/detaxizer_to_reads_samplesheet.py", checkIfExists: true),
        file(params.detaxizer_outdir, type: 'dir', checkIfExists: true),
    )
}
