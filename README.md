# spring_wrapper
A wrapper script for the compression tool spring. Under development, use at your own risk. 
# Requirements
pigz
spring
# Data format
The files to be compresses should be paired Illumina data
-  Names MUST have R1 or R2 in their names and follow the structure below as R1 and R2 and dashes and underscores are of importance for the script.
	- "testtesttest-dashesareok-213123_S43_L001_R1_001.fastq.gz" and "testtesttest-dashesareok-213123_S43_L001_R2_001.fastq.gz"
	- testtesttest-dashesareok-213123_S43_L001_R1.fastq.gz and testtesttest-dashesareok-213123_S43_L001_R2.fastq.gz
	- testtesttest-dashesareok-213123_S43_L001_R1_001_002.fastq.gz testtesttest-dashesareok-213123_S43_L001_R2_001_002.fastq.gz
fastq.gz files will be removed automatically 
# quick start
```
nohup bash ~/testar_colord/spring_wrapper/spring_wrapper.sh ./ &> spring_wrapper.out &
```

# Decompress. Note that this is another script
Use the input.tab file produced during compression with spring_wrapper.sh. You must be in the directory where the .spring files are located.  
A directory with the fastq.gz files will be created. The .spring files must be removed manually
```
bash ../spring_wrapper/spring_decompress_wrapper.sh test_input.txt
```
