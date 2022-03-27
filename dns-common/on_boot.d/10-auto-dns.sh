#!/bin/sh

## Configuration variables:
# File location - it should be a csv in in the order vlan description, vlan id, ipv4 gateway, ipv6 gateway
VLAN_FILE="/mnt/data/podman/vlan/vlan.csv"
VLAN_HEADER=true
IMAGES_FILE="/mnt/data/podman/images/images.csv"
IMAGES_HEADER=true
# Timezone
TZ="Europe/London"

## Functions
# This function adds allows the use of a vlan network. The first variable is the file to read.
read_vlan()
{
    if [ ! -f $1 ]; then
        echo "No vlan file"
        return 1
    fi
    while IFS=, read -r vlan_description vlan_id gateway gateway_v6
    do
        # skip the header of the csv
        if [ $VLAN_HEADER = true ]; then
           VLAN_HEADER=false
           continue
        fi
        activate_vlan $vlan_id $gateway $gateway_v6
    done < $1
}
# Activates the vlan network. Variable 1 is vlan id, varuable 2 is gateway ip v4/mask, variable 3 is gatewat ip v6/mask.
activate_vlan()
{
    # set VLAN bridge promiscuous
    ip link set br${1} promisc on
    # create macvlan bridge and add IPv4 IP
    ip link add br${1}.mac link br${1} type macvlan mode bridge
    ip addr add ${2} dev br${1}.mac noprefixroute
    # (optional) add IPv6 IP to VLAN bridge macvlan bridge
    if [ ! -z $3 ]; then
        ip -6 addr add ${3} dev br${1}.mac noprefixroute
    fi
    # set macvlan bridge promiscuous and bring it up
    ip link set br${1}.mac promisc on
    ip link set br${1}.mac up

    # Make DNSMasq listen to the container network for split horizon or conditional forwarding
    if ! grep -qxF interface=br${1}.mac /run/dnsmasq.conf.d/custom.conf; then
        echo interface=br${1}.mac >> /run/dnsmasq.conf.d/custom.conf
        kill -9 `cat /run/dnsmasq.pid`
    fi
}
# This function reads the list of images to use. The first variable is the file to read.
read_images()
{
    if [ ! -f $1 ]; then
        echo "No images file"
        return 1
    fi
    while IFS=, read -r image_name image_description image_id image_repo version hostname network_name vlan ip ip_net ip_v6 ip_v6_net run_command
    do
        # skip the header of the csv
        if [ $IMAGES_HEADER = true ]; then
           IMAGES_HEADER=false
           continue
        fi
        # Image
        # if network is type is network then prepare it for use.
        if [ $network_type = "network" ]
            prepare_network $vlan $ipv4 $ipv6
        fi
        # auto update check if update if required
        # pull the image if it's not a dockerfile and does not exist or needs updating
        pull_image $repo $version $repo_location
        # if auto update is on and required; update image
        update_image $name
        # run image if required, else start if status is not running
        run_image
    done < $1
}
# Prepare the network for use. First variable is the vlan, second is the ipv4, third is ipv6
prepare_network()
{
    # add IPv4 route to DNS container
    ip route add "${2}/32" dev "br${1}.mac"
    # (optional) add IPv6 route to DNS container
    if [ -n "${3}" ]; then
        ip -6 route add "${3}/128" dev "br${1}.mac"
    fi
}
# Pull image. Pass in the arguement for the repo.
pull_image()
{
    if [ ! -z $1 ]; then
        echo "No repo specified"
        return 1
    fi
    podman pull $1
}
# Update image. Pass the name oof the container.
update_image()
{
    if [ ! -z $1 ]; then
        echo "No name specified"
        return 1
    fi
    podman stop $1
    podman rm $1
}
#
network_command()
{
    # Set the network
    case NETWORK in
        bridge)
            PODMAN_COMMAND=${PODMAN_COMMAND}" --net=bridge"
            ;;        
        host)
            PODMAN_COMMAND=${PODMAN_COMMAND}" --net=host"
            ;;
        none)
            PODMAN_COMMAND=${PODMAN_COMMAND}" --net=none"
            ;;
        network)
            if [ -z NETWORK]; then
                break
            fi
            if [ -z $(docker network ls --filter name=^${NETWORK_NAME}$ --format="{{ .Name }}") ]; then
                break
            fi
            PODMAN_COMMAND=${PODMAN_COMMAND}" --network ${NETWORK_NAME}"
            ;;
    esac
}
# Build run command
build_run_command()
{
    # Reset the command
    PODMAN_COMMAND=""
    # Set the privileged flag
    if [ $PRIVILEGED = true ]; then
        PODMAN_COMMAND=${PODMAN_COMMAND}" --privileged"
    fi
    # set the network
    network_command
    # Set the restart
    if [ ! -z $RESTART ]; then
        PODMAN_COMMAND=${PODMAN_COMMAND}" --restart ${RESTART}"
    else
        PODMAN_COMMAND=${PODMAN_COMMAND}" --restart always"
    fi
    # Set the name
    if [ ! -z $NAME ]; then
        PODMAN_COMMAND=${PODMAN_COMMAND}" -name ${NAME}"
    fi           
    # Set the timezone - checks to see if its valid by looing for relvant file
    if [ -f "/usr/share/zoneinfo/${TZ}" ]; then
        PODMAN_COMMAND=${PODMAN_COMMAND}" -e TZ=${TZ}"
    fi
    # Set the ports
    if [ ! -z $PORTS ]; then
        PODMAN_COMMAND=${PODMAN_COMMAND}" --v ${PORTS}"
    fi
    # Set the volumes
    if [ ! -z $VOLUMES ]; then
        PODMAN_COMMAND=${PODMAN_COMMAND}" --v ${VOLUMES}"
    fi
    # Set the DNS
    if [ ! -z $DNS ]; then
        PODMAN_COMMAND=${PODMAN_COMMAND}" --dns=${DNS}"
    fi
    # Set the hostname
    if [ ! -z $HOSTNAME ]; then
        PODMAN_COMMAND=${PODMAN_COMMAND}" --hostname ${HOSTNAME}"
    fi
    # Set the environmental values
    if [ ! -z $ENV_VALUES ]; then
        PODMAN_COMMAND=${PODMAN_COMMAND}" -e ${ENV_VALUES}"
    fi
    # Set Repo
    if [ ! -z $REPO ]; then
        return 1
    fi
    PODMAN_COMMAND=${PODMAN_COMMAND}" ${REPO}"
    if [ ! -z $VERSION ]; then
        PODMAN_COMMAND=${PODMAN_COMMAND}":${VERSION}"
    fi
    echo "${PODMAN_COMMAND}"
}
# Run the image
run_image()
{
    podman run -d ${PODMAN_COMMAND}
}
# Main function
main()
{
    read_vlan ${VLAN_FILE}
    read_images ${IMAGES_FILE}
}
# Script
main
