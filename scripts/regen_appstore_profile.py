#!/usr/bin/env python3
"""Regenerate an App Store provisioning profile and install it.

Why this exists: a provisioning profile freezes the App ID's capabilities at
the moment it is created. Add an entitlement to the app (HealthKit on
2026-09-02, Time Sensitive Notifications on 2026-09-06) and `release.sh`
fails at the archive step with "Provisioning profile ... doesn't include
the ... entitlement" until the profile is made again. The capability itself
has to be ticked on developer.apple.com first (Identifiers > GrowDaily),
because the public App Store Connect API cannot add most capabilities; this
script does everything after that click.

What it does, with the same API key release.sh uses (ASC_KEY_ID and
ASC_ISSUER_ID in the environment, the .p8 in ~/.appstoreconnect/private_keys):
  1. finds the profile by name and remembers its bundle id, type and
     certificates;
  2. deletes it and creates it again under the same name;
  3. installs the new file in both folders Xcode reads and removes the old
     copy;
  4. checks that every key in the matching .entitlements file is now in the
     profile, and says so.

Usage:
  python3 scripts/regen_appstore_profile.py
  python3 scripts/regen_appstore_profile.py --profile "GrowDailyWidget AppStore" \
      --entitlements ios/GrowDailyWidget/GrowDailyWidgetExtension.entitlements

Needs the PyJWT and cryptography packages: pip3 install pyjwt cryptography
"""
import argparse
import base64
import glob
import json
import os
import plistlib
import subprocess
import sys
import time
import urllib.error
import urllib.request

try:
    import jwt
except ImportError:  # pragma: no cover
    sys.exit('PyJWT is missing: pip3 install pyjwt cryptography')

API = 'https://api.appstoreconnect.apple.com/v1'
PROFILE_DIRS = [
    os.path.expanduser('~/Library/MobileDevice/Provisioning Profiles'),
    os.path.expanduser('~/Library/Developer/Xcode/UserData/Provisioning Profiles'),
]


def token():
    key_id = os.environ.get('ASC_KEY_ID', '')
    issuer = os.environ.get('ASC_ISSUER_ID', '')
    if not key_id or not issuer:
        sys.exit('ASC_KEY_ID and ASC_ISSUER_ID must be set, see the header of release.sh')
    key_path = os.path.expanduser(f'~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8')
    if not os.path.exists(key_path):
        sys.exit(f'missing {key_path}')
    now = int(time.time())
    return jwt.encode(
        {'iss': issuer, 'iat': now, 'exp': now + 900, 'aud': 'appstoreconnect-v1'},
        open(key_path).read(), algorithm='ES256', headers={'kid': key_id, 'typ': 'JWT'})


def call(method, path, body=None):
    req = urllib.request.Request(
        API + path, method=method,
        headers={'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'},
        data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, {'raw': raw.decode(errors='replace')}


def decoded(path):
    raw = subprocess.run(['security', 'cms', '-D', '-i', path], capture_output=True).stdout
    return plistlib.loads(raw) if raw else {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--profile', default='GrowDaily AppStore')
    ap.add_argument('--entitlements', default='ios/Runner/Runner.entitlements')
    args = ap.parse_args()

    st, found = call('GET', '/profiles?filter[name]=' + urllib.request.quote(args.profile)
                     + '&include=bundleId,certificates')
    if st != 200 or not found.get('data'):
        sys.exit(f'profile "{args.profile}" not found on App Store Connect ({st}): '
                 + json.dumps(found)[:300])
    first = found['data'][0]
    profile_type = first['attributes']['profileType']
    bundle_id = first['relationships']['bundleId']['data']['id']
    certs = [c['id'] for c in first['relationships']['certificates']['data']]
    print(f'{args.profile}: {profile_type}, bundle {bundle_id}, certificates {certs}')

    for d in found['data']:
        st, _ = call('DELETE', f"/profiles/{d['id']}")
        print('  deleted', d['id'], st)

    st, made = call('POST', '/profiles', {'data': {
        'type': 'profiles',
        'attributes': {'name': args.profile, 'profileType': profile_type},
        'relationships': {
            'bundleId': {'data': {'type': 'bundleIds', 'id': bundle_id}},
            'certificates': {'data': [{'type': 'certificates', 'id': c} for c in certs]}}}})
    if st != 201:
        sys.exit('create failed: ' + json.dumps(made)[:600])
    attrs = made['data']['attributes']
    print('  created', made['data']['id'], attrs['profileState'], 'expires', attrs['expirationDate'])
    content = base64.b64decode(attrs['profileContent'])

    new_name = attrs['uuid'] + '.mobileprovision'
    for d in PROFILE_DIRS:
        os.makedirs(d, exist_ok=True)
        for old in glob.glob(d + '/*.mobileprovision'):
            if old.endswith(new_name):
                continue
            if decoded(old).get('Name') == args.profile:
                os.remove(old)
                print('  removed old', os.path.basename(old))
        with open(os.path.join(d, new_name), 'wb') as f:
            f.write(content)
        print('  installed', os.path.join(d, new_name).replace(os.path.expanduser('~'), '~'))

    have = decoded(os.path.join(PROFILE_DIRS[0], new_name)).get('Entitlements', {})
    want = plistlib.load(open(args.entitlements, 'rb'))
    missing = [k for k in want if k not in have]
    if missing:
        sys.exit('still missing from the profile: ' + ', '.join(missing)
                 + '\nTick the capability on developer.apple.com > Identifiers first, then run this again.')
    print('every entitlement in', args.entitlements, 'is in the new profile')


if __name__ == '__main__':
    main()
