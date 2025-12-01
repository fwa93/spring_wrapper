search="$1"
# File to grep in 
file_grep="$2"
ls -l "$search"

scriptdir=$(dirname "$(realpath "$0")")
my_grep=$(grep -c "${search}/[^/]*\.fastq\.gz" "$file_grep")
my_ls=$(ls -1 "${search}/"*.fastq.gz | wc -l) 
my_find1=$(find "${search}/" -mtime +730 -iname '*.fastq.gz' | wc -l)
my_find2=$(find "${search}/" -mtime +730 -iname '*.fastq.gz' | grep -E "_R1_|_R2_" | wc -l)

echo "$my_grep"
echo "$my_ls"
echo "$my_find1"
echo "$my_find2"
# compare
if [[ $my_ls -eq $my_find1 ]] && [[ $my_ls -eq $my_find2 ]] && [[ $my_ls -eq $my_grep ]]; then
    echo "OK — alla variabler matchar."
    read -rp "Vill du fortsätta? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        cd "$search" || exit 1
        nohup bash ~/testar_colord/spring_wrapper/spring_wrapper.sh ./ &> spring_wrapper.out &
        pid=$!
        half=$(( my_find2 / 2 ))
        echo -e "${search}\t${my_find2}\t${half}\t${pid}"  >> "${scriptdir}/spring_runs.txt" 
    else
        echo "exit script."
        exit 0
    fi
else
    echo "⚠ EJ LIKA"
    [[ $my_ls -ne $my_find1 ]] && echo " - my_ls ($my_ls) matchar INTE my_find1 ($my_find1)"
    [[ $my_ls -ne $my_find2 ]] && echo " - my_ls ($my_ls) matchar INTE my_find2 ($my_find2)"
    [[ $my_ls -ne $my_grep ]] && echo " - my_ls ($my_ls) matchar INTE my_grep ($my_grep)"

    exit 1
fi

