#!/bin/bash

# Get the input parameters
YAML_FILE_TO_MOD=$1
YAML_PATH=$2
REPLACE_WITH=$3

# Check that all of the required parameters have been passed in
if [[ -z ${YAML_FILE_TO_MOD} ]] || [[ -z ${YAML_PATH} ]] || [[ -z ${REPLACE_WITH} ]]
then
    echo "Missing required input parameters:"
    echo "./subst.sh <file to modify> <yaml variable path> <replace yaml variable with>"
    exit 1
fi

# Add the additional wrapper to around the yaml path
TO_SUBST="<<.Values.${YAML_PATH}>>"

# Check if the file exists
if [[ ! -f ${YAML_FILE_TO_MOD} ]]
then
    echo "ERROR: ${YAML_FILE_TO_MOD} does not exist"
    exit 1
fi

# Check if the variable to substitute is present in the file
if ! grep "${TO_SUBST}" ${YAML_FILE_TO_MOD} > /dev/null; then
    echo "ERROR: Failed to find ${YAML_PATH} in ${YAML_FILE_TO_MOD} for substitution"
    exit 1
fi

# Use awk to substitute the variable in the file and check the command was executed successfully
OUTPUT=$(awk -v var1=${TO_SUBST} -v var2="${REPLACE_WITH}" '{sub(var1,var2)}1' ${YAML_FILE_TO_MOD})
echo "${OUTPUT}" > ${YAML_FILE_TO_MOD}
