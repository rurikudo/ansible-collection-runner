#!/bin/bash

# input: collection, playbook, playbook-vars
# 1. init runner dir
# 2. create requirements.yml, playbook.yml 
# 3. install collection
# 4. run

CMDNAME=`basename $0`
if [ $# -lt 4 ]; then
  echo "Usage: $CMDNAME <runner-dir> <collection-type> <collection> <playbook> <playbook EXTRA_VARS>" 1>&2
  exit 1
fi

CURRENT_DIR=$(pwd)
RUNNER_DIR=$1
TYPE=$2
COLLECTION=$3
PLAYBOOK=$4
EXTRA_VARS=$5

# check extra_vars
#  --cmdline "-e key=value" 
if [ -n "$EXTRA_VARS" ]; then
    if [[ "$EXTRA_VARS" != "-e"* ]]; then
        echo "please set EXTRA_VARS in the format: '-e key=value'"
         exit 1
    fi
fi


if [ ! -d $RUNNER_DIR ]; then
  mkdir $RUNNER_DIR
  cd $RUNNER_DIR
else
  if [ -n "$(ls -A $RUNNER_DIR)" ]; then
    echo "Runner directory already exists. Please remove it.=> $RUNNER_DIR"
    exit 1
  fi
fi

ABS_RUNNER_DIR=$(pwd)
PROJECT_DIR=$(pwd)/project
ENV_DIR=$(pwd)/env
REQUIREMTNES=$(pwd)/project/requirements.yml

echo [1]Initialize runner dir
mkdir $ENV_DIR
mkdir $PROJECT_DIR
cat << EOF > $ENV_DIR/settings
---
idle_timeout: 600
job_timeout: 3600
pexpect_timeout: 10
process_isolation_executable: docker
process_isolation: true
container_image: quay.io/ansible/ansible-runner:devel
EOF

cat << EOF > $ENV_DIR/envvars
---
ANSIBLE_COLLECTIONS_PATH: /runner/project/collection/
EOF
# yq w -i -d* $ENV_DIR/envvars 'ANSIBLE_COLLECTIONS_PATH' /$RUNNER_DIR/project/collection/

echo [2]Prepare requirements.yml
cat << EOF > $REQUIREMTNES
---
collections:
 - name: COLLECTION
   type: TYPE
EOF

if [[ "$TYPE" == "git" ]]; then
    yq w -i -d* $REQUIREMTNES 'collections.[0].type' git
    yq w -i -d* $REQUIREMTNES 'collections.[0].name' $COLLECTION
elif [[ "$TYPE" == "file" ]]; then
    yq w -i -d* $REQUIREMTNES 'collections.[0].type' file
    yq w -i -d* $REQUIREMTNES 'collections.[0].name' $COLLECTION
fi

echo [3]Install collection
ansible-galaxy collection install -r $REQUIREMTNES -p $PROJECT_DIR/collection/

echo [4]Get collection name
ansible-galaxy collection list -p $PROJECT_DIR/collection/ --format json > clist
# keys=$(jq 'keys' clist)
# key=$(cat clist |  jq -r '. | keys[]' | grep $PROJECT_DIR)
key=$(cat clist |  jq 'keys' clist | grep $PROJECT_DIR)
key2=$(echo ${key%,*})
collection=$(cat clist | jq '.'$key2'')
col_name=$(echo $collection | jq -r '. | keys[]')
echo $col_name

echo [5]Create root playbook
cat << EOF > $PROJECT_DIR/demo.yml
---
- import_playbook: COLLECTION_PLAYBOOK
EOF

playbook=$col_name.$4
yq w -i -d* $PROJECT_DIR/demo.yml '[0].import_playbook' $playbook

# set extra_vars
if [ -n "$EXTRA_VARS" ]; then
    echo [6]Set extra_vars
    echo "$EXTRA_VARS" > $ENV_DIR/cmdline
fi

echo Execute playbook
cd $CURRENT_DIR
ansible-runner run --container-option="--user=0" $RUNNER_DIR -p demo.yml