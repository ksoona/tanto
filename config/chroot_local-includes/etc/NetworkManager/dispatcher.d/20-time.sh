#!/bin/sh

# Rationale: Tor needs a somewhat accurate clock to work.
# If the clock is wrong enough to prevent it from opening circuits,
# we set the time to the middle of the valid time interval found
# in the Tor consensus, and we restart it.
# In any case, we use HTP to ask more accurate time information to
# a few authenticated HTTPS servers.


### Init variables

LOG=/var/log/htpdate.log
HTP_DIR=/var/run/htpdate
SUCCESS_FILE=${HTP_DIR}/success
TOR_DIR=/var/lib/tor
TOR_CONSENSUS=${TOR_DIR}/cached-consensus
TOR_DESCRIPTORS=${TOR_DIR}/cached-descriptors
INOTIFY_TIMEOUT=60
DATE_RE='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]'

### Exit conditions

# Run only when the interface is not "lo":
if [ "$1" = "lo" ]; then
	exit 0
fi

# Run whenever an interface gets "up", not otherwise:
if [ "$2" != "up" ]; then
	exit 0
fi

# Do not run if we already successed:
if [ -e "$SUCCESS_FILE" ]; then
	exit 0
fi


### Create status dir
install -o root -g root -m 0755 -d ${HTP_DIR}

### Create log file

# The htp user needs to write to this file.
# The $LIVE_USERNAME user may need to read this file.
touch "$LOG"
chown htp:nogroup "$LOG"
chmod 644 "$LOG"


### Functions

log() {
	echo "$@" >> "${LOG}"
}

tor_is_working() {
	[ -e $TOR_DESCRIPTORS ]
}

wait_for_tor_consensus() {
	log "Waiting for the Tor consensus file to contain a valid time interval"
	while :; do
		if grep -qs "^valid-until ${DATE_RE}"'$' ${TOR_CONSENSUS}; then
			break;
		fi

		inotifywait -q -t ${INOTIFY_TIMEOUT} -e close_write -e moved_to --format %w%f ${TOR_DIR} || :
	done
}

date_points_are_sane() {
	local vstart="$1"
	local vend="$2"

	vendchk=`date -ud "${vstart} -0300" +'%F %T'`
	[ "${vend}" = "${vendchk}" ]
}

time_is_in_valid_tor_range() {
	local curdate="$1"
	local vstart="$2"

	vendcons=`date -ud "${vstart} -0230" +'%F %T'`
	order="${vstart}
${curdate}
${vendcons}"
	ordersrt=`echo "${order}" | sort`

	[ "${order}" = "${ordersrt}" ]
}

maybe_set_time_from_tor_consensus() {
	# Get various date points in Tor's format, and do some sanity checks
	vstart=`sed -n "/^valid-after \(${DATE_RE}\)"'$/s//\1/p; t q; b n; :q q; :n' ${TOR_CONSENSUS}`
	vend=`sed -n "/^valid-until \(${DATE_RE}\)"'$/s//\1/p; t q; b n; :q q; :n' ${TOR_CONSENSUS}`
	vmid=`date -ud "${vstart} -0130" +'%F %T'`
	log "Tor: valid-after=${vstart} | valid-until=${vend}"

	if ! date_points_are_sane "${vstart}" "${vend}"; then
		log "Unexpected valid-until: [${vend}] is not [${vstart} + 3h]"
		return
	fi

	curdate=`date -u +'%F %T'`
	log "Current time is ${curdate}"

	if time_is_in_valid_tor_range "${curdate}" "${vstart}"; then
		log "Current time is in valid Tor range"
		return
	fi

	log "Current time is not in valid Tor range, setting to middle of this range: [${vmid}]"
	date -us "${vmid}" 1>/dev/null

	# Tor is unreliable with picking a circuit after time change
	if service tor status >/dev/null; then
		log "Restarting Tor service"
		service tor restart
	fi
}

### Main

# Delegate time setting to other daemons if Tor connections work
if tor_is_working; then
	log "Tor has already opened a circuit"
else
	wait_for_tor_consensus
	maybe_set_time_from_tor_consensus
fi

log "Restarting htpdate"
service htpdate restart
log "htpdate service restarted with return code $?"
