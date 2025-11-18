#!/usr/bin/env bash
# quit script if any of the commands fails. Note that && commands should be in parentheses for this to work.
set -eo pipefail
trap 'exit_status="$?" && echo Failed on line: $LINENO at command: $BASH_COMMAND && echo "exit status $exit_status"' ERR
{
if [ $# -ne 1 ]
then
    echo "Usage: bash $0 <path with paired fastq.gz>"
    exit 1
fi
search_here="$1"
cd "$search_here" || exit 1
date
today=$(date "+%F")
pwd

if [ ! -d "$search_here" ] ; then
    echo "$search_here is not a directory, please specify a directory to search for fastq.gz in."
    exit 1
fi

if [ "$search_here" = "/" ] ; then
    echo "ERROR: Refusing to operate on root directory '/'. Please specify a subdirectory. This script has no power  in root"
    exit 1
fi
echo "spring compression script for paired illumina data"
mkdir -p "spring_temp"
ls -1 *"fastq.gz" > "spring_temp/all_fastq_gz.txt"
md5sum *"fastq.gz" > "${spring_temp}/md5sums_spring_wrapper_${today}.txt"

###########
# generate a tab file
# Make an input.tab file for Nullarbor
cat "spring_temp/all_fastq_gz.txt" | sed '/_R2_/d' > "spring_temp/forward_reads.txt"
while IFS= read -r line; do
  # Get the filename of the forward read (R1)
  read1_n=$(basename "$line")
  # Full path to forward read
  read1_n_path="${search_here}/${read1_n}"
  # Entry name (everything in the filename before "_")
  sample_n=$(echo "$read1_n" | sed -r 's/_\w+_\w+_R[0-9]+_\w+\.fastq\.gz//')
  # Investigate if there are more than 2 hits
  matches=$(ls -1 "${search_here}/${sample_n}"* 2>/dev/null)
  count=$(echo "$matches" | wc -l)
  # If there are more than two hits, then skip the samplename
  if [[ "$count" -ne 2 ]] ; then
      echo "⚠️  $sample_n does not have 2 sequence files (it had $count files). Skipping.."
      echo "$sample_n" >> "spring_temp/failed_sequences.txt"
      continue
  fi
  # Filename of reverse read (R2)
  read2_n=$(echo "$read1_n" | sed 's/_R1_/_R2_/g')
  # Full path to reverse read
  read2_n_path="${search_here}/${read2_n}"
  spring_n=$(echo "$read1_n"  | sed 's/_R1_/_R1_R2_/g')
  # Create the input.tab file
  echo -e "${sample_n},${read1_n_path},${read2_n_path},${spring_n}" >> "${spring_temp}/input.tab"
  echo
done < "spring_temp/forward_reads.txt"

cat "spring_temp/input.tab"
echo
echo "tab file saved here spring_temp/input.tab"


############
# Run spring
echo "spring version"
conda list | grep "spring"
echo ""

while IFS="," read -r id fwd rev spring_name; do
  echo "This a record in input.tab: $id $fwd $rev $spring_name"
  spring -c -i "$fwd" "$rev" -t 6 -q lossless -g --output-file "$spring_name"
done < "spring_temp/input.tab"

cp "${spring_temp}/md5sums_spring_wrapper_${today}.txt"  "${search_here}/md5sums_spring_wrapper_${today}.txt"

} 2>&1 | tee "spring_wrapper_log${today}.log"


