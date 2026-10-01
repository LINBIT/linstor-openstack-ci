# LINSTOR OpenStack CI

A devstack plugin for the [LINSTOR](https://linbit.com/linstor/) Cinder
driver, and the Zuul configuration of LINBIT LINSTOR CI, the third-party CI
that runs the plugin against changes to Cinder and os-brick on
[review.opendev.org](https://review.opendev.org).

| Path | Contents |
|---|---|
| `devstack/` | The devstack plugin. Usable on its own, see below. |
| `zuul.d/` | Pipelines, the `base` job, the LINSTOR job, the node provider and job secrets. |
| `playbooks/` | The base job's node setup and log upload, and the LINSTOR package installation. |

## The devstack plugin

The plugin installs DRBD and LINSTOR on every node. It runs the LINSTOR
controller on the devstack controller, registers each node as a satellite
with an LVM thin pool, and adds two Cinder backend types:

- `linstordrbd`: volumes are DRBD resources, replicated between the nodes and
  attached over DRBD. This is the transport the CI tests.
- `linstoriscsi`: volumes are exported to the hypervisor over iSCSI.

Only Ubuntu is supported. Add the plugin to `local.conf`:

```ini
[[local|localrc]]
enable_plugin linstor-openstack-ci https://github.com/LINBIT/linstor-openstack-ci
```

By default this creates two DRBD backends, `linstor-drbd-a` and
`linstor-drbd-b`, so retype and migration have somewhere to move volumes.
It also sets the tempest options for the driver and turns off volume
multiattach, because a DRBD resource has a single writer. `local.conf` can
override all of these. See `devstack/override-defaults`.

### Settings

Set these in `localrc`. `devstack/settings` has the defaults.

| Variable | Default | Meaning |
|---|---|---|
| `LINSTOR_REPO` | `ppa:linbit/linbit-drbd9-stack` | APT source for the packages. `none` skips it, for when the packages are already installed. |
| `LINSTOR_BACKING_DEVICE` | empty | A whole block device to back the thin pool. **Everything on it is destroyed.** |
| `LINSTOR_BACKING_FILE` | `$DATA_DIR/linstor-backing-file` | Sparse file on a loop device, used when no device is given. |
| `LINSTOR_BACKING_FILE_SIZE` | `30G` | Size of that file. |
| `LINSTOR_STORAGE_POOL` | `thinpool` | LINSTOR storage pool and thin LV name. |
| `LINSTOR_VG` | `linstor_vg` | Volume group holding the thin pool. |
| `LINSTOR_REMOTE_CONTROLLER` | `False` | Set to `True` on subnodes, which then only run a satellite. |
| `LINSTOR_CONTROLLER_HOST` | `$SERVICE_HOST` | Where the LINSTOR controller listens. |
| `LINSTOR_CONTROLLER_PORT` | `3370` | LINSTOR REST API port. |
| `LINSTOR_LOG_LEVEL` | empty | Level of LINSTOR's own loggers on every node (`ERROR` to `TRACE`); empty keeps the packaged level. The CI sets `DEBUG`. |
| `LINSTOR_DRBD_FLUSHES` | `True` | `False` turns off DRBD's disk and metadata flushes: much faster writes, but data is lost on a crash. For throwaway nodes only; the CI sets it. |

When a second disk is available, use `LINSTOR_BACKING_DEVICE`. DRBD then
replicates over real storage rather than a file on the root filesystem. If
the device carries the root or devstack filesystem, the plugin refuses to
use it. It cannot tell a scratch disk from one holding data you care about.

### Multi-node

Enable the plugin on every node. Subnodes also set:

```ini
LINSTOR_REMOTE_CONTROLLER=True
CINDER_ENABLED_BACKENDS=linstordrbd:linstor-drbd-a,linstordrbd:linstor-drbd-b
```

Subnodes need the same backends if they run `cinder-volume`.

## The CI

LINBIT LINSTOR CI reports to review.opendev.org as `LINBIT_LINSTOR_CI`. It
comments on every patchset and never votes, as OpenDev requires of
third-party CI. To run it again on a change, comment `recheck` or
`run-linstor`.

- Wiki: https://wiki.openstack.org/wiki/ThirdPartySystems/LINBIT_LINSTOR_CI
- Contact: linbit_ci@linbit.com

### The job

`linstor-cinder-drbd` extends upstream `tempest-multinode-full-py3`. That
gives a two-node devstack, a controller plus a compute node, and both run
`cinder-volume` and a LINSTOR satellite. Zuul prepares Cinder and os-brick at
the speculative state of the change under test. Tempest then runs the volume
tests and `cinder-tempest-plugin` against the two DRBD backends.

Each node's thin pool is backed by a sparse file on its root disk. Packages
come from LINBIT's customer repository. `playbooks/linstor/packages.yaml`
installs them before devstack runs, not the plugin, because the repository URL
contains a token and devstack's output is published. The playbook hides its
own output and removes the repository configuration afterwards.

Logs are published on the Zuul VM at https://zuul.linbit.com/logs/ and kept
for 30 days; the Gerrit comment links to them.

### Rollout

`zuul.d/projects.yaml` enables the CI in stages:

1. `opendev/ci-sandbox` runs `noop`. This proves Gerrit reporting without
   booting any node.
2. `ci-sandbox` runs `linstor-cinder-drbd`. This proves the cloud, the plugin
   and log publishing.
3. Cinder and os-brick run `linstor-cinder-drbd` in `check`, and weekly in
   `periodic`.

### Using this repository as a config project

The tenant loads this repository as a config project. It reaches it through
a read-only `git` connection, so the Zuul host doesn't need to be reachable
from outside. The consequence is that Zuul only sees changes once they are
merged, and nothing tests them before that. Zuul picks up a merge at the
connection's next poll, and any configuration error then shows up in the
dashboard.

The tenant configuration needs something like the following, with
`github.com` as a `git` connection whose `baseurl` is `https://github.com`:

```yaml
- tenant:
    name: linbit
    source:
      github-git:
        config-projects:
          - LINBIT/linstor-openstack-ci
```

The canonical name `github.com/LINBIT/linstor-openstack-ci` appears in
`zuul.d/jobs-linstor.yaml`, in `devstack/plugin.sh` and in this file. If the
repository lives somewhere else, update all three. The devstack plugin name
has to stay equal to the repository name, because devstack's Zuul roles look
for a plugin's checkout under that name.

### Secrets

Secrets in `zuul.d/secrets.yaml` are encrypted with the tenant's public key
for this project. To change a value, encrypt it and replace the existing
`!encrypted/pkcs1-oaep` block:

```sh
echo -n "$VALUE" | zuul-client --zuul-url https://<zuul-web> encrypt \
    --tenant linbit --project github.com/LINBIT/linstor-openstack-ci \
    --secret-name linbit_packages --field-name repo_url
```

Only Zuul can decrypt the result, so it's safe to commit to this public
repository. Never commit a plain value.

## License

Apache License 2.0. See [LICENSE](LICENSE).
