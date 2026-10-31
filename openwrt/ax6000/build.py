"""Runtime-only secret rendering and ImageBuilder assembly. Never run in a derivation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def uci_value(value):
    # Templates put secret placeholders inside single-quoted UCI values.
    if not isinstance(value, str) or any(c in value for c in '\x00\r\n'):
        raise ValueError('Secrets must be single-line strings')
    return value.replace("'", "'\\''")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared', required=True)
    parser.add_argument('--specification', required=True)
    parser.add_argument('--secrets', required=True)
    parser.add_argument('--output', default='./private-artifacts/ax6000')
    args = parser.parse_args()
    os.umask(0o077)
    output = Path(args.output).resolve()
    if output.is_relative_to('/nix/store'):
        parser.error('Private firmware must be written outside /nix/store')
    if output.exists():
        parser.error('Output already exists; choose a new directory to preserve previous firmware')
    spec = json.loads(Path(args.specification).read_text())
    # Capture stdout, never print decrypted values or include them in argv/environment.
    result = subprocess.run(
        ['sops', 'decrypt', '--output-type', 'json', args.secrets],
        stdout=subprocess.PIPE, check=True,
    )
    secrets = json.loads(result.stdout)
    del result
    root_hash = secrets['root_password_hash']
    if not re.fullmatch(r'\$[156y]\$[^:\s]+', root_hash):
        raise ValueError('Expected a crypt password hash for root')
    output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    # The workspace and logs may contain secrets. Clean up on success AND failure.
    with tempfile.TemporaryDirectory(prefix='.ax6000-', dir=output.parent) as temporary:
        work = Path(temporary)
        builder = work / 'imagebuilder'
        shutil.copytree(args.prepared, builder, symlinks=True)
        for directory, _, files in os.walk(builder):
            Path(directory).chmod(0o700)
            for name in files:
                path = Path(directory) / name
                if not path.is_symlink():
                    path.chmod(path.stat().st_mode | 0o600)
        (builder / 'tmp').mkdir(exist_ok=True)
        overlay = builder / 'files'
        payload = overlay / 'usr/share/ax6000'
        payload.mkdir(parents=True)
        rendered = {}
        for relative, template in spec['templates'].items():
            text = re.sub(r'@SECRET:([a-z0-9_]+)@',
                          lambda m: uci_value(secrets[m[1]]), template)
            if '@SECRET:' in text:
                raise ValueError('Unresolved secret placeholder')
            path = payload / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            path.chmod(0o600)
            rendered[relative] = text
        (payload / 'root-password-hash').write_text(root_hash + '\n')
        (payload / 'root-password-hash').chmod(0o600)
        defaults = overlay / 'etc/uci-defaults'
        defaults.mkdir(parents=True)
        # These merge with system directories. Keep normal traversal permissions;
        # the containing temporary workspace and the secret payload remain 0700.
        for relative in ['etc', 'etc/uci-defaults', 'usr', 'usr/share']:
            (overlay / relative).chmod(0o755)
        (defaults / 'zz-ax6000').write_text(spec['firstBoot'])
        (defaults / 'zz-ax6000').chmod(0o700)
        subprocess.run(['sh', '-n', str(defaults / 'zz-ax6000')], check=True)
        for config in (payload / 'etc/config').iterdir():
            # Parse with libuci, suppressing exported passwords and parse diagnostics.
            parsed = subprocess.run(['uci', '-c', str(config.parent), 'export', config.name],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            if parsed.returncode:
                raise RuntimeError('Invalid UCI configuration: ' + config.name)
        command = [
            'make', 'image', f'PROFILE={spec["profile"]}',
            'PACKAGES=' + ' '.join(spec['packages']),
            'DISABLED_SERVICES=' + ' '.join(spec['disabledServices']),
            'EXTRA_IMAGE_NAME=nix-ax6000', 'FILES=' + str(overlay),
        ]
        print('Assembling OpenWrt ' + spec['release'] + ' for ' + spec['profile'], flush=True)
        log = work / 'imagebuilder.log'
        env = os.environ.copy()
        env['LC_ALL'] = 'C'
        env['HOME'] = str(work)
        env['TMPDIR'] = str(builder / 'tmp')
        with log.open('wb') as handle:
            process = subprocess.run(command, cwd=builder, env=env, stdout=handle,
                                     stderr=subprocess.STDOUT, umask=0o022)
        if process.returncode:
            # Redact known secrets before displaying diagnostics.
            message = log.read_text(errors='replace')
            for secret in sorted(secrets.values(), key=len, reverse=True):
                if secret:
                    message = message.replace(secret, '[REDACTED]')
                    message = message.replace(uci_value(secret), '[REDACTED]')
            print(message[-16000:])
            raise SystemExit('ImageBuilder failed; private temporary files removed')
        images = builder / 'bin/targets' / spec['target'] / spec['variant']
        firmware = list(images.glob('*-' + spec['profile'] + '-squashfs-sysupgrade.itb'))
        if len(firmware) != 1:
            raise RuntimeError('Expected exactly one AX6000 sysupgrade.itb')
        firmware_metadata = work / 'firmware-metadata.json'
        subprocess.run([str(builder / 'staging_dir/host/bin/fwtool'), '-i',
                        str(firmware_metadata), str(firmware[0])], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        device_metadata = json.loads(firmware_metadata.read_text())
        if 'xiaomi,redmi-router-ax6000-ubootmod' not in device_metadata.get('supported_devices', []):
            raise RuntimeError('Firmware metadata targets the wrong board')
        if device_metadata['version']['version'] != spec['release']:
            raise RuntimeError('Firmware metadata contains the wrong OpenWrt version')
        manifests = list(images.glob('*.manifest'))
        if len(manifests) != 1:
            raise RuntimeError('Expected one package manifest')
        installed = {line.split()[0] for line in manifests[0].read_text().splitlines() if line}
        required = {name for name in spec['packages'] if not name.startswith('-')}
        required.update(['dropbear', 'ppp-mod-pppoe', 'firewall4', 'kmod-mt7915e'])
        if not required <= installed or 'sing-box' in installed:
            raise RuntimeError('Installed package manifest does not match the specification')
        # Extract the rootfs directly from the final FIT, not an intermediate tree.
        def fdt(*arguments):
            return subprocess.check_output(['fdtget', *arguments], stderr=subprocess.PIPE).decode().strip()

        nodes = fdt('-l', str(firmware[0]), '/images').splitlines()
        roots = [node for node in nodes
                 if fdt('-t', 's', str(firmware[0]), '/images/' + node, 'type') == 'filesystem']
        if len(roots) != 1:
            raise RuntimeError('Expected one root filesystem in FIT')
        node = '/images/' + roots[0]
        position = int(fdt('-t', 'x', str(firmware[0]), node, 'data-position'), 16)
        size = int(fdt('-t', 'x', str(firmware[0]), node, 'data-size'), 16)
        with firmware[0].open('rb') as handle:
            handle.seek(position)
            rootfs = handle.read(size)
        if len(rootfs) != size or not rootfs.startswith(b'hsqs'):
            raise RuntimeError('Invalid squashfs payload in FIT')
        squashfs = work / 'verify.squashfs'
        squashfs.write_bytes(rootfs)
        for relative, expected in rendered.items():
            actual = subprocess.run(['unsquashfs', '-cat', str(squashfs),
                                     'usr/share/ax6000/' + relative],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
            if actual.stdout.decode() != expected:
                raise RuntimeError('Embedded configuration mismatch: ' + relative)
        for relative, expected in {
            'etc/uci-defaults/zz-ax6000': spec['firstBoot'],
            'usr/share/ax6000/root-password-hash': root_hash + '\n',
        }.items():
            actual = subprocess.check_output(['unsquashfs', '-cat', str(squashfs), relative],
                                             stderr=subprocess.PIPE)
            if actual.decode() != expected:
                raise RuntimeError('Embedded initialization mismatch: ' + relative)
        output.mkdir(mode=0o700)
        for source in firmware + manifests:
            shutil.copyfile(source, output / source.name)
            (output / source.name).chmod(0o600)
        digest = hashlib.sha256(firmware[0].read_bytes()).hexdigest()
        (output / 'sha256sums').write_text(digest + '  ' + firmware[0].name + '\n')
        metadata = {key: value for key, value in spec.items()
                    if key not in ('templates', 'firstBoot')}
        metadata['specificationSha256'] = hashlib.sha256(Path(args.specification).read_bytes()).hexdigest()
        metadata['encryptedSecretsSha256'] = hashlib.sha256(Path(args.secrets).read_bytes()).hexdigest()
        metadata['firmwareMetadata'] = device_metadata
        metadata['validation'] = 'Built image and embedded configuration verified; not boot-tested'
        (output / 'build-info.json').write_text(json.dumps(metadata, indent=2) + '\n')
        print('Firmware: ' + str(output / firmware[0].name))
        print('SHA256: ' + digest)


if __name__ == '__main__':
    main()
