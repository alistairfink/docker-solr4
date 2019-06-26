#!/bin/bash

# Make Bash intolerant to errors
set -o nounset
set -o errexit
set -o pipefail


# ===== Constants and functions


SOLR_DOWNLOAD_PATH="/tmp/solr.tgz"


RUNTIME_DEPENDENCIES="cgroup-tools=0.41-6"


function download_file() {
    local origin_url="$1"
    local destination_path="$2"
    local sha1_checksum="$3"
	
	echo "Downloading from ${origin_url}"

    wget -O "${destination_path}" "${origin_url}"
    check_file_sha1_sum "${destination_path}" "${sha1_checksum}"
}


function check_file_sha1_sum() {
    local file_path="$1"
    local expected_sha1_checksum="$2"
	
	echo "Checking sum of ${file_path}"

    local actual_sha1_checksum="$(sha1sum "${file_path}" | awk '{ print $1 }')"
    if [[ "${expected_sha1_checksum}" != "${actual_sha1_checksum}" ]]; then
        echo "File '${file_path}' did not pass integrity check" >&2
        exit 1
    fi
}


function expand_tgz() {
    local compressed_file_path="$1"
    local destination_dir_path="$2"
    local extra_tar_args="${@:3}"

	echo "Extracting ${compressed_file_path}"
	
    tar \
        --extract \
        --directory "${destination_dir_path}" \
        --file "${compressed_file_path}" \
        ${extra_tar_args}
    rm "${compressed_file_path}"
}


function deploy_solr_distribution() {
    local mirror_url="$1"
	
	echo "Deploying Solr Dist ${mirror_url}"

    local solr_download_url="${mirror_url}/solr-${SOLR_VERSION}.tgz"
    download_file \
        "${solr_download_url}" \
        "${SOLR_DOWNLOAD_PATH}" \
        "${SOLR_SHA1_CHECKSUM}"

    mkdir -p "${SOLR_DISTRIBUTION_PATH}"
    expand_tgz \
        "${SOLR_DOWNLOAD_PATH}" \
        "${SOLR_DISTRIBUTION_PATH}" \
        --strip-components=1
}


function configure_solr_home() {
    mkdir -p "${SOLR_HOME_PATH}"
	
	echo "Configuring Solr Home ${SOLR_HOME_PATH}"
	
    cp \
        "${SOLR_DISTRIBUTION_PATH}/example/solr/collection1/conf/solrconfig.xml" \
        "${SOLR_DISTRIBUTION_PATH}/example/solr/solr.xml" \
        "${SOLR_HOME_PATH}"
    mkdir -p "${SOLR_HOME_PATH}/cores"

    mkdir -p "${SOLR_INDICES_DIR_PATH}"
    chown "${SOLR_USER}" "${SOLR_INDICES_DIR_PATH}"
}


function configure_jetty_home() {
    mkdir -p "${JETTY_HOME_PATH}"
	
	echo "Configuring Jetty Home ${JETTY_HOME_PATH}"
	
    cp \
        --recursive \
        "${SOLR_DISTRIBUTION_PATH}/example/contexts" \
        "${SOLR_DISTRIBUTION_PATH}/example/etc" \
        "${SOLR_DISTRIBUTION_PATH}/example/lib" \
        "${SOLR_DISTRIBUTION_PATH}/example/webapps" \
        "${JETTY_HOME_PATH}"

    local solr_temp_dir_path="${JETTY_HOME_PATH}/solr-webapp"
    mkdir -p "${solr_temp_dir_path}"
    chown "${SOLR_USER}" "${solr_temp_dir_path}"
}


function install_deb_packages() {
    local package_specs="${@}"

	echo "Installing Debian Packages"
	echo ${package_specs}
    apk update
    rm -rf /var/lib/apk/lists/*
}


# ===== Main


adduser -S "${SOLR_USER}"
echo "Step 1/4"
deploy_solr_distribution "$1"
echo "Step 2/4"
configure_solr_home
echo "Step 3/4"
configure_jetty_home
echo "Step 4/4"
install_deb_packages ${RUNTIME_DEPENDENCIES}
