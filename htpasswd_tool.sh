#!/bin/bash

# Tool to add and remove htpasswd users from OpenShift Clusters.

# Display usage information
usage() {
    cat <<- EOF
Usage: $0 [OPTIONS] <command> [args]

COMMANDS:
    --add-user <username>                   Adds a user and provided password value to local htpasswd file.  Automagically appends '_clusteradmin' to username.
    --delete-user <username>                Removes a user from local htpasswd file.
    --apply-clusteradmin-role <username>    Applies the "cluster-admin" cluster binding role to the specified user.

OPTIONS:
    -h, --help                              Show this help message.

EXAMPLES:
    # Add a new user:
    htpasswd_tool.sh --add-user james  #(Results in the 'james_clusteradmin' user being created/added)

    # Delete an existing user:
    htpasswd_tool.sh --delete-user james_clusteradmin

    # Apply cluster-admin cluster binding role to a user:
    htpasswd_tool.sh --apply-clusteradmin-role james_clusteradmin
EOF
    exit 1
}

# Define Global Variables
htpasswd_userfile_location="/htpasswd_files/poc_clusteradmins.htpasswd"
htpasswd_secret_location="/htpasswd_files/poc_clusteradmins_secret.yaml"

# Define Functions
add_user () {
    local username="${1}_clusteradmin"
    read -sp "Please enter the desired password for user $username: " password_value
    htpasswd -B -b $htpasswd_userfile_location $username $password_value
    echo "Added user: $username"
    apply_htpasswd_secret
}

delete_user () {
    local username=$1
    
    # Remove user from HTPASSWD Secret
    htpasswd -D $htpasswd_userfile_location $username
    echo "Removed user: $username"
    apply_htpasswd_secret

    # Delete user objects from OpenShift cluster
    echo "Now deleting user objects from OpenShift cluster..."
    oc delete user $username
    oc delete identity poc_clusteradmin_htpasswd_provider:$username
}

apply_htpasswd_secret () {
    # Read updated base64-encoded content
    base64_content=$(cat $htpasswd_userfile_location | base64 -w 0)
    
    # Overwrite the secret file with new htpasswd value (keeping specific yaml spacing)
    cat > $htpasswd_secret_location <<- EOF
apiVersion: v1
kind: Secret
metadata:
  name: htpass-secret
  namespace: openshift-config
type: Opaque
data:
  htpasswd: ${base64_content}
EOF
    echo "The htpasswd secret file has been updated..."
    echo "Preparing to apply updated secret file to openshift cluster..."
    oc apply -f $htpasswd_secret_location
}

apply_clusteradmin_role () {
    local username=$1
    oc adm policy add-cluster-role-to-user cluster-admin $username
}

# Check if user is logged into OpenShift cluster
if ! oc whoami &> /dev/null; then
    echo "Error: You must be logged into the OpenShift cluster as the kubeadmin user to use this script successfully."
    exit 1
fi

# Check for no arguments provided
if [ $# -eq 0 ]; then
    usage
fi

# Do command line executions
while [ $# -gt 0 ]; do
    case $1 in 
        --add-user)
            if [ -z "$2" ]; then
                echo "Error: '--add-user' requires a username"
                exit 1
            fi
            add_user "$2"
            shift 2
            ;;
        --delete-user)
            if [ -z "$2" ]; then
                echo "Error: '--delete-user' requires a username"
                exit 1
            fi
            delete_user "$2"
            shift 2
            ;;
        --apply-clusteradmin-role)
            if [ -z "$2" ]; then
                echo "Error: '--apply-clusteradmin-role' requires a username"
                exit 1
            fi
            apply_clusteradmin_role "$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option: $1"
            usage
            ;;
    esac
done
