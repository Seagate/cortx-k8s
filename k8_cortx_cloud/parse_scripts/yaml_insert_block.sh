#!/bin/bash

# Get the input parameters
OUTPUT_YAML_FILE=$1
BLOCK_TO_INSERT=$2
INDENT=$3
YAML_PATH=$4

# Check that all of the required parameters have been passed in
if [[ -z $OUTPUT_YAML_FILE ]] || [[ -z $BLOCK_TO_INSERT ]]
then
    echo "Invalid input parameters: <output yaml file> and <block to insert> are required"
    echo "./yaml_insert_block.sh <output yaml file> <block to insert> [<indent> OPTIONAL] [<yaml variable path> OPTIONAL]"
    exit 1
fi

# Check if we should indent
if [[ -z $INDENT ]]
then
    # No. Set the outpuit to the extracted block
    OUTPUT=$BLOCK_TO_INSERT
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
            if [[ -z $YAML_PATH ]]
            then
                OUTPUT="$INDENT_PATTERN""$LINE"
            else
                 OUTPUT="$LINE"
            fi
        else
            OUTPUT="$OUTPUT"$'\n'"$INDENT_PATTERN""$LINE"
        fi
    done <<< "$BLOCK_TO_INSERT"
fi

if [[ -z $YAML_PATH ]]
then
    echo "${OUTPUT}" >> $OUTPUT_YAML_FILE
else
    ./parse_scripts/subst.sh $OUTPUT_YAML_FILE $YAML_PATH "${OUTPUT}"
fi
