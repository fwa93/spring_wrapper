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
search_here_relpath=$(realpath "$search_here")
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
# Validate input directory does not contain spaces
if [[ "$search_here_relpath" =~ [[:space:]] ]]; then
    echo "Error: The specified directory real path contains spaces $search_here_relpath. Please provide a path without spaces."
    exit 1
fi
echo "spring compression script for paired illumina data"
mkdir -p "spring_temp"
mkdir -p "${search_here}/spring_wrapper_results_logs_${today}"

# check if spring is in path
if type spring &>/dev/null;then 
    echo "spring is in path and that is good"
else
    echo "spring env spring is not activated. Can not run spring"
    exit 1 
fi
# check if pigz is in path
if type pigz &>/dev/null;then 
    echo "pigz is in path and that is good"
else
    echo "pigz is not found. Can not run pigz"
    exit 1 
fi

# check size of fastq.gz and spring
du_fastq_gz_before=$(du -h -d 1 -c "${search_here}/"*".fastq.gz"  | tail -n 1) || :
du_spring_before=$(du -h -d 1 -c "${search_here}/"*".spring"  | tail -n 1) || :

for i in "${search_here}/"*".fastq.gz";
do
    if [ ! -f "$i" ];then
        echo "Skipping $i because it is not a real file"
        continue
    else
        echo "$i" >> "spring_temp/all_fastq_gz.txt"
    fi
done
# remove file names from  spring_temp/all_fastq_gz.txt which are not following R1_ R2_ patter
sed -i '/_R1_\|_R2_/!d' "spring_temp/all_fastq_gz.txt"
###########
# generate a tab file
# Make an input.tab file
cat "spring_temp/all_fastq_gz.txt" | sed '/_R2_/d' > "spring_temp/forward_reads.txt"
matches_fastq_gz=$(wc -l "spring_temp/forward_reads.txt")
count_1=$(echo "$matches_fastq_gz" | wc -l)
# If there are more than two hits, then skip the samplename
if [[ "$count_1" -lt 1 ]] ; then
    echo "There were 1 or less fastq.gz files in the search path. Please provide a path with more paired fastq.gz files. exiting script."
    exit 1
fi

while IFS= read -r line; do
  # Get the filename of the forward read (R1)
  read1_n=$(basename "$line")
  # Full path to forward read
  read1_n_path="${search_here}/${read1_n}"
  # Entry name (everything in the filename before "_")
  # ALL FILES MUST HAVE _R1_ and _R2_ even though it is not in the pattern here
  #sample_n=$(echo "$read1_n" | sed -r 's/_\w+_\w+_R[0-9]+_\w+\.fastq\.gz//')
  sample_n=$(echo "$read1_n" | sed -r 's/_\w+\.fastq\.gz//')
  # Investigate if there are more than 2 hits
  matches=$(find "${search_here}" -maxdepth 1 -type f -name "${sample_n}*fastq.gz")
  count=$(echo "$matches" | wc -l)
  # If there are not two hits, then skip the samplename
  if [[ "$count" -ne 2 ]] ; then
      echo "⚠️  $sample_n does not have 2 sequence files (it had $count files). Skipping.."
      echo "$sample_n" >> "spring_temp/failed_sequences.txt"
      continue
  fi
  # Filename of reverse read (R2)
  read2_n=$(echo "$read1_n" | sed 's/_R1_/_R2_/g')
  # Full path to reverse read
  read2_n_path="${search_here}/${read2_n}"
  if [ ! -f "$read2_n_path" ];then
        echo "Skipping $i because $read2_n_path does not exist or is not a file"
        continue
  fi
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
conda list | grep "spring" || echo "Could not get the spring version, the version will only been seen if the spring installation is in a conda env"
echo ""
# spring_name is actually the real apath to the to-be spring-file in resultdir.
while IFS="," read -r id fwd rev spring_name; do
    # In this while loop we check that the file is actually possible to extract and get the original md5sum as in the original fastq-file
    echo "This a record in input.tab: $id $fwd $rev $spring_name"
    basename_fastq_gz_fwd=$(basename "$fwd")
    basename_fastq_gz_rev=$(basename "$rev")
    basename_spring_name=$(basename "$spring_name")
    pigz -c -d "$fwd" | md5sum  > "spring_temp/fwd_md5sum.txt"
    pigz -c -d "$rev" | md5sum  > "spring_temp/rev_md5sum.txt"

    echo "spring -c -i "$fwd" "$rev" -t 6 -q lossless -g --output-file "spring_temp/${basename_spring_name}""
    spring -c -i "$fwd" "$rev" -t 6 -q lossless -g --output-file "spring_temp/${basename_spring_name}"
    echo "spring -d -g -t 4 -i "spring_temp/${basename_spring_name}" -o "spring_temp/${basename_fastq_gz_fwd}" "spring_temp/${basename_fastq_gz_rev}""
    spring -d -g -t 4 -i  "spring_temp/${basename_spring_name}" -o "spring_temp/${basename_fastq_gz_fwd}" "spring_temp/${basename_fastq_gz_rev}"
    pigz -c -d "spring_temp/${basename_fastq_gz_fwd}" | md5sum  > "spring_temp/fwd2_md5sum.txt"
    pigz -c -d "spring_temp/${basename_fastq_gz_rev}" | md5sum  > "spring_temp/rev2_md5sum.txt"

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
    if [ -f "$fwd" ] && [ -f "$rev" ] && [ -f "$spring_name" ]  && [ -s "$spring_name" ] ; then
        echo "deleting ${fwd} and ${rev} because $spring_name has been created."
        rm "$fwd"  "$rev"
    fi

done < "spring_temp/input.tab"
# copy more things to the results dir
rsync "spring_temp/original_fastq_md5sums.txt" "${search_here}/spring_wrapper_results_logs_${today}/"
rsync "spring_temp/input.tab" "${search_here}/spring_wrapper_results_logs_${today}/"
rm -r spring_temp

# disc usage
du_fastq_gz_after=$(du -h -d 1 -c "${search_here}/"*".fastq.gz" | tail -n 1) || :
du_spring_after=$(du -h -d 1 -c "${search_here}/"*".spring"  | tail -n 1) || :

echo "--------------------------"
echo "Disc usage of .fastq.gz before and after"
echo "fastq.gz before: $du_fastq_gz_before"
echo "fastq.gz after $du_fastq_gz_after"
echo "--------------------"
echo "Disc usage of .spring before and after"
echo "spring before: $du_spring_before"
echo "spring after: $du_spring_after"
echo "--------------------------"

echo "Script finished $(date)"

if [ -f "spring_wrapper.out" ];then
    rsync --remove-source-files spring_wrapper.out "${search_here}/spring_wrapper_results_logs_${today}/"nohup_${today}.log
fi


