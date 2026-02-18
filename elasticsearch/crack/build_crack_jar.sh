#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${VERSION:-}" ]]; then
  echo "VERSION env is not set"
  exit 1
fi

v=( ${VERSION//./ } )
BRANCH="${v[0]}.${v[1]}"

echo "Runtime:"
echo "  version: ${VERSION}"
echo "  branch:  ${BRANCH}"

mkdir -p /crack/output
cd /crack

echo "Download sources ..."
curl -fsS -o License.java "https://raw.githubusercontent.com/elastic/elasticsearch/${BRANCH}/x-pack/plugin/core/src/main/java/org/elasticsearch/license/License.java"
curl -fsS -o LicenseVerifier.java "https://raw.githubusercontent.com/elastic/elasticsearch/${BRANCH}/x-pack/plugin/core/src/main/java/org/elasticsearch/license/LicenseVerifier.java"

echo "Patch sources ..."
sed -i '/void validate()/{h;s/validate/validate2/;x;G}' License.java
sed -i '/void validate()/ s/$/}/' License.java
sed -i '/boolean verifyLicense(/{h;s/verifyLicense/verifyLicense2/;x;G}' LicenseVerifier.java
sed -i '/boolean verifyLicense(/ s/$/return true;}/' LicenseVerifier.java

LIB_CP="/usr/share/elasticsearch/lib/*:/usr/share/elasticsearch/modules/x-pack-core/*"

echo "Compile ..."
javac -proc:none -cp "${LIB_CP}" LicenseVerifier.java
javac -proc:none -cp "${LIB_CP}" License.java

echo "Repack jar ..."
cp "/usr/share/elasticsearch/modules/x-pack-core/x-pack-core-${VERSION}.jar" "x-pack-core-${VERSION}.jar"
unzip -q "x-pack-core-${VERSION}.jar" -d "./x-pack-core-${VERSION}"
cp LicenseVerifier.class "./x-pack-core-${VERSION}/org/elasticsearch/license/"
cp License.class "./x-pack-core-${VERSION}/org/elasticsearch/license/"
jar -cf "x-pack-core-${VERSION}.crack.jar" -C "x-pack-core-${VERSION}/" .

cp "x-pack-core-${VERSION}.crack.jar" "/crack/output/"

echo
echo "Done."
echo "Cracked jar: /crack/output/x-pack-core-${VERSION}.crack.jar"
