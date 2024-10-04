#!/bin/sh

set -euox pipefail


# will download the extension respecting the max download
# duration setting
download_extension() {
    mkdir -p $download_dir
    echo "Downloading the UI extension..."
    curl -Lf --max-time $download_max_sec $ext_url -o $ext_file
    if [ "$checksum_url" != "" ]; then
        echo "Validating the UI extension checksum..."
        expected_sha=$(curl -Lf $checksum_url | grep "$ext_filename" | awk '{print $1;}')
        current_sha=$(sha256sum $ext_file | awk '{print $1;}')
        if [ "$expected_sha" != "$current_sha" ]; then
            echo "ERROR: extension checksum mismatch"
            exit 1
        fi
    fi
    echo "UI extension downloaded successfully"
}

install_extension() {
    echo "Installing the UI extension..."
    cd $download_dir
    local mime_type=$(file --mime-type "$ext_filename" | awk '{print $2}')
    if [ "$mime_type" = "application/gzip" ]; then
        tar -zxf $ext_filename
    elif [ "$mime_type" = "application/x-tar" ]; then
        tar -xf $ext_filename
    else
        echo "error: unsupported extension archive: $mime_type"
        echo "supported formats: gzip and tar"
        exit 1
    fi
    if [ ! -d "/tmp/extensions/resources" ]; then
        mkdir -p /tmp/extensions/resources
    fi
    cp -Rf resources/* /tmp/extensions/resources/

    if [ -n "$ext_vars" ] && [ -n "$ext_name" ]; then
        create_extension_js_file_with_vars
    fi

    echo "UI extension installed successfully"

}

create_extension_js_file_with_vars() {
  echo "Generating extension vars js file..."
  ext_js_file_path="/tmp/extensions/resources/extension-$ext_name.js"
  ext_js_file_name="vars-$(date +"%Y%m%d%H%M%S")"
  js_file_path="${ext_js_file_path}/extension-${ext_js_file_name}.js"
  js_code=$(echo "$ext_vars" | jq -r 'to_entries | map("\"" + .key + "\": \"" + .value + "\"") | join(", ")')
  js_code="((window) => {\n  const vars = {\n    $js_code\n  };\n  window.ARGOCD_EXT_VARS = vars;\n})(window);"
  echo "Exporting extension vars file at $js_file_path"
  echo "$js_code" > "$js_file_path"
}

## Script
ext_enabled="${EXTENSION_ENABLED:-true}"
ext_name="${EXTENSION_NAME:-}"

if [ "$ext_enabled" != "true" ]; then
    echo "$ext_name extension is disabled"
    exit 0
fi

ext_version="${EXTENSION_VERSION:-}"
ext_url="${EXTENSION_URL:-}"
if [ "$ext_url" = "" ]; then
    echo "error: the env var EXTENSION_URL must be provided"
    exit 1
fi
checksum_url="${EXTENSION_CHECKSUM_URL:-}"
download_max_sec="${MAX_DOWNLOAD_SEC:-30}"

ext_filename=$(basename -- "$ext_url")
download_dir=`mktemp -d -t extension-XXXXXX`
ext_file="$download_dir/$ext_filename"
if [ -f $ext_file ]; then
    rm $ext_file
fi

ext_vars=$(echo "$EXTENSION_EXT_JS_VARS" | jq -c '.')
ext_js_file_path="${EXTENSION_EXT_JS_FILE_PATH:-}"


download_extension
install_extension

