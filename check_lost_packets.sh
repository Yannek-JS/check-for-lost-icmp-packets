#! /bin/bash

#
START_TIME=$(date +%F__%T | sed 's/:/-/g')		# a time stamp to put in a log filename
SCRIPT_PATH=$(dirname $(realpath $0))    # full path to the directory where the script is located
START_TIMESTAMP=$(date +"%s") # UNIX timestamp
PROBING_TIME=1 # length of a single probing timeslot (in mins) which the lost packet stat is recorded for
DEST_ADDRESS='google.com' # a destination that is pinged
EXIT_TIME_MARGIN=10 # if probing last less than $PROBING_TIME (in seconds) minus $EXIT_TIME_MARGIN,
                    # then make a global stats and exit the script
PING_FILE=${SCRIPT_PATH}'/ping_'${START_TIME}'.txt' # a file where the ping tests are registered to 
TMP_PING_FILE=${SCRIPT_PATH}'/ping.tmp' # a file containing a temporary (the most recent) ping result 
CSV_FILE=${SCRIPT_PATH}'/ping_result_'${START_TIME}'.csv'
IGNORED_LOSS=1 # a percent of ignored lost packets amount
PP_BEGINS_TAG='PP begins' # tag to mark probation period start. It must not contain any digit !
TEST_END_TAG='Test ends' # test end tag. It must not contain any digit !

function get_ping_results {
    PROBING_TIME=$(( ${PROBING_TIME} * 60 ))
    realProbingTime=${PROBING_TIME} # realProbingTime allows control over quitting the script
    while [ $realProbingTime -gt $(( ${PROBING_TIME} - ${EXIT_TIME_MARGIN} )) ]
    do
        echo ${PP_BEGINS_TAG}' - '$(date +"%s") > ${TMP_PING_FILE}
        ping -q -w ${PROBING_TIME} ${DEST_ADDRESS} >> ${TMP_PING_FILE}
        realProbingTime=$(( $(grep --regexp 'loss' "${TMP_PING_FILE}" | cut --delimiter ',' --fields 4 | sed --regexp-extended 's/[A-Za-z\ ]//g') / 1000 ))
        if [ $(grep --regexp 'loss' "${TMP_PING_FILE}" | cut --delimiter ',' --fields 1 | sed --regexp-extended 's/[A-Za-z\ ]//g') -gt 20 ]
        then
            cat ${TMP_PING_FILE} >> ${PING_FILE}
        fi
        # echo $realProbingTime
    done
    echo ${TEST_END_TAG}' - '$(date +"%s") >> ${PING_FILE}
}

function create_csv_result_file {
    linkStatus='IDK' # current link status from range of OK, Failure, IDK
    lineToRecord='' # a string to put into CSV file
    echo $(date +%F','%T -d @${START_TIMESTAMP})',test starts' >> ${CSV_FILE}
    cat "${PING_FILE}" | while read line
    do
        if $(echo $line | grep --quiet --regexp "${PP_BEGINS_TAG}")
        then
            if [ "$lineToRecord" != '' ]
            then
                echo $lineToRecord >> ${CSV_FILE}
                lineToRecord=''
            fi
            probationStartTimestamp=$(echo $line | sed --regexp-extended 's/[A-Za-z\ \-]//g')
        elif $(echo $line | grep --quiet --regexp 'loss')
        then
            lostPackets=$(echo $line | cut --delimiter ',' --fields 3 | sed --regexp-extended 's/[A-Za-z\ ]//g')
            if [ $(echo "$lostPackets-$IGNORED_LOSS>0" | bc) -eq 1 ] && [ "$linkStatus" != 'Failure' ]
            then
                linkStatus='Failure'
                lineToRecord=$(date +%F','%T -d @$probationStartTimestamp)','$linkStatus
            elif [ $(echo "$lostPackets-$IGNORED_LOSS<=0" | bc) -eq 1 ] && [ "$linkStatus" != 'OK' ]
            then
                linkStatus='OK'
                lineToRecord=$(date +%F','%T -d @$probationStartTimestamp)','$linkStatus
            fi
        elif $(echo $line | grep --quiet --regexp "${TEST_END_TAG}")
        then
            echo $(date +%F','%T -d @$(echo $line | sed --regexp-extended 's/[A-Za-z\ \-]//g'))',test ends' >> ${CSV_FILE}
        fi
    done
}


get_ping_results
create_csv_result_file
