#!/usr/bin/env bash
# quit script if any of the commands fails. Note that && commands should be in parentheses for this to work.
set -eo pipefail
trap 'exit_status="$?" && echo Failed on line: $LINENO at command: $BASH_COMMAND && echo "exit status $exit_status"' ERR
today=$(date "+%F")

if [ $# -ne 1 ]
then
    echo "Usage: nohup bash $0 <path to input.tab>   &> spring_wrapper_dec.out &"
    echo "The script expects that it is executed while standing in a directory containing .spring-files"
    echo "The input tab file must be formatted accoring to the input.tab which is created by spring_wrapper.sh. Example:"
    echo "samplename,/realpath/samplename_S10_L001_R1_001.fastq.gz,/realpath/samplename_S10_L001_R2_001.fastq.gz,/realpath/samplename_S10_L001_R1_R2_001.spring"
    exit 1
fi
input_tab="$1"
date
today=$(date "+%F")
pwd

if [ ! -f "$input_tab" ] ; then
    echo "$input.tab does not exist. Please specify the path to the input tab which was created with spring_wrapper.sh"
    exit 1
fi


if [ "$search_here" = "/" ] ; then
    echo "ERROR: Refusing to operate on root directory '/'. Please specify a subdirectory. This script has no power  in root"
    exit 1
fi
echo "spring decompression script for paired illumina data"

# check if spring is in path
if type spring &>/dev/null;then 
    echo "spring is in path and that is good"
else
    echo "spring env spring is not activated. Could not run spring"
    exit 1 
fi

############

# Run spring decompression
echo "spring version"
conda list | grep "spring" || echo "Could not get the spring version, the version will only been seen if the spring installation is in a conda env"
echo ""
mkdir -p spring_restored_files
# spring_name is actually the real path to the to-be spring-file in resultdir.
while IFS="," read -r id fwd rev spring_name; do
    # In this while loop we check that the file is actually possible to extract and get the original md5sum as in the original fastq-file
    echo "This a record in input.tab: $id $fwd $rev $spring_name"
    basename_fastq_gz_fwd=$(basename "$fwd")
    basename_fastq_gz_rev=$(basename "$rev")
    basename_spring_name=$(basename "$spring_name")
    if [ ! -f "$basename_spring_name" ] ; then
        echo "$basename_spring_name does not exist. Please check script. The script should be executed in a directory containing .spring files. You should only have records in the input.tab that are also present as spring in the current directory."
        exit 1
    fi
    echo "spring -d -g -i "$basename_spring_name}" -o "spring_restored_files/${basename_fastq_gz_fwd}" "spring_restored_files/${basename_fastq_gz_rev}""
    spring -d -g -i "$basename_spring_name" -o "spring_restored_files/${basename_fastq_gz_fwd}" "spring_restored_files/${basename_fastq_gz_rev}"
    echo -e "created 
          spring_restored_files/${basename_fastq_gz_fwd} \n
          spring_restored_files/${basename_fastq_gz_rev} \n
          from $basename_spring_name
          "
done < "$input_tab"

echo "--------------------------"

echo "Script finished $(date)"


