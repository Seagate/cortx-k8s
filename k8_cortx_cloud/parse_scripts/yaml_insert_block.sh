#!/bin/bash

# Get the input parameters
OUTPUT_YAML_FILE=$1
BLOCK_TO_INSERT=$2
INDENT=$3

# Check that all of the required parameters have been passed in
if [ "$OUTPUT_YAML_FILE" == "" ] || [ "$BLOCK_TO_INSERT" == "" ]
then
    echo "Invalid input paramters"
    echo "./yaml_insert_block.sh <output yaml file> <block to insert> [<indent> OPTIONAL]"
    echo "<input yaml file>   = $OUTPUT_YAML_FILE"
    echo "<block to insert>   = $BLOCK_TO_INSERT"
    echo "[<indent> OPTIONAL] = $INDENT"
    exit 1
fi

# Check if we should indent
if [ "$INDENT" == "" ]
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
        if [ "$OUTPUT" == "" ]
        then
            OUTPUT="$INDENT_PATTERN""$LINE"
        else
            OUTPUT="$OUTPUT"$'\n'"$INDENT_PATTERN""$LINE"
        fi
    done <<< "$BLOCK_TO_INSERT"
fi

cat <<EOF>> $OUTPUT_YAML_FILE
${OUTPUT}
EOF