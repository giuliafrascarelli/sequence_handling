#!/bin/env bash

#   This script performs quality trimming
#   on a series of FASTQ samples using sickle and seqqs.
#   Please install these before use.

set -e
set -o pipefail

#   What are the dependencies for Adapter_Trimming?
declare -a Quality_Trimming_Dependencies=(sickle seqqs Rscript)

#   A function that checks the compression of a raw FastQ file and uses seqqs to get quality information
function checkRawCompression() {
    #   Collect arguments
    local sample="$1" # What's the sample?
    local name="$2" # What is the name of the sample?
    local direction="$3" # Which direction is our sample?
    local out="$4" # Where are we storing our results?
    local stats="$5" # Where are the stats from seqqs going?
    #   Create a suffix for the seqqs output
    if [[ "${direction}" == 'forward' ]] # If we're working with forward files
    then
        local suffix='R1' # Use 'R1' as the suffix
    elif [[ "${direction}" == 'reverse' ]] # If we're working with reverse files
    then
        local suffix='R2' # Use 'R2' as the suffix
    else # Assume single end
        local suffix='single' # Use 'single' as the suffix
    fi
    #   Check the compression level, we support gzip and bz2
    if [[ $( echo "${sample}" | rev | cut -f 1 -d '.' | rev) == 'gz' ]] # If gzipped...
    then
        local toTrim="${out}/${name}_${direction}_PIPE" # Create a name for the pipe
        rm -f "${toTrim}" # Remove any existing pipes
        mkfifo "${toTrim}" # Make the pipe
        gzip -cd "${sample}" | seqqs -e -p "${stats}/raw_${name}_${suffix}" - > "${toTrim}" & # Uncompress the file, run seqqs, and write to pipe
    elif [[ $( echo "${sample}" | rev | cut -f 1 -d '.' | rev) == 'bz2' ]] # If bzipped...
    then
        local toTrim="${out}/${name}_${direction}_PIPE" # Create a name for the pipe
        rm -f "${toTrim}" # Remove any existing pipes
        mkfifo "${toTrim}" # Make the pipe
        bzip2 -cd "${sample}" | seqqs -e -p "${stats}/raw_${name}_${suffix}" - > "${toTrim}" & # Uncompress the file, run seqqs, and write to pipe
    else # Otherwise
        local toTrim="${sample}" # Use the name of the sample as 'toTrim'
        seqqs -p "${stats}/raw_${name}_${suffix}" "${toTrim}" # Run seqqs
    fi
    echo "${toTrim}" # Return the name of the pipe or sample
}

#   Export the function
export -f checkRawCompression

