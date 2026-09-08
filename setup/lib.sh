#!/usr/bin/env bash

es_ca_cert="${BASH_SOURCE[0]%/*}"/ca.crt

# Log a message.
function log {
	echo "[+] $1"
}

# Log a message at a sub-level.
function sublog {
	echo "   ⠿ $1"
}

# Log an error.
function err {
	echo "[x] $1" >&2
}

# Log an error at a sub-level.
function suberr {
	echo "   ⠍ $1" >&2
}

# Inject common arguments to curl commands based on the environment.
function augment_curl_args {
	local args_var_name=$1
	local -n args_ref="${args_var_name}"
	if [[ -n "${ELASTIC_PASSWORD:-}" ]]; then
		args_ref+=( '-u' "elastic:${ELASTIC_PASSWORD}" )
	fi
	if [[ -n "${ELASTICSEARCH_ADDR:-}" ]]; then
		args_ref+=( '--resolve' "elasticsearch:9200:${ELASTICSEARCH_ADDR}" )
	fi
}

# Poll the 'elasticsearch' service until it responds with HTTP code 200.
function wait_for_elasticsearch {
	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}' 'https://elasticsearch:9200/' '--cacert' "$es_ca_cert" )

	augment_curl_args args

	local -i result=1
	local output

	# retry for max 300s (60*5s)
	for _ in $(seq 1 60); do
		local -i exit_code=0
		output="$(curl "${args[@]}")" || exit_code=$?

		if ((exit_code)); then
			result=$exit_code
		fi

		if [[ "${output: -3}" -eq 200 ]]; then
			result=0
			break
		fi

		sleep 5
	done

	if ((result)) && [[ "${output: -3}" -ne 000 ]]; then
		echo -e "\n${output::-3}"
	fi

	return $result
}

# Poll the Elasticsearch users API until it returns users.
function wait_for_builtin_users {
	local -a args=( '-s' '-D-' '-m15' 'https://elasticsearch:9200/_security/user?pretty' '--cacert' "$es_ca_cert" )

	augment_curl_args args

	local -i result=1

	local line
	local -i exit_code
	local -i num_users

	# retry for max 30s (30*1s)
	for _ in $(seq 1 30); do
		num_users=0

		# read exits with a non-zero code if the last read input doesn't end
		# with a newline character. The printf without newline that follows the
		# curl command ensures that the final input not only contains curl's
		# exit code, but causes read to fail so we can capture the return value.
		# Ref. https://unix.stackexchange.com/a/176703/152409
		while IFS= read -r line || ! exit_code="$line"; do
			if [[ "$line" =~ _reserved.+true ]]; then
				(( num_users++ ))
			fi
		done < <(curl "${args[@]}"; printf '%s' "$?")

		if ((exit_code)); then
			result=$exit_code
		fi

		# we expect more than just the 'elastic' user in the result
		if (( num_users > 1 )); then
			result=0
			break
		fi

		sleep 1
	done

	return $result
}

# Verify that the given Elasticsearch user exists.
function check_user_exists {
	local username=$1

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"https://elasticsearch:9200/_security/user/${username}"
		'--cacert' "$es_ca_cert"
		)

	augment_curl_args args

	local -i result=1
	local -i exists=0
	local output

	output="$(curl "${args[@]}")"
	if [[ "${output: -3}" -eq 200 || "${output: -3}" -eq 404 ]]; then
		result=0
	fi
	if [[ "${output: -3}" -eq 200 ]]; then
		exists=1
	fi

	if ((result)); then
		echo -e "\n${output::-3}"
	else
		echo "$exists"
	fi

	return $result
}

# Set password of a given Elasticsearch user.
function set_user_password {
	local username=$1
	local password=$2

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"https://elasticsearch:9200/_security/user/${username}/_password"
		'--cacert' "$es_ca_cert"
		'-X' 'POST'
		'-H' 'Content-Type: application/json'
		'-d' "{\"password\" : \"${password}\"}"
		)

	augment_curl_args args

	local -i result=1
	local output

	output="$(curl "${args[@]}")"
	if [[ "${output: -3}" -eq 200 ]]; then
		result=0
	fi

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}

# Create the given Elasticsearch user.
function create_user {
	local username=$1
	local password=$2
	local role=$3

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"https://elasticsearch:9200/_security/user/${username}"
		'--cacert' "$es_ca_cert"
		'-X' 'POST'
		'-H' 'Content-Type: application/json'
		'-d' "{\"password\":\"${password}\",\"roles\":[\"${role}\"]}"
		)

	augment_curl_args args

	local -i result=1
	local output

	output="$(curl "${args[@]}")"
	if [[ "${output: -3}" -eq 200 ]]; then
		result=0
	fi

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}

# Ensure that the given Elasticsearch role is up-to-date, create it if required.
function ensure_role {
	local name=$1
	local body=$2

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"https://elasticsearch:9200/_security/role/${name}"
		'--cacert' "$es_ca_cert"
		'-X' 'POST'
		'-H' 'Content-Type: application/json'
		'-d' "$body"
		)

	augment_curl_args args

	local -i result=1
	local output

	output="$(curl "${args[@]}")"
	if [[ "${output: -3}" -eq 200 ]]; then
		result=0
	fi

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}

# PUT JSON to an Elasticsearch path. Succeeds on any of the given HTTP codes (default: 200).
function es_put {
	local path=$1
	local body=$2
	shift 2
	local -a ok_codes=( "$@" )
	(( ${#ok_codes[@]} )) || ok_codes=( 200 201 )

	local -a args=( '-s' '-D-' '-m30' '-w' '%{http_code}'
		"https://elasticsearch:9200/${path}"
		'--cacert' "$es_ca_cert"
		'-X' 'PUT'
		'-H' 'Content-Type: application/json'
		'-d' "$body"
		)

	augment_curl_args args

	local output
	output="$(curl "${args[@]}")"
	local -i code="${output: -3}"
	local -i result=1
	local ok
	for ok in "${ok_codes[@]}"; do
		if (( code == ok )); then
			result=0
			break
		fi
	done

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}

# Short ILM for pocket disks. Uses logs@custom / metrics@custom so Fleet package
# updates do not wipe the policy. RETENTION_DAYS=0 skips this.
function ensure_retention {
	local days="${RETENTION_DAYS:-0}"

	if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
		sublog "RETENTION_DAYS=${days:-<empty>} — skipping custom ILM"
		return 0
	fi

	log "ILM retention ${days}d (logs-* / metrics-*)"

	local policy
	policy=$(cat <<EOF
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_age": "1d",
            "max_primary_shard_size": "10gb"
          }
        }
      },
      "delete": {
        "min_age": "${days}d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
EOF
)

	sublog 'Policy elk-retention'
	es_put '_ilm/policy/elk-retention' "$policy"

	local custom
	custom=$(cat <<EOF
{
  "template": {
    "settings": {
      "index": {
        "lifecycle": {
          "name": "elk-retention"
        }
      }
    }
  },
  "_meta": {
    "managed_by": "elk-docker"
  }
}
EOF
)

	sublog 'Component template logs@custom'
	es_put '_component_template/logs@custom' "$custom"

	sublog 'Component template metrics@custom'
	es_put '_component_template/metrics@custom' "$custom"

	# Existing backing indices keep the old policy until rollover; nudge them.
	local settings='{"index":{"lifecycle":{"name":"elk-retention"}}}'
	es_put 'logs-*/_settings?allow_no_indices=true&ignore_unavailable=true' "$settings" 200 400 || true
	es_put 'metrics-*/_settings?allow_no_indices=true&ignore_unavailable=true' "$settings" 200 400 || true
}
