#!/bin/bash
PROFILEFILE="$HOME/.aws/config"
CONNECTIONFILE="$HOME/.steampipe/config/aws.spc"
#PROFILEFILE="~/.aws/config"
#CONNECTIONFILE="~/.aws/aws.spc"

#cp -p ${PROFILEFILE} ${PROFILEFILE}_$(date +"%Y%m%d_%H%M")

#if [ $# -lt 2 ];
#then
#    echo "";
#    echo "Syntax: $0 <region> <start_url> [<profile_file>]"
#    echo "";
#    exit 1 
#fi

#if [ $# -eq 3 ];
#then
#    profilefile=$3
#else
#    profilefile=$PROFILEFILE
#fi

profilefile=${PROFILEFILE};
START_URL="https://[start-url].awsapps.com/start#/";
REGION="us-east-1";

touch ${PROFILEFILE}

if [[ $(aws --version) == aws-cli/1* ]]
then
    echo "";
    echo "ERROR: $0 requires AWS CLI v2 or higher";
    echo "";
    exit 1
fi

# Get secret and client ID to begin authentication session

echo
echo -n "Registering client... "

out=$(aws sso-oidc register-client --client-name 'profiletool' --client-type 'public' --region "${REGION}" --output text)

if [ $? -ne 0 ];
then
    echo "";
    echo "Failed"
    exit 1
else
    echo "Succeeded"
fi

secret=$(awk -F ' ' '{print $3}' <<< "$out")
clientid=$(awk -F ' ' '{print $1}' <<< "$out")

# Start the authentication process

echo -n "Starting device authorization... "

out=$(aws sso-oidc start-device-authorization --client-id "$clientid" --client-secret "$secret" --start-url "${START_URL}" --region "${REGION}" --output text)

if [ $? -ne 0 ];
then
    echo "";
    echo "Failed"
    exit 1
else
    echo "Succeeded"
fi

regurl=$(awk -F ' ' '{print $6}' <<< "$out")
devicecode=$(awk -F ' ' '{print $1}' <<< "$out")

echo
echo "Open the following URL in your browser and sign in, then click the Allow button:"
echo
echo "$regurl"
echo
echo "Press <ENTER> after you have signed in to continue..."

read continue

# Get the access token for use in the remaining API calls

echo -n "Getting access token... "

out=$(aws sso-oidc create-token --client-id "$clientid" --client-secret "$secret" --grant-type 'urn:ietf:params:oauth:grant-type:device_code' --device-code "$devicecode" --region "${REGION}" --output text)

if [ $? -ne 0 ];
then
    echo "Failed"
    exit 1
else
    echo "Succeeded"
fi

token=$(awk -F ' ' '{print $1}' <<< "$out")

# Set defaults for profiles

defregion="${REGION}"
defoutput="json"

# Batch or interactive

echo
echo "$0 will create all profiles with default values"

# Retrieve accounts first

echo
echo -n "Retrieving accounts... "

acctsfile="$(mktemp ./sso.accts.XXXXXX)"

# Set up trap to clean up temp file
trap '{ rm -f "$acctsfile"; echo; exit 255; }' SIGINT SIGTERM
    
aws sso list-accounts --access-token "$token" --region "${REGION}" --output text | sort -k 3 > "$acctsfile"

if [ $? -ne 0 ];
then
    echo "Failed"
    exit 1
else
    echo "Succeeded"
fi

declare -a created_profiles

#echo "### The section below added by awsssoprofiletool.sh TimeStamp: $(date +"%Y%m%d.%H%M")" >> "$profilefile"

# Read in accounts

while IFS=$'\t' read skip acctnum acctname acctowner;
do
    echo
    echo "Working on roles for account $acctnum ($acctname)..."
    rolesfile="$(mktemp ./sso.roles.XXXXXX)"

    # Set up trap to clean up both temp files
    trap '{ rm -f "$rolesfile" "$acctsfile"; echo; exit 255; }' SIGINT SIGTERM
    
    aws sso list-account-roles --account-id "$acctnum" --access-token "$token" --region "${REGION}" --output text | sort -k 3 > "$rolesfile"
    sleep 1
    if [ $? -ne 0 ];
    then
	echo "Failed to retrieve roles."
	exit 1
    fi
   
    i=1
    rolecount=$(cat $rolesfile | wc -l)
    
    while IFS=$'\t' read junk junk rolename;
    do
	
	if [[ $rolecount -gt 1 ]]; then
		p="${acctname}_"$rolename"_Account_$i"
		((i++))
	else
		p="$acctname"
		
	fi
	Profile_Name=$(echo $p | sed 's/-/_/g' | sed 's/[[:space:]]/_/g')
	profilename=$Profile_Name
	    
