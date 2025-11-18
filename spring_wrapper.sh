#!/usr/bin/env bash
# quit script if any of the commands fails. Note that && commands should be in parentheses for this to work.
set -eo pipefail
trap 'exit_status="$?" && echo Failed on line: $LINENO at command: $BASH_COMMAND && echo "exit status $exit_status"' ERR
today=$(date "+%F")

if [ $# -ne 1 ]
then
    echo "Usage: nohup bash $0 <path with paired fastq.gz>  &> spring_wrapper.out &"
    exit 1
fi
search_here="$1"
#cd "$search_here" || exit 1
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
mkdir -p "${search_here}/spring_wrapper_results_logs_${today}"
for i in "${search_here}/"*".fastq.gz";
do
    if [ ! -f "$i" ];then
        echo "Skipping $i because it is not a real file"
        continue
    else
        echo "$i" >> "spring_temp/all_fastq_gz.txt"
    fi
done
#md5sum "${search_here}/"*"fastq.gz"  > "spring_temp/md5sums_spring_wrapper_${today}.txt"

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
  matches=$(ls -1 "${search_here}/${sample_n}"*"fastq.gz" )
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
  spring_n=$(echo "$read1_n"  | sed 's/_R1_/_R1_R2_/g' | sed 's/.fastq.gz/.spring/')
  # extract the realpaths
  read1_n_real_path=$(realpath "${read1_n_path}")
  read2_n_real_path=$(realpath "${read2_n_path}")
  reads_dir=$(realpath $(dirname "${read2_n_real_path}"))
  
  # Create the input.tab file
  echo -e "${sample_n},${read1_n_real_path},${read2_n_real_path},${reads_dir}/${spring_n}" >> "spring_temp/input.tab"
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
# spring_name is actually the real apath to the to-be spring-file in resultdir.
while IFS="," read -r id fwd rev spring_name; do
    # In this while loop we check that the file is actually possible to extract and get the original md5sum as in the original fastq-file
    echo "This a record in input.tab: $id $fwd $rev $spring_name"
    basename_fastq_gz_fwd=$(basename "$fwd")
    basename_fastq_gz_rev=$(basename "$rev")
    basename_spring_name=$(basename "$spring_name")
    gunzip -c "$fwd" | md5sum  > "spring_temp/fwd_md5sum.txt"
    gunzip -c "$rev" | md5sum  > "spring_temp/rev_md5sum.txt"

    echo "spring -c -i "$fwd" "$rev" -t 6 -q lossless -g --output-file "spring_temp/${basename_spring_name}""
    spring -c -i "$fwd" "$rev" -t 6 -q lossless -g --output-file "spring_temp/${basename_spring_name}"
    echo "spring -d -g -i "spring_temp/${basename_spring_name}" -o "spring_temp/${basename_fastq_gz_fwd}" "spring_temp/${basename_fastq_gz_rev}""
    spring -d -g -i "spring_temp/${basename_spring_name}" -o "spring_temp/${basename_fastq_gz_fwd}" "spring_temp/${basename_fastq_gz_rev}"
    gunzip -c "spring_temp/${basename_fastq_gz_fwd}" | md5sum  > "spring_temp/fwd2_md5sum.txt"
    gunzip -c "spring_temp/${basename_fastq_gz_rev}" | md5sum  > "spring_temp/rev2_md5sum.txt"

    # see if the md5sums are the same (of it has succeded)
    # Compare fwd
    if diff <(awk '{print $1}' spring_temp/fwd_md5sum.txt) <(awk '{print $1}' spring_temp/fwd2_md5sum.txt); then
        echo "Forward reads match"
       log1=$( echo "$basename_fastq_gz_fwd" | sed 's/.gz//')
       log2=$(cat "spring_temp/fwd_md5sum.txt")
    else
        echo "Forward reads do NOT match in md5sum!Skipping this fileset"
        continue
    fi

    # Compare rev
    if diff <(awk '{print $1}' spring_temp/rev_md5sum.txt) <(awk '{print $1}' spring_temp/rev2_md5sum.txt); then
        echo "Reverse reads match"
        log3=$( echo "$basename_fastq_gz_rev" | sed 's/.gz//')
        log4=$(cat "spring_temp/rev_md5sum.txt")
    else
        echo "rev reads do NOT match in md5sum! Skipping this fileset"
        continue
    fi
    echo "${log1},${log2}" >> "spring_temp/original_fastq_md5sums.txt"
    echo "${log3},${log4}" >> "spring_temp/original_fastq_md5sums.txt"
    # copy important files
    rsync "spring_temp/${basename_spring_name}" "$spring_name"
    echo "deleting ${fwd} and ${rev}"
    if [ -f "$fwd" ] && [ -f "$rev" ] ; then
        rm "$fwd"  "$rev"
    fi

done < "spring_temp/input.tab"
# copy more things to the results dir
rsync "spring_temp/original_fastq_md5sums.txt" "${search_here}/spring_wrapper_results_logs_${today}/"
rsync "spring_temp/input.tab" "${search_here}/spring_wrapper_results_logs_${today}/"
echo "Script finished $(date)"
rm -r spring_temp
if [ -f "spring_wrapper.out" ];then
    rsync spring_wrapper.out "${search_here}/spring_wrapper_results_logs_${today}/"nohup_${today}.log
fi


