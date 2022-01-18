#!/bin/bash

# Get the input parameters
YAML_FILE_TO_MOD=$1
YAML_PATH=$2
REPLACE_WITH=$3

# Check that all of the required parameters have been passed in
if [ "$YAML_FILE_TO_MOD" == "" ] || [ "$YAML_PATH" == "" ] || [ "$REPLACE_WITH" == "" ]
then
    echo "Invalid input paramters"
    echo "./subst.sh <file to modify> <yaml variable path> <replace yaml variable with>"
    echo "<file to modify>             = $YAML_FILE_TO_MOD"
    echo "<yaml variable path>         = $YAML_PATH"
    echo "<replace yaml variable with> = $REPLACE_WITH"
    exit 1
fi

# Add the additional wrapper to around the yaml path
TO_SUBST="<<.Values.$YAML_PATH>>"

# Check if the file exists
if [ ! -f $YAML_FILE_TO_MOD ]
then
    echo "ERROR: $YAML_FILE_TO_MOD does not exist"
    exit 1
fi

# Check if the variable to substitute is present in the file
grep "$TO_SUBST" $YAML_FILE_TO_MOD > /dev/null
if [ $? -ne 0 ]
then
    echo "ERROR: Failed to find $YAML_PATH in $YAML_FILE_TO_MOD for substitution"
    exit 1
fi

# Use awk to substitute the variable in the file and check the command was executed successfully
OUTPUT=$(awk -v var1=$TO_SUBST -v var2="$REPLACE_WITH" '{sub(var1,var2)}1' $YAML_FILE_TO_MOD)
echo "${OUTPUT}" > $YAML_FILE_TO_MOD