VIEW=$(cat <<EOF
[profile $profilename]
sso_start_url = ${START_URL}
sso_region = ${REGION}
sso_account_id = $acctnum
sso_role_name = $rolename
region = $defregion
output = $defoutput
EOF
)


	PROFILE_ID_COUNT=$(cat "$profilefile" | grep -e "sso_account_id = ${acctnum}" --no-group-separator -A3 -B3 | grep -ce "sso_role_name = $rolename" --no-group-separator -A2 -B4) >> /dev/null 2>&1

	if [[ ${PROFILE_ID_COUNT} -eq 1 ]]; then
		OLD_PROFILE_VIEW=$(cat "$profilefile" | grep -e "sso_account_id = ${acctnum}" --no-group-separator -A3 -B3 | grep -e "sso_role_name = $rolename" --no-group-separator -A2 -B4)
		if [[ "${OLD_PROFILE_VIEW}" == "${VIEW}" ]]; then
			echo "	Profile for Account_Name: ${acctname}, SSO_Account_ID:${acctnum}, SSO_Role_Name: ${rolename} name already exists!"
			continue
		else
			OLD_PROFILE=$(cat "$profilefile" | grep -e "sso_account_id = ${acctnum}" --no-group-separator -A3 -B3 | grep -e "sso_role_name = $rolename" --no-group-separator -A2 -B4 | grep "profile"| awk '{$1="";print}' | sed 's/\]//g'| sed 's/^[[:space:]]//g')
	echo ${OLD_PROFILE} id ;
			sed -i "/profile ${OLD_PROFILE}/,+6d" ${profilefile}
			echo -n "  Profile Detected, Updating $profilename... "
			echo "$VIEW" >> "$profilefile";
			echo "" >> "$profilefile";

			echo "$CONNECTION_VIEW" >> "$CONNECTIONFILE";
			echo "" >> "$CONNECTIONFILE";

			echo "Succeeded"
			continue
		fi
	elif [[ ${PROFILE_ID_COUNT} -gt 1 ]]; then
		echo "	 Multiple Profile Detected for Account_Name: ${acctname}, SSO_Account_ID:${acctnum}, SSO_Role_Name: ${rolename}";
		OLD_PROFILE_NAME=$(cat "$profilefile" | grep -e "sso_account_id = ${acctnum}" --no-group-separator -A3 -B3 | grep -e "sso_role_name = $rolename" --no-group-separator -A2 -B4 | grep "profile" | awk '{$1="";print}' | sed 's/\]//g'| sed 's/^[[:space:]]//g')
		for PROFILE in ${OLD_PROFILE_NAME}; do
			sed -i "/profile ${PROFILE}/,+6d" ${profilefile}
		done
		echo -n "  Multiple Profile Detected, Reconfiguring $profilename... "
		echo "$VIEW" >> "$profilefile";
		echo "" >> "$profilefile";

		echo "$CONNECTION_VIEW" >> "$CONNECTIONFILE";
		echo "" >> "$CONNECTIONFILE";

		echo "Succeeded"
		continue
	fi

	echo -n "  Creating New Profile $profilename... "
	echo "$VIEW" >> "$profilefile";
	echo "" >> "$profilefile";


	echo "Succeeded"
	created_profiles+=("$profilename")

    done < "$rolesfile"
    rm "$rolesfile"

    echo
    echo " Done, Processing profile for AWS account $acctnum ($acctname)"

    sleep 1
done < "$acctsfile"
rm "$acctsfile"

#echo "### The section above added by awsssoprofiletool.sh TimeStamp: $(date +"%Y%m%d.%H%M")" >> "$profilefile"

echo
echo "Processing complete."
echo

if [[ "${#created_profiles[@]}" -eq 0 ]]; then
	echo "No New Profile Added!!";
	tail -n1 $profilefile | grep "The section above added by awsssoprofiletool.sh TimeStamp:" >> /dev/null 2>&1
	if [ $? -eq 0 ]; then
		sed -i '$d' $profilefile
	fi

	tail -n1 $profilefile | grep "The section below added by awsssoprofiletool.sh TimeStamp:" >> /dev/null 2>&1
	if [ $? -eq 0 ]; then
		sed -i '$d' $profilefile
	fi
else
	echo "Added the following profiles to $profilefile:"
	echo

	for i in "${created_profiles[@]}"
	do
		echo "$i"
	done
fi

echo
cat $profilefile | awk '!NF {if (++n <= 1) print; next}; {n=0;print}' > ${profilefile}_$(date +"%Y%m%d")
mv ${profilefile}_$(date +"%Y%m%d") $profilefile
#############
## AWS Config Profiles for Steampipe
AWS_PROFILES=$(cat ${profilefile} | grep "^\[profile" | awk '{print $2}' | sed 's/\]//g')

rm -f ${CONNECTIONFILE}
for SC in ${AWS_PROFILES}; do

CONNECTION_VIEW=$(cat <<EOF
connection "aws_${SC}" {
plugin = "aws"
profile = "${SC}"
regions = ["us-east-1", "us-east-2", "us-west-1", "us-west-2"]
ignore_error_codes = ["AccessDenied", "AccessDeniedException", "NotAuthorized", "UnauthorizedOperation", "UnrecognizedClientException", "AuthorizationError", "InvalidInstanceId", "NoCredentialProviders", "operation", "timeout", "InvalidParameterValue"]
}
EOF
)
	echo "$CONNECTION_VIEW" >> "$CONNECTIONFILE";
	echo "" >> "$CONNECTIONFILE";
done

AGGREGATOR_VIEW=$(cat <<EOF
connection "aws_all" {
  type        = "aggregator"
  plugin      = "aws"
  connections = ["aws_*"]
}
EOF
)
echo "$AGGREGATOR_VIEW" >> "$CONNECTIONFILE"
###########

exit 0
