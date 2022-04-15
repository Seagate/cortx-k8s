#!/bin/bash

INPUT_FILE=$1
OUTPUT_FILE=$2
YAML_PATH_FILTER=$3
TEMPLATE_UPDATE=$4

# Check that all of the required parameters have been passed in
if [[ -z ${INPUT_FILE} ]] || [[ -z ${OUTPUT_FILE} ]]
then
    echo "Missing required input parameters:"
    echo "./yaml_update_block.sh <input file> <output file> [<yaml path filter> OPTIONAL] [<template update> OPTIONAL]"
    exit 1
fi

# Check if the file exists
if [[ ! -f ${INPUT_FILE} ]]
then
    echo "ERROR: input file ${INPUT_FILE} does not exist"
    exit 1
fi

# Update the template
if [[ -n ${TEMPLATE_UPDATE} ]]
then
    sed -i "s/<<#>>/${TEMPLATE_UPDATE}/g" ${OUTPUT_FILE}
fi

# Check if the file exists
if [[ ! -f ${OUTPUT_FILE} ]]
then
    echo "ERROR: output file ${OUTPUT_FILE} does not exist"
    exit 1
fi

PARSED_OUTPUT=$(./parse_yaml.sh ${INPUT_FILE} ${YAML_PATH_FILTER})

# Split parsed output into an array of vars and vals
IFS=';' read -r -a PARSED_VAR_VAL_ARRAY <<< "${PARSED_OUTPUT}"

# Loop the var val tuple array
for VAR_VAL_ELEMENT in "${PARSED_VAR_VAL_ARRAY[@]}"
do
    # Get the var and val from the tuple
    VAR=$(echo ${VAR_VAL_ELEMENT} | cut -f1 -d'>')
	VAL=$(echo ${VAR_VAL_ELEMENT} | cut -f2 -d'>')
    # Call the substitution script the update the output file
    ./subst.sh ${OUTPUT_FILE} ${VAR} ${VAL}
done
