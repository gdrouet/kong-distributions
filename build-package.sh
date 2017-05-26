#!/bin/bash

set -o errexit

##############################################################
#                      Parse Arguments                       #
##############################################################

function usage {
cat << EOF
usage: $0 options

This script build Kong in different distributions

OPTIONS:
 -h      Show this message
 -k      Kong GitHub branch/tag to build. At least -k or -d needs to be specified.
 -d      Kong directory to build. At least -k or -d needs to be specified.
 -p      Platforms to target
 -t      Execute tests
EOF
}

ARG_PLATFORMS=
KONG_BRANCH=
KONG_DIRECTORY=
TEST=false
while getopts "hk:d:p:t" OPTION
do
  case $OPTION in
    h)
      usage
      exit 1
      ;;
    d) 
      KONG_DIRECTORY=$OPTARG
      ;;
    k)
      KONG_BRANCH=$OPTARG
      ;;
    p)
      ARG_PLATFORMS=$OPTARG
      ;;
    t)
      TEST=true
      ;;
    ?)
      usage
      exit
      ;;
  esac
done

if [[ -z $ARG_PLATFORMS || -z "${KONG_DIRECTORY}${KONG_BRANCH}" ]]; then
  usage
  exit 1
fi

if [[ ! -z $KONG_DIRECTORY && ! -z $KONG_BRANCH ]]; then
  echo "You cannot set both a GitHub tag and a directory"
  exit 1
fi

IS_DIR=false
if [[ ! -z $KONG_DIRECTORY ]]; then
  IS_DIR=true
fi

# Check system
if [[ "$OS" =~ Windows ]]; then
  echo "Run this script from a *nix system"
  exit 1
fi

##############################################################
#                      Check Arguments                       #
##############################################################

supported_platforms=( centos:6 centos:7 debian:7 debian:8 ubuntu:12.04.5 ubuntu:14.04.2 ubuntu:15.04 ubuntu:16.04 osx )
platforms_to_build=( )

for var in "$ARG_PLATFORMS"
do
  if [[ "all" == "$var" ]]; then
    platforms_to_build=( "${supported_platforms[@]}" )
  elif ! [[ " ${supported_platforms[*]} " == *" $var "* ]]; then
    echo "[ERROR] \"$var\" not supported. Supported platforms are: "$( IFS=$'\n'; echo "${supported_platforms[*]}" )
    echo "You can optionally specify \"all\" to build all the supported platforms"
    exit 1
  else
    platforms_to_build+=($var)
  fi
done

if [ ${#platforms_to_build[@]} -eq 0 ]; then
  echo "Please specify an argument!"
  exit 1
fi

##############################################################
#                        Start Build                         #
##############################################################

# Preparing environment
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
echo "Current directory is: "$DIR
if [ "$DIR" == "/" ]; then
  DIR=""
fi

if [[ $IS_DIR == true ]]; then
  rm -rf $DIR/kong-copy
  mkdir $DIR/kong-copy
  cp -R $KONG_DIRECTORY/* $DIR/kong-copy

  echo "cp -R $KONG_DIRECTORY $DIR/kong-copy"
  KONG_BRANCH="dir"
  echo "Building from Kong directory: "$( IFS=$'\n'; echo "${platforms_to_build[*]}" )
else
  echo "Building Kong from branch/tag $KONG_BRANCH: "$( IFS=$'\n'; echo "${platforms_to_build[*]}" )
fi

# Delete previous packages
rm -rf $DIR/build-output

for i in "${platforms_to_build[@]}"
do
  echo "Building for $i"
done

# Start build
for i in "${platforms_to_build[@]}"
do

  echo "Building for $i"
  if [[ "$i" == "osx" ]]; then
    /bin/bash $DIR/.build-package-script.sh ${KONG_BRANCH}
  elif [[ "$i" == "aws" ]]; then
    echo "TODO: Build on AWS Linux AMI!"
  else
    docker pull $i # Because of https://github.com/CentOS/CentOS-Dockerfiles/issues/33
    docker run -v $DIR/:/build-data $i /bin/bash -c "/build-data/.build-package-script.sh ${KONG_BRANCH}"
  fi
  if [ $? -ne 0 ]; then
    echo "Error building for $i"
    exit 1
  fi

  # Check if tests are enabled, and execute them
  if [[ $TEST == true ]]; then
    echo "Testing $i"
    last_file=$(ls -dt $DIR/build-output/* | head -1)
    last_file_name=`basename $last_file`
    if [[ "$i" == "osx" ]]; then
      /bin/bash $DIR/.test-package-script.sh $DIR/build-output/$last_file_name
    elif [[ "$i" == "aws" ]]; then
      echo "TODO: Test on AWS Linux AMI!"
    else
      docker run -v $DIR/:/build-data $i /bin/bash -c "/build-data/.test-package-script.sh /build-data/build-output/$last_file_name"
    fi
    if [ $? -ne 0 ]; then
      echo "Error testing for $i"
      exit 1
    fi
  fi
done

echo "Build done"
