#!/bin/bash

# Get the input parameters
INPUT_YAML_FILE=$1
YAML_PATH_FILTER=$2

# Function to parse the yaml. Each tuple is , separated
# and the vals and vals are > separated
function parseYaml
{
    local -r yaml_file=$1
    local -r s='[[:space:]]*'
    local -r w='[a-zA-Z0-9_]*'
    local fs
    fs=$(echo @|tr @ '\034')
    readonly fs

    # shellcheck disable=SC2312
    sed -ne "s|^\(${s}\):|\1|" \
        -e "s|^\(${s}\)\(${w}\)${s}:${s}[\"']\(.*\)[\"']${s}\$|\1${fs}\2${fs}\3|p" \
        -e "s|^\(${s}\)\(${w}\)${s}:${s}\(.*\)${s}\$|\1${fs}\2${fs}\3|p" "${yaml_file}" |
    awk -F"${fs}" '{
        indent = length($1)/2;
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])(".")}
            printf("%s%s>%s;",vn, $2, $3);
        }
    }'
}

# Check that all of the required parameters have been passed in
if [[ -z ${INPUT_YAML_FILE} ]]
then
    echo "Missing required input parameters:"
    echo "./parse_yaml.sh <input yaml file> [<yaml path filter> OPTIONAL]"
    exit 1
fi

# Check if the file exists
if [[ ! -f ${INPUT_YAML_FILE} ]]
then
    echo "ERROR: ${INPUT_YAML_FILE} does not exist"
    exit 1
fi

# Store the parsed output in a single string
PARSED_OUTPUT=$(parseYaml "${INPUT_YAML_FILE}")
# Remove any additional indent '.' characters
PARSED_OUTPUT=${PARSED_OUTPUT//../.}

# Star with empty output
OUTPUT=""

# Check if we need to do any filtering
if [[ -z ${YAML_PATH_FILTER} ]]
then
    OUTPUT=${PARSED_OUTPUT}
else
    # Split parsed output into an array of vars and vals
    IFS=';' read -r -a PARSED_VAR_VAL_ARRAY <<< "${PARSED_OUTPUT}"
    # Loop the var val tuple array
    for VAR_VAL_ELEMENT in "${PARSED_VAR_VAL_ARRAY[@]}"
    do
        # Get the var and val from the tuple
        VAR=$(echo "${VAR_VAL_ELEMENT}" | cut -f1 -d'>')
        # Check is the filter matches the var
        #
        # Ignore SC2053: YAML_PATH_FILTER is a filter which can take wildcard
        # (*) characters, so this comparison is intentionally relying on glob
        # pattern matching.
        #
        # shellcheck disable=SC2053
        if [[ ${VAR} == ${YAML_PATH_FILTER} ]]
        then
            # If the OUTPUT is empty set it otherwise append
            if [[ -z ${OUTPUT} ]]
            then
                OUTPUT=${VAR_VAL_ELEMENT}
            else
                OUTPUT=${OUTPUT}";"${VAR_VAL_ELEMENT}
            fi
        fi
    done
fi

# Return the parsed output
echo "${OUTPUT}"
