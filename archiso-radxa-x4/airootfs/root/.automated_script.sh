#!/usr/bin/env bash

script_cmdline () {
    for param in $(< /proc/cmdline); do
        case "$param" in
            script=*) echo "${param#*=}" ; return 0 ;;
        esac
    done
}

automated_script () {
    local script
    script="$(script_cmdline)"
    if [[ -n "$script" && -x "/usr/local/bin/$script" ]]; then
        echo "Running automated script: $script"
        /usr/local/bin/"$script"
        echo "Automated script finished."
    else
        echo "No valid script=... found in cmdline or script not executable"
    fi
}

echo "Hello from automated script!"

automated_script

echo "Automated script done!"