#   A function to perform the paired-end trimming and plotting
#       Adapted from Tom Kono and Peter Morrell
function trimAutoplotPaired() {
    #   Set the arguments for trimming
    local sampleName="$1" #   Name of the sample
    local forward="$2" #  Forward file
    local reverse="$3" #  Reverse file
    local out="$4"/"${sampleName}" #  Outdirectory
    local threshold="$5" #    Threshold Value
    local encoding="$6" # Platform for sequencing
    local seqHand="$7" #  The sequence_handling directory
    if [[ -d "${seqHand}"/HelperScripts ]] #   Check to see if helper scripts directory exists
    then
        local helper="${seqHand}"/HelperScripts #   The directory for the helper scripts
    else
        echo "Cannot find directory with helper scripts!"
        exit 1
    fi
    #   Make the out directory
    local stats="${out}"/stats
    local plots="${stats}"/plots
    mkdir -p "${plots}"
    #   Check compression type and run seqqs on raw samples
    local forwardTrim=$(checkRawCompression "${forward}" "${sampleName}" 'forward' "${out}" "${stats}")
    local reverseTrim=$(checkRawCompression "${reverse}" "${sampleName}" 'forward' "${out}" "${stats}")
    # #   Run seqqs on the raw samples
    # seqqs -q "${encoding}" -p "${stats}"/raw_"${sampleName}"_R1 "${forward}"
    # seqqs -q "${encoding}" -p "${stats}"/raw_"${sampleName}"_R2 "${reverse}"
    #   Trim the sequences based on quality
    sickle pe -t "${encoding}" -q "${threshold}" --gzip-output \
        -f "${forwardTrim}" \
        -r "${reverseTrim}" \
        -o "${out}"/"${sampleName}"_R1_trimmed.fastq.gz \
        -p "${out}"/"${sampleName}"_R2_trimmed.fastq.gz \
        -s "${out}"/"${sampleName}"_singles_trimmed.fastq.gz
    #   Run seqqs on the trimmed samples
    gzip -cd "${out}"/"${sampleName}"_R1_trimmed.fastq.gz | seqqs -q "${encoding}" -p "${stats}"/trimmed_"${sampleName}"_R1 -
    gzip -cd "${out}"/"${sampleName}"_R2_trimmed.fastq.gz | seqqs -q "${encoding}" -p "${stats}"/trimmed_"${sampleName}"_R2 -
    # #   Gzip the trimmed files
    # gzip "${out}"/"${sampleName}"_R1_trimmed.fastq
    # gzip "${out}"/"${sampleName}"_R2_trimmed.fastq
    # gzip "${out}"/"${sampleName}"_singles_trimmed.fastq
    #   Fix the quality scores
    "${helper}"/fix_quality.sh "${stats}"/raw_"${sampleName}"_R1_qual.txt
    "${helper}"/fix_quality.sh "${stats}"/raw_"${sampleName}"_R2_qual.txt
    "${helper}"/fix_quality.sh "${stats}"/trimmed_"${sampleName}"_R1_qual.txt
    "${helper}"/fix_quality.sh "${stats}"/trimmed_"${sampleName}"_R2_qual.txt
    #   Make the forward plots
    Rscript "${helper}"/plot_seqqs.R \
    "${stats}/raw_${sampleName}_R1_nucl.txt" "${stats}/raw_${sampleName}_R1_len.txt" "${stats}/raw_${sampleName}_R1_qual.txt_adj" \
    "${stats}/trimmed_${sampleName}_R1_nucl.txt" "${stats}/trimmed_${sampleName}_R1_len.txt" "${stats}/trimmed_${sampleName}_R1_qual.txt_adj" \
    "${sampleName}" "forward"
    #   Make the reverse plots
    Rscript "${helper}"/plot_seqqs.R \
    "${stats}/raw_${sampleName}_R2_nucl.txt" "${stats}/raw_${sampleName}_R2_len.txt" "${stats}/raw_${sampleName}_R2_qual.txt_adj" \
    "${stats}/trimmed_${sampleName}_R2_nucl.txt" "${stats}/trimmed_${sampleName}_R2_len.txt" "${stats}/trimmed_${sampleName}_R2_qual.txt_adj" \
    "${sampleName}" "reverse"
}

#   Export the function
export -f trimAutoplotPaired

