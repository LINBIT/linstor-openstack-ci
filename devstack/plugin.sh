# devstack plugin for the LINSTOR Cinder driver.
#
# Installs DRBD and LINSTOR on every node, runs the LINSTOR controller on
# the devstack controller, registers each node as a satellite with a thin
# pool, and provides the configure_cinder_backend_linstor* hooks that
# devstack's lib/cinder calls for CINDER_ENABLED_BACKENDS entries of type
# "linstordrbd" and "linstoriscsi".
#
# Enable with:
#   enable_plugin linstor-openstack-ci https://github.com/LINBIT/linstor-openstack-ci

LINSTOR_PLUGIN_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$LINSTOR_PLUGIN_DIR/lib/linstor"

if [[ "$1" == "stack" && "$2" == "pre-install" ]]; then
    echo_summary "Installing DRBD and LINSTOR"
    install_linstor
elif [[ "$1" == "stack" && "$2" == "install" ]]; then
    echo_summary "Configuring the LINSTOR cluster"
    start_linstor
    configure_linstor_client
    register_linstor_node
    create_linstor_storage_pool
elif [[ "$1" == "stack" && "$2" == "extra" ]]; then
    echo_summary "LINSTOR cluster state"
    show_linstor_status
elif [[ "$1" == "unstack" ]]; then
    stop_linstor
elif [[ "$1" == "clean" ]]; then
    cleanup_linstor
fi
