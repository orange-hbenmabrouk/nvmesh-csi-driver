#!/usr/bin/env bash

print_help() {
    echo "Usage: $(basename "$0") [--servers node1 node2 node3 --master node1]"
    echo ""
    echo "-h|--help        this help"
    echo "-s|--servers     list of server hostnames / IP on which the driver image would be built"
    echo "-m|--master      the hostname or IP of the master node with kubectl available for deploying the yamls"
    echo "--mgmt           the address of the management server for overriding the ConfigMap value e.g n115:4000"
    echo "--mgmt-protocol  the protocol of the management server for overriding the ConfigMap value e.g http | https"
    echo ""
}

SERVERS=()
MASTER=""
MANAGMENT_ADDRESS=""
MANAGMENT_PROTOCOL=https

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -h|--help)
    print_help
    exit 0
    ;;
    -s|--servers)
        nextArg="$2"
        while ! [[ "$nextArg" =~ -.* ]] && [[ $# > 1 ]]; do
            SERVERS+=( "$2" )
            shift
            nextArg="$2"
        done
    ;;
    -m|--master)
        MASTER="$2"
        shift
    ;;
    --mgmt)
        MANAGMENT_ADDRESS="$2"
        shift
    ;;
    --mgmt-protocol)
        MANAGMENT_PROTOCOL="$2"
        shift
    ;;
    *)
    # unknown option
    echo "Unknown option $key"
    print_help
    exit 1
    ;;
esac
shift # past argument or value
done

if [ -z "$MASTER" ] && [ "${#SERVERS[@]}" -eq 0 ]; then
    echo "Error: Please provide atleast one of the folloing flags: --master , --servers"
    print_help
    exit 1
fi

if [ ! -z "$MASTER" ]; then
    # clear deployment from master node
    ssh $MASTER "~/nvmesh-csi-driver/deploy/kubernetes/scripts/remove_deployment.sh"
fi

if [ "${#SERVERS[@]}" -gt 0 ];then
    # copy souorces to all nodes
    ./copy_sources_to_machine.sh "${SERVERS[@]}"

    # build on all servers
    echo "Buildig on all servers"
    for server in "${SERVERS[@]}"
    do
        echo "Buildig on $server"
        ssh $server "cd ~/nvmesh-csi-driver/build_tools ; ./build.sh" &
        pids[${i}]=$!
    done

    # wait for all children
    for pid in ${pids[*]}; do
        wait $pid
    done

    echo "Finished buildig on all servers"
else
    echo "No remote build servers given. deploying"
    ./copy_sources_to_machine.sh $MASTER
fi

if [ ! -z "$MASTER" ]; then
    # deploy on master node
    ssh $MASTER "cd ~/nvmesh-csi-driver/deploy/kubernetes/scripts ; ./build_deployment_file.sh ; cd .. ; kubectl apply -f ./deployment-k8s-1.17.yaml"

    # set management address
    if [ ! -z "$MANAGMENT_ADDRESS" ]; then
        ssh $MASTER "~/nvmesh-csi-driver/deploy/kubernetes/scripts/set_mgmt_address.sh --protocol $MANAGMENT_PROTOCOL --address $MANAGMENT_ADDRESS"
    fi
fi
