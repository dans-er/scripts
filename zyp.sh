#!/bin/bash --
## script to recursively unzip all zip-files in a directory structure.

## the name of this script
NAME=$(basename $0)

## required parameter
## The name of the file or directory to process
ARGUMENT=""

## optional parameters

## Ask if zip-files processed without errors should be deleted. Default = no, do not ask.
ASK_DELETE_ZIP=0

## Do gzip preprocessing. Default = no, do not preprocess
GZIP_PRE=0

## List compressed files
LIST_COMPRESSED=0

## Do not print file paths of gzip and tar victims
QUIET=0

## expand these extensions with tar
EXPAND_TAR=("zip" "tar")
## expand with gzip
EXPAND_GZIP=("gz" "tgz" "bz2")

## how many files did we inspect
INSPECTED=0

## unzyp counts
## how many files passed to gzip
GZIPPED=0
## how many exceptions in gzip
ERR_GZIPPED=0
## how many files passed to tar
TARRED=0
## how many exceptions in tar
ERR_TARRED=0

## inspect counts
ZIP_COUNT=0
GZIP_COUNT=0
TAR_COUNT=0

## print a usage message to the console
usage() {
	echo -en "\033[1m$NAME\033[0m Recursively unzip a file or directory."
	echo -e " Files with the extensions"
	echo -e "    ${EXPAND_TAR[*]}"
	echo -e "will be unzipped. (This script uses tar.) With the option -g --gzip"
	echo -e "files with double extensions like tar.gz will also be expanded."
	echo
	echo -e "\033[1mUsage\033[0m: \t$NAME [[options] [-f]] file | directory"
	echo
	echo -e "\033[1mOptions\033[0m:"
	echo -e "\t \033[1m-a --ask\033[0m \t Ask if a successfully unzipped zip-files should be deleted."
	echo -e "\t   \t \t Default is no, don't ask."
	
	echo -e "\t \033[1m-f --file\033[0m \t Name of the file or directory to process. (Required)"
	
	echo -e "\t \033[1m-g --gzip\033[0m \t Do gzip preprocessing. Default is no, do not preprocess."
	echo -e "\t \t \t With this option files with the extensions"
	echo -e "\t \t \t    ${EXPAND_GZIP[*]}"
	echo -e "\t \t \t will be preprocessed by gzip, which will deflate the files"
	echo -e "\t \t \t and strip the above mentioned extensions."
	
	echo -e "\t \033[1m-l --list\033[0m \t List compressed files. Do not expand."
	
	echo -e "\t \033[1m-q --quiet\033[0m \t Do not print file paths of gzip and tar victims."
	
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
	extension="${filename##*.}" # double ##: gz zip etc.
	if [ "$GZIP_PRE" = 1 ]; then
		# can it be handled by gzip?
		for ext in "${EXPAND_GZIP[@]}"
		do
			if [ "$ext" = "$extension" ]; then
				[ "$QUIET" = 1 ] || echo "++++++++++ gzip -d "${file#$ARGUMENT}
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
	fi
	
	# now expand using tar
	for ext in "${EXPAND_TAR[@]}"
	do
		if [ "$ext" = "$extension" ]; then
			directory=$(dirname "$file")
			zipname="${filename%.*}"
			
			# are all items in the compressed file in one directory?
			array=( $(tar --exclude "__MACOSX" -tf "$file") )
			fi="${array[0]}"
			prevdir="${fi%%/*}"
			onedir=1
			for fi in "${array[@]}"
			do
				dir="${fi%%/*}"
				if [ "$dir" != "$prevdir" ]; then
					onedir=$((onedir+1))
				fi
			done
			
			
			if [ "$onedir" != 1 ]; then
				newdir="$directory/$zipname"
				while [ -e "$newdir" ]
				do
					newdir="$newdir"_
				done
				mkdir "$newdir"
				target="$newdir"
			else # only one directory or file in this compressed file
				if [ "$prevdir" = "." -o "$prevdir" = "" ]; then
					newdir="" 
				else
					newdir="$directory/${prevdir%/}"
				fi
				
				target="$directory"
			fi
				
			[ "$QUIET" = 1 -a "$ASK_DELETE_ZIP" != 1 ] || echo "********** tar -xf "${file#$ARGUMENT}
			TARRED=$((TARRED+1))
			
			#### untar
			tar --exclude "__MACOSX" -xf "$file" -C "$target"
			####
			
			if [ "$?" != 0 ]; then
				ERR_TARRED=$((ERR_TARRED+1))
			elif [ "$ASK_DELETE_ZIP" = 1 ]; then
					echo -e "* Delete the file $filename? \n> (y/n)"
					read
					if [ "$REPLY" = "y" -o "$REPLY" = "yes" ]; then
						rm "$file"
					fi
			else
				rm "$file"
			fi
			
			if [ -d "$newdir" ]; then
				walk_directory "$newdir"
			fi
		fi
	done
}

## possible finds with file command:
## application/zip 		<-- .zip, .jar
## application/x-gzip	<-- .tar.gz
## application/x-tar	<-- .tar
inspect() {
	INSPECTED=$((INSPECTED+1))
	local file=$1
	filename=$(basename "$file")
	extension="${filename##*.}" # double ##: gz zip etc.
	
	mt=$(file -b --mime-type "$file")
	if [[ "$mt" == *gzip ]]; then
		GZIP_COUNT=$((GZIP_COUNT+1))
		echo -e "$mt \t"${file#$ARGUMENT}	
	elif [[ "$mt" == *zip ]]; then
		ZIP_COUNT=$((ZIP_COUNT+1))
		echo -e "$mt \t"${file#$ARGUMENT}
	elif [[ "$mt" == *tar ]]; then
		TAR_COUNT=$((TAR_COUNT+1))
		echo -e "$mt \t"${file#$ARGUMENT}
	fi
}

## list all files, test if compressed, if so take appropriate action.
##
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
		if [ "$LIST_COMPRESSED" = 1 ]; then
			inspect "$file"
		else
			unzyp "$file"
		fi
	done
}

## if the argument is the name of a file: unzyp 
## if the argument is the name of a directory: walk_directory 
##
## $@ - argument(s) to check
start_processing() {
	
	[ -e "$ARGUMENT" ] || die "Not found: $ARGUMENT"
	
	if [ -f "$ARGUMENT" ]; then
		if [ "$LIST_COMPRESSED" = 1 ]; then
			inspect "$ARGUMENT"
		else
			unzyp "$ARGUMENT"
		fi
	else
		[ -d "$ARGUMENT" ] || die "Not a directory: $ARGUMENT"
		[ -r "$ARGUMENT" ] || die "Cannot read the directory: $ARGUMENT"
		[ -w "$ARGUMENT" ] || die "Cannot write to directory: $ARGUMENT"
		walk_directory "$ARGUMENT"
	fi
}

ARGUMENT=${1%/} # strip trailing slash from path name

while [ "$1" != "" ]; do
	case $1 in
		-f | --file )	shift
						ARGUMENT=${1%/} # strip trailing slash from path name
						;;
		-a | --ask )	ASK_DELETE_ZIP=1
						;;
		-g | --gzip	)	GZIP_PRE=1
						;;
		-l | --list )	LIST_COMPRESSED=1
						;;
		-q | --quiet )	QUIET=1
						;;
		-h | --help )	usage
						exit
						;;
	esac
	shift
done

if [ "$ARGUMENT" = "" ]; then
	usage
	exit 1
fi

start_processing

echo -e "number of files inspected:\t$INSPECTED"

if [ "$LIST_COMPRESSED" = 1 ]; then
	echo -e "application/zip:\t$ZIP_COUNT"
	echo -e "application/x-gzip:\t$GZIP_COUNT"
	echo -e "application/x-tar:\t$TAR_COUNT"
else
	echo -e "number of files passed to gzip:\t$GZIPPED"
	echo -e "number of files passed to tar:\t$TARRED"
	echo
	echo -e "number of errors in gzip:\t$ERR_GZIPPED"
	echo -e "number of errors in tar:\t$ERR_TARRED"
fi
exit
