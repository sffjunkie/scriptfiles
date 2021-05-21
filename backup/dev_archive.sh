#!/bin/bash

# Creates archives of dev projects and gists

# The script assumes the following directory structure
# $DEV_DIRECTORY/project/
# $DEV_DIRECTORY/project/<project name>/
# $DEV_DIRECTORY/gist/
# $DEV_DIRECTORY/gist/<gist name>/

# You can change the shebang to use zsh but you'll need to have the mapfile module enabled

DEV_DIRECTORY=${DEV_HOME:-$HOME/development}

help() {
  echo "usage: $(basename $0) [options] [item]"
  echo
  echo "Archive projects or gists"
  echo
  echo "options:"
  echo "  -h | --help     Show this help text"
  echo "  -a | --all      Whether to process all items"
  echo "  -k | --keep     The number of previous archives to keep"
  echo "  -o | --output   Directory to output archives to. The directory is created if it doesn't exist"
  echo "  -p | --period   The period this backup is for either 'day', 'week' or 'month'"
  echo "                  Where 'week' creates an archive for the ISO week number in the current year"
  echo "                  The default period is 'day'"
  echo "  -t | --type     The type of item to archive either 'project' or 'gist'."
  echo "                  The default type is 'project'"
  echo "  -v | --verbose  Verbose mode"
}

# Prune archives if more than KEEP items already exist
prune() {
  output_directory=$1
  archive_regex=$2
  keep=$3

  mapfile -d $'\0' match < <(find ${output_directory} \
               -type f \
               -regextype posix-extended \
               -regex ${archive_regex} \
               -print0 | sort -z)
  if [[ ${#match[@]} -gt $keep ]]; then
    trim_count=$(( ${#match[@]} - ${keep} ))
    to_delete=${match[@]:0:$trim_count}
    [[ ${VERBOSE} ==  1 ]] && echo "Pruning $trim_count file(s)"
    for value in $to_delete; do
      [[ ${VERBOSE} ==  1 ]] && echo "Pruning $value"
      rm -r "$value"
    done
  fi
}

TEMP=$(getopt --options 'hak:o:p:t:v' --longoptions 'help,all,keep:,output:,period:,type:,verbose:' -- "$@")

if [[ ${#} -eq 0 ]]; then
   help
   exit 1
fi

eval set -- "${TEMP}"

# Defaults
[[ "${TYPE}" == "" ]] && TYPE=project
[[ "${PERIOD}" == "" ]] && PERIOD=day
[[ "${KEEP}" == "" ]] && KEEP=5
[[ "${VERBOSE}" == "" ]] && VERBOSE=0
[[ "${OUTPUT_DIRECTORY}" == "" ]] && OUTPUT_DIRECTORY=${DEV_DIRECTORY}/archive
ALL=0

while true ; do
  case "$1" in
    -h|--help) help; exit 0 ;;
    -a|--all) ALL=1; shift;;
    -k|--keep) _KEEP=$2; shift; shift ;;
    -o|--output) OUTPUT_DIRECTORY=$2; shift; shift ;;
    -p|--period) PERIOD=$2; shift; shift ;;
    -t|--type) TYPE=$2; shift; shift ;;
    -v|--verbose) VERBOSE=1; shift;;
    *) shift; break ;;
  esac
done

mkdir -p ${OUTPUT_DIRECTORY}

if [[ ${_KEEP} =~ ^-?[0-9]+$ ]] && [[ ${_KEEP} -gt 0 ]]; then
  KEEP=${_KEEP}
fi

case "${TYPE}" in
  project|gist) ;;
  *)
    echo "Unknown item type '${TYPE}'. It must be one of 'project' or 'gist'"
    exit 1
esac

case "${PERIOD}" in
  day|week|month) ;;
  *)
    echo "Unknown period '${PERIOD}'. It must be one of 'day', 'week' or 'month'"
    exit 1
esac

TYPE_DIRECTORY=${DEV_DIRECTORY}/${TYPE}

DATE_DAILY="$(date +%Y-%m-%d)"
DATE_WEEKLY="$(date +%Y)-wk$(date +%V)"
DATE_MONTHLY="$(date +%Y-%m)"

ARCHIVE_REGEX_DAILY="[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}"
ARCHIVE_REGEX_WEEKLY="[[:digit:]]{4}-wk[[:digit:]]{2}"
ARCHIVE_REGEX_MONTHLY="[[:digit:]]{4}-[[:digit:]]{2}"

ARCHIVE_SUFFIX=".tar.zstd"

archive() {
  item=$1

  case "$PERIOD" in
    week)
      ARCHIVE_FILE="${OUTPUT_DIRECTORY}/${TYPE}-${item}-${DATE_WEEKLY}${ARCHIVE_SUFFIX}"
      ARCHIVE_REGEX="${OUTPUT_DIRECTORY}/${TYPE}-${item}-${ARCHIVE_REGEX_WEEKLY}${ARCHIVE_SUFFIX}"
      ;;

    month)
      ARCHIVE_FILE="${OUTPUT_DIRECTORY}/${TYPE}-${item}-${DATE_MONTHLY}${ARCHIVE_SUFFIX}"
      ARCHIVE_REGEX="${OUTPUT_DIRECTORY}/${TYPE}-${item}-${ARCHIVE_REGEX_MONTHLY}${ARCHIVE_SUFFIX}"
      ;;

    *)
      ARCHIVE_FILE="${OUTPUT_DIRECTORY}/${TYPE}-${item}-${DATE_DAILY}${ARCHIVE_SUFFIX}"
      ARCHIVE_REGEX="${OUTPUT_DIRECTORY}/${TYPE}-${item}-${ARCHIVE_REGEX_DAILY}${ARCHIVE_SUFFIX}"
      ;;
  esac

  [[ ${VERBOSE} ==  1 ]] && echo "Archiving ${TYPE} ${item} => ${ARCHIVE_FILE}"
  [[ ${VERBOSE} ==  1 ]] && [ -f ${ARCHIVE_FILE} ] && echo "Archive ${ARCHIVE_FILE} already exists, overwriting"

  tar \
    --exclude-from=./ignore \
    --zstd \
    --create \
    --file=${ARCHIVE_FILE} \
    -C ${TYPE_DIRECTORY} \
    ${item}

  prune "${OUTPUT_DIRECTORY}" "${ARCHIVE_REGEX}" "${KEEP}"
}

archive_all() {
  while read -d $'\0' directory; do
    directory="$(basename -- $(printf '%q' ${directory}) )"
    archive $directory
  done < <( find ${TYPE_DIRECTORY} -maxdepth 1 -mindepth 1 -type d -print0 )
}

if [[ ${ALL} -eq 1 ]]; then
  echo "Archiving all ${TYPE}s"
  archive_all
else
  for arg in $@; do
    if [[ ! -d ${TYPE_DIRECTORY}/${arg} ]]; then
      echo "Unable to create archive: ${TYPE} '${arg}' does not exist."
      continue
    fi
    archive ${arg}
  done
fi
