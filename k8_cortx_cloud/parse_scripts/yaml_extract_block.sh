#!/bin/bash

# Get the input parameters
INPUT_YAML_FILE=$1
YAML_PATH_FILTER=$2
INDENT=$3

# Check that all of the required parameters have been passed in
if [[ -z $INPUT_YAML_FILE ]]
then
    echo "Invalid input parameters: <input yaml file> is required"
    echo "./yaml_extract_block.sh <input yaml file> [<yaml path filter> OPTIONAL] [<indent> OPTIONAL]"
    exit 1
fi

# Convert the filter
YQ_YAML_PATH_FILTER=".$YAML_PATH_FILTER"

# Call the yq command
EXTRACTED_BLOCK=$(./parse_scripts/yq_linux_amd64 e $YQ_YAML_PATH_FILTER $INPUT_YAML_FILE)

# Check if we should indent
if [[ -z $INDENT ]]
then
    # No. Set the outpuit to the extracted block
    OUTPUT=$EXTRACTED_BLOCK
else
    # Yes. Create the whitespace indent pattern
    INDENT_PATTERN=$(printf '%*s' "$INDENT" | tr ' ' " ")
    # Set the output of emtpy
    OUTPUT=""
    # Loop the extracted block
    while IFS= read -r LINE; do
        # If the OUTPUT is empty set it otherwise append
        if [[ -z $OUTPUT ]]
        then
            OUTPUT="$INDENT_PATTERN""$LINE"
        else
            OUTPUT="$OUTPUT"$'\n'"$INDENT_PATTERN""$LINE"
        fi
    done <<< "$EXTRACTED_BLOCK"
fi

echo "${OUTPUT}"