#   A function to perform the single-end trimming and plotting
#       Adapted from Tom Kono and Peter Morrell
function trimAutoplotSingle() {
    #   Set the arguments for trimming
    local sampleName="$1" #   Name of the sample
    local single="$2" #  Single file
    local out="$3"/"${sampleName}" #  Outdirectory
    local threshold="$4" #    Threshold Value
    local encoding="$5" # Platform for sequencing
    local seqHand="$6" #  The sequence_handling directory
    if [[ -d "${seqHand}"/HelperScripts ]] #   Check to see if helper scripts directory exists
    then
        local helper="${seqHand}"/HelperScripts #   The directory for the helper scripts
    else
        echo "Cannot find directory with helper scripts!"
        exit 1
    fi
    #   Make the out directories
    local stats="${out}"/stats
    local plots="${stats}"/plots
    mkdir -p "${plots}"
    #   Check compression type and run seqqs on raw samples
    local toTrim=$(checkRawCompression "${single}" "${sampleName}" 'single' "${out}" "${stats}")
    # #   Run seqqs on the raw samples
    # seqqs -q "${encoding}" -p "${stats}"/raw_"${sampleName}"_single "${single}"
    #   Trim the sequences based on quality
    sickle se -t "${encoding}" -q "${threshold}" --gzip-output \
        -f "${toTrim}" \
        -o "${out}"/"${sampleName}"_single_trimmed.fastq.gz \
    #   Run seqqs on the trimmed samples
    gzip -cd "${out}"/"${sampleName}"_single_trimmed.fastq.gz | seqqs -q "${encoding}" -p "${stats}"/trimmed_"${sampleName}"_single -
    # #   Gzip the trimmed files
    # gzip "${out}"/"${sampleName}"_single_trimmed.fastq
    #   Fix the quality scores
    "${helper}"/fix_quality.sh "${stats}"/raw_"${sampleName}"_single_qual.txt
    "${helper}"/fix_quality.sh "${stats}"/trimmed_"${sampleName}"_single_qual.txt
    #   Make the single plots
    Rscript "${helper}"/plot_seqqs.R \
    "${stats}/raw_${sampleName}_single_nucl.txt" "${stats}/raw_${sampleName}_single_len.txt" "${stats}/raw_${sampleName}_single_qual.txt_adj" \
    "${stats}/trimmed_${sampleName}_single_nucl.txt" "${stats}/trimmed_${sampleName}_single_len.txt" "${stats}/trimmed_${sampleName}_single_qual.txt_adj" \
    "${sampleName}" "single"
}

#   Export the function
export -f trimAutoplotSingle

#   A function to run the quality trimming
function Quality_Trimming() {
    local sampleList="$1" #   List of samples
    local forwardNaming="$2" #  Forward naming
    local reverseNaming="$3" #  Reverse naming
    local singleNaming="$4" #  Singles naming
    local outPrefix="$5"/"Quality_Trimming" #  Outdirectory
    local threshold="$6" #  Threshold Value
    local encoding="$7" #  Platform for sequencing
    local seqHand="$8" #  The sequence_handling directory
    #   Create arrays of forward and reverse samples
    local -a forwardSamples=(`grep -E "${forwardNaming}" "${sampleList}"`)
    local -a reverseSamples=(`grep -E "${reverseNaming}" "${sampleList}"`)
    local -a singleSamples=(`grep -E "${singleNaming}" "${sampleList}"`)
    #   Check to see whether we have paired-end or single samples
    if [[ ! -z "${forwardSamples[@]}" && ! -z "${reverseSamples[@]}" ]] # If we have paired-end samples
    then
        # Make sure we have equal numbers of forward and reverse samples
        if [[ "${#forwardSamples[@]}" -ne "${#reverseSamples[@]}" ]] 
            then echo "Unequal numbers of forward and reverse reads." >&2 
            exit 1
        fi 
        #   Create an array of sample names
        declare -a pairedNames=($(parallel basename {} "${forwardNaming}" ::: "${forwardSamples[@]}"))
        #   Run the paired trimmer in parallel
        parallel --xapply trimAutoplotPaired {1} {2} {3} ${outPrefix} ${threshold} ${encoding} ${seqHand} ::: ${pairedNames[@]} ::: ${forwardSamples[@]} ::: ${reverseSamples[@]}
    fi
    if ! [[ -z "${singleSamples[@]}" ]] # If we have single-end samples
    then
        #   Create an array of sample names
        declare -a singleNames=($(parallel basename {} "${singleNaming}" ::: "${singleSamples[@]}"))
        #   Run the single trimmer in parallel
        parallel --xapply trimAutoplotSingle {1} {2} ${outPrefix} ${threshold} ${encoding} ${seqHand} ::: ${singleNames[@]} ::: ${singleSamples[@]}
    fi
    find "${outPrefix}" -type p -exec rm {} \; # Clean up all pipes
}

#   Export the function
export -f Quality_Trimming
