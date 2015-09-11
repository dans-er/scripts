#!/bin/bash --
## script to recursively unzip all zip-files in a directory structure.

## the name of this script
NAME=$(basename $0)

## do not expand files with following extensions
NOT_EXPAND=("jar")
## expand these extensions with tar
EXPAND_TAR=("zip" "tar")
## expand with gzip
EXPAND_GZIP=("gz" "bz2")

## how many files did we inspect
INSPECTED=0
## how many files passed to gzip
GZIPPED=0
## how many exceptions in gzip
ERR_GZIPPED=0
## how many files passed to tar
TARRED=0
## how many exceptions in tar
ERR_TARRED=0

## print a usage message to the console
usage() {
	echo -e "Usage: \t$NAME {directory-or-file-to-unzip}"
}

## print error message then die
## $@ - arguments to print
die () {
	usage
    echo >&2 "$@"
    exit 1   
}


## test if file is compressed, if so take appropriate action.
## native file detection cannot be used because tar-files are directories:
##   $ file --mime-type random_paragraphs.tar --> application/x-directory
## we use a lists of known extensions.
##
## every file can be gzipped, txt.gz, json.gz, raw.gz, tar.gz
## difficult to read double extensions: x.y.z.zip  -> z.zip?
##                                      x.y.tar.gz -> tar.gz?
## therefore double treatment: first gzip, than tar.
##
## $1 - the file to test
unzyp() {
	INSPECTED=$((INSPECTED+1))
	local file=$1
	filename=$(basename "$file")
	extension="${filename##*.}" # single #: gz zip etc.
	
	# can it be handled by gzip?
	for ext in "${EXPAND_GZIP[@]}"
	do
		if [ "$ext" = "$extension" ]; then
			echo "++++++++++ gzip -d $file"
			GZIPPED=$((GZIPPED+1))
			gzip -d "$file"
			if [ "$?" != 0 ]; then
				ERR_GZIPPED=$((ERR_GZIPPED+1))
			fi
			# strip the .gz, .bz2 from file
			file="${file%.*}"
			filename=$(basename "$file")
			extension="${filename##*.}"
		fi
	done
	
	# now expand using tar
	for ext in "${EXPAND_TAR[@]}"
	do
		if [ "$ext" = "$extension" ]; then
			directory=$(dirname "$file")
			zipname="${filename%.*}"
			
			newdir="$directory/$zipname"
			while [ -e "$newdir" ]
			do
				newdir="$newdir"_
			done
			mkdir "$newdir"
			echo "********** tar -xf $file"
			TARRED=$((TARRED+1))
			tar -xf "$file" -C "$newdir"
			if [ "$?" != 0 ]; then
				ERR_TARRED=$((ERR_TARRED+1))
			else
				:
				#rm "$file" ## is this wise?
			fi
			walk_directory "$newdir"
		fi
	done
}

## list all files, test if compressed, if so take appropriate action.
## $1 - the directory to inspect
walk_directory() {
	#echo "########## walking $1"
	
	# list all files in the directory and subdirectories.
	declare -a array
	while IFS= read -r -d '' n; do
  		array+=( "$n" )
	done < <(find "$1" -mindepth 1 -type f -print0)
	
	for file in "${array[@]}"
	do
		unzyp "$file"
	done
}

## check if there is 1 argument
## if the argument is the name of a file: unzyp 
## if the argument is the name of a directory: walk_directory 
##
## $@ - argument(s) to check
start_processing() {
	[ "$#" -eq 1 ] || die "1 argument required, $# provided"
	
	ARGUMENT=${1%/} # strip trailing slash from path name
	[ -e "$ARGUMENT" ] || die "Not found: $ARGUMENT"
	
	if [ -f "$ARGUMENT" ]; then
		unzyp "$ARGUMENT"
	else
		[ -d "$ARGUMENT" ] || die "Not a directory: $ARGUMENT"
		[ -r "$ARGUMENT" ] || die "Cannot read the directory: $ARGUMENT"
		[ -w "$ARGUMENT" ] || die "Cannot write to directory: $ARGUMENT"
		walk_directory "$ARGUMENT"
	fi
}

start_processing "$@"

echo -e "number of files inspected:\t$INSPECTED"
echo -e "number of files passed to gzip:\t$GZIPPED"
echo -e "number of files passed to tar:\t$TARRED"
echo
echo -e "number of errors in gzip:\t$ERR_GZIPPED"
echo -e "number of errors in tar:\t$ERR_TARRED"
exit
