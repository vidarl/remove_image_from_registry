#!/bin/bash

IMAGE_ARG=""
HOST=""
IMAGE=""
URI=""
TAG=""
USERNAME=""
CREDENTIALS_STRING=""
INSECURE=""
RAW_URL=""
RAW_HTTP_METHOD=""
RAW_HTTP_HEADER=""

function printUsage
{
    local RESULT=$1
    if [ "$RESULT" == "" ]; then
        RESULT=0
    fi
    cat << EOF

Usage:
 $ ./remove_image_from_registry.sh [OPTIONS] [IMAGE]

IMAGE
 Image name has the format registryhost:port/reposityry/imagename:version
 For instance : mydockerregistry:5000/myrepo/zoombie:latest
 Note that the version tag ("latest" in this example) is mandatory.

REQUIREMENTS
 The registry must run a v2 registry and have token based authentication enabled.
 Deletion must be enabled on the registry server (REGISTRY_STORAGE_DELETE_ENABLED=true).
 
NOTE
  The blobs are actually not deleted from the registry server automatically after running this script.
  In order to do that you must manually (for the time being) run the registry garbage collector.
  See https://docs.docker.com/registry/garbage-collection/ for more info about this.

OPTIONS
 -h, --help
        Print help
 --insecure
        Connect to a registry which has a self-signed SSL certificate
 -p
        Prompt for password
 -u <username>
        Use the given username when authenticating with the registry
 --raw <url> <http-method> [http-header]
        Send custom request to the registry. When using this argument, do not use the  [IMAGE] argument too.
        Example:
        ./remove_image_from_registry.sh \\
             -u admin \\
             --insecure \\
             --raw \\
             mydockerregistry:5000/v2/imagename/manifests/latest \\
             GET \\
             "Accept: application/vnd.docker.distribution.manifest.v2+json"

 
Password may also be set using the environment variable REGISTRY_PASSWORD
 $ export REGISTRY_PASSWORD=sesame

EOF
    exit $RESULT;
}

function parseArguments
{
    while (( "$#" )); do
        if [ "$1" = "-u" ]; then
            shift
            USERNAME=$1
        elif [ "$1" = "-p" ]; then
            echo -n "Password: "
            read -s REGISTRY_PASSWORD
        elif [ "$1" = "--insecure" ]; then
            INSECURE=" --insecure"
        elif [ "$1" = "--help" ]; then
            printUsage
        elif [ "$1" = "-h" ]; then
            printUsage
        elif [ "$1" = "--raw" ]; then
            shift
            RAW_URL="$1"
            shift
            RAW_HTTP_METHOD="$1"
            shift
            RAW_HTTP_HEADER="$1"
        else
            # If first param is a dash, we have an invalid argumwent
            if [ ${1:0:1} == "-" ]; then
                echo "Error: Unknown parameter : $1"
                exit 1
            fi
            if [ "$IMAGE_ARG" != "" ]; then
                echo "Error: You may only provide IMAGE name once"
                exit 1
            fi
            IMAGE_ARG="$1"
            HOST=`echo $IMAGE_ARG|cut -f 1 -d "/"`
            IMAGE=`echo $IMAGE_ARG|cut -f 2- -d "/"|cut -f 1 -d ":"`
            TAG=`echo $IMAGE_ARG|cut -f 2- -d "/"|cut -f 2 -d ":"`
        fi
        shift
    done

    if [ "$IMAGE_ARG" = "" ] && [ "$RAW_URL" = "" ]; then
        echo "Error: You need to provide image name"
        printUsage 1
    fi

    if [ "$USERNAME" != "" ]; then
        CREDENTIALS_STRING=" --user ${USERNAME}:${REGISTRY_PASSWORD}"
    fi
}

# $1 is URL
# $2 is HTTP METHOD (default GET)
# $2 is additional header ( optional )
function sendRegistryRequest
{
    local URL
    local WWW_AUTH_HEADER
    local TOKEN
    local TOKEN_RESP
    local REALM
    local SERVICE
    local SCOPE
    local CUSTOM_HEADER
    local HTTP_METHOD
    local CURL_ARG
    local RESULT
    
    URL="$1"

    if [ "$2" != "" ]; then
        HTTP_METHOD="$2"
    else
        HTTP_METHOD="GET"
    fi
    
    if [ "$3" != "" ]; then
        CUSTOM_HEADER="$3"
    else
        CUSTOM_HEADER=""
    fi
    
    WWW_AUTH_HEADER=`curl -s -i $INSECURE -X $HTTP_METHOD -H "Content-Type: application/json" ${URL} |grep Www-Authenticate|sed 's|.*realm="\(.*\)",service="\(.*\)",scope="\(.*\)".*|\1,\2,\3|'`

    REALM=`echo $WWW_AUTH_HEADER|cut -f 1 -d ","`
    SERVICE=`echo $WWW_AUTH_HEADER|cut -f 2 -d ","`
    SCOPE=`echo $WWW_AUTH_HEADER|cut -f 3 -d ","`

    TOKEN=`curl -f -s $INSECURE "${REALM}?service=${SERVICE}&scope=${SCOPE}" -K- <<< $CREDENTIALS_STRING|jq .token|cut -f 2 -d "\""`
    RESULT=$?
    if [ $RESULT -ne 0 ] || [ "$TOKEN" == "" ]; then
        # Run command again (without -f arg) and output message to std err 
        >&2 echo Auth server responded:
        >&2 curl -s $INSECURE "${REALM}?service=${SERVICE}&scope=${SCOPE}" -K- <<< $CREDENTIALS_STRING
        if [ $RESULT -eq 0 ]; then
            RESULT=42
        fi
        exit $RESULT
    fi

    # We only use -f parameter if we are doing a ordinary delete request
    # If we are doing raw request, we output both request and response ( including headers )
    if [ "$RAW_URL" = "" ]; then
        CURL_ARG="-f "
    else
        CURL_ARG="-v "
    fi
    if [ "$CUSTOM_HEADER" == "" ]; then
        curl $CURL_ARG -s $INSECURE -X $HTTP_METHOD -H "Authorization: Bearer $TOKEN" "${URL}"
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
        # Run command again (without -f arg) and output message to std err 
            >&2 curl -s $INSECURE -X $HTTP_METHOD -H "Authorization: Bearer $TOKEN" "${URL}"
            exit $RESULT
        fi
    else
        curl $CURL_ARG -i -s $INSECURE -X $HTTP_METHOD -H "$CUSTOM_HEADER" -H "Authorization: Bearer $TOKEN" "${URL}"
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
        # Run command again (without -f arg) and output message to std err 
            >&2 curl -i -s $INSECURE -X $HTTP_METHOD -H "$CUSTOM_HEADER" -H "Authorization: Bearer $TOKEN" "${URL}"
            exit $RESULT
        fi
    fi
}

parseArguments "$@"

if [ "$RAW_URL" = "" ]; then
    SHA_REQ=`sendRegistryRequest https://${HOST}/v2/${IMAGE}/manifests/${TAG} GET "Accept: application/vnd.docker.distribution.manifest.v2+json"`
    RESULT=$?
    if [ "$SHA_REQ" == "" ] || [ $RESULT -ne 0 ]; then
        exit $RESULT
    fi

    SHA=$(echo "$SHA_REQ"|grep "Docker-Content-Digest:"|cut -f 2- -d ":"|tr -d '[:space:]')
    sendRegistryRequest https://${HOST}/v2/${IMAGE}/manifests/${SHA} DELETE
else
    sendRegistryRequest "https://${RAW_URL}" "${RAW_HTTP_METHOD}" "${RAW_HTTP_HEADER}"
fi

