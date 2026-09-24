#!/usr/bin/env python3
"""Build a separate guest-only Android review app without changing the main app.

Usage: PATH=/path/to/flutter/bin:$PATH python3 tool/build-review-android.py
No installation, data reset, public account config, or production flavor change.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'apps/mobile'
OUTPUT = ROOT / 'artifacts/builds/trimmy-review-arm64.apk'


def replace_once(path, old, new):
    content = path.read_text()
    if content.count(old) != 1:
        raise RuntimeError(f'Review substitution no longer matches {path.name}; review the build script.')
    path.write_text(content.replace(old, new, 1))


def main():
    flutter = shutil.which('flutter')
    if flutter is None:
        raise RuntimeError('Add the pinned Flutter SDK to PATH before building the review app.')
    with tempfile.TemporaryDirectory(prefix='trimmy-review-') as temporary:
        project = Path(temporary) / 'mobile'
        project.mkdir()
        for folder in ('lib', 'assets', 'android'):
            shutil.copytree(SOURCE / folder, project / folder,
                            ignore=shutil.ignore_patterns('build', '.gradle', '.cxx', '.DS_Store'))
        for filename in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'):
            shutil.copyfile(SOURCE / filename, project / filename)
        replace_once(project / 'android/app/build.gradle.kts',
                     'applicationId = "com.trimmy.trimmy"',
                     'applicationId = "com.trimmy.trimmy.review"')
        manifest = project / 'android/app/src/main/AndroidManifest.xml'
        replace_once(manifest, 'android:label="Trimmy"', 'android:label="Trimmy Review"')
        replace_once(manifest, 'android:name=".MainActivity"',
                     'android:name="com.trimmy.trimmy.MainActivity"')
        replace_once(manifest, 'android:scheme="com.trimmy.trimmy.privy"',
                     'android:scheme="com.trimmy.trimmy.review.privy"')
        # Source snapshot identity excludes build output and local toolchain paths.
        inputs = list((project / 'lib').rglob('*.dart')) + [project / 'pubspec.yaml', project / 'pubspec.lock',
                  project / 'android/app/build.gradle.kts', project / 'android/app/src/main/AndroidManifest.xml']
        source_hashes = {'apps/mobile/' + str(path.relative_to(project)): hashlib.sha256(path.read_bytes()).hexdigest()
                         for path in sorted(inputs)}
        print('Building isolated com.trimmy.trimmy.review with guest configuration.', flush=True)
        subprocess.run([flutter, 'pub', 'get', '--offline', '--enforce-lockfile'], cwd=project, check=True)
        # Keep release-specific plugin registration enabled; --no-pub after
        # pub get can leave development integration_test in the Java registrant.
        subprocess.run([flutter, 'build', 'apk', '--release', '--target-platform', 'android-arm64'],
                       cwd=project, check=True)
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        candidate = project / 'build/app/outputs/flutter-apk/app-release.apk'
        digest = hashlib.sha256(candidate.read_bytes()).hexdigest()
        shutil.copyfile(candidate, OUTPUT)
        record = {'package': 'com.trimmy.trimmy.review', 'label': 'Trimmy Review',
                  'mainPackageUnchanged': True, 'publicAccountConfigured': False, 'installedByScript': False,
                  'entry': 'lib/main.dart', 'signing': 'development/debug', 'bytes': OUTPUT.stat().st_size,
                  'sha256': digest, 'buildSourceHashes': source_hashes}
        OUTPUT.with_suffix('.json').write_text(json.dumps(record, indent=2) + '\n')
        print(json.dumps({'apk': str(OUTPUT.relative_to(ROOT)), 'bytes': OUTPUT.stat().st_size, 'sha256': digest}), flush=True)


if __name__ == '__main__':
    main()
