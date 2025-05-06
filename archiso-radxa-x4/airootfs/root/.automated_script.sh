#!/usr/bin/env bash

script_cmdline ()
{
    local param
    for param in $(< /proc/cmdline); do
        case "${param}" in
            script=*) echo "${param#*=}" ; return 0 ;;
        esac
    done
}

automated_script ()
{
    local script rt
    script="$(script_cmdline)"
    if [[ -n "${script}" && -f "/usr/local/bin/${script}" ]]; then
        /usr/local/bin/"${script}"
        rt=$?
        echo
        echo "automated script completed"
        echo
        return "${rt}"
    fi
}

if [[ $(tty) == "/dev/tty1" ]]; then
    automated_script
fi
